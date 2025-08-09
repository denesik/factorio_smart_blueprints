local recipe_utils = require("recipe_utils")

local signal_selector = {}

function signal_selector.filter_by(products, filter)
  local out = {}
  for _, product in ipairs(products) do
    if filter(product) then
      table.insert(out, product)
    end
  end
  return out
end

function signal_selector.is_filtered_by_recipe_any(product, recipe_filter)
  local recipes = recipe_utils.get_recipes_for_signal(prototypes.recipe, product)
  for _, recipe in ipairs(recipes) do
    if recipe_filter(recipe.name, recipe) then
      return true
    end
  end
  return false
end

function signal_selector.is_filtered_by_recipe_all(product, recipe_filter)
  local recipes = recipe_utils.get_recipes_for_signal(prototypes.recipe, product)
  for _, recipe in ipairs(recipes) do
    if not recipe_filter(recipe.name, recipe) then
      return false
    end
  end
  return true
end

return signal_selector
