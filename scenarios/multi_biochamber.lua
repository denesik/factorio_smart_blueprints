local multi_biochamber = {}

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
local GREEN_RED = base.decider_conditions.GREEN_RED
local MAKE_SIGNALS = EntityController.MAKE_SIGNALS
local EACH = base.decider_conditions.EACH
local EVERYTHING = base.decider_conditions.EVERYTHING
local ANYTHING = base.decider_conditions.ANYTHING

local UNIQUE_RECIPE_ID_START  = 1000000
local BAN_ITEMS_OFFSET        = -1000000

multi_biochamber.name = "multi_biochamber"

multi_biochamber.defines = {
  {name = "main_cc",              label = "<multi_biochamber_main_cc>",              type = "constant-combinator"},
  {name = "secondary_cc",         label = "<multi_biochamber_secondary_cc>",         type = "constant-combinator"},
  {name = "crafter_machine",      label = 715711,                                    type = "assembling-machine"},
  {name = "crafter_dc",           label = "<multi_biochamber_crafter_dc>",           type = "decider-combinator"},
  --{name = "fluids_empty_dc",      label = "<multi_biochamber_fluids_empty_dc>",      type = "decider-combinator"},
  --{name = "fluids_fill_dc",       label = "<multi_biochamber_fluids_fill_dc>",       type = "decider-combinator"},
  --{name = "requester_rc",         label = 715712,                                    type = "logistic-container"},
  --{name = "barrels_rc",           label = 715713,                                    type = "logistic-container"},
  --{name = "chest_priority_dc",    label = "<multi_biochamber_chest_priority_dc>",    type = "decider-combinator"},
  --{name = "chest_priority_cc",    label = "<multi_biochamber_chest_priority_cc>",    type = "constant-combinator"},
  --{name = "pipe_check_g_cc",      label = "<multi_biochamber_pipe_check_g_cc>",      type = "constant-combinator"},
  --{name = "pipe_check_r_cc",      label = "<multi_biochamber_pipe_check_r_cc>",      type = "constant-combinator"},
  --{name = "pipe_check_dc",        label = "<multi_biochamber_pipe_check_dc>",        type = "decider-combinator"},
}


local function fill_data_table(requests, ingredients, recipe_signals)
  for i, _, signal in algorithm.enumerate(recipe_signals) do
    signal.value.unique_recipe_id = UNIQUE_RECIPE_ID_START + i
  end
  for i, item in ipairs(requests) do
    item.need_produce_count = item.min
  end
end

function multi_biochamber.run(entities, player)
  local raw_requests = entities.main_cc:read_all_logistic_filters()
  local requests, recipe_signals = base.recipes.enrich_with_recipes(raw_requests, entities.crafter_machine.name)
  local ingredients = base.recipes.make_ingredients(requests)
  base.recipes.enrich_with_ingredients(requests, ingredients)
  base.recipes.enrich_with_barrels(ingredients)
  fill_data_table(requests, ingredients, recipe_signals)

  do
    local recipes_filters = MAKE_SIGNALS(recipe_signals, function(e, i) return e.value.unique_recipe_id end)
    entities.secondary_cc:set_logistic_filters(recipes_filters)
  end

  do
    local all_ingredients = base.recipes.get_machine_ingredients(entities.crafter_machine.name)
    local all_products = base.recipes.get_machine_products(entities.crafter_machine.name)
    local all_filters = MAKE_SIGNALS(algorithm.merge(all_ingredients, all_products), function(e, i) return BAN_ITEMS_OFFSET end)
    entities.main_cc:set_logistic_filters(all_filters)

    local ban_barrel_filters = MAKE_SIGNALS(base.recipes.get_all_barrels(), function(e, i) return BAN_ITEMS_OFFSET end)
    entities.main_cc:set_logistic_filters(ban_barrel_filters)
  end
end

return multi_biochamber