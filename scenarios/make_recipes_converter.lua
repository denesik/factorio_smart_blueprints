local entity_finder = require("entity_finder")
local recipe_selector = require("recipe_selector")
local product_utils = require("product_utils")
local recipe_utils = require("recipe_utils")
local table_utils= require("table_utils")
local entity_control = require("entity_control")
local decider_conditions = require("decider_conditions")

function make_recipes_converter(search_area, constant_name, decider_name, offset)
  offset = offset or 1

  local Condition = decider_conditions.Condition
  local OR = Condition.OR
  local AND = Condition.AND
  local MAKE = decider_conditions.MAKE
  local EACH = decider_conditions.EACH

  local constant_dst = entity_finder.find(constant_name, search_area)
  local decider_dst = entity_finder.find(decider_name, search_area)

  local recipes = recipe_selector.filter_by(prototypes.recipe, function(recipe_name, recipe)
    return not recipe_selector.is_hidden(recipe_name, recipe) and
           not recipe_selector.has_parameter(recipe_name, recipe) and
           recipe_selector.has_main_product(recipe_name, recipe)
  end)

  local recipe_products = recipe_utils.recipes_as_products(recipes)
  recipe_products = product_utils.merge_duplicates(recipe_products, function(a, b) return a + b end)
  table.sort(recipe_products, function(a, b) return a.min > b.min end)
  table_utils.for_each(recipe_products, function(e, i) e.min = offset + i end)

  local tree = OR()
  for _, recipe_product in ipairs(recipe_products) do
    local product = prototypes.recipe[recipe_product.value.name].main_product
    if product ~= nil then
      local forward = MAKE(EACH, "=", recipe_product.value, true, false, true, false)
      local condition = MAKE(product, "!=", 0, false, true, true, true)
      tree:add_child(AND(forward, condition))
    end
  end

  outputs = {{
    signal = EACH,
    copy_count_from_input = true,
    networks = { green = false , red = true },
  }}

  entity_control.set_logistic_filters(constant_dst, recipe_products)
  entity_control.fill_decider_combinator(decider_dst, decider_conditions.to_flat_dnf(tree), outputs)
end

return make_recipes_converter
