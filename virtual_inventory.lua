local VirtualInventory = {}

-- Хранилище для виртуальных комбинаторов
local function get_storage()
    storage.bp_virtual_combinators = storage.bp_virtual_combinators or {}
    return storage.bp_virtual_combinators
end

-------------------------------
-- Создание и открытие виртуального комбинатора
-- slots = количество слотов (по умолчанию 3)
-------------------------------
function VirtualInventory.open(player, slots)
    if not (player and player.valid) then return end
    local storage_table = get_storage()
    slots = slots or 3

    -- Создаём постоянный комбинатор
    local combinator = player.surface.create_entity{
        name = "constant-combinator",
        position = player.position,
        force = player.force,
        create_build_effect_smoke = false
    }
    combinator.destructible = false
    combinator.minable = false
    combinator.operable = true -- важно, чтобы GUI открылся
    combinator.active = false

    -- Сохраняем ссылку
    storage_table[player.index] = combinator

    -- Открываем GUI постоянного комбинатора
    player.opened = combinator
end

-------------------------------
-- Чтение данных из виртуального комбинатора
-------------------------------
function VirtualInventory.read(player)
    if not (player and player.valid) then return {} end
    local storage_table = get_storage()
    local combinator = storage_table[player.index]
    if not combinator or not combinator.valid then return {} end

    local behavior = combinator.get_or_create_control_behavior()
    local data = {}

    if behavior and behavior.valid then
        for i = 1, 3 do
            local sig = behavior.get_signal(i)
            if sig then
                data[i] = {signal = sig.signal, value = sig.count}
            end
        end
    end

    return data
end

-------------------------------
-- Закрытие виртуального комбинатора
-------------------------------
function VirtualInventory.close(player)
    if not (player and player.valid) then return end
    local storage_table = get_storage()
    local combinator = storage_table[player.index]
    if combinator and combinator.valid then
        combinator.destroy()
    end
    storage_table[player.index] = nil
end

return VirtualInventory
