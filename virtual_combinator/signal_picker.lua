local SignalPicker = {}

local function get_storage()
    storage.signal_picker = storage.signal_picker or {}
    return storage.signal_picker
end

--------------------------------------------------------------------------------
-- 1. Формирование данных
--------------------------------------------------------------------------------

-- Собираем все прототипы
local function gather_all_protos()
    local all = {}

    for _, proto in pairs(prototypes.item) do table.insert(all, proto) end
    for _, proto in pairs(prototypes.fluid) do table.insert(all, proto) end
    for _, proto in pairs(prototypes.virtual_signal) do table.insert(all, proto) end

    -- собрать имена для фильтрации рецептов
    local used_names = {}
    for _, proto in ipairs(all) do
        used_names[proto.name] = true
    end

    for _, proto in pairs(prototypes.recipe) do
        if not used_names[proto.name] then
            table.insert(all, proto)
        end
    end

    return all
end

-- Группировка по group → subgroup
local function collect_categories(protos)
    local categories = {}

    for _, proto in ipairs(protos) do
        local group_name = proto.subgroup and proto.subgroup.group and proto.subgroup.group.name or "other"
        local subgroup_name = proto.subgroup and proto.subgroup.name or "other"

        categories[group_name] = categories[group_name] or {}
        categories[group_name][subgroup_name] = categories[group_name][subgroup_name] or {}
        table.insert(categories[group_name][subgroup_name], proto)
    end

    local grouped_categories = {}
    for group_name, subgroups in pairs(categories) do
        local subgroup_list = {}
        for subgroup_name, protos in pairs(subgroups) do
            table.insert(subgroup_list, {name=subgroup_name, protos=protos})
        end
        table.insert(grouped_categories, {group=group_name, subgroups=subgroup_list})
    end

    return grouped_categories
end

-- Публичная функция: подготовка данных
function SignalPicker.build_data()
    local all_protos = gather_all_protos()
    local grouped = collect_categories(all_protos)
    return grouped
end

--------------------------------------------------------------------------------
-- 2. GUI
--------------------------------------------------------------------------------

-- Добавление элементов в таблицу
local function add_grouped_elements(table_elem, grouped_categories)
    for _, cat in ipairs(grouped_categories) do
        for _, subgroup in ipairs(cat.subgroups) do
            for _, proto in ipairs(subgroup.protos) do
                local sprite, base_name
                if proto.type == "item" then
                    sprite = "item/"..proto.name
                    base_name = "signal_picker_"..proto.type.."_"..proto.name
                elseif proto.type == "fluid" then
                    sprite = "fluid/"..proto.name
                    base_name = "signal_picker_"..proto.type.."_"..proto.name
                elseif proto.type == "virtual-signal" then
                    sprite = "virtual-signal/"..proto.name
                    base_name = "signal_picker_"..proto.type.."_"..proto.name
                elseif proto.type == "recipe" then
                    sprite = "recipe/"..proto.name
                    base_name = "signal_picker_"..proto.type.."_"..proto.name
                end

                if sprite and not table_elem[base_name] then
                    local btn = table_elem.add{
                        type="sprite-button",
                        sprite=sprite,
                        tooltip=proto.localised_name,
                        name=base_name,
                        style="slot_button"
                    }
                    btn.style.width = 38
                    btn.style.height = 38
                end
            end

            -- выравнивание по строкам
            local count = #subgroup.protos
            local remainder = count % 10
            if remainder > 0 then
                for _ = 1, 10 - remainder do
                    table_elem.add{type = "sprite"}
                end
            end
        end
    end
end

function SignalPicker.open_1(player)
    if not (player and player.valid) then return end
    if player.gui.screen.signal_picker_window then return end

    local inv = game.create_inventory(10, "TEST")
    

    local i = 0
    --[[
    local gui = player.gui.screen.add{
        type="frame",
        name="signal_picker_window",
        direction="vertical"
    }
    gui.auto_center = true

    do
        local flow = gui.add{type="flow", direction="horizontal", style = "frame_header_flow"}
        flow.drag_target = gui
        local label = flow.add{type = "label", style = "cf_frame_title", caption = "Virtual combinator", ignored_by_interaction = true}
        local filler = flow.add{ type = "empty-widget", style = "cf_draggable_space_header", ignored_by_interaction = true}
        flow.add{
            type = "sprite-button",
            name = "signal_picker_close",
            style = "cancel_close_button",
            sprite = "utility/close",
            hovered_sprite = "utility/close_black",
            clicked_sprite = "utility/close_black",
            tooltip = {"gui.close-instruction"},
        }
    end

    local outer = (function()
        local inset_flow = gui.add{
            type = "flow",
            style = "inset_frame_container_vertical_flow",
            direction = "vertical",
        }

        local outer = inset_flow.add{
            type = "frame",
            style = "inside_deep_frame",
            direction = "vertical",
        }

        local frame = outer.add{type = "frame", direction = "vertical", style = "cf_filter_frame"}
        frame.style.right_padding = 13

        return frame
    end)()

    do
        local label = outer.add{type = "label", caption = "Output"}
        local flow =  outer.add{type = "flow", direction = "horizontal"}
        flow.add{type = "label", caption = "Disabled"}
        flow.add{type = "switch"}
        flow.add{type = "label", caption = "State"}
        outer.add{type = "line", direction = "horizontal"}
    end

    do
        local flow = outer.add{type = "flow", direction = "vertical", style = "two_module_spacing_vertical_flow"}
        --flow.style.maximal_height = 120
        local scroll = flow.add{type = "scroll-pane", direction="vertical", style = "deep_slots_scroll_pane"}
        local drag_flow = scroll.add{type = "flow", direction = "vertical", style = "packed_vertical_flow"}

        local vertical_flow = drag_flow.add{type = "flow", direction = "vertical"}
        do
            local frame = vertical_flow.add{type="frame", direction="horizontal", style = "logistic_section_subheader_frame"}
            frame.add{type = "checkbox", state = true, caption = "Section name", style = "subheader_caption_checkbox"}
            local button = frame.add{type = "sprite-button", sprite = "utility/rename_icon", style = "mini_button_aligned_to_text_vertically_when_centered"}
            button.style.width = 16
            button.style.height = 16
            local header = frame.add{ type = "empty-widget", style = "cf_draggable_space_header", ignored_by_interaction = true}
            header.drag_target = gui
            frame.add{type = "sprite-button", sprite = "utility/trash", style = "tool_button_red"}
        end

        do
            local frame = vertical_flow.add{type="frame", direction="vertical"}
            local table = frame.add{type = "table", column_count = 10, style = "filter_slot_table"}
            --scroll.style.vertically_stretchable = true

            for _, proto in pairs(prototypes.fluid) do
                local btn = table.add{
                    type = "sprite-button",
                    --sprite = "fluid/" .. proto.name,
                    style = "slot_button"
                }
                btn.style.width = 40
                btn.style.height = 40
                --btn.drag_target = frame
            end
        end
        

    end
    ]]
end

-- Создание GUI
function SignalPicker.open(player)
    if not (player and player.valid) then return end
    if player.gui.screen.signal_picker_window then return end

    local gui = player.gui.screen.add{
        type="frame",
        name="signal_picker_window",
        direction="vertical"
    }
    gui.auto_center = true

    do
        local flow = gui.add{type="flow", direction="horizontal", style = "frame_header_flow"}
        flow.drag_target = gui
        local label = flow.add{type = "label", style = "cf_frame_title", caption = "Select signal", ignored_by_interaction = true}
        local filler = flow.add{ type = "empty-widget", style = "cf_draggable_space_header", ignored_by_interaction = true}
        flow.add{
            type = "sprite-button",
            name = "signal_picker_close",
            style = "cancel_close_button",
            sprite = "utility/close",
            hovered_sprite = "utility/close_black",
            clicked_sprite = "utility/close_black",
            tooltip = {"gui.close-instruction"},
        }
    end

    local inset_flow = gui.add({
        type = "flow",
        style = "inset_frame_container_vertical_flow",
        direction = "vertical",
    })

    local outer = inset_flow.add({
        type = "frame",
        style = "inside_deep_frame",
        direction = "vertical",
    })

    do
        local frame = outer.add{type="frame", direction="vertical", style = "cf_inside_deep_frame"}
        local table = frame.add{type = "table", column_count=6, style = "filter_slot_table"}
        for _, group in pairs(prototypes.item_group) do
            local button = table.add{
                type = "sprite-button",
                sprite = "item-group/" .. group.name,
                style = "cf_filter_group_button_tab"
            }
        end
    end

    do
        local frame = outer.add{type = "frame", direction = "horizontal", style = "cf_filter_frame"}
        frame.style.height = 500
        local scroll = frame.add{type = "scroll-pane", direction="vertical", style = "deep_slots_scroll_pane",
                                 vertical_scroll_policy = "always", horizontal_scroll_policy = "never"}
        local table_elem = scroll.add{type = "table", column_count = 10, style = "filter_slot_table"}
        scroll.style.vertically_stretchable = true

        for _, proto in pairs(prototypes.fluid) do
            local btn = table_elem.add{
                type = "sprite-button",
                sprite = "fluid/" .. proto.name,
                tooltip = proto.localised_name,
                style = "slot_button"
            }
            btn.style.width = 40
            btn.style.height = 40
        end
    end

    do
        local frame = outer.add{type = "frame", direction = "horizontal", style = "subfooter_frame"}
        frame.style.horizontally_stretchable = true

        local flow = frame.add{type = "flow", direction = "horizontal", style = "player_input_horizontal_flow"}
        local packed_flow = flow.add{type = "flow", direction = "horizontal", style = "packed_horizontal_flow"}

        for _, proto in pairs(prototypes.quality) do
            local btn = packed_flow.add{
                type = "sprite-button",
                sprite = "quality/" .. proto.name,
                tooltip = proto.localised_name,
                style = "tool_button"
            }
            btn.style.width = 28
            btn.style.height = 28
        end
        local empty_widget = flow.add{ type = "empty-widget"}
        empty_widget.style.horizontally_stretchable = true
    end

    do
        local frame = inset_flow.add({type = "frame",style = "inside_shallow_frame_with_padding",direction = "horizontal"})
        local horizontal_flow = frame.add{type = "flow", direction = "horizontal", style = "two_module_spacing_horizontal_flow"}
        local input_vertical_flow = horizontal_flow.add{type = "flow", direction = "vertical", style = "two_module_spacing_vertical_flow"}
        local input_flow = input_vertical_flow.add{type = "flow", direction = "horizontal", style = "player_input_horizontal_flow"}
        local slider = input_flow.add{type = "slider"}
        slider.style.horizontally_stretchable = true
        input_flow.add{type = "text-box", style = "wide_slider_value_textfield"}
        local apply_vertical_flow = horizontal_flow.add{type = "flow", direction = "vertical", style = "two_module_spacing_vertical_flow"}
        local btn = apply_vertical_flow.add{
            type = "sprite-button",
            sprite = "utility/confirm_slot",
            style = "item_and_count_select_confirm"
        }
        btn.style.width = 28
        btn.style.height = 28
    end
    --[[
    local tabbed_pane = frame.add{type="tabbed-pane", name="signal_picker_tabs"}
    tabbed_pane.style.maximal_height = 700
    local category_tables = {}

    local function add_tab(cat_name, caption)
        if category_tables[cat_name] then
            return category_tables[cat_name]
        end
        local tab = tabbed_pane.add{type="tab", caption=caption}
        local scroll = tabbed_pane.add{type="scroll-pane", style = "deep_slots_scroll_pane"}
        scroll.style.maximal_height = 700
        tabbed_pane.add_tab(tab, scroll)
        local table_elem = scroll.add{type="table", name="table_"..cat_name, column_count=10, style="filter_slot_table"}
        category_tables[cat_name] = table_elem
        return table_elem
    end

    -- --- ВАЖНО --- теперь читаем только данные
    local grouped_data = SignalPicker.build_data()

    for _, cat in ipairs(grouped_data) do
        local table_elem = add_tab(cat.group, cat.group)
        add_grouped_elements(table_elem, {cat})
    end

    frame.add{
        type="textfield",
        name="signal_picker_count",
        text="0",
        numeric=true,
        allow_decimal=false,
        allow_negative=true
    }

    local flow = frame.add{type="flow", direction="horizontal"}
    flow.add{type="button", name="signal_picker_ok", caption="OK"}
    flow.add{type="button", name="signal_picker_cancel", caption="Cancel"}
    ]]

    get_storage()[player.index] = {
        frame = frame,
        selected = nil,
        count = 0,
        selected_button = nil
    }
end

--------------------------------------------------------------------------------
-- Остальное без изменений (close, on_gui_click, on_gui_text_changed)
--------------------------------------------------------------------------------

function SignalPicker.close(player)
    local storage_table = get_storage()
    local data = storage_table[player.index]
    if data and data.frame and data.frame.valid then
        data.frame.destroy()
    end
    storage_table[player.index] = nil
end

function SignalPicker.on_gui_click(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    local element = event.element
    if not (element and element.valid) then return end

    local data = get_storage()[player.index]
    if not data then return end
--[[
    -- Выбор сигнала
    if element.name:find("^signal_picker_") and element.name ~= "signal_picker_ok" and element.name ~= "signal_picker_cancel" then
        if data.selected_button and data.selected_button.valid then
            data.selected_button.style = "slot_button"
        end
        data.selected = element.name
        data.selected_button = element
        return
    end

    -- OK
    if element.name == "signal_picker_ok" then
        if data.selected then
            player.print("Выбран: " .. data.selected .. " x" .. data.count)
        else
            player.print("Сигнал не выбран")
        end
        SignalPicker.close(player)
        return
    end

    -- Cancel
    if element.name == "signal_picker_cancel" then
        SignalPicker.close(player)
        return
    end
    ]]
end

function SignalPicker.on_gui_text_changed(event)
    --[[
    local player = game.get_player(event.player_index)
    if not player then return end
    local element = event.element
    if not (element and element.valid) then return end

    local data = get_storage()[player.index]
    if not data then return end

    if element.name == "signal_picker_count" then
        data.count = tonumber(element.text) or 0
    end
    ]]
end

return SignalPicker
