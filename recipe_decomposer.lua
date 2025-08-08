local table_utils = require("table_utils")
local recipe_utils = require("recipe_utils")

local recipe_decomposer = {}

--- Разлагает один элемент на ингредиенты по рецепту.
-- @param recipes_for_product table Список рецептов, где main_product = product
-- @param product table Элемент для разложения
-- @return table Список ингредиентов
local function decomposition_element(recipes_for_product, product)
  local out = {}
  if product.min <= 0 then
    return out
  end

  -- Перебираем все рецепты, у которых main_product совпадает с product
  for _, recipe in ipairs(recipes_for_product) do
    local multiplier = product.min / recipe.main_product.amount
    for _, ingredient in ipairs(recipe.ingredients) do
      table.insert(out, {
        value = {
          name = ingredient.name,
          type = ingredient.type,
          quality = product.value.quality
        },
        min = ingredient.amount * multiplier
      })
    end
  end

  return out
end

--- Рекурсивно разлагает список предметов на ингредиенты.
-- @param recipes table Все доступные рецепты (нужны только при первом вызове)
-- @param products table Список предметов для разложения
-- @return table Список всех полученных ингредиентов
function recipe_decomposer.decompose(recipes, products)
  local out = {}

  while #products ~= 0 do
    local results = {}
    for _, product in ipairs(products) do
      local recipes_for_product = recipe_utils.get_recipes_for_product(recipes, product)
      table_utils.extend(results, decomposition_element(recipes_for_product, product))
    end
    products = results
    table_utils.extend(out, results)
  end

  return out
end

return recipe_decomposer
