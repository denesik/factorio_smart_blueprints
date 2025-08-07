local entity_finder = require("entity_finder")
local entity_control = require("entity_control")
local logistic_filters = require("logistic_filters")
local recipe_selector = require("recipe_selector")
local recipe_decomposer = require("recipe_decomposer")
local product_utils = require("product_utils")
local conditions = require("conditions")
local table_utils= require("table_utils")
local item_selector = require("product_selector")
local recipe_utils = require("recipe_utils")
local Condition = conditions.Condition

local function process_decider_combinator(target)
  if not target or not target.valid then
    error("Invalid object for 'process_decider_combinator'")
    return {}
  end

  local controller = entity_control.get_control_interface(target)
  if not controller then
    return {}
  end

  return {}
end

local function main()


  local a = { first_signal={type="item",name="a"}, comparator="=", second_signal={type="virtual",name="signal-A"}, first_signal_networks={}, second_signal_networks={} }
  local b = { first_signal={type="item",name="b"}, comparator="=", second_signal={type="virtual",name="signal-B"}, first_signal_networks={}, second_signal_networks={} }
  local c = { first_signal={type="item",name="c"}, comparator="<", second_signal={type="virtual",name="signal-C"}, first_signal_networks={}, second_signal_networks={} }
  local d = { first_signal={type="item",name="d"}, comparator="<", second_signal={type="virtual",name="signal-D"}, first_signal_networks={}, second_signal_networks={} }
  local e = { first_signal={type="item",name="e"}, comparator="<", second_signal={type="virtual",name="signal-E"}, first_signal_networks={}, second_signal_networks={} }
  local f = { first_signal={type="item",name="f"}, comparator="<", second_signal={type="virtual",name="signal-F"}, first_signal_networks={}, second_signal_networks={} }
  local j = { first_signal={type="item",name="j"}, comparator="<", second_signal={type="virtual",name="signal-J"}, first_signal_networks={}, second_signal_networks={} }

  local tree = Condition._and(
    a, b, c,
    Condition._or(d, Condition._and(e, f), j)
  )

  local flat_conditions = conditions.to_flat_dnf(tree)

  local search_area = {}
  if area == nil then
    search_area = { { 0, 0 }, { 100, 100 } }
  else
    search_area = area
  end

  local crafter = entity_finder.find(999, search_area)

  local recipes = prototypes.recipe
  local entities = prototypes.entity
  local machine = crafter and entities[crafter.name]

  recipes = recipe_selector.filter_by(recipes, function(recipe_name, recipe)
    return not recipe_selector.is_hidden(recipe_name, recipe) and
           not recipe_selector.has_parameter(recipe_name, recipe) and
           recipe_selector.has_main_product(recipe_name, recipe) and
           recipe_selector.can_craft_from_machine(recipe_name, recipe, machine)
  end)

  local src_products_to_craft = entity_finder.find("<src_logistic_filters>", search_area)
  local dst = entity_finder.find("<dst_logistic_filters>", search_area)
  local decider_combinator = entity_finder.find("<decider_combinator>", search_area)

  process_decider_combinator(decider_combinator)

  local products_to_craft = logistic_filters.read_all_filters(src_products_to_craft)

  local products = {}
  products = recipe_utils.get_all_products(recipe_selector.filter_by(prototypes.recipe, function(recipe_name, recipe)
    return not recipe_selector.is_hidden(recipe_name, recipe) and
           not recipe_selector.has_parameter(recipe_name, recipe) and
           recipe_selector.has_main_product(recipe_name, recipe)
  end))
  products = product_utils.merge_duplicates(products, function(a, b) return a + b end)
  table.sort(products, function(a, b) return a.min > b.min end)

  --table_utils.extend(products, product_utils.fill_by_prototypes(prototypes.item))
  --table_utils.extend(products, product_utils.fill_by_prototypes(prototypes.fluid))

  

  --[[

  products = recipe_decomposer.decompose(recipes, products_to_craft)
  products = product_utils.merge_duplicates(products, function(a, b) return a + b end)
  table_utils.for_each(products, function(e) if e.min < 1 then e.min = 1 end end)
  table_utils.extend(products, products_to_craft)

  products = item_selector.filter_by(products, function(item)
    return item_selector.is_filtered_by_recipe(item,
      function(recipe_name, recipe)
        return recipe_selector.can_craft_from_machine(recipe_name, recipe, machine)
      end)
  end)

  -- бежим по каждому рецепту, 

  table.sort(products, function(a, b) return a.min > b.min end)
  ]]
  
  logistic_filters.set_filters(dst, products)

  game.print("Finish!")
end

return main