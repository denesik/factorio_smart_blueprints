local game_utils = {}

local function shallow_copy(t)
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = v
  end
  return copy
end

function game_utils.items_key_fn(v)
  return v.name .. "|" .. v.type .. "|" .. v.quality
end

function game_utils.merge_max(a, b)
  return { value = a.value, min = math.max(a.min, b.min) }
end

function game_utils.merge_sum(a, b)
  return { value = a.value, min = a.min + b.min }
end

function game_utils.merge_depth(a, b)
  return { value = a.value, depth = math.max(a.depth, b.depth), min = math.max(a.min, b.min) }
end

--- Удаляет дубликаты по ключу, создаваемому key_fn (по умолчанию items_key_fn)
-- @param entries table Массив с элементами { value = ..., min = число }
-- @param merge_fn function Функция (existing_min, new_min) → новое значение min
-- @param key_fn function|nil Функция (value) → строковый ключ, по умолчанию items_key_fn
-- @return table Массив с объединёнными элементами без дубликатов
function game_utils.merge_duplicates(entries, merge_fn, key_fn)
  key_fn = key_fn or game_utils.items_key_fn

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

function game_utils.get_stack_size(signal, fluid_stack_size)
  fluid_stack_size = fluid_stack_size or 100

  local name = signal.value.name
  if prototypes.item[name] then
    return prototypes.item[name].stack_size
  elseif prototypes.fluid[name] then
    return fluid_stack_size
  end

  return 0
end

function game_utils.correct_signal(signal)
  local name = signal.value.name
  if prototypes.fluid[name] then
    signal.value.quality = "normal"
  end
  return signal
end

local quality_order = nil

local function init_quality_order()
  local qualities = {}

  for name, _ in pairs(prototypes.quality) do
    table.insert(qualities, name)
  end

  return qualities
end

function game_utils.get_all_qualities()
  if not quality_order then
    quality_order = init_quality_order()
  end
  return quality_order
end

function game_utils.get_quality_index(quality_name)
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

function game_utils.get_all_better_qualities(quality)
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

function game_utils.is_fluid(item)
  return item.value.type == "fluid"
end

function game_utils.get_prototype(item)
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


-- Локальный кеш индекса item_name → {recipes}
local _recipe_index = nil

--- Внутренняя функция для построения полного индекса по всем рецептам
-- @param all_recipes table Список всех рецептов
local function _build_index(all_recipes)
  local index = {}
  for _, recipe in pairs(all_recipes) do
    if recipe.main_product and recipe.main_product.name then
      local name = recipe.main_product.name
      index[name] = index[name] or {}
      table.insert(index[name], recipe)
    end
  end
  return index
end

--- Возвращает список рецептов для указанного продукта,
-- отфильтрованных по переданному набору `recipes`.
-- @param recipes table Ограниченный список доступных рецептов (ключи — имена)
-- @param item_name string Имя продукта
-- @return table|nil Список рецептов или nil, если нет
function game_utils.get_recipes_for_signal(recipes, signal)
  -- Строим полный индекс один раз
  if not _recipe_index then
    _recipe_index = _build_index(prototypes.recipe)
  end

  local filtered = {}

  for _, recipe in ipairs(_recipe_index[signal.value.name] or {}) do
    if recipes[recipe.name] then
      table.insert(filtered, recipe)
    end
  end

  return filtered
end

function game_utils.make_signal(recipe_part, quality)
  quality = quality or "normal"

  return {
    value = {
      name = recipe_part.name,
      type = recipe_part.type,
      quality = quality
    },
    min = recipe_part.amount
  }
end

function game_utils.recipe_as_signal(recipe, quality)
  quality = quality or "normal"

  if recipe.main_product == nil then
    return nil
  end

  return {
    value = {
      name = recipe.name,
      type = "recipe",
      quality = quality
    },
    min = recipe.main_product.amount
  }
end

function game_utils.recipes_as_signals(recipes, quality)
  quality = quality or "normal"

  local out = {}
  for _, recipe in pairs(recipes) do
    local product = game_utils.recipe_as_signal(recipe, quality)
    if product ~= nil then
      table.insert(out, product)
    end
  end
  return out
end

function game_utils.get_first_recipe_signal(allowed_recipes, item)
  local recipes = game_utils.get_recipes_for_signal(allowed_recipes, item)
  for _, recipe in ipairs(recipes) do
    return game_utils.recipe_as_signal(recipe, item.value.quality)
  end
  return nil
end

return game_utils
