local EntityFinder = require("entity_finder")
local game_utils = require("game_utils")
local algorithm = require("llib.algorithm")
local entity_control = require("entity_control")
local decider_conditions = require("decider_conditions")
local recipes = require("recipes")
local barrel = require("barrel")

local OR = decider_conditions.Condition.OR
local AND = decider_conditions.Condition.AND
local MAKE_IN = decider_conditions.MAKE_IN
local MAKE_OUT = decider_conditions.MAKE_OUT
local RED_GREEN = decider_conditions.RED_GREEN
local GREEN_RED = decider_conditions.GREEN_RED
local EACH = decider_conditions.EACH
local EVERYTHING = decider_conditions.EVERYTHING
local ANYTHING = decider_conditions.ANYTHING

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

local multi_assembler = {}

multi_assembler.name = "multi_assembler"

function enrich_with_uncommon_fluids(ingredients)
  for _, item in pairs(ingredients) do
    if item.value.type == "fluid" then
      item.value.uncommon_fluid = {
        value = recipes.make_value(item.value, "uncommon")
      }
    end
  end
end

local function fill_data_table(requests, ingredients)
  for i, _, item in algorithm.enumerate(ingredients) do
    item.value.filter_id = FILTER_ITEMS_OFFSET + i * FILTER_ITEMS_WIDTH
  end
  local function filter_barrels(e)
    return e.value.barrel_fill ~= nil and e.value.barrel_empty ~= nil
  end
  for i, _, item in algorithm.enumerate(algorithm.filter(ingredients, filter_barrels)) do
    item.value.barrel_fill.barrel_recipe_id = UNIQUE_RECIPE_ID_START - i * 2
    item.value.barrel_empty.barrel_recipe_id = UNIQUE_RECIPE_ID_START - i * 2 + 1
  end
  for i, item in ipairs(requests) do
    item.recipe_signal.unique_recipe_id = UNIQUE_RECIPE_ID_START + i
    item.need_produce_count = item.min
  end
  for _, item in ipairs(requests) do item.recipe = nil end
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
      if ingredient.value.type == "fluid" then has_fluid = true end

      local ingredient_check = MAKE_IN(ingredient.value, ">=", BAN_ITEMS_OFFSET + 2 * ingredient.recipe_min, RED_GREEN(false, true), RED_GREEN(true, true))
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
    local choice_priority = MAKE_IN(EVERYTHING, "<=", item.recipe_signal.unique_recipe_id, RED_GREEN(false, true), RED_GREEN(true, false))

    local need_produce = MAKE_IN(item.value, "<", BAN_ITEMS_OFFSET + item.need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true))

    tree:add_child(AND(check_forward, forward, ingredients_check_first, need_produce, first_lock))
    tree:add_child(AND(check_forward, forward, ingredients_check_second, need_produce, second_lock, choice_priority))
  end

  local outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
  entity_control.fill_decider_combinator(entities.crafter_dc, decider_conditions.to_flat_dnf(tree), outputs)
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
  entity_control.fill_decider_combinator(entities.fluids_empty_dc, decider_conditions.to_flat_dnf(tree), outputs)
end

local function fill_fluids_fill_dc(entities, requests, ingredients)
  -- разрешать закачку, если рецепт с жижами есть и в трубах отсутствуют жижи других рецептов
  local fluids = algorithm.filter(ingredients, function(e) return e.value.type == "fluid" end)

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
        if fluid.value.barrel_item then
          local forward_barrel = MAKE_IN(EACH, "=", fluid.value.barrel_empty.value, RED_GREEN(true, false), RED_GREEN(true, false))
          forward = OR(forward, forward_barrel)
        end
        local recipe_check = MAKE_IN(item.recipe_signal.value, "!=", 0, RED_GREEN(false, true), RED_GREEN(true, true))
        -- TODO сколько закачивать в цистерну?
        local fluid_check = MAKE_IN(fluid.value, "<", fluid.value.filter_id + 400, RED_GREEN(true, false), RED_GREEN(true, true))
        tree:add_child(AND(forward, other_recipes_absent, recipe_check, fluid_check, fluid_check_pipe_empty))
      end
    end
  end

  local outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
  entity_control.fill_decider_combinator(entities.fluids_fill_dc, decider_conditions.to_flat_dnf(tree), outputs)
end

local function fill_chest_priority_dc(entities, requests, ingredients)
  local tree = OR()
  for _, item in ipairs(requests) do
    for _, ingredient in pairs(item.ingredients) do
      if ingredient.value.type ~= "fluid" then
        local forward = MAKE_IN(EACH, "=", ingredient.value, RED_GREEN(true, false), RED_GREEN(true, false))
        local recipe_check = MAKE_IN(ANYTHING, "=", item.recipe_signal.unique_recipe_id, RED_GREEN(false, true), RED_GREEN(false, true))
        local ingredient_check = MAKE_IN(ingredient.value, "<=", ingredient.value.filter_id, RED_GREEN(true, false), RED_GREEN(true, false))
        tree:add_child(AND(forward, recipe_check, ingredient_check))
      end
    end
  end

  local outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
  entity_control.fill_decider_combinator(entities.chest_priority_dc, decider_conditions.to_flat_dnf(tree), outputs)
end

local function fill_pipe_check(entities, requests, ingredients)
  -- Отдает сигналы жиж. Сколько тиков жижа отсутствовала в трубе.
  local fluids = algorithm.filter(ingredients, function(e) return e.value.type == "fluid" end)

  local PC_FLUID_OFFSET = 10000000

  for i, _, fluid in algorithm.enumerate(fluids) do
    fluid.value.uncommon_fluid.value.pipe_check_unique_id = i * PC_FLUID_OFFSET
  end

  local fluids_filters = game_utils.make_logistic_signals(fluids, function(e, i) return e.value.uncommon_fluid.value.pipe_check_unique_id, e.value.uncommon_fluid.value end)
  local negative_fluids_filters = game_utils.make_logistic_signals(fluids, function(e, i) return 1 - e.value.uncommon_fluid.value.pipe_check_unique_id, e.value.uncommon_fluid.value end)
  entity_control.set_logistic_filters(entities.pipe_check_g_cc, fluids_filters)
  entity_control.set_logistic_filters(entities.pipe_check_r_cc, negative_fluids_filters)

  local tree = OR()
  for _, fluid in pairs(fluids) do
    local forward = MAKE_IN(EACH, "=", fluid.value.uncommon_fluid.value, RED_GREEN(false, true), RED_GREEN(false, true))
    local counter_check = MAKE_IN(fluid.value.uncommon_fluid.value, "<", fluid.value.uncommon_fluid.value.pipe_check_unique_id - PC_FLUID_OFFSET, RED_GREEN(true, false), RED_GREEN(true, true))
    local fluid_check = MAKE_IN(fluid.value, "=", 0, RED_GREEN(false, true), RED_GREEN(true, true))
    tree:add_child(AND(forward, counter_check, fluid_check))
  end

  local outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, true)) }
  entity_control.fill_decider_combinator(entities.pipe_check_dc, decider_conditions.to_flat_dnf(tree), outputs)

  local ban_fluids_filters = game_utils.make_logistic_signals(fluids, function(e, i) return PC_FLUID_BAN_OFFSET, e.value.uncommon_fluid.value end)
  entity_control.set_logistic_filters(entities.main_cc, ban_fluids_filters)
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
    entity_control.set_logistic_filters(requester, requester_filters)
  end
end

function multi_assembler.run(player, area)
  local defs = {
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

  local entities = EntityFinder.new(player.surface, area, defs)
  local raw_requests = entity_control.read_all_logistic_filters(entities.main_cc)
  local requests = recipes.enrich_with_recipes(raw_requests, entity_control.get_name(entities.crafter_machine))
  local ingredients = recipes.make_ingredients(requests)
  recipes.enrich_with_ingredients(requests, ingredients)
  recipes.enrich_with_barrels(ingredients)
  enrich_with_uncommon_fluids(ingredients)
  fill_data_table(requests, ingredients)

  -- Крафтим с жижей, если рецепта с жижей не было N тиков
  -- Крафтим без жижи низкоприоритетно
  -- Крафтим если ингредиенты есть в цистернах/бочках или в буферах машин
  -- Крафтим если трубы пусты (все жижи отсутствовали больше N тиков)
  -- Опустошаем трубы если рецепта с этой жижей нет, но жижа есть в трубах

  fill_crafter_dc(entities, requests, ingredients)
  fill_fluids_empty_dc(entities, requests, ingredients)
  fill_fluids_fill_dc(entities, requests, ingredients)
  fill_chest_priority_dc(entities, requests, ingredients)
  fill_pipe_check(entities, requests, ingredients)

  do
    local recipes_filters = game_utils.make_logistic_signals(requests, function(e, i) return e.recipe_signal.unique_recipe_id, e.recipe_signal.value end)
    entity_control.set_logistic_filters(entities.secondary_cc, recipes_filters)

    local ban_recipes_filters = game_utils.make_logistic_signals(requests, function(e, i) return BAN_RECIPES_OFFSET, e.recipe_signal.value end)
    entity_control.set_logistic_filters(entities.ban_recipes_empty_cc, ban_recipes_filters)
    entity_control.set_logistic_filters(entities.ban_recipes_fill_cc, ban_recipes_filters)
  end

  entity_control.set_logistic_filters(entities.main_cc, raw_requests, { multiplier = -1 })
  do
    local all_ingredients = {}
    for _, item in ipairs(requests) do
      algorithm.append(all_ingredients, item.ingredients)
    end
    table.sort(all_ingredients, function(a, b)
      if a.value.key == b.value.key then
        return a.request_min > b.request_min
      end
      return a.value.key < b.value.key
    end)
    all_ingredients = algorithm.unique(all_ingredients, function(e) return e.value.key end)

    local all_ingredients_filters = game_utils.make_logistic_signals(all_ingredients, function(e, i) return e.request_min end)
    fill_requester_rc(entities, all_ingredients_filters)

    local all_items = {}
    algorithm.extend(all_items, requests)
    algorithm.extend(all_items, all_ingredients)
    table.sort(all_items, function(a, b)
      if a.value.key == b.value.key then
        return a.request_min > b.request_min
      end
      return a.value.key < b.value.key
    end)
    all_items = algorithm.unique(all_items, function(e) return e.value.key end)
    local all_items_filters = game_utils.make_logistic_signals(all_items, function(e, i) return BAN_ITEMS_OFFSET end)
    entity_control.set_logistic_filters(entities.main_cc, all_items_filters)

    local barrels = algorithm.filter(ingredients, function(e) return e.value.barrel_item ~= nil end)
    if next(barrels) then
      local fill_barrel_filters = game_utils.make_logistic_signals(barrels, function(e, i) return e.value.barrel_fill.barrel_recipe_id, e.value.barrel_fill.value end)
      local empty_barrel_filters = game_utils.make_logistic_signals(barrels, function(e, i) return e.value.barrel_empty.barrel_recipe_id, e.value.barrel_empty.value end)
      local ban_barrel_filters = game_utils.make_logistic_signals(barrels, function(e, i) return BAN_ITEMS_OFFSET, e.value.barrel_item.value end)
      local request_barrel_filters = game_utils.make_logistic_signals(barrels, function(e, i) return 10, e.value.barrel_item.value end)
      for _, e in ipairs(request_barrel_filters) do e.max = 50 end

      entity_control.set_logistic_filters(entities.secondary_cc, fill_barrel_filters)
      entity_control.set_logistic_filters(entities.secondary_cc, empty_barrel_filters)
      entity_control.set_logistic_filters(entities.barrels_rc, request_barrel_filters)

      table.insert(ban_barrel_filters, { value = barrel.barrel_item.value, min = BAN_ITEMS_OFFSET })
      entity_control.set_logistic_filters(entities.main_cc, ban_barrel_filters)
    end

    local filter_filters = game_utils.make_logistic_signals(ingredients, function(e, i) return e.value.filter_id end)
    entity_control.set_logistic_filters(entities.secondary_cc, filter_filters)
    entity_control.set_logistic_filters(entities.chest_priority_cc, filter_filters)
  end
end

return multi_assembler
