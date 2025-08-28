local SignalPicker = {}

local function get_storage()
    storage.signal_picker = storage.signal_picker or {}
    return storage.signal_picker
end

-- 1. Собираем все прототипы
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

-- 2. Группировка по group → subgroup
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

-- 3. Формирование GUI элементов
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
                    local empty_slot = table_elem.add{
                        type = "sprite",
                        --sprite = "utility/slot",
                        --sprite = "utility/slot",
                        --enabled = true,
                        --style = "slot_button_in_shallow_frame"
                    }
                end
            end
        end
    end
end

-- Создание GUI
function SignalPicker.open(player)
    if not (player and player.valid) then return end
    if player.gui.screen.signal_picker_window then return end

    local frame = player.gui.screen.add{
        type="frame",
        name="signal_picker_window",
        caption="Выбор сигнала",
        direction="vertical"
    }
    frame.auto_center = true

    local tabbed_pane = frame.add{type="tabbed-pane", name="signal_picker_tabs"}
    tabbed_pane.style.maximal_height = 700
--    tabbed_pane.sprite = "utility/slots_view"
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

    local all_protos = gather_all_protos()
    local grouped = collect_categories(all_protos)

    -- создаем вкладки по группам
    for _, cat in ipairs(grouped) do
        local table_elem = add_tab(cat.group, cat.group)
        add_grouped_elements(table_elem, {cat})
    end

    -- текстовое поле для числа
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

    get_storage()[player.index] = {
        frame = frame,
        selected = nil,
        count = 0,
        selected_button = nil
    }
end

-- Закрытие окна
function SignalPicker.close(player)
    local storage_table = get_storage()
    local data = storage_table[player.index]
    if data and data.frame and data.frame.valid then
        data.frame.destroy()
    end
    storage_table[player.index] = nil
end

-- Обработка кликов
function SignalPicker.on_gui_click(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    local element = event.element
    if not (element and element.valid) then return end

    local data = get_storage()[player.index]
    if not data then return end

    -- Выбор сигнала
    if element.name:find("^signal_picker_") and element.name ~= "signal_picker_ok" and element.name ~= "signal_picker_cancel" then
        if data.selected_button and data.selected_button.valid then
            data.selected_button.style = "slot_button"
        end
        --element.style = "selected_slot_button"
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
end

-- Обработка изменения числа
function SignalPicker.on_gui_text_changed(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    local element = event.element
    if not (element and element.valid) then return end

    local data = get_storage()[player.index]
    if not data then return end

    if element.name == "signal_picker_count" then
        data.count = tonumber(element.text) or 0
    end
end

return SignalPicker
