local table_utils = require("table_utils")
local recipe_utils = require("recipe_utils")

local recipe_decomposer = {}

function recipe_decomposer.deep_strategy(recipe, product, ingredient)
  return ingredient.amount * (product.min / recipe.main_product.amount)
end

function recipe_decomposer.shallow_strategy(recipe, product, ingredient)
  return ingredient.amount
end

--- Разлагает один элемент на ингредиенты по рецепту.
-- @param recipes_for_product table Список рецептов, где main_product = product
-- @param product table Элемент для разложения
-- @return table Список ингредиентов
local function decomposition_element(recipes_for_product, product, strategy)
  local out = {}

  -- Перебираем все рецепты, у которых main_product совпадает с product
  for _, recipe in ipairs(recipes_for_product) do
    for _, ingredient in ipairs(recipe.ingredients) do
      table.insert(out, {
        value = {
          name = ingredient.name,
          type = ingredient.type,
          quality = product.value.quality
        },
        min = strategy(recipe, product, ingredient)
      })
    end
  end

  return out
end

--- Рекурсивно разлагает список предметов на ингредиенты.
-- @param recipes table Все доступные рецепты (нужны только при первом вызове)
-- @param products table Список предметов для разложения
-- @return table Список всех полученных ингредиентов
function recipe_decomposer.decompose(recipes, products, strategy)
  local out = {}

  while #products ~= 0 do
    local results = {}
    for _, product in ipairs(products) do
      local recipes_for_product = recipe_utils.get_recipes_for_signal(recipes, product)
      table_utils.extend(results, decomposition_element(recipes_for_product, product, strategy))
    end
    products = results
    table_utils.extend(out, results)
  end

  return out
end

return recipe_decomposer
