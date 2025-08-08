local entity_finder = require("entity_finder")
local recipe_selector = require("recipe_selector")
local product_utils = require("product_utils")
local recipe_utils = require("recipe_utils")
local item_selector = require("product_selector")
local table_utils= require("table_utils")
local entity_control = require("entity_control")
local decider_conditions = require("decider_conditions")
local recipe_decomposer = require("recipe_decomposer")

function make_simple_crafter(search_area, products_to_craft_src_name, decider_dst_name, requests_dst_name, crafter_id)
  offset = offset or 1

  local Condition = decider_conditions.Condition
  local OR = Condition.OR
  local AND = Condition.AND
  local MAKE = decider_conditions.MAKE
  local EACH = decider_conditions.EACH
  local EVERYTHING = decider_conditions.EVERYTHING

  local products_to_craft_src = entity_finder.find(products_to_craft_src_name, search_area)
  local decider_dst = entity_finder.find(decider_dst_name, search_area)
  local crafter = entity_finder.find(crafter_id, search_area)
  local requester = entity_finder.find(requests_dst_name, search_area)

  local allowed_recipes = recipe_selector.filter_by(prototypes.recipe, function(recipe_name, recipe)
    return not recipe_selector.is_hidden(recipe_name, recipe) and
           not recipe_selector.has_parameter(recipe_name, recipe) and
           recipe_selector.has_main_product(recipe_name, recipe) and
           recipe_selector.can_craft_from_machine(recipe_name, recipe, crafter)
  end)

  local products_to_craft = entity_control.read_all_logistic_filters(products_to_craft_src)

  local products = recipe_decomposer.decompose(allowed_recipes, products_to_craft)
  products = product_utils.merge_duplicates(products, function(a, b) return a + b end)
  table_utils.for_each(products, function(e) if e.min < 1 then e.min = 1 end end)
  table_utils.extend(products, products_to_craft)

  local source_products = item_selector.filter_by(products, function(item)
    return item_selector.is_filtered_by_recipe(item,
      function(recipe_name, recipe)
        return not recipe_selector.can_craft_from_machine(recipe_name, recipe, crafter)
      end)
  end)
  table_utils.for_each(source_products, function(e) e.min = product_utils.get_stack_size(e) - 20 end)

  products = item_selector.filter_by(products, function(item)
    return item_selector.is_filtered_by_recipe(item,
      function(recipe_name, recipe)
        return recipe_selector.can_craft_from_machine(recipe_name, recipe, crafter)
      end)
  end)

  local tree = OR()
  for _, product in ipairs(products) do
    local recipes = recipe_utils.get_recipes_for_product(allowed_recipes, product)
    for _, recipe in ipairs(recipes) do
      local recipe_product = recipe_utils.recipe_as_product(recipe, product.value.quality)
      if recipe_product ~= nil then

        local ingredients_check = AND()
        for _, ingredient in ipairs(recipe.ingredients) do
          ingredient_product = recipe_utils.ingredient_as_product(ingredient, product.value.quality)
          ingredients_check:add_child(MAKE(ingredient_product.value, ">=", ingredient_product.min, false, true, true, true))
        end

        local forward = MAKE(EACH, "=", recipe_product.value, true, false, true, false)
        local need_produce = MAKE(product.value, "<", product_utils.get_stack_size(product) - 20, false, true, true, true)
        local first_lock = MAKE(EVERYTHING, "<", 499999, false, true, true, true)
        local second_lock = MAKE(recipe_product.value, ">", 1000000, false, true, true, true)
        local choice_priority = MAKE(EVERYTHING, "<=", recipe_product.value, false, true, true, false)

        tree:add_child(AND(forward, ingredients_check, need_produce, OR(first_lock, AND(second_lock, choice_priority))))
      end
    end
  end

  outputs = {{
    signal = EACH,
    copy_count_from_input = true,
    networks = { green = false , red = true },
  }}

  entity_control.fill_decider_combinator(decider_dst, decider_conditions.to_flat_dnf(tree), outputs)
  entity_control.set_logistic_filters(requester, source_products)
end

return make_simple_crafter
