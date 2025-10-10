local EntityFinder = require("entity_finder")
local game_utils = require("game_utils")
local algorithm = require("llib.algorithm")
local decider_conditions = require("decider_conditions")
local recipes = require("recipes")
local utils = {
  quality = require("utils.quality")
}

local OR = decider_conditions.Condition.OR
local AND = decider_conditions.Condition.AND
local MAKE_IN = decider_conditions.MAKE_IN
local MAKE_OUT = decider_conditions.MAKE_OUT
local RED_GREEN = decider_conditions.RED_GREEN
local GREEN_RED = decider_conditions.GREEN_RED
local EACH = decider_conditions.EACH
local EVERYTHING = decider_conditions.EVERYTHING

local UNIQUE_QUALITY_ID_START = -10000000
local UNIQUE_RECIPE_ID_START  = 10000000
local UNIQUE_RECYCLE_ID_START = 0
local BAN_ITEMS_OFFSET        = -1000000
local UNIQUE_ID_WIDTH         = 10000 -- TODO: удалить

local quality_rolling = {}

quality_rolling.name = "quality_rolling"

quality_rolling.defines = {
  {name = "crafter_dc_dst",                   label = "<quality_rolling_crafter_dc>",   type = "decider-combinator"},
  {name = "quality_rolling_main_cc_dst",      label = "<quality_rolling_main_cc>",      type = "constant-combinator"},
  {name = "quality_rolling_secondary_cc_dst", label = "<quality_rolling_secondary_cc>", type = "constant-combinator"},
  {name = "crafter_machine",                  label = 583402,                           type = "assembling-machine"},
  {name = "requester_rc_dst",                 label = 583401,                           type = "logistic-container"},
  {name = "provider_bc_src",                  label = 583405,                           type = "logistic-container"},
  {name = "recycler_dc_dst",                  label = "<quality_rolling_recycler_dc>",  type = "decider-combinator"},
  {name = "manipulator_black",                label = 583403,                           type = "inserter"},
  {name = "manipulator_white",                label = 583404,                           type = "inserter"},
}

-- Подготавливаем входные сигналы
-- удаляем дубликаты, игнорируем пустые и положительные
-- складываем одинаковые, добавляем недостающие (меньше 2 и промежуточного качества)
local function prepare_input(input)
  local qualities_proto = utils.quality.get_all_qualities();
  local grouped = {}

  -- первый проход: суммируем min и считаем количество качеств
  local group_count = 0
  for _, element in ipairs(input) do
    if element.min > 0 then
      local key = element.value.type .. "|" .. element.value.name

      if not grouped[key] then
        grouped[key] = { count = 0, qualities = {} }
        group_count = group_count + 1
      end

      local bucket = grouped[key]
      local slot = bucket.qualities[element.value.quality]

      if slot then
        slot.min = slot.min + element.min
      else
        bucket.qualities[element.value.quality] = element
        bucket.count = bucket.count + 1
      end
    end
  end

  if group_count > 5 then
    error("You cannot specify more than five items of each quality.")
  end

  -- второй проход: добавляем недостающие качества
  -- у нас должно получиться как минимум по 2 элемента каждого качества
  local result = {}
  for _, bucket in pairs(grouped) do
    if bucket.count < 5 then
      local value = bucket.qualities[next(bucket.qualities)].value
      for _, proto in ipairs(qualities_proto) do
        local element = bucket.qualities[proto.name]
        if not element then
          table.insert(result, {
            value = { quality = proto.name, type = value.type, name = value.name },
            min = 2,
            missing_count = 2
          })
        elseif element.min == 1 then
          table.insert(result, {
            value = { quality = element.value.quality, type = element.value.type, name = element.value.name },
            min = 2,
            missing_count = 1
          })
        else
          table.insert(result, {
            value = { quality = element.value.quality, type = element.value.type, name = element.value.name },
            min = element.min,
            missing_count = 0
          })
        end
      end
    else
      for _, element in pairs(bucket.qualities) do
        table.insert(result, {
          value = { quality = element.value.quality, type = element.value.type, name = element.value.name },
          min = element.min,
          missing_count = 0
        })
      end
    end
  end
  return result
end

local function fill_data_table(requests)
  table.sort(requests, function(a, b)
    return utils.quality.get_quality_index(a.value.quality) < utils.quality.get_quality_index(b.value.quality)
  end)

  local allowed_requests_map = algorithm.to_map(requests, function(item) return game_utils.items_key_fn(item) end)
  local recycle_signals = {}
  local next_letter_code = string.byte("1")

  for i, item in ipairs(requests) do
    item.recipe_signal = game_utils.recipe_as_signal(item.recipe, item.value.quality)
    item.recipe_signal.unique_recipe_id = UNIQUE_RECIPE_ID_START + i * UNIQUE_ID_WIDTH
    item.need_produce_count = item.min
    item.ingredients = {}
    for _, ingredient in ipairs(item.recipe.ingredients) do
      local ingredient_signal = game_utils.make_signal(ingredient, item.value.quality)
      ingredient_signal.recipe_min = ingredient_signal.min
      ingredient_signal.min = ingredient_signal.min * (item.min / item.recipe.main_product.amount)
      table.insert(item.ingredients, ingredient_signal)
      if allowed_requests_map[game_utils.items_key_fn(ingredient_signal)] then
        error("It is prohibited to specify both a product and an ingredient at the same time.")
      end
    end
    item.better_qualities = {}
    for _, proto in ipairs(utils.quality.get_all_better_qualities(item.value.quality)) do
      local quality_parent = {
        value = {
          name = item.value.name,
          type = item.value.type,
          quality = proto.name
        }
      }
      table.insert(item.better_qualities, allowed_requests_map[game_utils.items_key_fn(quality_parent)])
    end
    do
      if not recycle_signals[item.value.name] then
        recycle_signals[item.value.name] = string.char(next_letter_code)
        next_letter_code = next_letter_code + 1
      end
      item.recycle_signal = {
        value = {
          name = "signal-" .. recycle_signals[item.value.name],
          type = "virtual",
          quality = item.value.quality
        },
        recycle_unique_id = UNIQUE_QUALITY_ID_START - i * UNIQUE_ID_WIDTH
      }
    end
  end

  for _, item in ipairs(requests) do
    item.recipe = nil
  end
end

local function fill_recycler_tree(entity_control, entities, requests)
  -- Пробрасываем сигнал заказа если установлен сигнал на переработку этого заказа
  do
    local recycler_tree = OR()
    for _, item in ipairs(requests) do
      local forward = MAKE_IN(EACH, "=", item.value, RED_GREEN(true, false), RED_GREEN(true, false))
      local condition = MAKE_IN(item.recycle_signal.value, "!=", 0, RED_GREEN(false, true), RED_GREEN(true, true))
      recycler_tree:add_child(AND(forward, condition))
    end

    local crafter_outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
    entity_control.fill_decider_combinator(entities.recycler_dc_dst, decider_conditions.to_flat_dnf(recycler_tree), crafter_outputs)
  end

  local recycler_tree = OR()
  for _, item in ipairs(requests) do
    -- Проверяем надо ли разбирать. 
    -- Если нужно скрафтить более качестванное и на это мало ингредиентов
    local ingredients_check = OR()
    for _, parent in ipairs(item.better_qualities) do
      for _, ingredient in ipairs(parent.ingredients) do
        if not game_utils.is_fluid(ingredient) then
            -- Если предмет более высого качества мало (< 100)
            -- Если ингредиент более высокого качества мало (<100)
            -- Если разрешено крафтить это качество
            local parent_check = MAKE_IN(parent.value, "<", BAN_ITEMS_OFFSET + parent.need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true))
            local ingredient_check = MAKE_IN(ingredient.value, "<", BAN_ITEMS_OFFSET + ingredient.min, RED_GREEN(false, true), RED_GREEN(true, true))
            local quality_check = MAKE_IN({ name = parent.value.quality, type = "quality" }, "!=", 0, GREEN_RED(true, false), GREEN_RED(true, true))
            ingredients_check:add_child(AND(parent_check, ingredient_check, quality_check))
        end
      end
    end

    if not ingredients_check:is_empty() then
      -- Создаем, и запоминаем один приоритетный сигнал переработки
      local forward = MAKE_IN(EACH, "=", item.recycle_signal.value, RED_GREEN(true, false), RED_GREEN(true, false))
      local first_lock = MAKE_IN(EVERYTHING, ">", UNIQUE_QUALITY_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
      local second_lock = MAKE_IN(item.recycle_signal.value, "<", UNIQUE_QUALITY_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
      local choice_priority = MAKE_IN(EVERYTHING, ">", item.recycle_signal.recycle_unique_id - UNIQUE_ID_WIDTH, RED_GREEN(false, true), RED_GREEN(true, false))

      -- Если предмет много (>= 100)
      -- Если предмет есть (> 0)
      local need_recycle_start = MAKE_IN(item.value, ">=", BAN_ITEMS_OFFSET + item.need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true))
      local need_recycle_continue = MAKE_IN(item.value, ">", BAN_ITEMS_OFFSET, RED_GREEN(false, true), RED_GREEN(false, true))

      recycler_tree:add_child(AND(forward, need_recycle_start, ingredients_check, first_lock))
      recycler_tree:add_child(AND(forward, need_recycle_continue, ingredients_check, second_lock, choice_priority))
    end
  end

  return recycler_tree
end

local function fill_crafter_dc(entity_control, entities, requests)
  local crafter_tree = OR()
  for _, item in ipairs(requests) do
    -- Начинаем крафт если ингредиентов хватает на два крафта
    local ingredients_check_first = AND()
    for _, ingredient in ipairs(item.ingredients) do
      if not game_utils.is_fluid(ingredient) then
        ingredients_check_first:add_child(MAKE_IN(ingredient.value, ">=", BAN_ITEMS_OFFSET + 2 * ingredient.recipe_min, RED_GREEN(false, true), RED_GREEN(true, true)))
      end
    end
    -- Продолжаем крафт, пока ингредиентов хватает хотя бы на один крафт
    local ingredients_check_second = AND()
    for _, ingredient in ipairs(item.ingredients) do
      if not game_utils.is_fluid(ingredient) then
        ingredients_check_second:add_child(MAKE_IN(ingredient.value, ">=", BAN_ITEMS_OFFSET + ingredient.recipe_min, RED_GREEN(false, true), RED_GREEN(false, true)))
      end
    end

    local forward = MAKE_IN(EACH, "=", item.recipe_signal.value, RED_GREEN(true, false), RED_GREEN(true, false))
    local first_lock = MAKE_IN(EVERYTHING, "<", UNIQUE_RECIPE_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
    local second_lock = MAKE_IN(item.recipe_signal.value, ">", UNIQUE_RECIPE_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
    local choice_priority = MAKE_IN(EVERYTHING, "<=", item.recipe_signal.unique_recipe_id, RED_GREEN(false, true), RED_GREEN(true, false))

    local need_produce = MAKE_IN(item.value, "<", BAN_ITEMS_OFFSET + item.need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true))

    crafter_tree:add_child(AND(forward, ingredients_check_first, need_produce, first_lock))
    crafter_tree:add_child(AND(forward, ingredients_check_second, need_produce, second_lock, choice_priority))
  end

  local recycler_tree = fill_recycler_tree(entity_control, entities, requests)
  crafter_tree:add_child(recycler_tree)

  local crafter_outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
  entity_control.fill_decider_combinator(entities.crafter_dc_dst, decider_conditions.to_flat_dnf(crafter_tree), crafter_outputs)
end

function quality_rolling.run(entity_control, entities, player)
  local raw_requests = entity_control.read_all_logistic_filters(entities.quality_rolling_main_cc_dst)

  local prepared_requests = prepare_input(raw_requests)
  local requests = recipes.enrich_with_recipes(prepared_requests, entity_control.get_name(entities.crafter_machine))
  fill_data_table(requests)

  fill_crafter_dc(entity_control, entities, requests)

  do
    if entity_control.get_logistic_sections(entities.provider_bc_src) then
      entity_control.set_logistic_filters(entities.provider_bc_src, game_utils.make_logistic_signals(requests))
    end
    local requests_filters = game_utils.make_logistic_signals(requests, function(e, i) return UNIQUE_RECYCLE_ID_START + i end)
    entity_control.set_logistic_filters(entities.quality_rolling_secondary_cc_dst, requests_filters)
    entity_control.set_logistic_filters(entities.quality_rolling_main_cc_dst, game_utils.make_logistic_signals(raw_requests), { multiplier = -1 })

    local resipes_id_filters = game_utils.make_logistic_signals(requests, function(e, i) return e.recipe_signal.unique_recipe_id, e.recipe_signal.value end)
    entity_control.set_logistic_filters(entities.quality_rolling_secondary_cc_dst, resipes_id_filters)

    local recycles_id_filters = game_utils.make_logistic_signals(requests, function(e, i) return e.recycle_signal.recycle_unique_id, e.recycle_signal.value end)
    entity_control.set_logistic_filters(entities.quality_rolling_secondary_cc_dst, recycles_id_filters)
  end

  do
    if #requests > 0 then
      local quality_signals = {}
      for _, proto in ipairs(utils.quality.get_all_qualities()) do
        local quality_signal = {
          value = {
            name = proto.name,
            type = "quality",
            quality = "normal"
          },
          min = 1
        }
        if not player.force.is_quality_unlocked(proto.name) then
          quality_signal.min = 0
        end
        table.insert(quality_signals, quality_signal)
      end
      entity_control.set_logistic_filters(entities.quality_rolling_main_cc_dst, game_utils.make_logistic_signals(quality_signals))
    end

    do
      local ingredients = {}
      for _, item in ipairs(requests) do
        for _, ingredient in ipairs(item.ingredients) do
          table.insert(ingredients, ingredient)
        end
      end
      ingredients = game_utils.merge_duplicates(ingredients, game_utils.merge_max)
      entity_control.set_logistic_filters(entities.requester_rc_dst, game_utils.make_logistic_signals(ingredients))
      local all_items = {}
      algorithm.extend(all_items, requests)
      algorithm.extend(all_items, ingredients)

      algorithm.for_each(all_items, function(e, i) e.min = BAN_ITEMS_OFFSET end)
      entity_control.set_logistic_filters(entities.quality_rolling_main_cc_dst, game_utils.make_logistic_signals(all_items))
    end
  end

  do
    local unique_requested_crafts = game_utils.merge_duplicates(requests, game_utils.merge_max, function(v)
      return v.value.name .. "|" .. v.value.type
    end)
    for i, item in ipairs(unique_requested_crafts) do
      local filter = {
        name = item.value.name,
      }
      entity_control.set_filter(entities.manipulator_black, i, filter)
      entity_control.set_filter(entities.manipulator_white, i, filter)
    end
    for i = #unique_requested_crafts + 1, 5 do
      entity_control.set_filter(entities.manipulator_black, i, {})
      entity_control.set_filter(entities.manipulator_white, i, {})
    end
  end
end

return quality_rolling
