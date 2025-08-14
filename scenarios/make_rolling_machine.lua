local entity_finder = require("entity_finder")
local recipe_selector = require("recipe_selector")
local game_utils = require("game_utils")
local signal_selector = require("signal_selector")
local table_utils= require("table_utils")
local entity_control = require("entity_control")
local decider_conditions = require("decider_conditions")
local recipe_decomposer = require("recipe_decomposer")

function make_rolling_machine(search_area)
  local Condition = decider_conditions.Condition
  local OR = Condition.OR
  local AND = Condition.AND
  local MAKE_IN = decider_conditions.MAKE_IN
  local MAKE_OUT = decider_conditions.MAKE_OUT
  local RED_GREEN = decider_conditions.RED_GREEN
  local GREEN_RED = decider_conditions.GREEN_RED
  local EACH = decider_conditions.EACH
  local EVERYTHING = decider_conditions.EVERYTHING

  local products_to_craft_src = entity_finder.find("<rolling_machine_requests_cc>", search_area)
  local decider_dst = entity_finder.find("<rolling_machine_crafter_dc>", search_area)
  local throw_away_dc_dst = entity_finder.find("<rolling_machine_throw_away_dc>", search_area)
  local recycler_unique_id_cc_dst = entity_finder.find("<rolling_machine_recycler_unique_id_cc>", search_area)
  local crafter_bans_cc_dst = entity_finder.find("<rolling_machine_crafter_bans_cc>", search_area)
  local crafter = entity_finder.find(999, search_area)
  local requester = entity_finder.find("<rolling_machine_input_rc>", search_area)
  local recycler_dst = entity_finder.find("<rolling_machine_recycler_dc>", search_area)

  local allowed_recipes = recipe_selector.filter_by(prototypes.recipe, function(recipe_name, recipe)
    return not recipe_selector.is_hidden(recipe_name, recipe) and
           not recipe_selector.has_parameter(recipe_name, recipe) and
           recipe_selector.has_main_product(recipe_name, recipe) and
           recipe_selector.can_craft_from_machine(recipe_name, recipe, crafter)
  end)

  local requested_crafts = entity_control.read_all_logistic_filters(products_to_craft_src)
  requested_crafts = game_utils.merge_duplicates(requested_crafts, game_utils.merge_sum)

  local allowed_requested_crafts = signal_selector.filter_by(requested_crafts, function(item)
    return signal_selector.is_filtered_by_recipe_any(item,
      function(recipe_name, recipe)
        return recipe_selector.can_craft_from_machine(recipe_name, recipe, crafter)
      end)
  end)

  table.sort(allowed_requested_crafts, function(a, b)
    return game_utils.get_quality_index(a.value.quality) < game_utils.get_quality_index(b.value.quality)
  end)

  local decompose_results = recipe_decomposer.decompose_once(allowed_recipes, allowed_requested_crafts, recipe_decomposer.deep_strategy)
  decompose_results = game_utils.merge_duplicates(decompose_results, game_utils.merge_max)

  local UNIQUE_RECIPES_ID_START     = 1000000
  local UNIQUE_ITEMS_ID_START       = 10000000
  local UNIQUE_BAN_ITEMS_ID_START   = 100000000
  local UNIQUE_ID_WIDTH = 10000
  local all_crafts = allowed_requested_crafts
  table_utils.for_each(all_crafts, function(item, i)
    item.need_produce_count = item.min
    item.unique_id = UNIQUE_ITEMS_ID_START + i * UNIQUE_ID_WIDTH
  end)

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
          ingredients_check_first:add_child(MAKE_IN(ingredient_signal.value, ">=", ingredient_signal.min * 2, RED_GREEN(game_utils.is_fluid(ingredient_signal), true), RED_GREEN(true, true)))
        end

        local ingredients_check_second = AND()
        for _, ingredient in ipairs(recipe.ingredients) do
          local ingredient_signal = game_utils.make_signal(ingredient, item.value.quality)
          ingredient_signal = game_utils.correct_signal(ingredient_signal)
          ingredients_check_second:add_child(MAKE_IN(ingredient_signal.value, ">=", ingredient_signal.min, RED_GREEN(game_utils.is_fluid(ingredient_signal), true), RED_GREEN(true, true)))
        end

        local forward = MAKE_IN(EACH, "=", recipe_signal.value, RED_GREEN(true, false), RED_GREEN(true, false))
        local need_produce = MAKE_IN(item.value, "<", item.need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true))
        local first_lock = MAKE_IN(EVERYTHING, "<", UNIQUE_RECIPES_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
        local second_lock = MAKE_IN(recipe_signal.value, ">", UNIQUE_RECIPES_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
        local choice_priority = MAKE_IN(EVERYTHING, "<=", recipe_signal.value, RED_GREEN(false, true), RED_GREEN(true, false))

        crafter_tree:add_child(AND(forward, ingredients_check_first, need_produce, first_lock))
        crafter_tree:add_child(AND(forward, ingredients_check_second, need_produce, AND(second_lock, choice_priority)))
      end
    end
  end

  local crafter_outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }

  entity_control.fill_decider_combinator(decider_dst, decider_conditions.to_flat_dnf(crafter_tree), crafter_outputs)


  local source_products = decompose_results

  do
    local quality_ingredients = {}
    table_utils.extend(quality_ingredients, all_crafts)
    table_utils.extend(quality_ingredients, source_products)

    local ingredients_map = table_utils.to_map(quality_ingredients, function(item) return game_utils.items_key_fn(item.value) end)

    local recycler_tree = OR()
    for _, item in ipairs(all_crafts) do
      local recipes = game_utils.get_recipes_for_signal(allowed_recipes, item)
      for _, recipe in ipairs(recipes) do
        local ingredients_check = OR()

        for _, quality in ipairs(game_utils.get_all_better_qualities(item.value.quality)) do
          for _, ingredient in ipairs(recipe.ingredients) do
            local ingredient_signal = game_utils.make_signal(ingredient, quality)

            if not game_utils.is_fluid(ingredient_signal) and ingredients_map[game_utils.items_key_fn(ingredient_signal.value)] then
              local ingredient_min = ingredients_map[game_utils.items_key_fn(ingredient_signal.value)].min

              local parent = {
                name = item.value.name,
                type = item.value.type,
                quality = quality
              }
              local parent_signal = ingredients_map[game_utils.items_key_fn(parent)]
              local parent_check = MAKE_IN(parent_signal.value, "<", parent_signal.need_produce_count, GREEN_RED(false, true), GREEN_RED(true, true))

              local ingredient_check = MAKE_IN(ingredient_signal.value, "<", ingredient_min, GREEN_RED(false, true), GREEN_RED(true, true))
              local quality_check = MAKE_IN({ name = quality, type = "quality" }, "!=", 0, GREEN_RED(true, false), GREEN_RED(true, true))
              ingredients_check:add_child(AND(parent_check, ingredient_check, quality_check))
            end
          end
        end

        if not ingredients_check:is_empty() then

          local first_lock = MAKE_IN(EVERYTHING, "<", UNIQUE_ITEMS_ID_START, GREEN_RED(false, true), GREEN_RED(true, true))
          local choice_priority = MAKE_IN(EVERYTHING, "<", item.unique_id + UNIQUE_ID_WIDTH, GREEN_RED(false, true), GREEN_RED(true, false))

          local forward = MAKE_IN(EACH, "=", item.value, GREEN_RED(true, false), GREEN_RED(true, false))
          local need_recycle_start = MAKE_IN(item.value, ">=", item.need_produce_count, GREEN_RED(false, true), GREEN_RED(true, true))
          local need_recycle_continue = MAKE_IN(item.value, ">", item.unique_id, GREEN_RED(false, true), GREEN_RED(true, true))

          recycler_tree:add_child(AND(forward, need_recycle_start, ingredients_check, first_lock))
          recycler_tree:add_child(AND(forward, need_recycle_continue, ingredients_check, choice_priority))
        end
      end
    end

    local recycler_outputs = { MAKE_OUT(EACH, true, GREEN_RED(true, false)) }

    entity_control.fill_decider_combinator(recycler_dst, decider_conditions.to_flat_dnf(recycler_tree), recycler_outputs)
  end

  entity_control.clear_logistic_filters(requester)
  entity_control.set_logistic_filters(requester, source_products)

  do
    local input_recipe_signals = {}
    local quality_signals = {}
 
    local requested_crafts_signals = table_utils.deep_copy(allowed_requested_crafts)
    for _, item in ipairs(requested_crafts_signals) do
      local recipes = game_utils.get_recipes_for_signal(allowed_recipes, item)
      for _, recipe in ipairs(recipes) do
        local recipe_signal = game_utils.recipe_as_signal(recipe, item.value.quality)
        if recipe_signal ~= nil then
          table.insert(input_recipe_signals, recipe_signal)
        end
      end

      local quality_signal = {
        value = {
          name = item.value.quality,
          type = "quality",
          quality = "normal"
        },
        min = 1
      }
      table.insert(quality_signals, quality_signal)
    end
    quality_signals = game_utils.merge_duplicates(quality_signals, game_utils.merge_max)

    input_recipe_signals = game_utils.merge_duplicates(input_recipe_signals, game_utils.merge_max)
    table_utils.for_each(input_recipe_signals, function(e, i) e.min = UNIQUE_RECIPES_ID_START + i end)

    table_utils.for_each(requested_crafts_signals, function(e, i) e.min = e.unique_id end)

    entity_control.clear_logistic_filters(recycler_unique_id_cc_dst)
    entity_control.set_logistic_filters(recycler_unique_id_cc_dst, requested_crafts_signals)
    entity_control.set_logistic_filters(recycler_unique_id_cc_dst, input_recipe_signals)
    entity_control.set_logistic_filters(recycler_unique_id_cc_dst, quality_signals)
  end

  do
    local all_ban_items = {}
    local requested_crafts_signals = table_utils.deep_copy(allowed_requested_crafts)
    local decompose_results_signals = table_utils.deep_copy(decompose_results)
    table_utils.for_each(requested_crafts_signals, function(e, i) e.need_out = e.min end)
    table_utils.for_each(decompose_results_signals, function(e, i) e.need_out = 0 end)

    table_utils.extend(all_ban_items, requested_crafts_signals)
    table_utils.extend(all_ban_items, decompose_results_signals)
    table_utils.for_each(all_ban_items, function(e, i) e.unique_id = -1 * (UNIQUE_BAN_ITEMS_ID_START + i * UNIQUE_ID_WIDTH) end)

    local tree = OR()
    for _, item in ipairs(all_ban_items) do
      local forward = MAKE_IN(EACH, "=", item.value, GREEN_RED(true, false), GREEN_RED(true, false))
      local out_check = MAKE_IN(item.value, ">=", item.need_out + item.unique_id, GREEN_RED(true, false), GREEN_RED(true, false))
      if game_utils.is_fluid(item) then
        local fluid_forward = MAKE_IN(EACH, "=", item.value, GREEN_RED(false, true), GREEN_RED(false, true))
        local fluid_check = MAKE_IN(item.value, "!=", 0, GREEN_RED(false, true), GREEN_RED(true, true))
        tree:add_child(AND(fluid_forward, fluid_check))
      end
      tree:add_child(AND(forward, out_check))
    end

    local outputs = { MAKE_OUT(EACH, true, GREEN_RED(true, true)) }
    entity_control.fill_decider_combinator(throw_away_dc_dst, decider_conditions.to_flat_dnf(tree), outputs)

    table_utils.for_each(all_ban_items, function(e, i) 
      if game_utils.is_fluid(e) then
        e.min = 0
      else
        e.min = e.unique_id
      end
    end)
    entity_control.clear_logistic_filters(crafter_bans_cc_dst)
    entity_control.set_logistic_filters(crafter_bans_cc_dst, all_ban_items)
  end

end

return make_rolling_machine
