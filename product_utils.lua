local product_utils = {}

local items_key_fn = function(v)
  return v.name .. "|" .. v.type .. "|" .. v.quality
end

--- Удаляет дубликаты по ключу, создаваемому key_fn (по умолчанию items_key_fn)
-- @param entries table Массив с элементами { value = ..., min = число }
-- @param merge_fn function Функция (existing_min, new_min) → новое значение min
-- @param key_fn function|nil Функция (value) → строковый ключ, по умолчанию items_key_fn
-- @return table Массив с объединёнными элементами без дубликатов
function product_utils.merge_duplicates(entries, merge_fn, key_fn)
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

function product_utils.get_stack_size(product, fluid_stack_size)
  fluid_stack_size = fluid_stack_size or 100

  if prototypes.item[product.value.name] then
    return prototypes.item[product.value.name].stack_size
  elseif prototypes.fluid[product.value.name] then
    return fluid_stack_size
  end

  return 0
end

return product_utils
