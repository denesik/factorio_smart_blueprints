local algorithm = require("llib.algorithm")
local EntityController = require("entity_controller")

local base = {
  recipes = require("base.recipes"),
  barrel = require("base.barrel"),
  decider_conditions = require("base.decider_conditions")
}

local OR = base.decider_conditions.Condition.OR
local AND = base.decider_conditions.Condition.AND
local MAKE_IN = base.decider_conditions.MAKE_IN
local MAKE_OUT = base.decider_conditions.MAKE_OUT
local RED_GREEN = base.decider_conditions.RED_GREEN
local MAKE_SIGNALS = EntityController.MAKE_SIGNALS
local ADD_SIGNAL = EntityController.ADD_SIGNAL
local EACH = base.decider_conditions.EACH
local EVERYTHING = base.decider_conditions.EVERYTHING
local ANYTHING = base.decider_conditions.ANYTHING

local UNIQUE_RECIPE_ID_START  = 1000000
local UNIQUE_FLUID_ID_START   = -110000
local BAN_ITEMS_OFFSET        = -1000000
local BAN_RECIPES_OFFSET      = -10000000
local FILTER_ITEMS_OFFSET     = 10000000
local FILTER_ITEMS_WIDTH      = 100000

local PC_FLUID_EMPTY_TICKS = 10
local FLUID_RECIPE_WAIT_TICKS = 20
local PC_FLUID_BAN_OFFSET = -100000000
local PC_FLUID_EMPTY_TICKS_OFFSET = PC_FLUID_BAN_OFFSET + PC_FLUID_EMPTY_TICKS

local BARREL_CAPACITY = 50 -- TODO: использовать значение из рецепта
local TANK_MINIMUM_CAPACITY = 3000

local multi_assembler = {}

multi_assembler.name = "multi_assembler"

multi_assembler.defines = {
  {name = "main_cc",              label = "<multi_assembler_main_cc>",              type = "constant-combinator"},
  {name = "secondary_cc",         label = "<multi_assembler_secondary_cc>",         type = "constant-combinator"},
  {name = "ban_recipes_empty_cc", label = "<multi_assembler_ban_recipes_empty_cc>", type = "constant-combinator"},
  {name = "ban_recipes_fill_cc",  label = "<multi_assembler_ban_recipes_fill_cc>",  type = "constant-combinator"},
  {name = "crafter_machine",      label = 881781,                                   type = "assembling-machine"},
  {name = "crafter_dc",           label = "<multi_assembler_crafter_dc>",           type = "decider-combinator"},
  {name = "fluids_empty_dc",      label = "<multi_assembler_fluids_empty_dc>",      type = "decider-combinator"},
  {name = "fluids_fill_dc",       label = "<multi_assembler_fluids_fill_dc>",       type = "decider-combinator"},
  {name = "requester_rc",         label = 881782,                                   type = "logistic-container", multiple = true},
  {name = "barrels_rc",           label = 881783,                                   type = "logistic-container"},
  {name = "chest_priority_dc",    label = "<multi_assembler_chest_priority_dc>",    type = "decider-combinator"},
  {name = "chest_priority_cc",    label = "<multi_assembler_chest_priority_cc>",    type = "constant-combinator"},
  {name = "pipe_check_g_cc",      label = "<multi_assembler_pipe_check_g_cc>",      type = "constant-combinator"},
  {name = "pipe_check_r_cc",      label = "<multi_assembler_pipe_check_r_cc>",      type = "constant-combinator"},
  {name = "pipe_check_dc",        label = "<multi_assembler_pipe_check_dc>",        type = "decider-combinator"},
}

local function enrich_specific_data(objects)
  -- priority_id для итемов используется в системе приоритетной подачи в крафтер
  -- tank_fluid_offset для жидкостей используется для определения количества жидкости в цистернах и проброса
  local ingredients = algorithm.filter(objects, function(obj) return obj.ingredient_max_count ~= nil end)
  for i, _, object in algorithm.enumerate(ingredients) do
    if object.type == "item" then
      object.priority_id = FILTER_ITEMS_OFFSET + i * FILTER_ITEMS_WIDTH
    elseif object.type == "fluid" then
      object.tank_fluid_offset = FILTER_ITEMS_OFFSET + i * FILTER_ITEMS_WIDTH
      object.uncommon_fluid = object.next_quality_object
    end
  end
end

local function enrich_barrels_recipe_id(objects)
  local recipes = algorithm.filter(objects, function(obj)
    return (obj.is_fill_barrel_recipe or obj.is_empty_barrel_recipe) and obj.is_barrel_ingredient
  end)
  for i, _, object in algorithm.enumerate(recipes) do
    object.barrel_recipe_id = UNIQUE_RECIPE_ID_START - i
  end
end

local function enrich_unique_recipe_id(objects)
  local sorted_recipes = {}
  for _, object in pairs(objects) do
    if object.type == "recipe" and object.recipe_order ~= nil then
      table.insert(sorted_recipes, object)
    end
  end

  -- Приоритеты: жижи продукты, жижи ингредиенты, рецепты без жиж
  table.sort(sorted_recipes, function(a, b)
    local function get_priority(object)
      if algorithm.find(object.proto.products, function(e) return e.type == "fluid" end) ~= nil then
        return 2
      elseif algorithm.find(object.proto.ingredients, function(e) return e.type == "fluid" end) ~= nil then
        return 3
      else
        return 1
      end
    end

    local sa = get_priority(a)
    local sb = get_priority(b)

    if sa == sb then
      return a.recipe_order < b.recipe_order
    else
      return sa < sb
    end
  end)

  for i, object in ipairs(sorted_recipes) do
    object.unique_recipe_id = UNIQUE_RECIPE_ID_START + i
  end
end

--TODO: использовать число из рецепта вместо константы
local function min_barrels(value)
  return math.ceil(value / BARREL_CAPACITY)
end

local function fill_crafter_dc(entities, requests, ingredients)
  local fluids = algorithm.filter(ingredients, function(e) return e.value.type == "fluid" end)

  -- Рецепт с жижей можно установить, если рецепта с жижей не было 10 тиков и трубы пусты
  local fluid_recipe_is_set = {
    value = { name = "signal-C", type = "virtual", quality = "normal" }
  }
  local fluid_recipe_is_not_set_counter = {
    value = { name = "signal-F", type = "virtual", quality = "normal" }
  }

  local fluid_check_pipe_empty = AND()
  for _, fluid in pairs(fluids) do
    local fluid_empty_check = MAKE_IN(fluid.value.uncommon_fluid.value, ">", PC_FLUID_EMPTY_TICKS_OFFSET, RED_GREEN(false, true), RED_GREEN(true, true))
    fluid_check_pipe_empty:add_child(fluid_empty_check)
  end

  local tree = OR()
  for _, item in ipairs(requests) do
    local has_fluid = false
    -- Начинаем крафт если ингредиентов хватает на два крафта
    local ingredients_check_first = AND()
    for _, ingredient in pairs(item.ingredients) do
      local ingredient_check = MAKE_IN(ingredient.value, ">=", BAN_ITEMS_OFFSET + 2 * ingredient.recipe_min, RED_GREEN(false, true), RED_GREEN(true, true))

      if ingredient.value.type == "fluid" then
        has_fluid = true
        -- если жижа, проверяем также есть ли в цистернах
        local tank_check = MAKE_IN(ingredient.value, ">=", ingredient.value.tank_fluid_offset + 2 * ingredient.recipe_min + TANK_MINIMUM_CAPACITY, RED_GREEN(true, false), RED_GREEN(true, true))
        ingredient_check = OR(ingredient_check, tank_check)
      end

      if ingredient.value.barrel_item then
        local barrel_check = MAKE_IN(ingredient.value.barrel_item.value, ">=", BAN_ITEMS_OFFSET + min_barrels(2 * ingredient.recipe_min), RED_GREEN(false, true), RED_GREEN(true, true))
        ingredients_check_first:add_child(OR(ingredient_check, barrel_check))
      else
        ingredients_check_first:add_child(ingredient_check)
      end
    end
    -- Разрешаем крафт с жижами
    -- если рецепта с жижей не было FLUID_RECIPE_WAIT_TICKS тиков
    -- если в трубах нет жиж
    if has_fluid then
      local fluid_recipe_wait_check = MAKE_IN(fluid_recipe_is_not_set_counter.value, ">", FLUID_RECIPE_WAIT_TICKS, RED_GREEN(false, true), RED_GREEN(true, true))
      ingredients_check_first:add_child(fluid_recipe_wait_check)
      ingredients_check_first:add_child(fluid_check_pipe_empty)
    end

    -- Продолжаем крафт, пока ингредиентов хватает хотя бы на один крафт
    local ingredients_check_second = AND()
    for _, ingredient in pairs(item.ingredients) do
      local ingredient_check = MAKE_IN(ingredient.value, ">=", BAN_ITEMS_OFFSET + ingredient.recipe_min, RED_GREEN(false, true), RED_GREEN(false, true))
      if ingredient.value.type == "fluid" then
        -- если жижа, проверяем также есть ли в цистернах
        local tank_check = MAKE_IN(ingredient.value, ">=", ingredient.value.tank_fluid_offset + ingredient.recipe_min + TANK_MINIMUM_CAPACITY / 2, RED_GREEN(true, false), RED_GREEN(true, true))
        ingredient_check = OR(ingredient_check, tank_check)
      end
      if ingredient.value.barrel_item then
        local barrel_check = MAKE_IN(ingredient.value.barrel_item.value, ">=", BAN_ITEMS_OFFSET + min_barrels(ingredient.recipe_min), RED_GREEN(false, true), RED_GREEN(true, true))
        ingredients_check_second:add_child(OR(ingredient_check, barrel_check))
      else
        ingredients_check_second:add_child(ingredient_check)
      end
    end

    local check_forward = OR(MAKE_IN(item.recipe_signal.value, "!=", 0, RED_GREEN(true, false), RED_GREEN(true, false)))
    local forward = OR(MAKE_IN(EACH, "=", item.recipe_signal.value, RED_GREEN(true, false), RED_GREEN(true, false)))
    if has_fluid then
      local forward_virtual_is_set = MAKE_IN(EACH, "=", fluid_recipe_is_set.value, RED_GREEN(true, false), RED_GREEN(true, false))
      forward:add_child(forward_virtual_is_set)
    end

    local first_lock = MAKE_IN(EVERYTHING, "<", UNIQUE_RECIPE_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
    local second_lock = MAKE_IN(item.recipe_signal.value, ">", UNIQUE_RECIPE_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
    local choice_priority = MAKE_IN(EVERYTHING, "<=", item.recipe_signal.value.unique_recipe_id, RED_GREEN(false, true), RED_GREEN(true, false))

    local need_produce = MAKE_IN(item.value, "<", BAN_ITEMS_OFFSET + item.need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true))
    if item.value.type == "fluid" then
      local need_produce_tank_offset = 0
      if fluids[item.value.key] then need_produce_tank_offset = fluids[item.value.key].value.tank_fluid_offset end
      local need_produce_tank = MAKE_IN(item.value, "<", need_produce_tank_offset + item.need_produce_count, RED_GREEN(true, false), RED_GREEN(true, true))
      need_produce = AND(need_produce, need_produce_tank)
    end
    tree:add_child(AND(check_forward, forward, ingredients_check_first, need_produce, first_lock))
    tree:add_child(AND(check_forward, forward, ingredients_check_second, need_produce, second_lock, choice_priority))
  end

  local outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
  entities.crafter_dc:fill_decider_combinator(base.decider_conditions.to_flat_dnf(tree), outputs)
end

local function fill_fluids_empty_dc(entities, requests, ingredients)
  local fluids = algorithm.filter(ingredients, function(e) return e.value.type == "fluid" end)

  local tree = OR()

  -- Держим в машине остатки пока все трубы пусты.
  -- Как только в трубу что-то попадет можно слить из машины остаток и он уничтожится
  local fluid_check_pipe_empty = AND()
  -- Во второй трубе у нас может быть гольмий и он мешает блокировать остатки, т.к. у нас общая проверка на обе трубы
  for _, fluid in pairs(algorithm.filter(fluids, function(e) return e.value.name ~= "holmium-solution" end)) do
    local fluid_empty_check = MAKE_IN(fluid.value.uncommon_fluid.value, ">", PC_FLUID_EMPTY_TICKS_OFFSET, RED_GREEN(false, true), RED_GREEN(true, true))
    fluid_check_pipe_empty:add_child(fluid_empty_check)
  end

  -- Разрешаем откачивать жижу, если каждый из рецептов с этой жижей отсутствует
  local fluid_requests = algorithm.filter(requests, function(request)
    return algorithm.find(request.ingredients, function(e) return e.value.type == "fluid" end) ~= nil
  end)
  for _, fluid in pairs(fluids) do
    -- Откачиваем, если нет рецептов с этой жижей
    local forbidden_recipe_check = AND()
    for _, request in pairs(fluid_requests) do
      if request.ingredients[fluid.value.key] ~= nil then
        local recipe_check = MAKE_IN(request.recipe_signal.value, "=", 0, RED_GREEN(false, true), RED_GREEN(true, true))
        forbidden_recipe_check:add_child(recipe_check)
      end
    end

    local forward = MAKE_IN(EACH, "=", fluid.value, RED_GREEN(true, false), RED_GREEN(true, false))
    if fluid.value.barrel_item then
      local forward_barrel = MAKE_IN(EACH, "=", fluid.value.barrel_fill.value, RED_GREEN(true, false), RED_GREEN(true, false))
      forward = OR(forward, forward_barrel)
    end
    local fluid_check_pipe = MAKE_IN(fluid.value.uncommon_fluid.value, "<=", PC_FLUID_EMPTY_TICKS_OFFSET, RED_GREEN(false, true), RED_GREEN(true, true))
    local fluid_check = MAKE_IN(fluid.value, ">", BAN_ITEMS_OFFSET, RED_GREEN(false, true), RED_GREEN(true, true))
    tree:add_child(AND(forward, forbidden_recipe_check, OR(fluid_check_pipe, AND(fluid_check_pipe_empty, fluid_check))))
  end

  -- Если рецепт сквозной, надо запрещать дополнительные помпы
  for _, request in pairs(fluid_requests) do
    local count = algorithm.count_if(request.ingredients, function(e) return e.value.type == "fluid" end)
    if count == 1 then
      local signal = { name = "signal-L", type = "virtual", quality = "normal" }
      local forward = MAKE_IN(EACH, "=", signal, RED_GREEN(true, false), RED_GREEN(true, false))
      local recipe_check = MAKE_IN(request.recipe_signal.value, "!=", 0, RED_GREEN(false, true), RED_GREEN(true, true))
      tree:add_child(AND(forward, recipe_check))
    end
  end

  local outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
  entities.fluids_empty_dc:fill_decider_combinator(base.decider_conditions.to_flat_dnf(tree), outputs)
end

local function fill_fluids_fill_dc(entities, requests, ingredients)
  -- разрешать закачку, если рецепт с жижами есть и в трубах отсутствуют жижи других рецептов
  local fluids = algorithm.filter(ingredients, function(e) return e.value.type == "fluid" end)

  -- ставим машину на паузу, если рецепт требующий жижу установлен, но жижи достаточно
  local fill_machine_work_signal = {
    value = { name = "signal-P", type = "virtual", quality = "normal" }
  }

  local tree = OR()
  for _, item in ipairs(requests) do
    if algorithm.find(item.ingredients, function(e) return e.value.type == "fluid" end) ~= nil then
      local other_recipes = algorithm.filter(requests, function(e) return e.recipe_signal.value.key ~= item.recipe_signal.value.key end)
      local other_recipes_absent = AND()
      for _, request in pairs(other_recipes) do
        local check_recipe_absent = MAKE_IN(request.recipe_signal.value, "=", 0, RED_GREEN(false, true), RED_GREEN(true, true))
        other_recipes_absent:add_child(check_recipe_absent)
      end

      local my_fluids, other_fluids = algorithm.partition(fluids, function(e)
        return item.ingredients[e.value.key] ~= nil
      end)

      local fluid_check_pipe_empty = AND()
      for _, fluid in pairs(other_fluids) do
        local fluid_check = MAKE_IN(fluid.value.uncommon_fluid.value, ">", PC_FLUID_EMPTY_TICKS_OFFSET, RED_GREEN(false, true), RED_GREEN(true, true))
        fluid_check_pipe_empty:add_child(fluid_check)
      end

      for _, fluid in pairs(my_fluids) do
        local forward = MAKE_IN(EACH, "=", fluid.value, RED_GREEN(true, false), RED_GREEN(true, false))
        local min_fluid_count = item.ingredients[fluid.value.key].recipe_min
        local recipe_check = MAKE_IN(item.recipe_signal.value, "!=", 0, RED_GREEN(false, true), RED_GREEN(true, true))
        if fluid.value.barrel_item then
          local forward_barrel = MAKE_IN(EACH, "=", fluid.value.barrel_empty.value, RED_GREEN(true, false), RED_GREEN(true, false))
          forward = OR(forward, forward_barrel)
          local forward_work = MAKE_IN(EACH, "=", fill_machine_work_signal.value, RED_GREEN(true, false), RED_GREEN(true, false))
          local fluid_check_more = MAKE_IN(fluid.value, ">=", BAN_ITEMS_OFFSET + 2 * min_fluid_count, RED_GREEN(false, true), RED_GREEN(true, true))
          tree:add_child(AND(forward_work, other_recipes_absent, recipe_check, fluid_check_more, fluid_check_pipe_empty))
        else
          local fluid_check = MAKE_IN(fluid.value, "<", BAN_ITEMS_OFFSET + 2 * min_fluid_count, RED_GREEN(false, true), RED_GREEN(true, true))
          forward = AND(forward, fluid_check)
        end
        tree:add_child(AND(forward, other_recipes_absent, recipe_check, fluid_check_pipe_empty))
      end
    end
  end

  local outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
  entities.fluids_fill_dc:fill_decider_combinator(base.decider_conditions.to_flat_dnf(tree), outputs)
end

local function fill_chest_priority_dc(entities, requests, ingredients)
  local tree = OR()
  for _, item in ipairs(requests) do
    for _, ingredient in pairs(item.ingredients) do
      if ingredient.value.type ~= "fluid" then
        local forward = MAKE_IN(EACH, "=", ingredient.value, RED_GREEN(true, false), RED_GREEN(true, false))
        local recipe_check = MAKE_IN(ANYTHING, "=", item.recipe_signal.value.unique_recipe_id, RED_GREEN(false, true), RED_GREEN(false, true))
        local ingredient_check = MAKE_IN(ingredient.value, "<=", ingredient.value.priority_id, RED_GREEN(true, false), RED_GREEN(true, false))
        tree:add_child(AND(forward, recipe_check, ingredient_check))
      end
    end
  end

  local outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
  entities.chest_priority_dc:fill_decider_combinator(base.decider_conditions.to_flat_dnf(tree), outputs)
end

local function fill_pipe_check_dc(entities, requests, ingredients)
  -- Отдает сигналы жиж. Сколько тиков жижа отсутствовала в трубе.
  local fluids = algorithm.filter(ingredients, function(e) return e.value.type == "fluid" end)

  local PC_FLUID_OFFSET = 10000000

  for i, _, fluid in algorithm.enumerate(fluids) do
    fluid.value.uncommon_fluid.value.pipe_check_unique_id = i * PC_FLUID_OFFSET
  end

  local fluids_filters = MAKE_SIGNALS(fluids, function(e, i) return e.value.uncommon_fluid.value.pipe_check_unique_id, e.value.uncommon_fluid.value end)
  local negative_fluids_filters = MAKE_SIGNALS(fluids, function(e, i) return 1 - e.value.uncommon_fluid.value.pipe_check_unique_id, e.value.uncommon_fluid.value end)
  entities.pipe_check_g_cc:set_logistic_filters(fluids_filters)
  entities.pipe_check_r_cc:set_logistic_filters(negative_fluids_filters)

  local tree = OR()
  for _, fluid in pairs(fluids) do
    local forward = MAKE_IN(EACH, "=", fluid.value.uncommon_fluid.value, RED_GREEN(false, true), RED_GREEN(false, true))
    local counter_check = MAKE_IN(fluid.value.uncommon_fluid.value, "<", fluid.value.uncommon_fluid.value.pipe_check_unique_id - PC_FLUID_OFFSET, RED_GREEN(true, false), RED_GREEN(true, true))
    local fluid_check = MAKE_IN(fluid.value, "=", 0, RED_GREEN(false, true), RED_GREEN(true, true))
    tree:add_child(AND(forward, counter_check, fluid_check))
  end

  local outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, true)) }
  entities.pipe_check_dc:fill_decider_combinator(base.decider_conditions.to_flat_dnf(tree), outputs)

  local ban_fluids_filters = MAKE_SIGNALS(fluids, function(e, i) return PC_FLUID_BAN_OFFSET, e.value.uncommon_fluid.value end)
  entities.main_cc:set_logistic_filters(ban_fluids_filters)
end

local function fill_requester_rc(entities, filters)
  local requesters = entities.requester_rc
  local num_requesters = #requesters

  for i, requester in ipairs(requesters) do
    local requester_filters = {}

    for _, filter in ipairs(filters) do
      local total_amount = filter.min
      local base_amount = math.floor(total_amount / num_requesters)
      local remainder = total_amount % num_requesters

      -- Распределяем остаток
      local amount = base_amount
      if i <= remainder then
        amount = amount + 1
      end

      -- Добавляем фильтр только если количество > 0
      if amount > 0 then
        table.insert(requester_filters, {
          value = filter.value,
          min = amount
        })
      end
    end

    -- Вызываем set_logistic_filters один раз на requester
    requester:set_logistic_filters(requester_filters)
  end
end

local function prepare_input(raw_requests)
  return raw_requests
end

function multi_assembler.run(entities, player)
  local raw_requests = entities.main_cc:read_all_logistic_filters()
  entities.main_cc:set_logistic_filters(raw_requests, { multiplier = -1 })

  local objects = base.recipes.get_machine_objects(entities.crafter_machine.name)
  base.recipes.make_links(objects)
  local requests = base.recipes.fill_requests_map(prepare_input(raw_requests), objects)

  enrich_unique_recipe_id(objects)
  enrich_barrels_recipe_id(objects)
  enrich_specific_data(objects)

  -- Крафтим с жижей, если рецепта с жижей не было N тиков
  -- Крафтим без жижи низкоприоритетно
  -- Крафтим если ингредиенты есть в цистернах/бочках или в буферах машин
  -- Крафтим если трубы пусты (все жижи отсутствовали больше N тиков)
  -- Опустошаем трубы если рецепта с этой жижей нет, но жижа есть в трубах

  --fill_crafter_dc(entities, requests, ingredients)
  --fill_fluids_empty_dc(entities, requests, ingredients)
  --fill_fluids_fill_dc(entities, requests, ingredients)
  --fill_chest_priority_dc(entities, requests, ingredients)
  --fill_pipe_check_dc(entities, requests, ingredients)

  do
    local unique_recipe_id_filters = {}
    local ban_recipes_filters = {}
    local not_intermediate_ingredients = {}
    local recipe_barrel_filters = {}
    local request_barrel_filters = {}
    local ingredients_tank_fluid_filters = {}
    local ingredients_priority_filters = {}
    local all_ban_filters = {}
    for _, object in pairs(objects) do
      if object.unique_recipe_id ~= nil then ADD_SIGNAL(unique_recipe_id_filters, object, object.unique_recipe_id) end
      if object.recipe_order ~= nil then ADD_SIGNAL(ban_recipes_filters, object, BAN_RECIPES_OFFSET) end
      if object.ingredient_max_count ~= nil and object.product_max_count == nil and object.type ~= "fluid" then
        ADD_SIGNAL(not_intermediate_ingredients, object, object.ingredient_max_count)
      end
      if object.barrel_recipe_id ~= nil then ADD_SIGNAL(recipe_barrel_filters, object, object.barrel_recipe_id) end
      if object.is_barrel_ingredient ~= nil and object.is_barrel then ADD_SIGNAL(request_barrel_filters, object, 10, 50) end
      if object.tank_fluid_offset ~= nil then ADD_SIGNAL(ingredients_tank_fluid_filters, object, object.tank_fluid_offset) end
      if object.priority_id ~= nil then ADD_SIGNAL(ingredients_priority_filters, object, object.priority_id) end
      if object.type == "item" or (object.type == "fluid" and object.quality == "normal") then ADD_SIGNAL(all_ban_filters, object, BAN_ITEMS_OFFSET) end
    end
    entities.secondary_cc:set_logistic_filters(unique_recipe_id_filters)
    entities.ban_recipes_empty_cc:set_logistic_filters(ban_recipes_filters)
    entities.ban_recipes_fill_cc:set_logistic_filters(ban_recipes_filters)
    -- Не запрашиваем промежуточные ингредиенты
    -- Если мы крафтим этот ингредиент (есть в реквестах), его не надо запрашивать
    fill_requester_rc(entities, not_intermediate_ingredients)
    entities.secondary_cc:set_logistic_filters(recipe_barrel_filters)
    entities.barrels_rc:set_logistic_filters(request_barrel_filters)
    entities.secondary_cc:set_logistic_filters(ingredients_tank_fluid_filters)
    entities.chest_priority_cc:set_logistic_filters(ingredients_priority_filters)
    entities.main_cc:set_logistic_filters(all_ban_filters)
  end
end

return multi_assembler
