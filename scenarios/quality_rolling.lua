local algorithm = require("llib.algorithm")
local EntityController = require("entity_controller")
local base = {
  recipes = require("base.recipes"),
  quality = require("base.quality"),
  decider_conditions = require("base.decider_conditions")
}

local OR = base.decider_conditions.Condition.OR
local AND = base.decider_conditions.Condition.AND
local MAKE_IN = base.decider_conditions.MAKE_IN
local MAKE_OUT = base.decider_conditions.MAKE_OUT
local RED_GREEN = base.decider_conditions.RED_GREEN
local GREEN_RED = base.decider_conditions.GREEN_RED
local MAKE_SIGNALS = EntityController.MAKE_SIGNALS
local ADD_SIGNAL = EntityController.ADD_SIGNAL
local ADD_FILTER = EntityController.ADD_FILTER
local MAKE_FILTERS = EntityController.MAKE_FILTERS
local EACH = base.decider_conditions.EACH
local EVERYTHING = base.decider_conditions.EVERYTHING

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
  local qualities_proto = base.quality.get_all_qualities();
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
    if bucket.count < #qualities_proto then
      local value = bucket.qualities[next(bucket.qualities)].value
      for _, proto in ipairs(qualities_proto) do
        local element = bucket.qualities[proto.name]
        if not element then
          table.insert(result, {
            value = base.recipes.make_value(value, proto.name),
            min = 2,
            missing_count = 2
          })
        elseif element.min == 1 then
          table.insert(result, {
            value = base.recipes.make_value(element.value, element.value.quality),
            min = 2,
            missing_count = 1
          })
        else
          table.insert(result, {
            value = base.recipes.make_value(element.value, element.value.quality),
            min = element.min,
            missing_count = 0
          })
        end
      end
    else
      for _, element in pairs(bucket.qualities) do
        table.insert(result, {
          value = base.recipes.make_value(element.value, element.value.quality),
          min = element.min,
          missing_count = 0
        })
      end
    end
  end
  return result
end

local function fill_recycle_signals(requests, objects)
  local next_letter_code = string.byte("1")
  local recycle_signals = {}
  local created_objects = {}

  for i, _, request in algorithm.enumerate(requests) do
    if not recycle_signals[request.object.name] then
      recycle_signals[request.object.name] = {
        name = "signal-" .. string.char(next_letter_code),
        type = "virtual",
      }
      next_letter_code = next_letter_code + 1
    end
    local recycle_virtual_object = base.recipes.get_or_create_object(objects, recycle_signals[request.object.name], request.object.quality)
    request.recycle_virtual_object = recycle_virtual_object
    created_objects[recycle_virtual_object.key] = recycle_virtual_object
    request.object.recycle_unique_id = UNIQUE_RECYCLE_ID_START + i
  end

  for i, _, object in algorithm.enumerate(created_objects) do
    object.quality_unique_id = UNIQUE_QUALITY_ID_START - i * UNIQUE_ID_WIDTH
  end
end

local function fill_quality_signals(requests, objects)
  local quality_signals = {}
  local created_objects = {}

  for _, request in pairs(requests) do
    if not quality_signals[request.object.quality] then
      quality_signals[request.object.quality] = {
          name = request.object.quality,
          type = "quality",
      }
    end
    local quality_virtual_object = base.recipes.get_or_create_object(objects, quality_signals[request.object.quality], "normal")
    request.quality_virtual_object = quality_virtual_object
    created_objects[quality_virtual_object.key] = quality_virtual_object
  end

  for i, _, object in algorithm.enumerate(created_objects) do
    object.is_virtual_quality = true
  end
end

-- Проверяем что машина может работать с этими запросами
-- На каждый запрос должен быть ровно один рецепт
-- Ингредиенты не могут быть продуктами
-- TODO: продукты разбора должны в точности совпадать с ингредиентами крафта
local function check_allowed_requests(requests)
  for _, request in pairs(requests) do
    local key, recipe = next(request.recipes)
    if key == nil or next(request.recipes, key) ~= nil then
      error("The product can only be crafted using one recipe.")
    end
    assert(recipe)
    for ingredient_key, _ in pairs(recipe.ingredients) do
      if requests[ingredient_key] ~= nil then
        error("It is prohibited to specify both a product and an ingredient at the same time.")
      end
    end
  end
end

local function fill_better_qualities(requests)
  for _, request in pairs(requests) do
    request.better_qualities = {}
    local next_quality_object = request.object.next_quality_object
    while next_quality_object ~= nil do
      assert(requests[next_quality_object.key])
      request.better_qualities[next_quality_object.key] = requests[next_quality_object.key]
      next_quality_object = next_quality_object.next_quality_object
    end
  end
end

local function fill_unique_recipe_id(objects)
  local sorted_recipes = {}
  for _, object in pairs(objects) do
    if object.type == "recipe" and object.order ~= nil then
      table.insert(sorted_recipes, object)
    end
  end

  -- сортируем качеству, а потом по порядку
  table.sort(sorted_recipes, function(a, b)
    local qa = base.quality.get_quality_index(a.quality)
    local qb = base.quality.get_quality_index(b.quality)

    if qa == qb then
      return a.order < b.order
    else
      return qa < qb
    end
  end)

  for i, object in ipairs(sorted_recipes) do
    object.unique_recipe_id = UNIQUE_RECIPE_ID_START + i * UNIQUE_ID_WIDTH
  end
end

local function fill_objects_max_count(requests)
  for _, product, recipe in base.recipes.requests_pairs(requests) do
    product.object.need_produce_max = math.max(product.object.need_produce_max or 0, recipe.need_produce_count)
    for _, ingredient in pairs(recipe.ingredients) do
      ingredient.object.full_produce_count_max = math.max(ingredient.object.full_produce_count_max or 0, ingredient.full_produce_count)
    end
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
    entities.recycler_dc_dst:fill_decider_combinator(base.decider_conditions.to_flat_dnf(recycler_tree), crafter_outputs)
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
      local choice_priority = MAKE_IN(EVERYTHING, ">", item.recycle_signal.quality_unique_id - UNIQUE_ID_WIDTH, RED_GREEN(false, true), RED_GREEN(true, false))

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
  entities.crafter_dc_dst:fill_decider_combinator(base.decider_conditions.to_flat_dnf(crafter_tree), crafter_outputs)
end

-- Для массива рецептов используем эту функцию, т.к. у нас всегда ровно один рецепт на продукт
local function first(map)
  return select(2, next(map))
end

function quality_rolling.run(entities, player)
  local raw_requests = entities.quality_rolling_main_cc_dst:read_all_logistic_filters()
  local prepared_requests = prepare_input(raw_requests)

  local objects = base.recipes.get_machine_objects(entities.crafter_machine.name)
  base.recipes.make_links(objects)
  local requests = base.recipes.fill_requests_map(prepared_requests, objects)
  check_allowed_requests(requests)
  fill_recycle_signals(requests, objects)
  fill_quality_signals(requests, objects)
  fill_better_qualities(requests)
  fill_unique_recipe_id(objects)
  fill_objects_max_count(requests)

  --fill_crafter_dc(entities, requests)

  entities.quality_rolling_main_cc_dst:set_logistic_filters(MAKE_SIGNALS(raw_requests), { multiplier = -1 })

  do
    local need_produce_max_filters = {}
    local full_produce_count_max_filters = {}
    local virtual_quality_filters = {}
    local recycle_unique_id_filters = {}
    local unique_recipe_id_filters = {}
    local quality_unique_id_filters = {}
    local all_ban_filters = {}
    for _, object in pairs(objects) do
      if object.need_produce_max ~= nil then ADD_SIGNAL(need_produce_max_filters, object, object.need_produce_max) end
      if object.full_produce_count_max ~= nil then ADD_SIGNAL(full_produce_count_max_filters, object, object.full_produce_count_max) end
      if object.is_virtual_quality ~= nil then ADD_SIGNAL(virtual_quality_filters, object, player.force.is_quality_unlocked(object.name) and 1 or 0) end
      if object.recycle_unique_id ~= nil then ADD_SIGNAL(recycle_unique_id_filters, object, object.recycle_unique_id) end
      if object.unique_recipe_id ~= nil then ADD_SIGNAL(unique_recipe_id_filters, object, object.unique_recipe_id) end
      if object.quality_unique_id ~= nil then ADD_SIGNAL(quality_unique_id_filters, object, object.quality_unique_id) end
      if object.type == "item" or (object.type == "fluid" and object.quality == "normal") then ADD_SIGNAL(all_ban_filters, object, BAN_ITEMS_OFFSET) end
    end
    if entities.provider_bc_src:has_logistic_sections() then
      entities.provider_bc_src:set_logistic_filters(need_produce_max_filters)
    end
    entities.requester_rc_dst:set_logistic_filters(full_produce_count_max_filters)
    entities.quality_rolling_main_cc_dst:set_logistic_filters(virtual_quality_filters)
    entities.quality_rolling_secondary_cc_dst:set_logistic_filters(recycle_unique_id_filters)
    entities.quality_rolling_secondary_cc_dst:set_logistic_filters(unique_recipe_id_filters)
    entities.quality_rolling_secondary_cc_dst:set_logistic_filters(quality_unique_id_filters)
    entities.quality_rolling_main_cc_dst:set_logistic_filters(all_ban_filters)
  end

  do
    local unique_named_objects = {}
    local filters = {}
    for _, request in pairs(requests) do
      unique_named_objects[request.object.name] = request.object
    end
    for _, object in pairs(unique_named_objects) do
      ADD_FILTER(filters, object)
    end
    entities.manipulator_black:set_filters(filters)
    entities.manipulator_white:set_filters(filters)
  end
end

return quality_rolling
