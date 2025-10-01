local EntityFinder = require("entity_finder")
local game_utils = require("game_utils")
local algorithm = require("llib.algorithm")
local entity_control = require("entity_control")
local decider_conditions = require("decider_conditions")
local recipes = require("recipes")
local barrel = require("barrel")
require("util")

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

local BARREL_CAPACITY = 50 -- TODO: использовать значение из рецепта

local multi_assembler = {}

multi_assembler.name = "multi_assembler"

local function fill_data_table(requests, ingredients)
  for i, _, item in algorithm.enumerate(ingredients) do
    item.filter_id = FILTER_ITEMS_OFFSET + i * FILTER_ITEMS_WIDTH
  end
  local function filter_barrels(e)
    return e.barrel_fill ~= nil and e.barrel_empty ~= nil
  end
  for i, _, item in algorithm.enumerate(algorithm.filter(ingredients, filter_barrels)) do
    item.barrel_fill.barrel_recipe_id = UNIQUE_RECIPE_ID_START - i * 2
    item.barrel_empty.barrel_recipe_id = UNIQUE_RECIPE_ID_START - i * 2 + 1
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
  local fluids = algorithm.filter(ingredients, function(e) return e.type == "fluid" end)

  local tree = OR()
  for _, item in ipairs(requests) do
    -- Начинаем крафт если ингредиентов хватает на два крафта
    local ingredients_check_first = AND()
    for _, ingredient in pairs(item.ingredients) do
      local ingredient_check = MAKE_IN(ingredient.value, ">=", BAN_ITEMS_OFFSET + 2 * ingredient.recipe_min, RED_GREEN(false, true), RED_GREEN(true, true))
      if ingredient.value.barrel_item then
        local barrel_check = MAKE_IN(ingredient.value.barrel_item.value, ">=", min_barrels(2 * ingredient.recipe_min), RED_GREEN(false, true), RED_GREEN(true, true))
        ingredients_check_first:add_child(OR(ingredient_check, barrel_check))
      else
        ingredients_check_first:add_child(ingredient_check)
      end
    end
    -- Разрешаем крафт с жижами
    -- если в цистернах нет жиж от других рецептов и есть все жижи от нашего рецепта
    -- если в цистернах нет жиж от других рецептов и нет жиж от нашего рецепта (цистерны пусты)
    if algorithm.find(item.ingredients, function(e) return e.value.type == "fluid" end) ~= nil then
      local my_fluids, other_fluids = algorithm.partition(fluids, function(e)
        return item.ingredients[e.key] ~= nil
      end)
      for _, fluid in pairs(other_fluids) do
        local fluid_empty_check = MAKE_IN(fluid, "<=", fluid.filter_id, RED_GREEN(true, false), RED_GREEN(true, true))
        ingredients_check_first:add_child(fluid_empty_check)
      end
      local my_fluids_empty_check = AND()
      local my_fluids_not_empty_check = AND()
      for _, fluid in pairs(my_fluids) do
        local fluid_empty_check = MAKE_IN(fluid, "<=", fluid.filter_id, RED_GREEN(true, false), RED_GREEN(true, true))
        local fluid_not_empty_check = MAKE_IN(fluid, ">", fluid.filter_id, RED_GREEN(true, false), RED_GREEN(true, true))
        my_fluids_empty_check:add_child(fluid_empty_check)
        my_fluids_not_empty_check:add_child(fluid_not_empty_check)
      end
      ingredients_check_first:add_child(OR(my_fluids_empty_check, my_fluids_not_empty_check))
    end

    -- Продолжаем крафт, пока ингредиентов хватает хотя бы на один крафт
    local ingredients_check_second = AND()
    for _, ingredient in pairs(item.ingredients) do
      local ingredient_check = MAKE_IN(ingredient.value, ">=", BAN_ITEMS_OFFSET + ingredient.recipe_min, RED_GREEN(false, true), RED_GREEN(false, true))
      if ingredient.value.barrel_item then
        local barrel_check = MAKE_IN(ingredient.value.barrel_item.value, ">=", min_barrels(ingredient.recipe_min), RED_GREEN(false, true), RED_GREEN(true, true))
        ingredients_check_second:add_child(OR(ingredient_check, barrel_check))
      else
        ingredients_check_second:add_child(ingredient_check)
      end
    end

    local forward = MAKE_IN(EACH, "=", item.recipe_signal.value, RED_GREEN(true, false), RED_GREEN(true, false))

    local first_lock = MAKE_IN(EVERYTHING, "<", UNIQUE_RECIPE_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
    local second_lock = MAKE_IN(item.recipe_signal.value, ">", UNIQUE_RECIPE_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
    local choice_priority = MAKE_IN(EVERYTHING, "<=", item.recipe_signal.unique_recipe_id, RED_GREEN(false, true), RED_GREEN(true, false))

    local need_produce = MAKE_IN(item.value, "<", BAN_ITEMS_OFFSET + item.need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true))

    tree:add_child(AND(forward, ingredients_check_first, need_produce, first_lock))
    tree:add_child(AND(forward, ingredients_check_second, need_produce, second_lock, choice_priority))
  end

  local outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
  entity_control.fill_decider_combinator(entities.crafter_dc, decider_conditions.to_flat_dnf(tree), outputs)
end

local function fill_fluids_empty_dc(entities, requests, ingredients)
  local fluids = algorithm.filter(ingredients, function(e) return e.type == "fluid" end)

  local tree = OR()

  -- Держим в машине остатки пока цистерны пусты.
  -- Как только в цистерну что-то попадет можно слить из машины остаток и он уничтожится
  local fluid_check_tank_empty = AND()
  for _, fluid in pairs(fluids) do
    local fluid_check = MAKE_IN(fluid, "<=", fluid.filter_id, RED_GREEN(true, false), RED_GREEN(true, true))
    fluid_check_tank_empty:add_child(fluid_check)
  end

  -- Разрешаем откачивать жижу, если каждый из рецептов с этой жижей отсутствует
  local fluid_requests = algorithm.filter(requests, function(request)
    return algorithm.find(request.ingredients, function(e) return e.value.type == "fluid" end) ~= nil
  end)
  for _, fluid in pairs(fluids) do
    -- Если эта жижа есть в рецепте, надо проверить что рецепт не установлен
    local forbidden_recipe_check = AND()
    for _, request in pairs(fluid_requests) do
      if request.ingredients[fluid.key] ~= nil then
        local recipe_check = MAKE_IN(request.recipe_signal.value, "=", 0, RED_GREEN(false, true), RED_GREEN(true, true))
        forbidden_recipe_check:add_child(recipe_check)
      end
      local forward = MAKE_IN(EACH, "=", fluid, RED_GREEN(true, false), RED_GREEN(true, false))
      if fluid.barrel_item then
        local forward_barrel = MAKE_IN(EACH, "=", fluid.barrel_fill.value, RED_GREEN(true, false), RED_GREEN(true, false))
        forward = OR(forward, forward_barrel)
      end
      local fluid_check_tank = MAKE_IN(fluid, ">", fluid.filter_id, RED_GREEN(true, false), RED_GREEN(true, true))
      local fluid_check = MAKE_IN(fluid, ">", BAN_ITEMS_OFFSET, RED_GREEN(false, true), RED_GREEN(true, true))
      tree:add_child(AND(forward, forbidden_recipe_check, OR(fluid_check_tank, AND(fluid_check_tank_empty, fluid_check))))
    end
  end

  local outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
  entity_control.fill_decider_combinator(entities.fluids_empty_dc, decider_conditions.to_flat_dnf(tree), outputs)
end

local function fill_fluids_fill_dc(entities, requests, ingredients)
  -- разрешать закачку, если рецепт с жижами есть и в цистернах отсутствуют жижи других рецептов
  local fluids = algorithm.filter(ingredients, function(e) return e.type == "fluid" end)

  local tree = OR()
  for _, item in ipairs(requests) do
    if algorithm.find(item.ingredients, function(e) return e.value.type == "fluid" end) ~= nil then
      local my_fluids, other_fluids = algorithm.partition(fluids, function(e)
        return item.ingredients[e.key] ~= nil
      end)

      local fluid_check_tank_empty = AND()
      for _, fluid in pairs(other_fluids) do
        local fluid_check = MAKE_IN(fluid, "<=", fluid.filter_id, RED_GREEN(true, false), RED_GREEN(true, true))
        fluid_check_tank_empty:add_child(fluid_check)
      end

      for _, fluid in pairs(my_fluids) do
        local forward = MAKE_IN(EACH, "=", fluid, RED_GREEN(true, false), RED_GREEN(true, false))
        if fluid.barrel_item then
          local forward_barrel = MAKE_IN(EACH, "=", fluid.barrel_empty.value, RED_GREEN(true, false), RED_GREEN(true, false))
          forward = OR(forward, forward_barrel)
        end
        local recipe_check = MAKE_IN(item.recipe_signal.value, "!=", 0, RED_GREEN(false, true), RED_GREEN(true, true))
        -- TODO сколько закачивать в цистерну?
        local fluid_check = MAKE_IN(fluid, "<", fluid.filter_id + 100, RED_GREEN(true, false), RED_GREEN(true, true))
        tree:add_child(AND(forward, recipe_check, fluid_check, fluid_check_tank_empty))
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

function multi_assembler.run(player, area)
  local defs = {
    {name = "main_cc",            label = "<multi_assembler_main_cc>",            type = "constant-combinator"},
    {name = "secondary_cc",       label = "<multi_assembler_secondary_cc>",       type = "constant-combinator"},
    {name = "ban_recipes_1_cc",   label = "<multi_assembler_ban_recipes_1_cc>",   type = "constant-combinator"},
    {name = "ban_recipes_2_cc",   label = "<multi_assembler_ban_recipes_2_cc>",   type = "constant-combinator"},
    {name = "crafter_machine",    label = 881781,                                 type = "assembling-machine"},
    {name = "crafter_dc",         label = "<multi_assembler_crafter_dc>",         type = "decider-combinator"},
    {name = "fluids_empty_dc",    label = "<multi_assembler_fluids_empty_dc>",    type = "decider-combinator"},
    {name = "fluids_fill_dc",     label = "<multi_assembler_fluids_fill_dc>",     type = "decider-combinator"},
    {name = "requester_rc",       label = 881782,                                 type = "logistic-container"},
    {name = "chest_priority_dc",  label = "<multi_assembler_chest_priority_dc>",  type = "decider-combinator"},
    {name = "chest_priority_cc",  label = "<multi_assembler_chest_priority_cc>",  type = "constant-combinator"},
  }

  local entities = EntityFinder.new(player.surface, area, defs)
  local raw_requests = entity_control.read_all_logistic_filters(entities.main_cc)
  local requests = recipes.enrich_with_recipes(raw_requests, entity_control.get_name(entities.crafter_machine))
  local ingredients = recipes.make_ingredients(requests)
  recipes.enrich_with_ingredients(requests, ingredients)
  recipes.enrich_with_barrels(ingredients)
  fill_data_table(requests, ingredients)

  fill_crafter_dc(entities, requests, ingredients)
  fill_fluids_empty_dc(entities, requests, ingredients)

  fill_fluids_fill_dc(entities, requests, ingredients)
  fill_chest_priority_dc(entities, requests, ingredients)

  do
    local allowed_requests_copy = util.table.deepcopy(requests)
    algorithm.for_each(allowed_requests_copy, function(e, i) e.value = e.recipe_signal.value e.min = e.recipe_signal.unique_recipe_id end)
    entity_control.set_logistic_filters(entities.secondary_cc, allowed_requests_copy)

    algorithm.for_each(allowed_requests_copy, function(e, i) e.min = BAN_RECIPES_OFFSET end)
    entity_control.set_logistic_filters(entities.ban_recipes_1_cc, allowed_requests_copy)
    entity_control.set_logistic_filters(entities.ban_recipes_2_cc, allowed_requests_copy)
  end

  entity_control.set_logistic_filters(entities.main_cc, raw_requests, { multiplier = -1 })
  do
    local ingredients_signals = {}
    for _, item in ipairs(requests) do
      for _, ingredient in pairs(item.ingredients) do
        table.insert(ingredients_signals, ingredient)
      end
    end
    ingredients_signals = game_utils.merge_duplicates(ingredients_signals, function(a, b)
      a.request_min = math.max(a.request_min, b.request_min)
    end)
    algorithm.for_each(ingredients_signals, function(e, i) e.min = e.request_min end)
    entity_control.set_logistic_filters(entities.requester_rc, ingredients_signals)
    local all_items = {}
    algorithm.extend(all_items, requests)
    algorithm.extend(all_items, ingredients_signals)

    algorithm.for_each(all_items, function(e, i) e.min = BAN_ITEMS_OFFSET end)
    entity_control.set_logistic_filters(entities.main_cc, all_items)

    local barrel_signals = {}
    local empty_barrel_signals = {}
    local filter_signals = {}
    for _, item in pairs(ingredients) do
      if item.barrel_item then
        table.insert(barrel_signals, item.barrel_fill)
        table.insert(empty_barrel_signals, item.barrel_empty)
      end

      table.insert(filter_signals, {
        value = item,
        min = item.filter_id
      })
    end
    algorithm.for_each(barrel_signals, function(e, i) e.min = e.barrel_recipe_id end)
    entity_control.set_logistic_filters(entities.secondary_cc, barrel_signals)
    algorithm.for_each(empty_barrel_signals, function(e, i) e.min = e.barrel_recipe_id end)
    entity_control.set_logistic_filters(entities.secondary_cc, empty_barrel_signals)
    entity_control.set_logistic_filters(entities.secondary_cc, filter_signals)
    entity_control.set_logistic_filters(entities.chest_priority_cc, filter_signals)
  end
end

return multi_assembler
