local entity_finder = require("entity_finder")
local recipe_selector = require("recipe_selector")
local signal_utils = require("signal_utils")
local recipe_utils = require("recipe_utils")
local signal_selector = require("signal_selector")
local table_utils= require("table_utils")
local entity_control = require("entity_control")
local decider_conditions = require("decider_conditions")
local recipe_decomposer = require("recipe_decomposer")
local math_utils = require("math_utils")

function make_simple_crafter(search_area, products_to_craft_src_name, decider_dst_name, requests_dst_name, decompose_crafts_dst_name, crafter_id)
  local Condition = decider_conditions.Condition
  local OR = Condition.OR
  local AND = Condition.AND
  local MAKE = decider_conditions.MAKE
  local EACH = decider_conditions.EACH
  local EVERYTHING = decider_conditions.EVERYTHING

  local products_to_craft_src = entity_finder.find(products_to_craft_src_name, search_area)
  local decider_dst = entity_finder.find(decider_dst_name, search_area)
  local decompose_crafts_dst = entity_finder.find(decompose_crafts_dst_name, search_area)
  local crafter = entity_finder.find(crafter_id, search_area)
  local requester = entity_finder.find(requests_dst_name, search_area)

  local allowed_recipes = recipe_selector.filter_by(prototypes.recipe, function(recipe_name, recipe)
    return not recipe_selector.is_hidden(recipe_name, recipe) and
           not recipe_selector.has_parameter(recipe_name, recipe) and
           recipe_selector.has_main_product(recipe_name, recipe) and
           recipe_selector.can_craft_from_machine(recipe_name, recipe, crafter)
  end)

  local requests_crafts = entity_control.read_all_logistic_filters(products_to_craft_src)

  requests_crafts = signal_selector.filter_by(requests_crafts, function(item)
    return signal_selector.is_filtered_by_recipe_any(item,
      function(recipe_name, recipe)
        return recipe_selector.can_craft_from_machine(recipe_name, recipe, crafter)
      end)
  end)

  local decompose_results = recipe_decomposer.decompose(allowed_recipes, requests_crafts, recipe_decomposer.shallow_strategy)
  decompose_results = signal_utils.merge_duplicates(decompose_results, function(a, b) return math.max(a, b) end)

  local decompose_crafts = signal_selector.filter_by(decompose_results, function(item)
    return signal_selector.is_filtered_by_recipe_any(item,
      function(recipe_name, recipe)
          return recipe_selector.can_craft_from_machine(recipe_name, recipe, crafter)
      end)
  end)

  local source_products = signal_selector.filter_by(decompose_results, function(item)
    return signal_selector.is_filtered_by_recipe_all(item,
      function(recipe_name, recipe)
        return not recipe_selector.can_craft_from_machine(recipe_name, recipe, crafter)
      end)
  end)

  local all_crafts = {}
  table_utils.extend(all_crafts, decompose_crafts)
  table_utils.extend(all_crafts, requests_crafts)

  do
    local energy = { min = 1000000, max = 0 }
    table_utils.for_each(all_crafts, function(item)
      signal_selector.is_filtered_by_recipe_any(item,
        function(recipe_name, recipe)
            if recipe_selector.can_craft_from_machine(recipe_name, recipe, crafter) then
              energy.min = math.min(energy.min, recipe.energy)
              energy.max = math.max(energy.max, recipe.energy)
              return true
            end
            return false
        end)
    end)

    table_utils.for_each(decompose_crafts, function(item)
      signal_selector.is_filtered_by_recipe_any(item,
        function(recipe_name, recipe)
            if recipe_selector.can_craft_from_machine(recipe_name, recipe, crafter) then
              local min = item.min * 2
              local max = signal_utils.get_stack_size(item) - 20
              local normalized = math_utils.normalize(recipe.energy, energy.min, energy.max)
              item.min = math_utils.denormalize(1.0 - normalized, min, max)
              return true
            end
            return false
        end)
    end)
  end

  table_utils.for_each(source_products, function(item)
    item.min = signal_utils.get_stack_size(item) - 20
  end)

  local tree = OR()
  for _, item in ipairs(all_crafts) do
    local recipes = recipe_utils.get_recipes_for_signal(allowed_recipes, item)
    for _, recipe in ipairs(recipes) do
      local recipe_signal = recipe_utils.recipe_as_signal(recipe, item.value.quality)
      if recipe_signal ~= nil then

        local ingredients_check_first = AND()
        for _, ingredient in ipairs(recipe.ingredients) do
          ingredient_signal = recipe_utils.make_signal(ingredient, item.value.quality)
          ingredient_signal = signal_utils.correct_signal(ingredient_signal)
          ingredients_check_first:add_child(MAKE(ingredient_signal.value, ">=", ingredient_signal.min * 2, false, true, true, true))
        end

        local ingredients_check_second = AND()
        for _, ingredient in ipairs(recipe.ingredients) do
          ingredient_signal = recipe_utils.make_signal(ingredient, item.value.quality)
          ingredient_signal = signal_utils.correct_signal(ingredient_signal)
          ingredients_check_second:add_child(MAKE(ingredient_signal.value, ">=", ingredient_signal.min, false, true, true, true))
        end

        local forward = MAKE(EACH, "=", recipe_signal.value, true, false, true, false)
        local need_produce = MAKE(item.value, "<", item.min, false, true, true, true)
        local first_lock = MAKE(EVERYTHING, "<", 499999, false, true, true, true)
        local second_lock = MAKE(recipe_signal.value, ">", 1000000, false, true, true, true)
        local choice_priority = MAKE(EVERYTHING, "<=", recipe_signal.value, false, true, true, false)

        tree:add_child(AND(forward, ingredients_check_first, need_produce, first_lock))
        tree:add_child(AND(forward, ingredients_check_second, need_produce, AND(second_lock, choice_priority)))
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

  entity_control.set_logistic_filters(decompose_crafts_dst, decompose_crafts)
  table_utils.for_each(requests_crafts, function(e) e.min = 0 e.max = 0 end)
  entity_control.set_logistic_filters(requester, requests_crafts)
end

return make_simple_crafter
