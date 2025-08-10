local signal_utils = {}

local function shallow_copy(t)
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = v
  end
  return copy
end

function signal_utils.items_key_fn(v)
  return v.name .. "|" .. v.type .. "|" .. v.quality
end

function signal_utils.merge_max(a, b)
  return { value = a.value, min = math.max(a.min, b.min) }
end

function signal_utils.merge_sum(a, b)
  return { value = a.value, min = a.min + b.min }
end

function signal_utils.merge_depth(a, b)
  return { value = a.value, depth = math.max(a.depth, b.depth), min = math.max(a.min, b.min) }
end

--- Удаляет дубликаты по ключу, создаваемому key_fn (по умолчанию items_key_fn)
-- @param entries table Массив с элементами { value = ..., min = число }
-- @param merge_fn function Функция (existing_min, new_min) → новое значение min
-- @param key_fn function|nil Функция (value) → строковый ключ, по умолчанию items_key_fn
-- @return table Массив с объединёнными элементами без дубликатов
function signal_utils.merge_duplicates(entries, merge_fn, key_fn)
  key_fn = key_fn or signal_utils.items_key_fn

  local map = {}

  for _, entry in ipairs(entries) do
    local key = key_fn(entry.value)

    if not map[key] then
      map[key] = shallow_copy(entry)
    else
      map[key] = merge_fn(map[key], entry)
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


local quality_order = nil

local function init_quality_order()
  local qualities = {}

  for name, _ in pairs(prototypes.quality) do
    table.insert(qualities, name)
  end

  return qualities
end

function signal_utils.get_quality_index(quality_name)
  if not quality_order then
    quality_order = init_quality_order()
  end

  for i, qname in ipairs(quality_order) do
    if qname == quality_name then
      return i
    end
  end
  return 0
end

function signal_utils.get_prototype(item)
  local name = item.value.name
  local type = item.value.type

  if type == "item" then
    return prototypes.item[name]
  elseif type == "fluid" then
    return prototypes.fluid[name]
  elseif type == "recipe" then
    return prototypes.recipe[name]
  end

  return nil
end

return signal_utils
