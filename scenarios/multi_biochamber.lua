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

-- Отметить рецепты у которых нет портящихся в гниль продуктов или продукт портится, но не является промежуточным
-- добавить фейковый ингредиент портящегося продукта?
-- добавить фейковый запрос портящегося продукта? (для руд)
local function enrich_with_initial_bio_products(recipe_signals, machine_name)
  local _, machine_recipes = base.recipes.get_machine_recipes(machine_name)

  local initials = {
    [base.recipes.make_key({ type="item", name="jellynut" })] = true,
    [base.recipes.make_key({ type="item", name="yumako" })] = true,
  }

  local items = {}
  local resipes_list = {}
  for key, recipe in pairs(machine_recipes) do
    for _, ingredient in ipairs (recipe.ingredients) do
      items[base.recipes.make_key(ingredient)] = false
    end
    for _, product in ipairs (recipe.products) do
      items[base.recipes.make_key(product)] = false
    end
    resipes_list[key] = recipe
  end
  for key, _ in pairs(initials) do
    if items[key] ~= nil then items[key] = true end
  end

  while true do
    local tmp = {}
    for key, recipe in pairs(resipes_list) do
      if algorithm.find(recipe.ingredients, function(e) return items[base.recipes.make_key(e)] == true end) ~= nil then
        for _, product in ipairs (recipe.products) do
          tmp[base.recipes.make_key(product)] = true
        end
        resipes_list[key] = nil
      end
    end
    for key, _ in pairs(tmp) do
      items[key] = true
    end
    if next(tmp) == nil then break end
  end
  local k = 0
end

--[[
Определяем конечный продукт - если из него ничего не крафтим (может крафтить самого себя) или если он не гниет
Остальные продукты промежуточные
Для промежуточных продуктов нужно сгенерить список конечных продуктов
Если продукт промежуточный, запрещаем крафтить его, если всех конечных продуктов достаточно
Добавить питательные вещества в ингредиенты каждого продукта, что бы у питательных веществ (удобрений) был список конечных

-- юмако            - рецепт юмако                    -- промежуточный
-- семечко юмако    - рецепт юмако                    -- конечный
-- желеорех         - рецепт желеорех                 -- промежуточный
-- семечко желеорех - рецепт желеорех                 -- конечный
-- биофлюс          - рецепт биофлюс                  -- промежуточный
-- удобрение        - рецепт удобрение из гнили       -- промежуточный
-- удобрение        - рецепт удобрение из юмако       -- промежуточный
-- удобрение        - рецепт удобрение из биофлюса    -- промежуточный

-- яйцо             - рецепт яйцо                     -- промежуточный (т.к. установлена колба)

-- железобактерия   - рецепт железобактерия           -- промежуточный
-- гниль            - рецепт железобактерия           -- конечный
-- железобактерия   - рецепт культ железобактерии     -- конечный, но проверять продукт по количеству (железобактерия или руда)

-- рыба             - рецепт рыба                     -- конечный (т.к. нет рецептов с рыбой)
-- удобрение        - рецепт удобрение из рыбы        -- промежуточный

-- колбы            - рецепт колбы                    -- конечный

Проверять на прямой продукт и альтернытивный (продукт гниения)
Семечки завысить в системе, что бы не крафтились пюре и желе
Рецепты гнили убрать (бактерии)
Гниль убрать из альтернативных продуктов
]]

local function fill_data_table(requests, ingredients, recipe_signals)
  for i, _, signal in algorithm.enumerate(recipe_signals) do
    signal.value.unique_recipe_id = UNIQUE_RECIPE_ID_START + i
  end
  for i, item in ipairs(requests) do
    item.need_produce_count = item.min
  end
end

local function fill_crafter_dc(entities, requests, ingredients)
  local tree = OR()
  for _, item in ipairs(requests) do
    -- Начинаем крафт если ингредиентов хватает на два крафта
    local ingredients_check_first = AND()
    for _, ingredient in pairs(item.ingredients) do
      local ingredient_check = MAKE_IN(ingredient.value, ">=", BAN_ITEMS_OFFSET + 2 * ingredient.recipe_min, RED_GREEN(false, true), RED_GREEN(true, true))
      ingredients_check_first:add_child(ingredient_check)
    end

    local ingredients_check_second = AND()
    for _, ingredient in pairs(item.ingredients) do
      local ingredient_check = MAKE_IN(ingredient.value, ">=", BAN_ITEMS_OFFSET + ingredient.recipe_min, RED_GREEN(false, true), RED_GREEN(false, true))
      ingredients_check_second:add_child(ingredient_check)
    end

    local need_produce = MAKE_IN(item.value, "<", BAN_ITEMS_OFFSET + item.need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true))

    local check_forward = OR(MAKE_IN(item.recipe_signal.value, ">", 0, RED_GREEN(true, false), RED_GREEN(true, false)))
    local forward = OR(MAKE_IN(EACH, "=", item.recipe_signal.value, RED_GREEN(true, false), RED_GREEN(true, false)))

    local first_lock = MAKE_IN(EVERYTHING, "<", UNIQUE_RECIPE_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
    local second_lock = MAKE_IN(item.recipe_signal.value, ">", UNIQUE_RECIPE_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
    local choice_priority = MAKE_IN(EVERYTHING, "<=", item.recipe_signal.value.unique_recipe_id, RED_GREEN(false, true), RED_GREEN(true, false))

    tree:add_child(AND(check_forward, forward, ingredients_check_first, need_produce, first_lock))
    tree:add_child(AND(check_forward, forward, ingredients_check_second, need_produce, second_lock, choice_priority))
  end

  local outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
  entities.crafter_dc:fill_decider_combinator(base.decider_conditions.to_flat_dnf(tree), outputs)
end

function multi_biochamber.run(entities, player)
  local raw_requests = entities.main_cc:read_all_logistic_filters()
  local requests, recipe_signals = base.recipes.enrich_with_recipes(raw_requests, entities.crafter_machine.name)
  local ingredients = base.recipes.make_ingredients(requests)
  base.recipes.enrich_with_ingredients(requests, ingredients)
  base.recipes.enrich_with_barrels(ingredients)
  enrich_with_initial_bio_products(recipe_signals, entities.crafter_machine.name)
  fill_data_table(requests, ingredients, recipe_signals)

  fill_crafter_dc(entities, requests, ingredients)

  entities.main_cc:set_logistic_filters(raw_requests, { multiplier = -1 })
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