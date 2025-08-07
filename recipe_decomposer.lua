--- Модуль разложения предметов на ингредиенты по рецептам.
-- Предоставляет функции для рекурсивного разложения списка предметов по рецептам на их составляющие.

local table_utils = require("table_utils")

local recipe_decomposer = {}

--- Разлагает один элемент на ингредиенты по рецепту.
-- Использует `item.value.name` для нахождения рецепта, соответствующего `main_product`.
-- Масштабирует количество ингредиентов пропорционально `item.min`.
-- @param recipe_index table Индекс рецептов по имени основного продукта: `{ [product_name] = recipe }`.
-- @param item table Элемент для разложения. Ожидает структуру:
--   {
--     value = { name = string, type = string, quality = any },
--     min = number
--   }
-- @return table Список ингредиентов, полученных из разложения.
local function decomposition_element(recipe_index, item)
  local out = {}
  if item.min <= 0 then
    return out
  end

  local recipe = recipe_index[item.value.name]
  if not recipe then
    return out
  end

  local multiplier = item.min / recipe.main_product.amount
  for _, ingredient in ipairs(recipe.ingredients) do
    table.insert(out, {
      value = {
        name = ingredient.name,
        type = ingredient.type,
        quality = item.value.quality
      },
      min = ingredient.amount * multiplier
    })
  end

  return out
end

--- Рекурсивно разлагает список предметов на ингредиенты по доступным рецептам.
-- Использует `main_product.name` для сопоставления рецепта с предметом.
-- Работает в несколько итераций, пока есть элементы для разложения.
-- @param recipes table Список всех доступных рецептов.
-- @param items table Список предметов для разложения. Каждый элемент должен быть:
--   {
--     value = { name = string, type = string, quality = any },
--     min = number
--   }
-- @return table Список всех полученных ингредиентов.
function recipe_decomposer.decompose(recipes, items)
  local recipe_index = (function()
    local index = {}
    for _, recipe in pairs(recipes) do
      if recipe.main_product and recipe.main_product.name then
        index[recipe.main_product.name] = recipe
      end
    end
    return index
  end)()

  local out = {}

  while #items ~= 0 do
    local results = {}
    for _, filter in ipairs(items) do
      table_utils.extend(results, decomposition_element(recipe_index, filter))
    end
    items = results
    table_utils.extend(out, results)
  end

  return out
end

return recipe_decomposer
