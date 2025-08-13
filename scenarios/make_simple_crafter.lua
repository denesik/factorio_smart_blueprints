local entity_finder = require("entity_finder")
local recipe_selector = require("recipe_selector")
local game_utils = require("game_utils")
local signal_selector = require("signal_selector")
local table_utils= require("table_utils")
local entity_control = require("entity_control")
local decider_conditions = require("decider_conditions")
local recipe_decomposer = require("recipe_decomposer")
local math_utils = require("math_utils")

function make_simple_crafter(search_area, products_to_craft_src_name, decider_dst_name, requests_dst_name, decompose_crafts_dst_name, recycler_dst_name, crafter_id)
  local Condition = decider_conditions.Condition
  local OR = Condition.OR
  local AND = Condition.AND
  local MAKE_IN = decider_conditions.MAKE_IN
  local MAKE_OUT = decider_conditions.MAKE_OUT
  local RED_GREEN = decider_conditions.RED_GREEN
  local EACH = decider_conditions.EACH
  local EVERYTHING = decider_conditions.EVERYTHING

  local products_to_craft_src = entity_finder.find(products_to_craft_src_name, search_area)
  local decider_dst = entity_finder.find(decider_dst_name, search_area)
  local decompose_crafts_dst = entity_finder.find(decompose_crafts_dst_name, search_area)
  local crafter = entity_finder.find(crafter_id, search_area)
  local requester = entity_finder.find(requests_dst_name, search_area)
  local recycler_dst = entity_finder.find(recycler_dst_name, search_area)

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

  local decompose_results = recipe_decomposer.decompose_full(allowed_recipes, requests_crafts, recipe_decomposer.shallow_strategy)
  decompose_results = game_utils.merge_duplicates(decompose_results, game_utils.merge_max)

  local decompose_crafts = signal_selector.filter_by(decompose_results, function(item)
    return signal_selector.is_filtered_by_recipe_any(item,
      function(recipe_name, recipe)
          return recipe_selector.can_craft_from_machine(recipe_name, recipe, crafter)
      end)
  end)

  local all_crafts = {}
  do
    table_utils.extend(all_crafts, decompose_crafts)
    table_utils.extend(all_crafts, requests_crafts)

    local energy = { min = 1000000, max = 0 }
    table_utils.for_each(all_crafts, function(item)
      local recipes = game_utils.get_recipes_for_signal(allowed_recipes, item)
      for _, recipe in ipairs(recipes) do
        energy.min = math.min(energy.min, recipe.energy)
        energy.max = math.max(energy.max, recipe.energy)
      end
      item.need_produce_count = item.min
    end)

    table_utils.for_each(decompose_crafts, function(item)
      local recipes = game_utils.get_recipes_for_signal(allowed_recipes, item)
      for _, recipe in ipairs(recipes) do
        local min = item.min * 2 + 1
        local max = game_utils.get_stack_size(item) - 20
        local scale = 2 ^ (game_utils.get_quality_index(item.value.quality) - 1);
        local normalized = math_utils.normalize(recipe.energy, energy.min, energy.max)
        item.need_produce_count = math_utils.denormalize((1.0 - normalized) / scale, min, max)
      end
    end)
  end

  local crafter_tree = OR()
  for _, item in ipairs(all_crafts) do
    local recipes = game_utils.get_recipes_for_signal(allowed_recipes, item)
    for _, recipe in ipairs(recipes) do
      local recipe_signal = game_utils.recipe_as_signal(recipe, item.value.quality)
      if recipe_signal ~= nil then

        local ingredients_check_first = AND()
        for _, ingredient in ipairs(recipe.ingredients) do
          local ingredient_signal = game_utils.make_signal(ingredient, item.value.quality)
          ingredient_signal = game_utils.correct_signal(ingredient_signal)
          ingredients_check_first:add_child(MAKE_IN(ingredient_signal.value, ">=", ingredient_signal.min * 2, RED_GREEN(false, true), RED_GREEN(true, true)))
        end

        local ingredients_check_second = AND()
        for _, ingredient in ipairs(recipe.ingredients) do
          local ingredient_signal = game_utils.make_signal(ingredient, item.value.quality)
          ingredient_signal = game_utils.correct_signal(ingredient_signal)
          ingredients_check_second:add_child(MAKE_IN(ingredient_signal.value, ">=", ingredient_signal.min, RED_GREEN(false, true), RED_GREEN(true, true)))
        end

        local forward = MAKE_IN(EACH, "=", recipe_signal.value, RED_GREEN(true, false), RED_GREEN(true, false))
        local need_produce_min = MAKE_IN(item.value, "<", math.min(item.min * 2, item.need_produce_count), RED_GREEN(false, true), RED_GREEN(true, true))
        local need_produce_max = MAKE_IN(item.value, "<", item.need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true))
        local first_lock = MAKE_IN(EVERYTHING, "<", 499999, RED_GREEN(false, true), RED_GREEN(true, true))
        local second_lock = MAKE_IN(recipe_signal.value, ">", 1000000, RED_GREEN(false, true), RED_GREEN(true, true))
        local choice_priority = MAKE_IN(EVERYTHING, "<=", recipe_signal.value, RED_GREEN(false, true), RED_GREEN(true, false))

        crafter_tree:add_child(AND(forward, ingredients_check_first, need_produce_min, first_lock))
        crafter_tree:add_child(AND(forward, ingredients_check_second, need_produce_max, AND(second_lock, choice_priority)))
      end
    end
  end

  local crafter_outputs = { MAKE_OUT(EACH, true, RED_GREEN(false, true)) }

  entity_control.fill_decider_combinator(decider_dst, decider_conditions.to_flat_dnf(crafter_tree), crafter_outputs)


  local source_products = signal_selector.filter_by(decompose_results, function(item)
    return signal_selector.is_filtered_by_recipe_all(item,
      function(recipe_name, recipe)
        return not recipe_selector.can_craft_from_machine(recipe_name, recipe, crafter)
      end)
  end)

  table_utils.for_each(source_products, function(item)
    item.min = game_utils.get_stack_size(item) - 20
    item.need_produce_count = item.min
  end)

  do
    local recycler_products = {}
    table_utils.extend(recycler_products, all_crafts)
    table_utils.extend(recycler_products, source_products)

    local ingredients_map = table_utils.to_map(recycler_products, function(item) return item.value.name end)

    local recycler_tree = OR()
    for _, item in ipairs(all_crafts) do
      local recipes = game_utils.get_recipes_for_signal(allowed_recipes, item)
      for _, recipe in ipairs(recipes) do

          local ingredients_check = OR()
          for _, quality in ipairs(game_utils.get_all_better_qualities(item.value.quality)) do
            for _, ingredient in ipairs(recipe.ingredients) do
              local ingredient_signal = game_utils.make_signal(ingredient, quality)

              if not game_utils.is_fluid(ingredient_signal) and ingredients_map[ingredient_signal.value.name] then
                local ingredient_min = ingredients_map[ingredient_signal.value.name].min * 2 + 1

                local ingredient_check = MAKE_IN(ingredient_signal.value, "<", ingredient_min, RED_GREEN(false, true), RED_GREEN(true, true))
                local quality_check = MAKE_IN({ name = quality, type = "quality" }, "!=", 0, RED_GREEN(true, false), RED_GREEN(true, true))
                ingredients_check:add_child(AND(ingredient_check, quality_check))
              end
            end
          end

          if not ingredients_check:is_empty() then
            local forward = MAKE_IN(EACH, "=", item.value, RED_GREEN(true, false), RED_GREEN(true, false))
            local item_check = MAKE_IN(item.value, ">=", item.need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true))
            recycler_tree:add_child(AND(forward, item_check, ingredients_check))
          end
      end
    end


    local recycler_outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }

    entity_control.fill_decider_combinator(recycler_dst, decider_conditions.to_flat_dnf(recycler_tree), recycler_outputs)
  end

  entity_control.set_logistic_filters(requester, source_products)

  entity_control.set_logistic_filters(decompose_crafts_dst, decompose_crafts)

  table_utils.for_each(requests_crafts, function(e) e.min = 0 e.max = 0 end)
  entity_control.set_logistic_filters(requester, requests_crafts)

end

return make_simple_crafter
