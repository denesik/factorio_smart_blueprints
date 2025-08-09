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

function signal_utils.is_fluid(signal)
  local name = signal.value.name
  if prototypes.fluid[name] then
    return true
  end
  return false
end

function signal_utils.correct_signal(signal)
  local name = signal.value.name
  if prototypes.fluid[name] then
    signal.value.quality = "normal"
  end
  return signal
end

function signal_utils.get_all_better_qualities(quality)
  local qualities = {}
  for _, proto in pairs(prototypes.quality) do
    if not proto.hidden then
      table.insert(qualities, proto)
    end
  end

  -- сортируем по order (как в игре)
  table.sort(qualities, function(a, b)
    return a.order < b.order
  end)

  local betters = {}
  local found = false
  for _, q in ipairs(qualities) do
    if found then
      table.insert(betters, q.name)
    elseif q.name == quality then
      found = true
    end
  end

  return betters
end

function signal_utils.to_map(signals)
  local map = {}
  for _, sig in ipairs(signals) do
    if sig.value and sig.value.name then
      map[sig.value.name] = sig
    end
  end
  return map
end

return signal_utils
