local BlueprintHandler = {}

local TARGET_BLUEPRINT_NAME = "<make_simple_rolling>"

-- Получаем таблицу для хранения данных модом
local function get_storage()
    storage.blueprint_installation = storage.blueprint_installation or {}
    return storage.blueprint_installation
end

-------------------------------
-- GUI
-------------------------------
function BlueprintHandler.open_signal_gui(player)
    if player.gui.center.bp_signals_frame then
        player.gui.center.bp_signals_frame.destroy()
    end
    local frame = player.gui.center.add{type="frame", name="bp_signals_frame", caption="Настройка сигналов", direction="vertical"}
    frame.add{type="label", caption="Сигнал 1:"}
    frame.add{type="textfield", name="signal_1", text=""}
    frame.add{type="label", caption="Сигнал 2:"}
    frame.add{type="textfield", name="signal_2", text=""}
    frame.add{type="label", caption="Сигнал 3:"}
    frame.add{type="textfield", name="signal_3", text=""}
    frame.add{type="button", name="apply_bp_signals", caption="Применить"}
end

local function get_signals_from_gui(player)
    local frame = player.gui.center.bp_signals_frame
    if not frame then return {} end
    return {frame.signal_1.text, frame.signal_2.text, frame.signal_3.text}
end

local function get_blueprint_area(entities)
    if #entities == 0 then return nil end
    local x_min, x_max = entities[1].position.x, entities[1].position.x
    local y_min, y_max = entities[1].position.y, entities[1].position.y
    for _, ent in pairs(entities) do
        local pos = ent.position
        if pos.x < x_min then x_min = pos.x end
        if pos.x > x_max then x_max = pos.x end
        if pos.y < y_min then y_min = pos.y end
        if pos.y > y_max then y_max = pos.y end
    end
    return {{x_min, y_min}, {x_max, y_max}}
end

-------------------------------
-- События
-------------------------------
function BlueprintHandler.on_built_entity(event)
    local storage_table = get_storage()

    local ent = event.entity
    if not ent or not ent.valid then return end
    local player_index = event.player_index or (event.robot and event.robot.owner.index)
    if not player_index then return end
    local player = game.get_player(player_index)

    local stack = event.stack
    local bp_name = stack and stack.valid_for_read and stack.is_blueprint and stack.label or "unknown"
    if bp_name ~= TARGET_BLUEPRINT_NAME then return end

    storage_table[player_index] = storage_table[player_index] or {}
    storage_table[player_index].entities = storage_table[player_index].entities or {}
    table.insert(storage_table[player_index].entities, ent)

    if not storage_table[player_index].gui_opened then
        BlueprintHandler.open_signal_gui(player)
        storage_table[player_index].gui_opened = true
    end
end

function BlueprintHandler.on_gui_click(event)
    local storage_table = get_storage()
    local element = event.element
    local player_index = event.player_index
    local player = game.get_player(player_index)
    if not element or not element.valid then return end

    if element.name == "apply_bp_signals" then
        local data = storage_table[player_index]
        if not data or not data.entities then return end

        local signals = get_signals_from_gui(player)
        local area = get_blueprint_area(data.entities)

        if area then
            if BlueprintHandler.make_simple_rolling then
                BlueprintHandler.make_simple_rolling(area, signals)
            else
                game.print("make_simple_rolling не определена")
            end
        end

        if player.gui.center.bp_signals_frame then
            player.gui.center.bp_signals_frame.destroy()
        end

        storage_table[player_index] = nil
    end
end

-------------------------------
-- Заглушка функции make_simple_rolling
-------------------------------
BlueprintHandler.make_simple_rolling = function(area, signals)
    game.print("Область: " .. serpent.line(area))
    game.print("Сигналы: " .. table.concat(signals, ", "))
end

return BlueprintHandler
