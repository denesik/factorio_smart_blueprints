local recipe_utils = {}

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
function recipe_utils.get_recipes_for_signal(recipes, signal)
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

function recipe_utils.make_signal(recipe_part, quality)
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

function recipe_utils.recipe_as_signal(recipe, quality)
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

function recipe_utils.recipes_as_signals(recipes, quality)
  quality = quality or "normal"

  local out = {}
  for _, recipe in pairs(recipes) do
    local product = recipe_utils.recipe_as_signal(recipe, quality)
    if product ~= nil then
      table.insert(out, product)
    end
  end
  return out
end

return recipe_utils
