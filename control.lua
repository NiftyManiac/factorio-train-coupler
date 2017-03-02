mod_name = "TrainCoupler"
debug_file = mod_name .. "_debug.txt"
debug_status = 1
require "lib"

--[[
Decouple two carriages:
1) Save and destroy the carriage blocking the coupler rail
2) Destroy the coupler rail
3) Restore and place the carriage in the same place it was. The missing rail prevents reconnection.
4) Place the coupler rail back
--]]
function decouple(carriage1, carriage2, rail)
  debug_print("Time to decouple")

  function dist_sq(ent1, ent2)
    return (ent1.position.x-ent2.position.x)^2+(ent1.position.y-ent2.position.y)^2
  end

  local closest_carriage = dist_sq(carriage1, rail) < dist_sq(carriage2, rail) and carriage1 or carriage2
  local car_info = carriage_info(closest_carriage)
  copy_carriage(closest_carriage, global.dummies[1])
  closest_carriage.destroy()

  local coupler_force = rail.force
  local coupler_pose = {pos=rail.position, dir=rail.direction}
  global.to_remove[#global.to_remove+1] = rail.unit_number
  rail.destroy()

  local new_carriage = copy_carriage(global.dummies[1], car_info)

  -- return both trains to automatic mode
  advance_station(new_carriage.train)
  for _,carriage in pairs({carriage1, carriage2}) do
    if carriage.valid then
      advance_station(carriage.train)
      break
    end
  end

  local new_coupler = game.surfaces.nauvis.create_entity{name="coupler-rail", 
        position=coupler_pose.pos, direction=coupler_pose.dir, force=coupler_force}
  global.coupler_rails[new_coupler.unit_number] = new_coupler
end

--[[
Couple two carriages:
1) Save and destroy one of the trains
2) Restore and place the wagons in the correct order so that connections are made
--]]
function couple(carriage1, carriage2)
  debug_print("time to couple")

  -- choose the train with fewer locomotives
  local near_carriage;
  if num_locos(carriage1.train) < num_locos(carriage2.train) then
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
  elseif near_carriage == near_carriage.train.back_stock then
    initial, final, step = #carriages_to_recreate-1, 1, -1
  else
    debug_print("Near carriage isn't front or back of train")
    return
  end

  copy_carriage(near_carriage, global.dummies[1])
  local last_info = carriage_info(near_carriage)
  local new_info = last_info
  near_carriage.destroy()

  local dummy_i = 2

  for i=initial,final,step do
    local carriage = carriages_to_recreate[i]
    copy_carriage(carriage, global.dummies[dummy_i])
    dummy_i = 3-dummy_i -- cycle between 1 and 2
    new_info = carriage_info(carriage)
    carriage.destroy()

    copy_carriage(global.dummies[dummy_i], last_info)

    last_info = new_info
  end

  last_carriage = copy_carriage(global.dummies[3-dummy_i], last_info)
  advance_station(last_carriage.train)
end

-- Record the information that can't be copied to the dummy plane
function carriage_info(carriage)
  return {pos=carriage.position, orient=carriage.orientation, pass=carriage.passenger}
end

-- copy all properties of one carriage to another. 
-- passengers are moved to the target.
-- target may be:
--  an entity to replace
--  a target on nauvis: target_info={pos={x,y}, orient=orient, pass=passenger}
-- return the new carriage
function copy_carriage(source, target)
  if source.name ~= target.name then
    local target_info, surf, dummy_i;
    if target.name == nil then -- passed a set of target info
      target_info = target
      surf = game.surfaces["nauvis"]
    else -- passed an entity
      target_info = {pos=target.position, orient=target.orientation}
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

    local dir = orientation_to_direction(target_info.orient)
    target = surf.create_entity{name=source.name, force=source.force, position=target_info.pos, direction=dir} 
    target.passenger = target_info.pass

    if dummy_i then
      global.dummies[dummy_i] = target
    end
  end

  -- only copy non-empty locomotive schedules
  if next(source.train.schedule) ~= nil and source.type == "locomotive" then
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

-- send a train to the next station on its schedule
-- if there's only one station on the schedule, set it to manual to avoid infinite loop
function advance_station(train)
  debug_print("advance",math.random())
  local schedule = train.schedule
  if num_locos(train) > 0 and #schedule.records > 1 then
    schedule.current = (schedule.current)% #schedule.records + 1
    train.schedule = schedule

    train.manual_mode = false
    debug_print("manual set to false")
  else
    debug_print("manual set to true")
    train.manual_mode = true
  end
end

-- determine which "direction" to specify for create_entity to achieve a certain orientation
function orientation_to_direction(orientation)
  if orientation==0 or orientation>0.5 then
    return defines.direction.north
  else
    return defines.direction.east
  end 
end

-- count number of locomotives in a train
function num_locos(train)
  return #train.locomotives.front_movers + #train.locomotives.back_movers
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
  debug_print("Train change: State ",train.state, " Speed: ",train.speed," Mode: ",train.manual_mode)
  if train.state == defines.train_state.wait_station and train.speed == 0 then
    for id,coupler_rail in pairs(global.coupler_rails) do
      if not coupler_rail.valid then
        global.to_remove[#global.to_remove+1] = id
      else
        local carriages = {}
        local surf = game.surfaces.nauvis
        for i,dir in ipairs({defines.rail_direction.front, defines.rail_direction.back}) do
          -- find next carriage in selected direction
          for _,con_dir in ipairs({defines.rail_connection_direction.straight,
                                  defines.rail_connection_direction.left,
                                  defines.rail_connection_direction.right}) do
            local rail = coupler_rail.get_connected_rail{rail_direction=dir, rail_connection_direction=con_dir}

            local carriage = rail and (surf.find_entities_filtered{position=rail.position, type="cargo-wagon", limit=1}[1] or
                             surf.find_entities_filtered{position=rail.position, type="locomotive", limit=1}[1])
            if carriage then
              carriages[i] = carriage
              break
            end
          end
        end

        -- we're not at a coupling
        if not carriages[1] or not carriages[2] or carriages[1] == carriages[2] then
          debug_print("Not at a coupling",math.random())
          debug_print("A",carriages[1]==nil,math.random())
          debug_print("B",carriages[2]==nil,math.random())
          debug_print("C",carriages[2]==carriages[1],math.random())

        elseif carriages[1].train == train or carriages[2].train == train then

          -- are the cars coupled already?
          if carriages[1].train == carriages[2].train then
            decouple(carriages[1], carriages[2], coupler_rail)
          else
            couple(carriages[1], carriages[2])
          end

          -- just in case anyone gets stuck on the dummy plane, move them back to nauvis
          for _,player in pairs(game.players) do
            if player.surface == game.surfaces.train_coupler_dummy then
              player.teleport{position={0,0}, surface="nauvis"}
            end
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
