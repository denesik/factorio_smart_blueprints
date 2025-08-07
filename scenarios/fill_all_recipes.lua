local entity_finder = require("entity_finder")
local recipe_selector = require("recipe_selector")
local product_utils = require("product_utils")
local recipe_utils = require("recipe_utils")
local table_utils= require("table_utils")
local entity_control = require("entity_control")

function fill_all_recipes(search_area, target_name, offset)
  offset = offset or 1000000

  local dst = entity_finder.find(target_name, search_area)

  local recipes = recipe_selector.filter_by(prototypes.recipe, function(recipe_name, recipe)
    return not recipe_selector.is_hidden(recipe_name, recipe) and
           not recipe_selector.has_parameter(recipe_name, recipe) and
           recipe_selector.has_main_product(recipe_name, recipe)
  end)

  local recipe_products = recipe_utils.get_recipe_products(recipes)
  recipe_products = product_utils.merge_duplicates(recipe_products, function(a, b) return a + b end)
  table.sort(recipe_products, function(a, b) return a.min > b.min end)
  table_utils.for_each(recipe_products, function(e, i) e.min = offset + i end)

  entity_control.set_logistic_filters(dst, recipe_products)
end

return fill_all_recipes
