local EntityFinder = require("entity_finder")
local recipe_selector = require("recipe_selector")
local game_utils = require("game_utils")
local signal_selector = require("signal_selector")
local table_utils = require("common.table_utils")
local entity_control = require("entity_control")
local decider_conditions = require("decider_conditions")
local recipe_decomposer = require("recipe_decomposer")
require("util")

local OR = decider_conditions.Condition.OR
local AND = decider_conditions.Condition.AND
local MAKE_IN = decider_conditions.MAKE_IN
local MAKE_OUT = decider_conditions.MAKE_OUT
local RED_GREEN = decider_conditions.RED_GREEN
local GREEN_RED = decider_conditions.GREEN_RED
local EACH = decider_conditions.EACH
local EVERYTHING = decider_conditions.EVERYTHING

local UNIQUE_QUALITY_ID_START     = -10000000
local UNIQUE_CRAFT_ITEMS_ID_START = 10000000
local BAN_ITEMS_OFFSET            = -1000000
local UNIQUE_ID_WIDTH = 10000

local quality_rolling = {}

quality_rolling.name = "quality_rolling"

local function fill_recycler_tree(entities, allowed_requested_crafts)
  -- Пробрасываем сигнал заказа если установлен сигнал на переработку этого заказа
  do
    local recycler_tree = OR()
    for _, item in ipairs(allowed_requested_crafts) do
      local forward = MAKE_IN(EACH, "=", item.value, RED_GREEN(true, false), RED_GREEN(true, false))
      local condition = MAKE_IN(item.recycle_signal.value, "!=", 0, RED_GREEN(false, true), RED_GREEN(true, true))
      recycler_tree:add_child(AND(forward, condition))
    end

    local crafter_outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
    entity_control.fill_decider_combinator(entities.recycler_dc_dst, decider_conditions.to_flat_dnf(recycler_tree), crafter_outputs)
  end

  local recycler_tree = OR()
  for _, item in ipairs(allowed_requested_crafts) do
    -- Проверяем надо ли разбирать. 
    -- Если нужно скрафтить более качестванное и на это мало ингредиентов
    local ingredients_check = OR()
    for _, parent in ipairs(item.better_qualities) do
      for _, ingredient in ipairs(parent.ingredients) do
        if not game_utils.is_fluid(ingredient) then
            -- Если предмет более высого качества мало и мы его не крафтим (< 100)
            -- Если предмет более высого качества мало и мы его крафтим (< 100)
            -- Если ингредиент более высокого качества мало (<100)
            -- Если разрешено крафтить это качество
            local parent_check_direct = MAKE_IN(parent.value, "<", BAN_ITEMS_OFFSET, RED_GREEN(false, true), RED_GREEN(true, true))
            local parent_check_offset = AND(
              MAKE_IN(parent.value, ">=", BAN_ITEMS_OFFSET + UNIQUE_CRAFT_ITEMS_ID_START, RED_GREEN(false, true), RED_GREEN(true, true)),
              MAKE_IN(parent.value, "<", BAN_ITEMS_OFFSET + parent.unique_craft_id, RED_GREEN(false, true), RED_GREEN(true, true))
            )
            local ingredient_check = MAKE_IN(ingredient.value, "<", BAN_ITEMS_OFFSET, RED_GREEN(false, true), RED_GREEN(true, true))
            local quality_check = MAKE_IN({ name = parent.value.quality, type = "quality" }, "!=", 0, GREEN_RED(true, false), GREEN_RED(true, true))
            ingredients_check:add_child(AND(OR(parent_check_offset, parent_check_direct), ingredient_check, quality_check))
        end
      end
    end

    if not ingredients_check:is_empty() then
      -- Создаем, и запоминаем один приоритетный сигнал переработки
      local first_lock = MAKE_IN(EVERYTHING, ">", UNIQUE_QUALITY_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
      local second_lock = MAKE_IN(item.recycle_signal.value, "<", UNIQUE_QUALITY_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
      local choice_priority = MAKE_IN(EVERYTHING, ">", item.recycle_signal.recycle_unique_id - UNIQUE_ID_WIDTH, RED_GREEN(false, true), RED_GREEN(true, false))

      local forward = MAKE_IN(EACH, "=", item.recycle_signal.value, RED_GREEN(true, false), RED_GREEN(true, false))
      -- Если предмет много и мы его не крафтим (>= 100)
      -- Если предмет есть и мы его не крафтим (> 0)
      local need_recycle_start_direct = AND(
        MAKE_IN(item.value, ">=", BAN_ITEMS_OFFSET, RED_GREEN(false, true), RED_GREEN(true, true)),
        MAKE_IN(item.value, "<", BAN_ITEMS_OFFSET + UNIQUE_CRAFT_ITEMS_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
      )
      local need_recycle_continue_direct = AND(
        MAKE_IN(item.value, ">", item.need_produce_offset, RED_GREEN(false, true), RED_GREEN(false, true)),
        MAKE_IN(item.value, "<", BAN_ITEMS_OFFSET + UNIQUE_CRAFT_ITEMS_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
      )
      -- Если предмет много и мы его крафтим (>= 100)
      -- Если предмет есть и мы его крафтим (> 0)
      local need_recycle_start_offset = MAKE_IN(item.value, ">=", BAN_ITEMS_OFFSET + item.unique_craft_id, RED_GREEN(false, true), RED_GREEN(true, true))
      local need_recycle_continue_offset = MAKE_IN(item.value, ">", item.need_produce_offset + item.unique_craft_id, RED_GREEN(false, true), RED_GREEN(true, true))

      recycler_tree:add_child(AND(forward, OR(need_recycle_start_direct, need_recycle_start_offset), ingredients_check, first_lock))
      recycler_tree:add_child(AND(forward, OR(need_recycle_continue_direct, need_recycle_continue_offset), ingredients_check, second_lock, choice_priority))
    end
  end

  do
    local quality_signals_copy = util.table.deepcopy(allowed_requested_crafts)
    table_utils.for_each(quality_signals_copy, function(e, i) e.value = e.recycle_signal.value e.min = e.recycle_signal.recycle_unique_id end)
    entity_control.set_logistic_filters(entities.quality_rolling_secondary_cc_dst, quality_signals_copy)
  end

  return recycler_tree
end

function quality_rolling.run(player, area)
  local defs = {
    {name = "crafter_dc_dst",                   label = "<quality_rolling_crafter_dc>",   type = "decider-combinator"},
    {name = "quality_rolling_main_cc_dst",      label = "<quality_rolling_main_cc>",      type = "constant-combinator"},
    {name = "quality_rolling_secondary_cc_dst", label = "<quality_rolling_secondary_cc>", type = "constant-combinator"},
    {name = "crafter_machine",                  label = 583402,                           type = "assembling-machine"},
    {name = "requester_rc_dst",                 label = 583401,                           type = "logistic-container"},
    {name = "recycler_dc_dst",                  label = "<quality_rolling_recycler_dc>",  type = "decider-combinator"},
    {name = "manipulator_black",                label = 583403,                           type = "inserter"},
    {name = "manipulator_white",                label = 583404,                           type = "inserter"},
  }

  local entities = EntityFinder.new(player.surface, area, defs)

  local allowed_recipes = recipe_selector.get_machine_recipes(entity_control.get_name(entities.crafter_machine))

  local requested_crafts = entity_control.read_all_logistic_filters(entities.quality_rolling_main_cc_dst)
  requested_crafts = game_utils.merge_duplicates(requested_crafts, game_utils.merge_sum)

  local allowed_requested_crafts = signal_selector.filter_by(requested_crafts, function(item)
    return signal_selector.is_filtered_by_recipe_any(item,
      function(recipe_name, recipe)
        return recipe_selector.can_craft_from_machine(recipe_name, recipe, entity_control.get_name(entities.crafter_machine))
      end)
  end)

  -- Добаляем запросы отсутсвующих качеств
  do
    local additional_requests = {}
    local allowed_requested_crafts_map = table_utils.to_map(allowed_requested_crafts, function(item) return game_utils.items_key_fn(item) end)
    local unique_requested_crafts = game_utils.merge_duplicates(allowed_requested_crafts, game_utils.merge_min, function(v)
      return v.value.name .. "|" .. v.value.type
    end)
    if #unique_requested_crafts > 5 then
      error("You cannot specify more than five items of each quality.")
    end
    for _, quality in ipairs(game_utils.get_all_qualities()) do
      for _, item in ipairs(unique_requested_crafts) do
        local quality_item = {
          value = {
            name = item.value.name,
            type = item.value.type,
            quality = quality
          },
          min = -2
        }
        local found = allowed_requested_crafts_map[game_utils.items_key_fn(quality_item)]
        if not found then
          table.insert(allowed_requested_crafts, quality_item)
          table.insert(additional_requests, quality_item)
        elseif found.min == -1 then
          found.min = -2
          quality_item.min = -1
          table.insert(additional_requests, quality_item)
        end
      end
    end
    entity_control.set_logistic_filters(entities.quality_rolling_main_cc_dst, additional_requests)
  end

  -- Не используем сигналы рецептов. На каждый заказ может быть только один рецепт крафта
  do
    local out = {}
    for _, item in ipairs(allowed_requested_crafts) do
      local recipes = game_utils.get_recipes_for_signal(allowed_recipes, item)
      for _, recipe in pairs(recipes) do
        local extended_item = util.table.deepcopy(item)
        extended_item.recipe = recipe
        table.insert(out, extended_item)
      end
    end
    allowed_requested_crafts = out
  end

  table.sort(allowed_requested_crafts, function(a, b)
    return game_utils.get_quality_index(a.value.quality) < game_utils.get_quality_index(b.value.quality)
  end)

  do
    local allowed_requested_crafts_map = table_utils.to_map(allowed_requested_crafts, function(item) return game_utils.items_key_fn(item) end)
    local signals = {}
    local next_letter_code = string.byte("1")

    table_utils.for_each(allowed_requested_crafts, function(item, i)
      item.unique_craft_id = UNIQUE_CRAFT_ITEMS_ID_START + i * UNIQUE_ID_WIDTH
      item.need_produce_count = item.min
      item.ingredients = {}
      for _, ingredient in ipairs(item.recipe.ingredients) do
        local ingredient_signal = game_utils.make_signal(ingredient, item.value.quality)
        ingredient_signal.recipe_min = ingredient_signal.min
        ingredient_signal.min = ingredient_signal.min * (item.min / item.recipe.main_product.amount)
        table.insert(item.ingredients, ingredient_signal)
        if allowed_requested_crafts_map[game_utils.items_key_fn(ingredient_signal)] then
          error("It is prohibited to specify both a product and an ingredient at the same time.")
        end
      end
      item.better_qualities = {}
      for _, quality in ipairs(game_utils.get_all_better_qualities(item.value.quality)) do
        local quality_parent = {
          value = {
            name = item.value.name,
            type = item.value.type,
            quality = quality
          },
          min = 0
        }
        table.insert(item.better_qualities, allowed_requested_crafts_map[game_utils.items_key_fn(quality_parent)])
      end
      do
        if not signals[item.value.name] then
          signals[item.value.name] = string.char(next_letter_code)
          next_letter_code = next_letter_code + 1
        end
        item.recycle_signal = {
          value = {
            name = "signal-" .. signals[item.value.name],
            type = "virtual",
            quality = item.value.quality
          },
          recycle_unique_id = UNIQUE_QUALITY_ID_START - i * UNIQUE_ID_WIDTH
        }
      end
      item.need_produce_offset = BAN_ITEMS_OFFSET + item.need_produce_count
    end)
  end

  do
    local crafter_tree = OR()
    for _, item in ipairs(allowed_requested_crafts) do
      -- Начинаем крафт если ингредиентов хватает на два крафта
      local ingredients_check_first = AND()
      for _, ingredient in ipairs(item.ingredients) do
        if not game_utils.is_fluid(ingredient) then
          ingredients_check_first:add_child(MAKE_IN(ingredient.value, ">=", BAN_ITEMS_OFFSET + ingredient.min + 2 * ingredient.recipe_min, RED_GREEN(false, true), RED_GREEN(true, true)))
        end
      end
      -- Продолжаем крафт, пока ингредиентов хватает хотя бы на один крафт
      local ingredients_check_second = AND()
      for _, ingredient in ipairs(item.ingredients) do
        if not game_utils.is_fluid(ingredient) then
          ingredients_check_second:add_child(MAKE_IN(ingredient.value, ">=", BAN_ITEMS_OFFSET + ingredient.min + ingredient.recipe_min, RED_GREEN(false, true), RED_GREEN(false, true)))
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

    local recycler_tree = fill_recycler_tree(entities, allowed_requested_crafts)
    crafter_tree:add_child(recycler_tree)

    local crafter_outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
    entity_control.fill_decider_combinator(entities.crafter_dc_dst, decider_conditions.to_flat_dnf(crafter_tree), crafter_outputs)
  end

  do
    local allowed_requested_crafts_copy = util.table.deepcopy(allowed_requested_crafts)
    table_utils.for_each(allowed_requested_crafts_copy, function(e, i) e.min = e.unique_craft_id end)
    entity_control.set_logistic_filters(entities.quality_rolling_secondary_cc_dst, allowed_requested_crafts_copy)
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
        if not player.force.is_quality_unlocked(quality) then
          quality_signal.min = 0
        end
        table.insert(quality_signals, quality_signal)
      end
      entity_control.set_logistic_filters(entities.quality_rolling_main_cc_dst, quality_signals)
    end

    do
      -- TODO: Избыточно. Генерировать промежуточные сигналы выше
      local source_products = recipe_decomposer.decompose_once(allowed_recipes, allowed_requested_crafts, recipe_decomposer.deep_strategy)
      source_products = game_utils.merge_duplicates(source_products, game_utils.merge_min)
      local all_items = {}
      table_utils.extend(all_items, allowed_requested_crafts)
      table_utils.extend(all_items, source_products)
      local all_ban_items_map = table_utils.to_map(util.table.deepcopy(all_items), function(item) return item.value.name end)
      local all_qualities = game_utils.get_all_qualities()
      local all_ban_items = {}
      for _, quality in ipairs(all_qualities) do
        for _, item in pairs(all_ban_items_map) do
          local copy_item = util.table.deepcopy(item)
          copy_item.value.quality = quality
          table.insert(all_ban_items, copy_item)
        end
      end
      table_utils.for_each(all_ban_items, function(e, i) e.min = BAN_ITEMS_OFFSET end)
      entity_control.set_logistic_filters(entities.quality_rolling_main_cc_dst, all_ban_items)

      entity_control.set_logistic_filters(entities.quality_rolling_main_cc_dst, source_products)
      entity_control.set_logistic_filters(entities.requester_rc_dst, source_products, { multiplier = -1 })
    end
  end

  do
    local unique_requested_crafts = game_utils.merge_duplicates(allowed_requested_crafts, game_utils.merge_min, function(v)
      return v.value.name .. "|" .. v.value.type
    end)
    for i, item in ipairs(unique_requested_crafts) do
      filter = {
        name = item.value.name,
      }
      if entities.manipulator_black then
        entities.manipulator_black.set_filter(i, filter)
      end
      if entities.manipulator_white then
        entities.manipulator_white.set_filter(i, filter)
      end
    end
    for i = #unique_requested_crafts + 1, 5 do
      if entities.manipulator_black then
        entities.manipulator_black.set_filter(i, {})
      end
      if entities.manipulator_white then
        entities.manipulator_white.set_filter(i, {})
      end
    end
  end
end

return quality_rolling
