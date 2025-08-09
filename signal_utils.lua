local signal_utils = {}

local items_key_fn = function(v)
  return v.name .. "|" .. v.type .. "|" .. v.quality
end

--- Удаляет дубликаты по ключу, создаваемому key_fn (по умолчанию items_key_fn)
-- @param entries table Массив с элементами { value = ..., min = число }
-- @param merge_fn function Функция (existing_min, new_min) → новое значение min
-- @param key_fn function|nil Функция (value) → строковый ключ, по умолчанию items_key_fn
-- @return table Массив с объединёнными элементами без дубликатов
function signal_utils.merge_duplicates(entries, merge_fn, key_fn)
  key_fn = key_fn or items_key_fn

  local map = {}

  for _, entry in ipairs(entries) do
    local key = key_fn(entry.value)

    if not map[key] then
      -- Копируем структуру
      map[key] = {
        value = entry.value,
        min = entry.min
      }
    else
      map[key].min = merge_fn(map[key].min, entry.min)
    end
  end

  -- Преобразуем результат в массив
  local result = {}
  for _, v in pairs(map) do
    table.insert(result, v)
  end

  return result
end

function signal_utils.get_stack_size(signal, fluid_stack_size)
  fluid_stack_size = fluid_stack_size or 100
  
  local name = signal.value.name
  if prototypes.item[name] then
    return prototypes.item[name].stack_size
  elseif prototypes.fluid[name] then
    return fluid_stack_size
  end

  return 0
end

function signal_utils.correct_signal(signal)
  local name = signal.value.name
  if prototypes.fluid[name] then
    signal.value.quality = "normal"
  end
  return signal
end

return signal_utils
