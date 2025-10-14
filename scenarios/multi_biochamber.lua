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

function multi_biochamber.run(entities, player)
  local raw_requests = entities.main_cc:read_all_logistic_filters()
  local requests = base.recipes.enrich_with_recipes(raw_requests, entities.crafter_machine.name)
  local ingredients = base.recipes.make_ingredients(requests)
  base.recipes.enrich_with_ingredients(requests, ingredients)
  base.recipes.enrich_with_barrels(ingredients)

end

return multi_biochamber