local EntityFinder = require("entity_finder")
local game_utils = require("game_utils")
local table_utils = require("common.table_utils")
local entity_control = require("entity_control")
local decider_conditions = require("decider_conditions")
local recipes = require("recipes")
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
local BAN_ITEMS_OFFSET        = -1000000
local FILTER_ITEMS_OFFSET     = 10000000
local FILTER_ITEMS_WIDTH      = 100000

local multi_assembler = {}

multi_assembler.name = "multi_assembler"

local function fill_ingredients(requests)
  local ingredients = {}

  for i, item in ipairs(requests) do
    item.ingredients = {}
    for _, ingredient in ipairs(item.recipe.ingredients) do
      local ingredient_signal = game_utils.make_signal(ingredient, item.value.quality)
      ingredient_signal.recipe_min = ingredient_signal.min
      ingredient_signal.min = ingredient_signal.min * (item.min / item.recipe.main_product.amount)
      table.insert(item.ingredients, ingredient_signal)
      table.insert(ingredients, ingredient_signal)
    end
  end

  ingredients = game_utils.merge_duplicates(ingredients, game_utils.merge_max)
  local all_items = {} -- TODO: ингредиент может быть в requests
  table_utils.extend(all_items, requests)
  table_utils.extend(all_items, ingredients)
  table_utils.for_each(all_items, function(e, i) e.filter_id = FILTER_ITEMS_OFFSET + i * FILTER_ITEMS_WIDTH end)

  local ingredients_map = table_utils.to_map(ingredients, function(item) return game_utils.items_key_fn(item) end)
  for _, item in ipairs(requests) do
    for _, ingredient in ipairs(item.ingredients) do
      ingredient.filter_id = ingredients_map[game_utils.items_key_fn(ingredient)].filter_id
    end
  end
end

local function fill_data_table(requests)
  for i, item in ipairs(requests) do
    item.recipe_signal = game_utils.recipe_as_signal(item.recipe, item.value.quality)
    item.recipe_signal.unique_recipe_id = UNIQUE_RECIPE_ID_START + i
    item.need_produce_count = item.min
  end

  fill_ingredients(requests)

  for _, item in ipairs(requests) do item.recipe = nil end
end

function multi_assembler.run(player, area)
  local defs = {
    {name = "main_cc",            label = "<multi_assembler_main_cc>",            type = "constant-combinator"},
    {name = "secondary_cc",       label = "<multi_assembler_secondary_cc>",       type = "constant-combinator"},
    {name = "crafter_machine",    label = 881781,                                 type = "assembling-machine"},
    {name = "crafter_dc",         label = "<multi_assembler_crafter_dc>",         type = "decider-combinator"},
    {name = "requester_rc",       label = 881782,                                 type = "logistic-container"},
    {name = "chest_priority_dc",  label = "<multi_assembler_chest_priority_dc>",  type = "decider-combinator"},
    {name = "chest_priority_cc",  label = "<multi_assembler_chest_priority_cc>",  type = "constant-combinator"},
  }

  local entities = EntityFinder.new(player.surface, area, defs)
  local raw_requests = entity_control.read_all_logistic_filters(entities.main_cc)
  local requests = recipes.enrich_with_recipes(raw_requests, entity_control.get_name(entities.crafter_machine))
  fill_data_table(requests)

  do
    local tree = OR()
    for _, item in ipairs(requests) do
      -- Начинаем крафт если ингредиентов хватает на два крафта
      local ingredients_check_first = AND()
      for _, ingredient in ipairs(item.ingredients) do
        ingredients_check_first:add_child(MAKE_IN(ingredient.value, ">=", BAN_ITEMS_OFFSET + 2 * ingredient.recipe_min, RED_GREEN(false, true), RED_GREEN(true, true)))
      end
      -- Продолжаем крафт, пока ингредиентов хватает хотя бы на один крафт
      local ingredients_check_second = AND()
      for _, ingredient in ipairs(item.ingredients) do
        ingredients_check_second:add_child(MAKE_IN(ingredient.value, ">=", BAN_ITEMS_OFFSET + ingredient.recipe_min, RED_GREEN(false, true), RED_GREEN(false, true)))
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

  do
    local tree = OR()
    for _, item in ipairs(requests) do
      for _, ingredient in ipairs(item.ingredients) do
        if not game_utils.is_fluid(ingredient) then
          local forward = MAKE_IN(EACH, "=", ingredient.value, RED_GREEN(true, false), RED_GREEN(true, false))
          local recipe_check = MAKE_IN(ANYTHING, "=", item.recipe_signal.unique_recipe_id, RED_GREEN(false, true), RED_GREEN(false, true))
          local ingredient_check = MAKE_IN(ingredient.value, "<=", ingredient.filter_id, RED_GREEN(true, false), RED_GREEN(true, false))
          tree:add_child(AND(forward, recipe_check, ingredient_check))
        end
      end
    end

    local outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
    entity_control.fill_decider_combinator(entities.chest_priority_dc, decider_conditions.to_flat_dnf(tree), outputs)
  end

  do
    local allowed_requests_copy = util.table.deepcopy(requests)
    table_utils.for_each(allowed_requests_copy, function(e, i) e.value = e.recipe_signal.value e.min = e.recipe_signal.unique_recipe_id end)
    entity_control.set_logistic_filters(entities.secondary_cc, allowed_requests_copy)
  end

  entity_control.set_logistic_filters(entities.main_cc, raw_requests, { multiplier = -1 })
  do
    local ingredients = {}
    for _, item in ipairs(requests) do
      for _, ingredient in ipairs(item.ingredients) do
        table.insert(ingredients, ingredient)
      end
    end
    ingredients = game_utils.merge_duplicates(ingredients, game_utils.merge_max)
    entity_control.set_logistic_filters(entities.requester_rc, ingredients)
    local all_items = {}
    table_utils.extend(all_items, requests)
    table_utils.extend(all_items, ingredients)

    table_utils.for_each(all_items, function(e, i) e.min = BAN_ITEMS_OFFSET end)
    entity_control.set_logistic_filters(entities.main_cc, all_items)

    table_utils.for_each(all_items, function(e, i) e.min = e.filter_id end)
    entity_control.set_logistic_filters(entities.chest_priority_cc, all_items)
  end
end

return multi_assembler
