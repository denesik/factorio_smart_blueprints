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


local SignalPicker = require("signal_picker")

-- Открыть окно по команде
commands.add_command("my_inv", "Открыть окно выбора сигнала", function(cmd)
    local player = game.get_player(cmd.player_index)
    SignalPicker.open(player)
end)

-- Подписка на клики
script.on_event(defines.events.on_gui_click, SignalPicker.on_gui_click)




local function make_row(pane, prefix, inset, count)
  local panel
  if inset then
    panel = pane.add({ type = "frame", style = "filter_frame" })
  else
    panel = pane.add({ type = "flow" })
  end
  panel.style.top_margin = 12
  local colors = { "default", "grey", "red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink" }
  i = 1
  for _, color in pairs(colors) do
    if i < count then
        panel.add({ type = "sprite-button", style = prefix .. color, sprite = "item/stone-brick" })
    end
    i = i + 1
  end
end

script.on_event(defines.events.on_player_created, function(e)
  local player = game.get_player(e.player_index)
  if not player then
    return
  end
  local frame = player.gui.screen.add({ type = "frame", name = "flib_test_frame", caption = "Slots" })
  frame.auto_center = true

  local inner = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  inner.style.top_padding = 0

  make_row(inner, "flib_slot_", false, 2)
  make_row(inner, "flib_selected_slot_", false, 3)
  make_row(inner, "flib_slot_button_", true, 4)
  make_row(inner, "flib_selected_slot_button_", true, 5)
  make_row(inner, "flib_standalone_slot_button_", false, 4)
  make_row(inner, "flib_selected_standalone_slot_button_", false, 3)
end)