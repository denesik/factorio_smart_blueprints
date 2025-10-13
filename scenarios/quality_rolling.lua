local EntityFinder = require("entity_finder")
local algorithm = require("llib.algorithm")
local decider_conditions = require("decider_conditions")
local recipes = require("recipes")
local EntityController = require("entity_controller")
local utils = {
  quality = require("utils.quality")
}

local OR = decider_conditions.Condition.OR
local AND = decider_conditions.Condition.AND
local MAKE_IN = decider_conditions.MAKE_IN
local MAKE_OUT = decider_conditions.MAKE_OUT
local RED_GREEN = decider_conditions.RED_GREEN
local GREEN_RED = decider_conditions.GREEN_RED
local MAKE_SIGNALS = EntityController.MAKE_SIGNALS
local MAKE_FILTERS = EntityController.MAKE_FILTERS
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
-- удаляем дубликаты, игнорируем пустые и отрицательные
-- складываем одинаковые, добавляем недостающие (меньше 2 и промежуточного качества)
local function prepare_input(input)
  local qualities_proto = utils.quality.get_all_qualities();
  local grouped = {}

  -- первый проход: суммируем одинаковые и считаем количество качеств
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
            value = recipes.make_value(value, proto.name),
            min = 2,
            missing_count = 2
          })
        elseif element.min == 1 then
          table.insert(result, {
            value = recipes.make_value(element.value, element.value.quality),
            min = 2,
            missing_count = 1
          })
        else
          table.insert(result, {
            value = recipes.make_value(element.value, element.value.quality),
            min = element.min,
            missing_count = 0
          })
        end
      end
    else
      for _, element in pairs(bucket.qualities) do
        table.insert(result, {
          value = recipes.make_value(element.value, element.value.quality),
          min = element.min,
          missing_count = 0
        })
      end
    end
  end
  return result
end

local function fill_data_table(requests, ingredients)
  table.sort(requests, function(a, b)
    return utils.quality.get_quality_index(a.value.quality) < utils.quality.get_quality_index(b.value.quality)
  end)

  local allowed_requests_map = algorithm.to_map(requests, function(item) return recipes.make_key(item.value, item.value.quality) end)
  local recycle_signals = {}
  local next_letter_code = string.byte("1")

  for i, item in ipairs(requests) do
    for _, ingredient in pairs(item.ingredients) do
      ingredient.min = ingredient.request_min
      if allowed_requests_map[ingredient.value.key] then
        error("It is prohibited to specify both a product and an ingredient at the same time.")
      end
    end

    item.better_qualities = {}
    for _, proto in ipairs(utils.quality.get_all_better_qualities(item.value.quality)) do
      local quality_parent_key = recipes.make_key(item.value, proto.name)
      table.insert(item.better_qualities, allowed_requests_map[quality_parent_key])
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

  for i, item in ipairs(requests) do
    item.recipe_signal.unique_recipe_id = UNIQUE_RECIPE_ID_START + i * UNIQUE_ID_WIDTH
    item.need_produce_count = item.min
  end
end

local function fill_recycler_tree(entities, requests)
  -- Пробрасываем сигнал заказа если установлен сигнал на переработку этого заказа
  do
    local recycler_tree = OR()
    for _, item in ipairs(requests) do
      local forward = MAKE_IN(EACH, "=", item.value, RED_GREEN(true, false), RED_GREEN(true, false))
      local condition = MAKE_IN(item.recycle_signal.value, "!=", 0, RED_GREEN(false, true), RED_GREEN(true, true))
      recycler_tree:add_child(AND(forward, condition))
    end

    local crafter_outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
    entities.recycler_dc_dst:fill_decider_combinator(decider_conditions.to_flat_dnf(recycler_tree), crafter_outputs)
  end

  local recycler_tree = OR()
  for _, item in ipairs(requests) do
    -- Проверяем надо ли разбирать. 
    -- Если нужно скрафтить более качестванное и на это мало ингредиентов
    local ingredients_check = OR()
    for _, parent in ipairs(item.better_qualities) do
      for _, ingredient in pairs(parent.ingredients) do
        if ingredient.value.type ~= "fluid" then
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

local function fill_crafter_dc(entities, requests)
  local crafter_tree = OR()
  for _, item in ipairs(requests) do
    -- Начинаем крафт если ингредиентов хватает на два крафта
    local ingredients_check_first = AND()
    for _, ingredient in pairs(item.ingredients) do
      if ingredient.value.type ~= "fluid" then
        ingredients_check_first:add_child(MAKE_IN(ingredient.value, ">=", BAN_ITEMS_OFFSET + 2 * ingredient.recipe_min, RED_GREEN(false, true), RED_GREEN(true, true)))
      end
    end
    -- Продолжаем крафт, пока ингредиентов хватает хотя бы на один крафт
    local ingredients_check_second = AND()
    for _, ingredient in pairs(item.ingredients) do
      if ingredient.value.type ~= "fluid" then
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

  local recycler_tree = fill_recycler_tree(entities, requests)
  crafter_tree:add_child(recycler_tree)

  local crafter_outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
  entities.crafter_dc_dst:fill_decider_combinator(decider_conditions.to_flat_dnf(crafter_tree), crafter_outputs)
end

function quality_rolling.run(entities, player)
  local raw_requests = entities.quality_rolling_main_cc_dst:read_all_logistic_filters()

  local prepared_requests = prepare_input(raw_requests)
  local requests = recipes.enrich_with_recipes(prepared_requests, entities.crafter_machine.name)
  local ingredients = recipes.make_ingredients(requests)
  recipes.enrich_with_ingredients(requests, ingredients)
  fill_data_table(requests, ingredients)

  fill_crafter_dc(entities, requests)

  do
    if entities.provider_bc_src:get_logistic_sections() then
      entities.provider_bc_src:set_logistic_filters(MAKE_SIGNALS(requests))
    end
    local requests_filters = MAKE_SIGNALS(requests, function(e, i) return UNIQUE_RECYCLE_ID_START + i end)
    entities.quality_rolling_secondary_cc_dst:set_logistic_filters(requests_filters)
    entities.quality_rolling_main_cc_dst:set_logistic_filters(MAKE_SIGNALS(raw_requests), { multiplier = -1 })

    local resipes_id_filters = MAKE_SIGNALS(requests, function(e, i) return e.recipe_signal.unique_recipe_id, e.recipe_signal.value end)
    entities.quality_rolling_secondary_cc_dst:set_logistic_filters(resipes_id_filters)

    local recycles_id_filters = MAKE_SIGNALS(requests, function(e, i) return e.recycle_signal.recycle_unique_id, e.recycle_signal.value end)
    entities.quality_rolling_secondary_cc_dst:set_logistic_filters(recycles_id_filters)
  end

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
    entities.quality_rolling_main_cc_dst:set_logistic_filters(MAKE_SIGNALS(quality_signals))
  end

  do
    local request_ingredients = {}
    for _, item in ipairs(requests) do
      algorithm.append(request_ingredients, item.ingredients)
    end
    table.sort(request_ingredients, function(a, b)
      if a.value.key == b.value.key then
        return a.request_min > b.request_min
      end
      return a.value.key < b.value.key
    end)
    request_ingredients = algorithm.unique(request_ingredients, function(e) return e.value.key end)

    local request_ingredients_filters = MAKE_SIGNALS(request_ingredients, function(e, i) return e.request_min end)
    entities.requester_rc_dst:set_logistic_filters(request_ingredients_filters)
  end

  do
    local unique_requested_crafts = requests
    table.sort(unique_requested_crafts, function(a, b)
      return recipes.make_key(a.value) < recipes.make_key(b.value)
    end)
    unique_requested_crafts = algorithm.unique(unique_requested_crafts, function(e) return recipes.make_key(e.value) end)
    entities.manipulator_black:set_filters(MAKE_FILTERS(unique_requested_crafts))
    entities.manipulator_white:set_filters(MAKE_FILTERS(unique_requested_crafts))
  end

  do
    local all_ingredients = recipes.get_machine_ingredients(entities.crafter_machine.name)
    local all_products = recipes.get_machine_products(entities.crafter_machine.name)
    local all_filters = MAKE_SIGNALS(algorithm.merge(all_ingredients, all_products), function(e, i) return BAN_ITEMS_OFFSET end)
    entities.quality_rolling_main_cc_dst:set_logistic_filters(all_filters)
  end
end

return quality_rolling
