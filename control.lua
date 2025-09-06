require("virtual_entity.control")

local main = require("main")

local blueprint_handler = require("blueprint_handler")

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

-- Обработка нажатия на Shortcut Bar кнопку
script.on_event(defines.events.on_lua_shortcut, function(event)
    if event.prototype_name == "rolling_button" then
        local player = game.get_player(event.player_index)
        if player and player.valid then
            if not player.cursor_stack.valid_for_read then
                player.cursor_stack.set_stack{name = "area-selection-tool"}
                player.print("Выдели область инструментом.")
            end
        end
    end
end)

-- Обработка выделения области инструментом
script.on_event(defines.events.on_player_selected_area, function(event)
    if event.item == "area-selection-tool" then
        local area = event.area
        local search_area = {
            {area.left_top.x, area.left_top.y},
            {area.right_bottom.x, area.right_bottom.y}
        }
        safe_call(main)(event.area)
    end
end)


script.on_event(defines.events.on_pre_build, safe_call(blueprint_handler.on_pre_build))
script.on_event(defines.events.on_gui_click, safe_call(blueprint_handler.on_gui_click))
