local scheduler = {}

local last_cleanup_tick = 0
local cleanup_interval = 120 -- очищаем каждые 120 тиков (~2 секунды)

local scheduler_tasks = {}

-- Очистка устаревших задач (периодическая)
local function cleanup_old_tasks()
  local current_tick = game.tick
  if current_tick - last_cleanup_tick >= cleanup_interval then
    local removed_count = 0
    for tick, _ in pairs(scheduler_tasks) do
      if tick < current_tick then
        scheduler_tasks[tick] = nil
        removed_count = removed_count + 1
      end
    end
    if removed_count > 0 then
      log("Scheduler cleanup: removed " .. removed_count .. " outdated tasks")
    end
    last_cleanup_tick = current_tick
  end
end

-- Планирование функции на будущее
-- delay_ticks: через сколько тиков вызвать
-- func: функция для вызова
-- ...: произвольные аргументы
function scheduler.schedule(delay_ticks, func, ...)
  cleanup_old_tasks()

  local target_tick = game.tick + delay_ticks
  scheduler_tasks[target_tick] = scheduler_tasks[target_tick] or {}
  table.insert(scheduler_tasks[target_tick], {func = func, args = {...}})
end

-- Обработчик on_tick
function scheduler.on_tick(event)
  local tasks = scheduler_tasks[event.tick]
  if tasks then
    for _, task in pairs(tasks) do
      local ok, err = pcall(task.func, table.unpack(task.args))
      if not ok then
        log("Scheduler error: " .. tostring(err))
      end
    end
    scheduler_tasks[event.tick] = nil
  end
end

return scheduler
