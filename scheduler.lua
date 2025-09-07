-- scheduler.lua
-- Универсальный планировщик вызовов через N тиков

local Scheduler = {}

-- TODO: использовать storage?
local scheduled_tasks = {}

-- Инициализация глобальной таблицы задач
local function init_storage()
    
end

-- Планирование функции на будущее
-- delay_ticks: через сколько тиков вызвать
-- func: функция для вызова
-- data: произвольные данные, передаются в func
function Scheduler.schedule(delay_ticks, func, data)
    local target_tick = game.tick + delay_ticks
    scheduled_tasks[target_tick] = scheduled_tasks[target_tick] or {}
    table.insert(scheduled_tasks[target_tick], {func = func, data = data})
end

-- Обработчик on_tick
local function on_tick(event)
    local tasks = scheduled_tasks[event.tick]
    if tasks then
        for _, task in pairs(tasks) do
            -- безопасный вызов (на всякий случай, чтобы не падал мод)
            local ok, err = pcall(task.func, task.data)
            if not ok then
                log("Scheduler error: " .. tostring(err))
            end
        end
        scheduled_tasks[event.tick] = nil
    end
end

-- Регистрируем обработчики
function Scheduler.register()
    script.on_init(init_storage)
    script.on_load(function()
        script.on_event(defines.events.on_tick, on_tick)
    end)
    script.on_configuration_changed(init_storage)
    script.on_event(defines.events.on_tick, on_tick)
end

return Scheduler
