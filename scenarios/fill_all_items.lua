local entity_finder = require("entity_finder")
local recipe_selector = require("recipe_selector")
local signal_utils = require("signal_utils")
local recipe_utils = require("recipe_utils")
local table_utils= require("table_utils")
local entity_control = require("entity_control")

function fill_all_items(search_area, target_name, functor)
  local dst = entity_finder.find(target_name, search_area)

  local recipes = recipe_selector.filter_by(prototypes.recipe, function(recipe_name, recipe)
    return not recipe_selector.is_hidden(recipe_name, recipe) and
           not recipe_selector.has_parameter(recipe_name, recipe) and
           recipe_selector.has_main_product(recipe_name, recipe)
  end)

  local signals = {}
  for _, recipe in pairs(recipes) do
    table.insert(signals, recipe_utils.make_signal(recipe.main_product))
  end

  signals = signal_utils.merge_duplicates(signals, function(a, b) return a + b end)
  table.sort(signals, function(a, b) return a.min > b.min end)
  table_utils.for_each(signals, functor)

  for _, proto in pairs(prototypes.quality) do
    if not proto.hidden then
      table_utils.for_each(signals, function(e, i) e.value.quality = proto.name end)
      entity_control.set_logistic_filters(dst, signals)
    end
  end
end

return fill_all_items
