local entity_finder = require("entity_finder")
local recipe_selector = require("recipe_selector")
local signal_utils = require("signal_utils")
local recipe_utils = require("recipe_utils")
local table_utils= require("table_utils")
local entity_control = require("entity_control")

function fill_all_recipes(search_area, target_name, functor)
  local dst = entity_finder.find(target_name, search_area)

  local recipes = recipe_selector.filter_by(prototypes.recipe, function(recipe_name, recipe)
    return not recipe_selector.is_hidden(recipe_name, recipe) and
           not recipe_selector.has_parameter(recipe_name, recipe) and
           recipe_selector.has_main_product(recipe_name, recipe)
  end)

  local recipe_signals = recipe_utils.recipes_as_signals(recipes)
  recipe_signals = signal_utils.merge_duplicates(recipe_signals, function(a, b) return a + b end)
  table.sort(recipe_signals, function(a, b) return a.min > b.min end)

  local offset = 0
  for _, proto in pairs(prototypes.quality) do
    if not proto.hidden then
      table_utils.for_each(recipe_signals, function(e, i) e.value.quality = proto.name functor(e, i + offset) end)
      entity_control.set_logistic_filters(dst, recipe_signals)
      offset = offset + 10000
    end
  end
end

return fill_all_recipes
