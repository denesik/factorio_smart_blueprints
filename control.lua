local blueprint_handler = require("tools.blueprint_handler")
local scheduler = require("common.scheduler")
local selection_tool = require("tools.selection_tool")

local DEBUG = true

local function debugLog(message)
  if DEBUG then log("[DEBUG] " .. message) end
end

local function safe_call(fn)
  return function(...)
    local success, result_or_error = pcall(fn, ...)
    if not success then
      game.print("Ошибка выполнения функции: " .. result_or_error)
      debugLog("Error: " .. result_or_error)
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

script.on_event(defines.events.on_tick, function(event)
  safe_call(scheduler.on_tick)(event)
end)

script.on_event(defines.events.on_pre_build, function(event)
  safe_call(blueprint_handler.on_pre_build)(event)
end)

script.on_event("virtual_entity_gui_close", function(event)
  safe_call(blueprint_handler.on_virtual_entity_gui_close)(event)
end)

