function copyPrototype(type, name, newName)
  if not data.raw[type][name] then error("type "..type.." "..name.." doesn't exist") end
  local p = table.deepcopy(data.raw[type][name])
  p.name = newName
  if p.minable and p.minable.result then
    p.minable.result = newName
  end
  if p.place_result then
    p.place_result = newName
  end
  if p.result then
    p.result = newName
  end
  return p
end

function debug_active(...)
  -- can be called everywhere, except in on_load where game is not existing
  local s = ""

  for i, v in ipairs({...}) do
    s = s .. tostring(v)
  end

  s = mod_name .. "(" .. game.tick .. "): " .. s
  game.write_file(debug_file, s .. "\n", true)
  
  if debug_status > 1 then
    for _, player in pairs(game.players) do
      if player.connected then player.print(s) end
    end
  end
end

if debug_status and debug_status > 0 then debug_print = debug_active else debug_print = function() end end