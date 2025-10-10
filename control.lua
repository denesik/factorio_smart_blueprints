local blueprint_handler = require("tools.blueprint_handler")
local scheduler = require("llib.scheduler")
local selection_tool = require("tools.selection_tool")
local ScenariosLibrary = require("scenarios_library")

local function safe_call(fn)
  return function(...)
    local success, result_or_error = pcall(fn, ...)
    if not success then
      game.print("Ошибка выполнения функции: " .. result_or_error)
      return nil
    end
    return result_or_error
  end
end

script.on_event(defines.events.on_lua_shortcut, function(event)
  safe_call(selection_tool.on_lua_shortcut)(event)
end)

script.on_event(defines.events.on_player_selected_area, function(event)
  safe_call(selection_tool.on_player_selected_area)(event)
end)

script.on_event(defines.events.on_player_alt_selected_area, function(event)
  safe_call(selection_tool.on_player_alt_selected_area)(event)
end) 

script.on_event(defines.events.on_tick, function(event)
  safe_call(scheduler.on_tick)(event)
end)

script.on_event(defines.events.on_pre_build, function(event)
  safe_call(blueprint_handler.on_pre_build)(event)
end)

script.on_event("virtual_entity_gui_close", function(event)
  safe_call(blueprint_handler.on_virtual_entity_gui_close)(event)
end)

commands.add_command("sb_run_tests", "Запустить тесты сценариев. Можно указать имя сценария.", function(command)
  local player = game.get_player(command.player_index)
  if not player then
    game.print("Эта команда должна вызываться игроком!")
    return
  end

  local arg = command.parameter
  if arg and arg ~= "" then
    ScenariosLibrary:run_test(player, arg)
  else
    ScenariosLibrary:run_tests(player)
  end
end)

