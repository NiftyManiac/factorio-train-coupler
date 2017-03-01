mod_name = "TrainCoupler"
debug_file = mod_name .. "_debug.txt"
debug_status = 2
require "lib"

--[[
Decouple two carriages:
1) Save and destroy the carriage blocking the coupler rail
2) Destroy the coupler rail
3) Restore and place the carriage in the same place it was. The missing rail prevents reconnection.
4) Place the coupler rail back
--]]
function decouple(carriage1, carriage2, rail)
  game.print("Time to decouple")
  game.print(carriage1==nil)
  game.print(carriage2==nil)

  function dist_sq(ent1, ent2)
    return (ent1.position.x-ent2.position.x)^2+(ent1.position.y-ent2.position.y)^2
  end

  local closest_carriage = dist_sq(carriage1, rail) < dist_sq(carriage2, rail) and carriage1 or carriage2
  local pose = {pos=closest_carriage.position, orient=closest_carriage.orientation}
  copy_carriage(closest_carriage, global.dummies[1])
  closest_carriage.destroy()

  local coupler_force = rail.force
  local coupler_pose = {pos=rail.position, dir=rail.direction}
  global.to_remove[#global.to_remove+1] = rail.unit_number
  rail.destroy()

  copy_carriage(global.dummies[1], pose)

  new_coupler = game.surfaces.nauvis.create_entity{name="coupler-rail", 
        position=coupler_pose.pos, direction=coupler_pose.dir, force=coupler_force}
  global.coupler_rails[new_coupler.unit_number] = new_coupler
end

--[[
Couple two carriages:
1) Save and destroy the shorter of the trains
2) Restore and place the wagons in the correct order so that connections are made
--]]
function couple(carriage1, carriage2)
  game.print("time to couple")

  -- choose the smaller train
  local near_carriage;
  if #carriage1.train.carriages < #carriage2.train.carriages then
    near_carriage = carriage1
  else
    near_carriage = carriage2
  end

  -- make a copy of the train being destroyed
  local carriages_to_recreate = {}
  for i=1,#near_carriage.train.carriages do
    carriages_to_recreate[i] = near_carriage.train.carriages[i]
  end

  local initial, final, step;
  if near_carriage == near_carriage.train.front_stock then
    initial, final, step = 2, #carriages_to_recreate, 1
    debug_print("Forward")
  elseif near_carriage == near_carriage.train.back_stock then
    initial, final, step = #carriages_to_recreate-1, 1, -1
    debug_print("Backward")
  else
    debug_print("Near carriage isn't front or back of train")
    return
  end

  copy_carriage(near_carriage, global.dummies[1])
  local last_pose = {pos=near_carriage.position, orient=near_carriage.orientation}
  local new_pose = last_pose
  near_carriage.destroy()

  local dummy_i = 2

  for i=initial,final,step do
    local carriage = carriages_to_recreate[i]
    copy_carriage(carriage, global.dummies[dummy_i])
    dummy_i = 3-dummy_i -- cycle between 1 and 2
    new_pose = {pos=carriage.position, orient=carriage.orientation}
    carriage.destroy()

    temp = copy_carriage(global.dummies[dummy_i], last_pose)

    last_pose = new_pose
  end

  temp = copy_carriage(global.dummies[3-dummy_i], last_pose)
end

-- copy all properties of one carriage to another. 
-- target may be:
--  an entity to replace
--  a pose on nauvis: target={pos={x,y},orient=orient}
-- return the new carriage
function copy_carriage(source, target)
  if source.name ~= target.name then
    local pose, surf, dummy_i;
    if target.name == nil then -- passed a pose
      pose = target
      surf = game.surfaces["nauvis"]
    else -- passed an entity
      pose = {pos=target.position, orient=target.orientation}
      surf = target.surface

      -- if we delete a dummy, make sure we update the reference
      for i,dummy in pairs(global.dummies) do
        if dummy==target then
          dummy_i = i
          break
        end
      end
      target.destroy()
    end

    local dir = orientation_to_direction(pose.orient)
    target = surf.create_entity{name=source.name, force=source.force, position=pose.pos, direction=dir} 
    if dummy_i then
      global.dummies[dummy_i] = target
    end
  end

  if source.train.schedule ~= {} then
    target.train.schedule = source.train.schedule
  end
  target.health = source.health
  target.force = source.force

  if source.name=="cargo-wagon" then
    copy_inventory(source.get_inventory(defines.inventory.cargo_wagon),target.get_inventory(defines.inventory.cargo_wagon))

  elseif source.name=="diesel-locomotive" then
    copy_inventory(source.get_inventory(defines.inventory.fuel),target.get_inventory(defines.inventory.fuel))
    if source.color then -- color will be nil if it wasn't changed
      target.color = source.color
    end
    -- can't set energy
    target.health = source.health
  end

  return target
end

-- determine which "direction" to specify for create_entity to achieve a certain orientation
function orientation_to_direction(orientation)
  if orientation==0 or orientation>0.5 then
    return defines.direction.north
  else
    return defines.direction.east
  end 
end

-- copy an inventory with filters and bar
-- settings could be copied with entity.copy_settings, but that prevents selective copying
function copy_inventory(source, target)
  -- copy contents
  for i=1,#source do
    target[i].set_stack(source[i])
  end

  -- copy filters
  if source.supports_filters() and source.is_filtered() then
    for i=1,#source do
      target.set_filter(i, source.get_filter(i))
    end
  end

  -- copy bars
  if source.hasbar() then
    target.setbar(source.getbar())
  end
end

function on_creation(event)
  if event.created_entity.name == "coupler-rail" then
    if not global.coupler_rails then
      global.coupler_rails = {}
    end
    local rail = event.created_entity
    global.coupler_rails[rail.unit_number] = rail
  end
end

script.on_event(defines.events.on_built_entity, on_creation)
script.on_event(defines.events.on_robot_built_entity, on_creation)

function on_destruction(event)
  if event.entity == "coupler-rail" then
    global.coupler_rails[event.entity.unit_number] = nil
  end
end

script.on_event(defines.events.on_preplayer_mined_item, on_destruction)
script.on_event(defines.events.on_robot_pre_mined, on_destruction)
script.on_event(defines.events.on_entity_died, on_destruction)

-- create dummy trains for copying info
function init_dummies()
  if game.surfaces["train_coupler_dummy"] then
    return
  end

  local dum_surf = game.create_surface("train_coupler_dummy",{water="none", starting_area="none"})
  local num_dummies = 2
  local force = game.forces["neutral"]
  global.dummies = {}
  for i=1,num_dummies do
    local y = i*2-1
    for x=1,7,2 do
      dum_surf.create_entity{name="straight-rail", force=force, direction=defines.direction.east, position={x,y}}
    end
    global.dummies[i] = dum_surf.create_entity{name="cargo-wagon", force=force, position={3,y}}
  end
end

function on_init()
  global.coupler_rails = global.coupler_rails or {}
  global.to_remove = {} -- ids of entities that need to be removed
  init_dummies()
end

script.on_init(on_init)

function on_train_change(event)
  local train = event.train
  if train.state == defines.train_state.wait_station and train.speed == 0 then
    for id,coupler_rail in pairs(global.coupler_rails) do
      if not coupler_rail.valid then
        global.to_remove[#global.to_remove+1] = id
      else
        -- use connection_direction.none?
        neighbor1 = coupler_rail.get_connected_rail{rail_direction = defines.rail_direction.front,
                                                    rail_connection_direction = defines.rail_connection_direction.straight}
        neighbor2 = coupler_rail.get_connected_rail{rail_direction = defines.rail_direction.back,
                                                    rail_connection_direction = defines.rail_connection_direction.straight}
        local surf = game.surfaces[1]
        carriage1 = surf.find_entities_filtered{position=neighbor1.position, type="cargo-wagon", limit=1}[1] or
                          surf.find_entities_filtered{position=neighbor1.position, type="locomotive", limit=1}[1]

        carriage2 = surf.find_entities_filtered{position=neighbor2.position, type="cargo-wagon", limit=1}[1] or
                          surf.find_entities_filtered{position=neighbor2.position, type="locomotive", limit=1}[1]

        -- we're not at a coupling
        if not carriage1 or not carriage2 or carriage1 == carriage2 then
          return
        end

        if carriage1.train == train or carriage2.train == train then

          -- are the cars coupled already?
          if carriage1.train == carriage2.train then
            decouple(carriage1, carriage2, coupler_rail)
          else
            couple(carriage1, carriage2)
          end

        end
      end
    end

    -- remove all invalid coupler_rails
    for _,id in ipairs(global.to_remove) do
      global.coupler_rails[id] = nil
    end
    global.to_remove = {}
  end
end

script.on_event(defines.events.on_train_changed_state, on_train_change)

--TODO 
-- copy_settings
-- move player
-- restore schedulesds 
