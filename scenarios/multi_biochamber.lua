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

local function enrich_ingredients_with_fuel(requests, ingredients)
  -- TODO: использовать список топлива от машины
  local nutrients_signal = {
    value = base.recipes.make_value({
      name = "nutrients",
      type = "item"
    }, "normal")
  }

  local nutrients_ingredient = ingredients[nutrients_signal.value.key]
  if nutrients_ingredient == nil then
    ingredients[nutrients_signal.value.key] = util.table.deepcopy(nutrients_signal)
    nutrients_ingredient = ingredients[nutrients_signal.value.key]
  end

  for _, ingredient in pairs(ingredients) do
    ingredient.value.is_fuel = false
  end
  nutrients_ingredient.value.is_fuel = true

  for _, item in ipairs(requests) do
    local as_ingredient = ingredients[item.value.key]
    item.value.is_fuel = as_ingredient and as_ingredient.value.is_fuel or false
  end

  -- Нужно максимум сколько влезет в слот топлива в машине, 
  -- что бы не встала машина из-за того что всё попадет в слот топлива
  for _, item in ipairs(requests) do
    local stack_size = base.recipes.get_stack_size(nutrients_ingredient.value)
    if item.value.is_fuel then stack_size = 1 end -- TODO: Посчитать сколько хватит на два крафта

    local ingredient = item.ingredients[nutrients_signal.value.key]
    if ingredient == nil then
      item.ingredients[nutrients_signal.value.key] = {
        value = nutrients_ingredient.value,
        recipe_min = stack_size,
        request_min = stack_size
      }
    else
      ingredient.recipe_min = ingredient.recipe_min + stack_size
      ingredient.request_min = ingredient.request_min + stack_size
    end
  end
end

--[[
Определяем конечный продукт - если из него ничего не крафтим (может крафтить самого себя) или если он не гниет
Остальные продукты промежуточные
Для промежуточных продуктов нужно сгенерить список конечных продуктов
Если продукт промежуточный, запрещаем крафтить его, если всех конечных продуктов достаточно
Добавить питательные вещества в ингредиенты каждого продукта, что бы у питательных веществ (удобрений) был список конечных

-- юмако            - рецепт юмако                    -- промежуточный [железобактерия, колба][семечко ю, семечко ж, железобактерия, рыба, колба]
-- семечко юмако    - рецепт юмако                    -- конечный
-- желеорех         - рецепт желеорех                 -- промежуточный [железобактерия, колба][железобактерия]
-- семечко желеорех - рецепт желеорех                 -- конечный
-- биофлюс          - рецепт биофлюс                  -- промежуточный [железобактерия, колба][семечко ю, семечко ж, железобактерия, рыба, колба]
-- удобрение        - рецепт удобрение из гнили       -- промежуточный [семечко ю, семечко ж, железобактерия, рыба, колба][колба][железобактерия]
-- удобрение        - рецепт удобрение из юмако       -- промежуточный [семечко ю, семечко ж, железобактерия, рыба, колба][колба][железобактерия]
-- удобрение        - рецепт удобрение из биофлюса    -- промежуточный [семечко ю, семечко ж, железобактерия, рыба, колба][колба][железобактерия]

-- яйцо             - рецепт яйцо                     -- промежуточный (т.к. установлена колба) [колба]

-- железобактерия   - рецепт железобактерия           -- промежуточный [железобактерия]
-- железобактерия   - рецепт культ железобактерии     -- конечный, но проверять продукт по количеству (железобактерия или руда)

-- рыба             - рецепт рыба                     -- конечный (т.к. нет рецептов с рыбой)
-- удобрение        - рецепт удобрение из рыбы        -- промежуточный

-- колба            - рецепт колбы                    -- конечный

Проверять на прямой продукт и альтернытивный (продукт гниения)
Семечки завысить в системе, что бы не крафтились пюре и желе
Рецепты гнили убрать (бактерии)
Гниль убрать из альтернативных продуктов

]]
local function enrich_with_final_products(requests)
  local function is_final_product(request, from)
    -- Определяем конечный продукт - если он не гниет или если из него ничего не крафтим 
    -- (может крафтить сам себя или являться ингредиентом питательных веществ)
    if request.proto.spoil_result == nil and request.proto.spoil_to_trigger_result == nil then
      return true
    end
    return algorithm.find(from, function(r)
      return r.ingredients[request.value.key] ~= nil
        and r.recipe_proto.name ~= request.recipe_proto.name
        and not r.value.is_fuel
    end) == nil
  end
  for _, item in ipairs(requests) do
    item.is_final_product = is_final_product(item, requests)
    item.final_products = {}
  end

  local enrich_list = {}
  algorithm.extend(enrich_list, requests)

  for i, item in pairs(enrich_list) do
    if item.is_final_product then
      for _, ingredient in pairs(item.ingredients) do
        for _, e in pairs(requests) do
          if not e.is_final_product and e.value.key == ingredient.value.key then
            e.final_products[item.value.key] = item
          end
        end
      end
      enrich_list[i] = nil
    end
  end

  local changed = true
  while changed do
    changed = false
    for _, item in pairs(enrich_list) do
      for _, ingredient in pairs(item.ingredients) do
        for _, e in pairs(requests) do
          if not e.is_final_product and e.value.key == ingredient.value.key then
            local before_count = algorithm.count(e.final_products)
            e.final_products = algorithm.merge(e.final_products, item.final_products)
            local after_count = algorithm.count(e.final_products)
            if after_count > before_count then
              changed = true
            end
          end
        end
      end
    end
  end

end

-- Если предмет крафтится сам из себя (и этот рецепт есть), то его надо оставлять как минимум на два крафта самого себя
local function enrich_with_down_threshold(requests, ingredients)
  local function is_self_craft(request, from)
    return algorithm.find(from, function(r)
      local ingredient = r.ingredients[request.value.key]
      return ingredient ~= nil
        and not ingredient.value.is_fuel
        and r.recipe_proto.name == request.recipe_proto.name
    end) ~= nil
  end
  for _, ingredient in pairs(ingredients) do
    ingredient.value.self_craft_min = 0
  end

  -- Для самокрафтов вычисляем сколько нужно этого предмета что бы накрафтить себя два раза
  for _, item in ipairs(requests) do
    item.is_self_craft = is_self_craft(item, requests)
    if item.is_self_craft then
      assert(item.ingredients[item.value.key] ~= nil)
      assert(ingredients[item.value.key] ~= nil)
      local self_craft_min = item.ingredients[item.value.key].recipe_min * 2
      local ingredient_value = ingredients[item.value.key].value
      ingredient_value.self_craft_min = math.max(ingredient_value.self_craft_min, self_craft_min)
    end
  end

  -- Финальный проход. Заполняем индивидуальные пороги. 
  -- Если это самокрафт, то порог на него не должен действовать, что бы смог запуститься самокрафт
  -- Нижний порог - начинаем крафтить если предмета 
  for _, item in ipairs(requests) do
    for _, ingredient in pairs(item.ingredients) do
      ingredient.start_threshold = ingredient.value.self_craft_min
      if item.is_self_craft and ingredient.value.key == item.value.key then
        ingredient.start_threshold = 0
      end
    end
  end
end

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
      local ingredient_check = MAKE_IN(ingredient.value, ">=", BAN_ITEMS_OFFSET + ingredient.start_threshold + 2 * ingredient.recipe_min, RED_GREEN(false, true), RED_GREEN(true, true))
      ingredients_check_first:add_child(ingredient_check)
    end

    local ingredients_check_second = AND()
    for _, ingredient in pairs(item.ingredients) do
      local ingredient_check = MAKE_IN(ingredient.value, ">=", BAN_ITEMS_OFFSET + ingredient.start_threshold + ingredient.recipe_min, RED_GREEN(false, true), RED_GREEN(false, true))
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
  enrich_ingredients_with_fuel(requests, ingredients)
  enrich_with_down_threshold(requests, ingredients)
  enrich_with_final_products(requests)
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