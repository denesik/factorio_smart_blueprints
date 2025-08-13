local entity_finder = require("entity_finder")
local recipe_selector = require("recipe_selector")
local game_utils = require("game_utils")
local table_utils= require("table_utils")
local entity_control = require("entity_control")
local recipe_decomposer = require("recipe_decomposer")

function fill_all_items(search_area, target_name, functor)
  local dst = entity_finder.find(target_name, search_area)

  local recipes = recipe_selector.filter_by(prototypes.recipe, function(recipe_name, recipe)
    return not recipe_selector.is_hidden(recipe_name, recipe) and
           not recipe_selector.has_parameter(recipe_name, recipe) and
           recipe_selector.has_main_product(recipe_name, recipe)
  end)

  local signals = {}
  for _, recipe in pairs(recipes) do
    table.insert(signals, game_utils.make_signal(recipe.main_product))
  end

  signals = game_utils.merge_duplicates(signals, game_utils.merge_max)

  local decompose_results = recipe_decomposer.decompose(recipes, signals, recipe_decomposer.shallow_strategy)
  table_utils.extend(decompose_results, signals)
  decompose_results = game_utils.merge_duplicates(decompose_results, game_utils.merge_depth)

  table.sort(decompose_results, function(a, b)
    if a.depth == b.depth then
      return game_utils.get_prototype(a).order < game_utils.get_prototype(b).order
    end
    return a.depth < b.depth
  end)

  for _, proto in pairs(prototypes.quality) do
    if not proto.hidden then
      table_utils.for_each(decompose_results, function(e, i) e.value.quality = proto.name functor(e, i) end)
      entity_control.set_logistic_filters(dst, decompose_results)
    end
  end
end

return fill_all_items
