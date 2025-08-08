local recipe_utils = require("recipe_utils")

local product_selector = {}

function product_selector.filter_by(products, filter)
  local out = {}
  for _, product in ipairs(products) do
    if filter(product) then
      table.insert(out, product)
    end
  end
  return out
end

function product_selector.is_filtered_by_recipe(product, recipe_filter)
  local recipes = recipe_utils.get_recipes_for_product(prototypes.recipe, product)
  for recipe_name, recipe in ipairs(recipes) do
    if recipe_filter(recipe_name, recipe) then
      return true
    end
  end
  return false
end

return product_selector
