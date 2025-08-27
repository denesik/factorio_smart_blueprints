local main = require("main")
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

local function timed_call(fn, fn_name)
    return function(...)
        local start_time = game.tick
        local result = fn(...)
        local execution_time = game.tick - start_time
        debugLog("Функция [" .. fn_name .. "] выполнена за " .. execution_time .. " ticks.")
        return result
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

