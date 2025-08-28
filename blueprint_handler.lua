local VirtualInventory = require("virtual_inventory")

local BlueprintHandler = {}
local TARGET_BLUEPRINT_NAME = "<make_simple_rolling>"

-- Состояние игроков
local function get_storage()
    storage.blueprint_installation = storage.blueprint_installation or {}
    return storage.blueprint_installation
end

-------------------------------
-- Расчёт BBox
-------------------------------
local function get_blueprint_bbox(stack, position, direction, flip_horizontal, flip_vertical)
    if not (stack and stack.valid and stack.valid_for_read) then return nil end

    local entities = nil
    local ok, result = pcall(function()
        return stack.get_blueprint_entities and stack.get_blueprint_entities()
    end)
    if ok then entities = result end
    if not entities or #entities == 0 then return nil end

    local x_min, x_max, y_min, y_max = nil, nil, nil, nil
    for _, ent in pairs(entities) do
        if ent and ent.position then
            local x = ent.position.x or 0
            local y = ent.position.y or 0
            x_min = (x_min == nil or x < x_min) and x or x_min
            x_max = (x_max == nil or x > x_max) and x or x_max
            y_min = (y_min == nil or y < y_min) and y or y_min
            y_max = (y_max == nil or y > y_max) and y or y_max
        end
    end

    if not (x_min and x_max and y_min and y_max) then return nil end

    local center_x = (x_min + x_max) / 2
    local center_y = (y_min + y_max) / 2

    local corners = {
        {x_min - center_x, y_min - center_y},
        {x_min - center_x, y_max - center_y},
        {x_max - center_x, y_min - center_y},
        {x_max - center_x, y_max - center_y},
    }

    direction = direction or defines.direction.north
    flip_horizontal = flip_horizontal or false
    flip_vertical = flip_vertical or false

    local x_min_r, x_max_r, y_min_r, y_max_r = nil, nil, nil, nil

    for _, corner in pairs(corners) do
        local x, y = corner[1], corner[2]
        if flip_horizontal then x = -x end
        if flip_vertical then y = -y end

        local x_rot, y_rot
        if direction == defines.direction.north then
            x_rot, y_rot = x, y
        elseif direction == defines.direction.east then
            x_rot, y_rot = y, -x
        elseif direction == defines.direction.south then
            x_rot, y_rot = -x, -y
        elseif direction == defines.direction.west then
            x_rot, y_rot = -y, x
        end

        x_min_r = (x_min_r == nil or x_rot < x_min_r) and x_rot or x_min_r
        x_max_r = (x_max_r == nil or x_rot > x_max_r) and x_rot or x_max_r
        y_min_r = (y_min_r == nil or y_rot < y_min_r) and y_rot or y_min_r
        y_max_r = (y_max_r == nil or y_rot > y_max_r) and y_rot or y_max_r
    end

    position = position or {x = 0, y = 0}
    return {
        {x_min_r + position.x, y_min_r + position.y},
        {x_max_r + position.x, y_max_r + position.y}
    }
end

-------------------------------
-- Нарисовать BBox
-------------------------------
local function draw_bbox(player, bbox, duration_ticks)
    if not (bbox and #bbox == 2 and player and player.valid) then return end
    local left_top, right_bottom = bbox[1], bbox[2]
    local color = {r=0, g=1, b=0, a=0.5}

    local object = rendering.draw_rectangle{
        color = color,
        width = 0.05,
        filled = false,
        left_top = {left_top[1], left_top[2]},
        right_bottom = {right_bottom[1], right_bottom[2]},
        surface = player.surface,
        players = {player.index}
    }

    if object.valid then
        local destroy_tick = game.tick + (duration_ticks or 180)
        script.on_event(defines.events.on_tick, function(event)
            if game.tick >= destroy_tick then
                object.destroy()
                script.on_event(defines.events.on_tick, nil)
            end
        end)
    end
end

-------------------------------
-- on_pre_build: открываем виртуальный инвентарь
-------------------------------
function BlueprintHandler.on_pre_build(event)
    if not (event and event.player_index and event.position) then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end

    local stack = player.cursor_stack
    if not (stack and stack.valid and stack.valid_for_read) then return end
    if stack.label ~= TARGET_BLUEPRINT_NAME then return end

    local storage_table = get_storage()
    storage_table[event.player_index] = storage_table[event.player_index] or {}

    if not storage_table[event.player_index].inventory_opened then
        VirtualInventory.open(player, 3)
        storage_table[event.player_index].inventory_opened = true
    end

    storage.blueprint_installation = storage_table

    local bbox = get_blueprint_bbox(stack, event.position, event.direction, event.flip_horizontal, event.flip_vertical)
    if bbox then
        game.print("BBox чертежа: " .. serpent.line(bbox))
        draw_bbox(player, bbox, 180)
    end
end

-------------------------------
-- on_gui_closed: читаем данные из виртуального инвентаря
-------------------------------
script.on_event(defines.events.on_gui_closed, function(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end

    local storage_table = get_storage()
    local state = storage_table[event.player_index]
    if not state or not state.inventory_opened then return end

    local signals = VirtualInventory.read(player)
    VirtualInventory.close(player)

    if BlueprintHandler.make_simple_rolling then
        pcall(BlueprintHandler.make_simple_rolling, nil, signals)
    end

    storage_table[event.player_index] = nil
end)

-------------------------------
-- Заглушка make_simple_rolling
-------------------------------
BlueprintHandler.make_simple_rolling = function(area, signals)
    for i, s in ipairs(signals or {}) do
        local sig_name = s.signal or "nil"
        local value = s.value or 0
        game.print("Сигнал "..i..": "..sig_name.." = "..value)
    end
end

return BlueprintHandler
