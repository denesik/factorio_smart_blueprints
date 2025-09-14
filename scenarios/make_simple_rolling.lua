local EntityFinder = require("entity_finder")
local recipe_selector = require("recipe_selector")
local game_utils = require("game_utils")
local signal_selector = require("signal_selector")
local table_utils = require("common.table_utils")
local entity_control = require("entity_control")
local decider_conditions = require("decider_conditions")
local recipe_decomposer = require("recipe_decomposer")

local make_simple_rolling = {}

make_simple_rolling.name = "make_simple_rolling"

function make_simple_rolling.run(surface, area)
  local Condition = decider_conditions.Condition
  local OR = Condition.OR
  local AND = Condition.AND
  local MAKE_IN = decider_conditions.MAKE_IN
  local MAKE_OUT = decider_conditions.MAKE_OUT
  local RED_GREEN = decider_conditions.RED_GREEN
  local GREEN_RED = decider_conditions.GREEN_RED
  local EACH = decider_conditions.EACH
  local EVERYTHING = decider_conditions.EVERYTHING

  local defs = {
    {name = "crafter_dc_dst",                   label = "<simple_rolling_crafter_dc>",    type = "decider-combinator"},
    {name = "simple_rolling_main_cc_dst",       label = "<simple_rolling_main_cc>",       type = "constant-combinator"},
    {name = "simple_rolling_secondary_cc_dst",  label = "<simple_rolling_secondary_cc>",  type = "constant-combinator"},
    {name = "crafter_machine",                  label = 583402,                           type = "assembling-machine"},
    {name = "requester_rc_dst",                 label = 583401,                           type = "logistic-container"},
    {name = "recycler_dc_dst",                  label = "<simple_rolling_recycler_dc>",   type = "decider-combinator"},
    {name = "manipulator_black",                label = 583403,                           type = "inserter"},
    {name = "manipulator_white",                label = 583404,                           type = "inserter"},
  }

  local entities = EntityFinder.new(surface, area, defs)

  local allowed_recipes = recipe_selector.filter_by(prototypes.recipe, function(recipe_name, recipe)
    return not recipe_selector.is_hidden(recipe_name, recipe) and
           not recipe_selector.has_parameter(recipe_name, recipe) and
           recipe_selector.has_main_product(recipe_name, recipe) and
           recipe_selector.can_craft_from_machine(recipe_name, recipe, entity_control.get_name(entities.crafter_machine))
  end)

  local requested_crafts = entity_control.read_all_logistic_filters(entities.simple_rolling_main_cc_dst)
  requested_crafts = game_utils.merge_duplicates(requested_crafts, game_utils.merge_sum)

  local allowed_requested_crafts = signal_selector.filter_by(requested_crafts, function(item)
    return signal_selector.is_filtered_by_recipe_any(item,
      function(recipe_name, recipe)
        return recipe_selector.can_craft_from_machine(recipe_name, recipe, entity_control.get_name(entities.crafter_machine))
      end)
  end)

  table.sort(allowed_requested_crafts, function(a, b)
    return game_utils.get_quality_index(a.value.quality) < game_utils.get_quality_index(b.value.quality)
  end)

  local UNIQUE_QUALITY_ID_START     = -10000000
  local UNIQUE_CRAFT_ITEMS_ID_START = 10000000
  local BAN_ITEMS_OFFSET            = -1000000
  local UNIQUE_ID_WIDTH = 10000

  local source_products = recipe_decomposer.decompose_once(allowed_recipes, allowed_requested_crafts, recipe_decomposer.deep_strategy)
  source_products = game_utils.merge_duplicates(source_products, game_utils.merge_min)

  local all_items = {}
  local recycle_signals = {}
  local need_recycle_constants = {}
  local ingredients_constants = {}
  do
    for _, item in ipairs(allowed_requested_crafts) do
      local signal = table_utils.deep_copy(item)
      signal.value.name = "signal-recycle"
      signal.value.type = "virtual"
      table.insert(recycle_signals, signal)
    end
    recycle_signals = game_utils.merge_duplicates(recycle_signals, game_utils.merge_max)
    table_utils.for_each(recycle_signals, function(e, i) e.quality_unique_id = UNIQUE_QUALITY_ID_START - i * UNIQUE_ID_WIDTH end)

    table_utils.extend(all_items, allowed_requested_crafts)
    table_utils.extend(all_items, source_products)

    table_utils.for_each(all_items, function(item, i)
      item.unique_craft_id = UNIQUE_CRAFT_ITEMS_ID_START + i * UNIQUE_ID_WIDTH
    end)

    table_utils.for_each(allowed_requested_crafts, function(item, i)
      item.need_produce_count = item.min
    end)

    local ingredients_map = table_utils.to_map(all_items, function(item) return game_utils.items_key_fn(item.value) end)
    do
      local signals = {}
      local next_letter_code = string.byte("1")

      for _, item in ipairs(allowed_requested_crafts) do
        local recipes = game_utils.get_recipes_for_signal(allowed_recipes, item)

        for _, recipe in ipairs(recipes) do
          for _, ingredient in ipairs(recipe.ingredients) do
            local ingredient_signal = game_utils.make_signal(ingredient, item.value.quality)
            assert(ingredients_map[game_utils.items_key_fn(ingredient_signal.value)])
            local signal = table_utils.deep_copy(ingredient_signal)
            signal.recipe_min = ingredient_signal.min
            signal.ingredient_min = ingredients_map[game_utils.items_key_fn(ingredient_signal.value)].min
            signal.ingredient_offset = BAN_ITEMS_OFFSET + signal.ingredient_min + signal.recipe_min
            signal.mapped_name = game_utils.items_key_fn(ingredient_signal.value)

            if not signals[ingredient_signal.value.name] then
              signals[ingredient_signal.value.name] = string.char(next_letter_code)
              next_letter_code = next_letter_code + 1
            end
            signal.value.name = "signal-" .. signals[ingredient_signal.value.name]
            signal.value.type = "virtual"

            table.insert(ingredients_constants, signal)
          end
        end
      end
      ingredients_constants = game_utils.merge_duplicates(ingredients_constants, game_utils.merge_min)
    end
    local ingredients_constants_map = table_utils.to_map(ingredients_constants, function(item) return item.mapped_name end)

    local crafter_tree = OR()
    for _, item in ipairs(allowed_requested_crafts) do
      local recipes = game_utils.get_recipes_for_signal(allowed_recipes, item)
      for _, recipe in ipairs(recipes) do

        local ingredients_check_first = AND()
        for _, ingredient in ipairs(recipe.ingredients) do
          local ingredient_signal = game_utils.make_signal(ingredient, item.value.quality)
          if not game_utils.is_fluid(ingredient_signal) then
            assert(ingredients_constants_map[game_utils.items_key_fn(ingredient_signal.value)])
            local ingredients_constant = ingredients_constants_map[game_utils.items_key_fn(ingredient_signal.value)]
            ingredients_check_first:add_child(MAKE_IN(ingredient_signal.value, ">=", ingredients_constant.value, RED_GREEN(false, true), RED_GREEN(true, true)))
          end
        end

        local ingredients_check_second = AND()
        for _, ingredient in ipairs(recipe.ingredients) do
          local ingredient_signal = game_utils.make_signal(ingredient, item.value.quality)
          if not game_utils.is_fluid(ingredient_signal) then
            assert(ingredients_constants_map[game_utils.items_key_fn(ingredient_signal.value)])
            local ingredients_constant = ingredients_constants_map[game_utils.items_key_fn(ingredient_signal.value)]
            ingredients_check_second:add_child(MAKE_IN(ingredient_signal.value, ">=", ingredients_constant.value, RED_GREEN(false, true), RED_GREEN(false, true)))
          end
        end

        local forward = MAKE_IN(EACH, "=", item.value, RED_GREEN(true, false), RED_GREEN(true, false))
        local first_lock = MAKE_IN(EVERYTHING, "<", BAN_ITEMS_OFFSET + UNIQUE_CRAFT_ITEMS_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
        local second_lock = MAKE_IN(item.value, ">", BAN_ITEMS_OFFSET + UNIQUE_CRAFT_ITEMS_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
        local choice_priority = MAKE_IN(EVERYTHING, "<", BAN_ITEMS_OFFSET + item.unique_craft_id, RED_GREEN(false, true), RED_GREEN(true, false))

        local first_need_produce = MAKE_IN(item.value, "<", BAN_ITEMS_OFFSET, RED_GREEN(false, true), RED_GREEN(true, true))
        local second_need_produce = MAKE_IN(item.value, "<", BAN_ITEMS_OFFSET + item.unique_craft_id, RED_GREEN(false, true), RED_GREEN(true, true))

        crafter_tree:add_child(AND(forward, ingredients_check_first, first_need_produce, first_lock))
        crafter_tree:add_child(AND(forward, ingredients_check_second, second_need_produce, second_lock, choice_priority))
      end
    end

    for _, item in ipairs(allowed_requested_crafts) do
      local signal = table_utils.deep_copy(item)
      signal.value.name = "signal-R"
      signal.value.type = "virtual"
      table.insert(need_recycle_constants, signal)
    end
    need_recycle_constants = game_utils.merge_duplicates(need_recycle_constants, game_utils.merge_max)
    table_utils.for_each(need_recycle_constants, function(e, i) e.need_produce_offset = BAN_ITEMS_OFFSET + e.need_produce_count end)

    local recycle_signals_map = table_utils.to_map(recycle_signals, function(item) return item.value.quality end)
    local need_recycle_constants_map = table_utils.to_map(need_recycle_constants, function(item) return item.value.quality end)
    local recycler_tree = OR()
    for _, item in ipairs(allowed_requested_crafts) do
      local recipes = game_utils.get_recipes_for_signal(allowed_recipes, item)
      for _, recipe in ipairs(recipes) do
        local ingredients_check = OR()

        for _, quality in ipairs(game_utils.get_all_better_qualities(item.value.quality)) do
          for _, ingredient in ipairs(recipe.ingredients) do
            local ingredient_signal = game_utils.make_signal(ingredient, quality)
            if not game_utils.is_fluid(ingredient_signal) then
              if ingredients_map[game_utils.items_key_fn(ingredient_signal.value)] then

                local parent = {
                  name = item.value.name,
                  type = item.value.type,
                  quality = quality
                }
                local parent_signal = ingredients_map[game_utils.items_key_fn(parent)]

                local parent_check_direct = MAKE_IN(parent_signal.value, "<", BAN_ITEMS_OFFSET, RED_GREEN(false, true), RED_GREEN(true, true))
                local parent_check_offset = AND(
                  MAKE_IN(parent_signal.value, ">=", BAN_ITEMS_OFFSET + UNIQUE_CRAFT_ITEMS_ID_START, RED_GREEN(false, true), RED_GREEN(true, true)),
                  MAKE_IN(parent_signal.value, "<", BAN_ITEMS_OFFSET + parent_signal.unique_craft_id, RED_GREEN(false, true), RED_GREEN(true, true))
                )
                local ingredient_check = MAKE_IN(ingredient_signal.value, "<", BAN_ITEMS_OFFSET, RED_GREEN(false, true), RED_GREEN(true, true))
                local quality_check = MAKE_IN({ name = quality, type = "quality" }, "!=", 0, GREEN_RED(true, false), GREEN_RED(true, true))
                ingredients_check:add_child(AND(OR(parent_check_offset, parent_check_direct), ingredient_check, quality_check))
              end
            end
          end
        end

        if not ingredients_check:is_empty() then
          assert(recycle_signals_map[item.value.quality])
          assert(need_recycle_constants_map[item.value.quality])
          local quality_signal = recycle_signals_map[item.value.quality]
          local need_recycle_constant = need_recycle_constants_map[item.value.quality]

          local first_lock = MAKE_IN(EVERYTHING, ">", UNIQUE_QUALITY_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
          local second_lock = MAKE_IN(quality_signal.value, "<", UNIQUE_QUALITY_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
          local choice_priority = MAKE_IN(EVERYTHING, ">", quality_signal.quality_unique_id - UNIQUE_ID_WIDTH, RED_GREEN(false, true), RED_GREEN(true, false))

          local forward = MAKE_IN(EACH, "=", quality_signal.value, RED_GREEN(true, false), RED_GREEN(true, false))
          local need_recycle_start_direct = AND(
            MAKE_IN(item.value, ">=", BAN_ITEMS_OFFSET, RED_GREEN(false, true), RED_GREEN(true, true)),
            MAKE_IN(item.value, "<", BAN_ITEMS_OFFSET + UNIQUE_CRAFT_ITEMS_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
          )
          local need_recycle_continue_direct = AND(
            MAKE_IN(item.value, ">", need_recycle_constant.value, RED_GREEN(false, true), RED_GREEN(false, true)),
            MAKE_IN(item.value, "<", BAN_ITEMS_OFFSET + UNIQUE_CRAFT_ITEMS_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
          )
          local need_recycle_start_offset = MAKE_IN(item.value, ">=", BAN_ITEMS_OFFSET + item.unique_craft_id, RED_GREEN(false, true), RED_GREEN(true, true))
          local need_recycle_continue_offset = MAKE_IN(item.value, ">", need_recycle_constant.value, RED_GREEN(false, true), RED_GREEN(true, true))

          recycler_tree:add_child(AND(forward, OR(need_recycle_start_direct, need_recycle_start_offset), ingredients_check, first_lock))
          recycler_tree:add_child(AND(forward, OR(need_recycle_continue_direct, need_recycle_continue_offset), ingredients_check, second_lock, choice_priority))
        end
      end
    end
    crafter_tree:add_child(recycler_tree)

    local crafter_outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }

    entity_control.fill_decider_combinator(entities.crafter_dc_dst, decider_conditions.to_flat_dnf(crafter_tree), crafter_outputs)
  end

  do
    local quality_signals_copy = table_utils.deep_copy(recycle_signals)
    table_utils.for_each(quality_signals_copy, function(e, i) e.min = e.quality_unique_id end)

    local allowed_requested_crafts_copy = table_utils.deep_copy(allowed_requested_crafts)
    table_utils.for_each(allowed_requested_crafts_copy, function(e, i) e.min = e.unique_craft_id end)

    local need_recycle_constants_copy = table_utils.deep_copy(need_recycle_constants)
    table_utils.for_each(need_recycle_constants_copy, function(e, i) e.min = e.unique_craft_id end)


    local ingredients_constants_copy = table_utils.deep_copy(ingredients_constants)
    table_utils.for_each(ingredients_constants_copy, function(e, i) e.min = e.recipe_min end)

    entity_control.set_logistic_filters(entities.simple_rolling_secondary_cc_dst, allowed_requested_crafts_copy)
    entity_control.set_logistic_filters(entities.simple_rolling_secondary_cc_dst, quality_signals_copy)
    entity_control.set_logistic_filters(entities.simple_rolling_secondary_cc_dst, need_recycle_constants_copy)
    entity_control.set_logistic_filters(entities.simple_rolling_secondary_cc_dst, ingredients_constants_copy)
  end

  do
    if #allowed_requested_crafts > 0 then
      local quality_signals = {}
      for _, quality in ipairs(game_utils.get_all_qualities()) do
        local quality_signal = {
          value = {
            name = quality,
            type = "quality",
            quality = "normal"
          },
          min = 1
        }
        table.insert(quality_signals, quality_signal)
      end
      quality_signals = game_utils.merge_duplicates(quality_signals, game_utils.merge_max)
      entity_control.set_logistic_filters(entities.simple_rolling_main_cc_dst, quality_signals)
    end

    do
      local source_products_copy = table_utils.deep_copy(source_products)
      table_utils.for_each(source_products_copy, function(e, i) e.min = UNIQUE_ID_WIDTH end)

      local source_groups = table_utils.group_by(source_products_copy, function(e) return e.value.name end)
      for _, items in pairs(source_groups) do
        entity_control.set_logistic_filters(entities.simple_rolling_main_cc_dst, items, { active = false })
      end
    end
    do
      local all_ban_items_map = table_utils.to_map(table_utils.deep_copy(all_items), function(item) return item.value.name end)
      local all_qualities = game_utils.get_all_qualities()
      local all_ban_items = {}
      for _, quality in ipairs(all_qualities) do
          for _, item in pairs(all_ban_items_map) do
              local copy_item = table_utils.deep_copy(item)
              copy_item.value.quality = quality
              table.insert(all_ban_items, copy_item)
          end
      end
      table_utils.for_each(all_ban_items, function(e, i) e.min = BAN_ITEMS_OFFSET end)
      entity_control.set_logistic_filters(entities.simple_rolling_main_cc_dst, all_ban_items)
    end
    entity_control.set_logistic_filters(entities.simple_rolling_main_cc_dst, source_products)
    do
      local need_recycle_constants_copy = table_utils.deep_copy(need_recycle_constants)
      table_utils.for_each(need_recycle_constants_copy, function(e, i) e.min = BAN_ITEMS_OFFSET end)
      entity_control.set_logistic_filters(entities.simple_rolling_main_cc_dst, need_recycle_constants_copy)
    end
    do
      local need_recycle_constants_copy = table_utils.deep_copy(need_recycle_constants)
      table_utils.for_each(need_recycle_constants_copy, function(e, i) e.min = e.need_produce_count end)
      entity_control.set_logistic_filters(entities.simple_rolling_main_cc_dst, need_recycle_constants_copy)
    end
    do
      local ingredients_constants_copy = table_utils.deep_copy(ingredients_constants)
      table_utils.for_each(ingredients_constants_copy, function(e, i) e.min = BAN_ITEMS_OFFSET end)
      entity_control.set_logistic_filters(entities.simple_rolling_main_cc_dst, ingredients_constants_copy)
    end
    do
      local ingredients_constants_copy = table_utils.deep_copy(ingredients_constants)
      table_utils.for_each(ingredients_constants_copy, function(e, i) e.min = e.ingredient_min end)
      entity_control.set_logistic_filters(entities.simple_rolling_main_cc_dst, ingredients_constants_copy)
    end
    do
      local ingredients_constants_copy = table_utils.deep_copy(ingredients_constants)
      table_utils.for_each(ingredients_constants_copy, function(e, i) e.min = e.recipe_min end)
      entity_control.set_logistic_filters(entities.simple_rolling_main_cc_dst, ingredients_constants_copy)
    end
  end

  do
    local source_products_copy = table_utils.deep_copy(source_products)
    table_utils.for_each(source_products_copy, function(e, i) e.min = e.min end)
    entity_control.set_logistic_filters(entities.requester_rc_dst, source_products_copy, { multiplier = -1 })
  end

  do
    local recycle_signals_map = table_utils.to_map(recycle_signals, function(item) return item.value.quality end)
    local recycler_tree = OR()
    for _, item in ipairs(allowed_requested_crafts) do
      assert(recycle_signals_map[item.value.quality])
      local quality_signal = recycle_signals_map[item.value.quality]

      local forward = MAKE_IN(EACH, "=", item.value, RED_GREEN(true, false), RED_GREEN(true, false))
      local condition = MAKE_IN(quality_signal.value, "!=", 0, RED_GREEN(false, true), RED_GREEN(true, true))

      recycler_tree:add_child(AND(forward, condition))
    end


    local crafter_outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }

    entity_control.fill_decider_combinator(entities.recycler_dc_dst, decider_conditions.to_flat_dnf(recycler_tree), crafter_outputs)
  end

  local filter = nil
  if #allowed_requested_crafts > 0 then
    filter = {
      name = allowed_requested_crafts[1].value.name,
    }
  end
  if entities.manipulator_black then
    entities.manipulator_black.set_filter(1, filter)
  end
  if entities.manipulator_white then
    entities.manipulator_white.set_filter(1, filter)
  end
end

return make_simple_rolling
