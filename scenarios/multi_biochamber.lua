local multi_biochamber = {}

local algorithm = require("llib.algorithm")
local EntityController = require("entity_controller")

local base = {
  recipes = require("base.recipes"),
  decider_conditions = require("base.decider_conditions")
}

local OR = base.decider_conditions.Condition.OR
local AND = base.decider_conditions.Condition.AND
local MAKE_IN = base.decider_conditions.MAKE_IN
local MAKE_OUT = base.decider_conditions.MAKE_OUT
local RED_GREEN = base.decider_conditions.RED_GREEN
local GREEN_RED = base.decider_conditions.GREEN_RED
local ADD_SIGNAL = EntityController.ADD_SIGNAL
local EACH = base.decider_conditions.EACH
local EVERYTHING = base.decider_conditions.EVERYTHING

local UNIQUE_RECIPE_ID_START  = 1000000
local BAN_ITEMS_OFFSET        = -1000000
local BAN_ITEMS_WIDTH         = -100000

local BARREL_CAPACITY = 50 -- TODO: использовать значение из рецепта
local MIN_FUEL_TWO_CRAFT = 1 -- TODO: Посчитать сколько хватит на два крафта из рецепта или машины

  -- TODO: использовать список топлива от машины (LuaBurnerPrototype)
local nutrients_object = nil

multi_biochamber.name = "multi_biochamber"

multi_biochamber.defines = {
  {name = "main_cc",              label = "<multi_biochamber_main_cc>",               type = "constant-combinator"},
  {name = "secondary_cc",         label = "<multi_biochamber_secondary_cc>",          type = "constant-combinator"},
  {name = "crafter_machine",      label = 715711,                                     type = "assembling-machine"},
  {name = "crafter_dc",           label = "<multi_biochamber_crafter_dc>",            type = "decider-combinator"},
  {name = "requester_dc",         label = "<multi_biochamber_requester_dc>",          type = "decider-combinator"},
  {name = "requester_cc",         label = "<multi_biochamber_requester_cc>",          type = "constant-combinator"},
  {name = "requester_rc",         label = 715712,                                     type = "logistic-container"},
  {name = "barrels_rc",           label = 715713,                                     type = "logistic-container"},
  {name = "barrels_empty_cc",     label = "<multi_biochamber_barrels_empty_cc>",      type = "constant-combinator"},
  {name = "barrels_fill_cc",      label = "<multi_biochamber_barrels_fill_cc>",       type = "constant-combinator"},
  {name = "nutrients_dc",         label = "<multi_biochamber_nutrients_dc>",          type = "decider-combinator"},
}

--TODO: использовать число из рецепта вместо константы
local function min_barrels(value)
  return math.ceil(value / BARREL_CAPACITY)
end

local function enrich_with_fuel(requests)
  assert(nutrients_object)
  nutrients_object.is_fuel = true

  local nutrients_object_stack_size = base.recipes.get_stack_size(nutrients_object)
  -- Если нет этого топлива, добавляем в рецепт
  for _, product, recipe in base.recipes.requests_pairs(requests) do
    -- Нужно максимум сколько влезет в слот топлива в машине, если в оригинальном крафте есть это топливо,
    -- что бы не встала машина из-за того что всё попадет в слот топлива.
    -- Если этого топлива нет в ингредиентах, его нужно чуть-чуть.
    if recipe.object.ingredients[nutrients_object.key] == nil then
      recipe.object.ingredients[nutrients_object.key] = {
        object = nutrients_object,
        one_craft_count = 0,
        max_request_count = 0,
        fuel_min = MIN_FUEL_TWO_CRAFT
      }
    end
    local found = algorithm.find(recipe.object.proto.ingredients, function(e)
      return base.recipes.make_key(e, recipe.object.quality) == nutrients_object.key
    end)
    if found then
      recipe.object.ingredients[nutrients_object.key].fuel_min = nutrients_object_stack_size
    end
    for _, ingredient in pairs(recipe.object.ingredients) do
      ingredient.fuel_min = ingredient.fuel_min or 0
    end
  end
end

-- Если предмет крафтится сам из себя (и этот рецепт есть), то его надо оставлять как минимум на два крафта самого себя
local function enrich_with_down_threshold(requests)
  for _, product, recipe in base.recipes.requests_pairs(requests) do
    product.object.self_craft_min = 0
    for _, ingredient in pairs(recipe.object.ingredients) do
      ingredient.object.self_craft_min = 0
    end
  end

  -- Для самокрафтов вычисляем сколько нужно этого предмета что бы накрафтить себя два раза
  -- На всякий случай сделаем порог в четыре крафта, что бы был маленький запас
  for _, product, recipe in base.recipes.requests_pairs(requests) do
    if recipe.is_self_craft then
      local entry = assert(recipe.object.ingredients[product.object.key])
      entry.object.self_craft_min = math.max(entry.object.self_craft_min or 0, entry.one_craft_count * 4)
    end
  end

  -- Финальный проход. Заполняем индивидуальные пороги. 
  -- Если это самокрафт, то порог на него не должен действовать, что бы смог запуститься самокрафт
  -- Нижний порог - начинаем крафтить если предмета 
  for _, product, recipe in base.recipes.requests_pairs(requests) do
    for _, ingredient in pairs(recipe.object.ingredients) do
      ingredient.self_craft_threshold = ingredient.object.self_craft_min
      if recipe.is_self_craft and ingredient.object.key == product.object.key then
        ingredient.self_craft_threshold = 0
      end
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

Семечки завысить в системе, что бы не крафтились пюре и желе

]]
local function enrich_with_final_products(requests)
  local function is_final_product(product, recipe)
    -- Определяем конечный продукт - если он не гниет или если из него ничего не крафтим среди других рецептов
    -- может являться ингредиентом топлива
    local proto = product.object.proto
    if proto.type == "item"
      and proto.spoil_result == nil
      and proto.spoil_to_trigger_result == nil then
      return true
    end
    -- Ищем среди всех других рецептов 
    local function is_not_final_spoil(target)
      for _, p, r in base.recipes.requests_pairs(requests) do
        if r.object.key ~= recipe.object.key                  -- ищем среди других рецептов
          and r.object.ingredients[target.object.key] ~= nil  -- искомый продукт должен быть ингредиентом
          and not p.object.is_fuel then                       -- найденный продукт не должен быть топливом
          return true
        end
      end
      return false
    end
    return not is_not_final_spoil(product)
  end

  -- 1. Определяем конечные продукты
  for _, product, recipe in base.recipes.requests_pairs(requests) do
    recipe.is_final_product = is_final_product(product, recipe)
    recipe.final_products = {} -- содержит структуру аналогичную requests. Позволяет понять какой продукт финальный и для какого рецепта
  end

  -- 2. Заполняем первичные связи: ингредиент → конечные продукты
  for _, product, recipe in base.recipes.requests_pairs(requests) do
    if recipe.is_final_product then
      for _, ingredient in pairs(recipe.object.ingredients) do
        for _, p, r in base.recipes.requests_pairs(requests) do
          if not r.is_final_product
            and p.object.key == ingredient.object.key then
            if r.final_products[product.object.key] == nil then
              r.final_products[product.object.key] = { object = product.object, recipes = {} }
            end
            r.final_products[product.object.key].recipes[recipe.object.key] = recipe
          end
        end
      end
    end
  end

  -- 3. Распространяем связи по цепочкам промежуточных продуктов
  local changed = true
  while changed do
    changed = false
    for _, product, recipe in base.recipes.requests_pairs(requests) do
      if not recipe.is_final_product then
        for _, ingredient in pairs(recipe.object.ingredients) do
          for _, p, r in base.recipes.requests_pairs(requests) do
            if not r.is_final_product
              and p.object.key == ingredient.object.key then

              local before_count = algorithm.count(r.final_products)

              -- проходим по всем конечным продуктам текущего рецепта
              for fkey, fprod in pairs(recipe.final_products) do
                if r.final_products[fkey] == nil then
                  r.final_products[fkey] = { object = fprod.object, recipes = {} }
                end

                -- объединяем списки рецептов
                for rk, rv in pairs(fprod.recipes) do
                  r.final_products[fkey].recipes[rk] = rv
                end
              end

              local after_count = algorithm.count(r.final_products)
              if after_count > before_count then
                changed = true
              end
            end
          end
        end
      end
    end
  end
end

local function enrich_ban_items_offset(objects)
  for i, _, object in algorithm.enumerate(objects) do
    if object.type == "item" or (object.type == "fluid" and object.quality == "normal") then
      object.ban_item_offset = BAN_ITEMS_OFFSET + i * BAN_ITEMS_WIDTH
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

  table.sort(sorted_recipes, function(a, b)
    return a.recipe_order < b.recipe_order
  end)

  for i, object in ipairs(sorted_recipes) do
    object.unique_recipe_id = UNIQUE_RECIPE_ID_START + i
  end
end

-- Если ингредиент не является продуктом, значит мы его не крафтим, надо запросить в количестве ingredient_max_count
-- Но если ингредиент самокрафт, надо проверить можем ли мы его скрафтить как-то еще сами. Если нет, то надо запросить self_craft_min
local function enrich_request_count(objects)
  for i, _, object in algorithm.enumerate(objects) do
    if object.is_ingredient and object.type == "item" then
      if object.as_self_craft_product_count > 0 and object.as_self_craft_product_count == object.as_product_count then
        assert(object.self_craft_min > 0)
        object.request_count = object.self_craft_min / 2
      elseif not object.is_product then
        object.request_count = object.ingredient_max_count
      end
    end
  end
end

-- Поиск предметов для запросов
-- Если мы сами не крафтим ингредиент (исключая самокрафт), его надо запросить в количестве request_min
-- Но если ингредиент самокрафт, надо запросить в количестве self_craft_min
-- Если ингредиент портится, то запрашивать надо если продукт конечный и продукта мало
-- или если продукт промежуточный и его крафт разрешен (любых из его конечных продуктов мало)
local function fill_requester_dc(entities, requests, objects)
  local alternative_ingredients = algorithm.filter(objects, function(obj)
    return obj.request_count ~= nil and (obj.proto.spoil_result ~= nil or obj.proto.spoil_to_trigger_result ~= nil)
  end)

  local tree = OR()

  -- Если ингредиент не портится, пробрасываем по количеству
  for _, item in pairs(alternative_ingredients) do
    local item_tree = AND()

    -- Если предмет портится, смотрим кому он вообще нужен
    -- Для каждого конечного продукта пробысываем, если продукта мало
    -- Для каждого промежуточного продукта пробысываем, если крафт промежуточного разрешен
    local alternative_check = OR()
    for _, product, recipe in base.recipes.requests_pairs(requests) do
      if recipe.object.ingredients[item.key] then
        if recipe.is_final_product then

          local need_produce = AND()
          need_produce:add_child(MAKE_IN(product.object, "<", product.object.ban_item_offset + recipe.need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true)))

          if product.object.spoil then
            local need_produce_alt = MAKE_IN(product.object.spoil, "<", product.object.spoil.ban_item_offset + recipe.need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true))
            need_produce:add_child(need_produce_alt)
          end

          alternative_check:add_child(need_produce)
        else

          local check_final_products = OR()
          for _, final_product, final_recipe in base.recipes.requests_pairs(recipe.final_products) do
            local check_final_product = MAKE_IN(final_product.object, "<", final_product.object.ban_item_offset + final_recipe.need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true))

            if final_product.object.spoil then
              local check_final_product_alt = MAKE_IN(final_product.object.spoil, "<", final_product.object.spoil.ban_item_offset + final_recipe.need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true))
              check_final_product = AND(check_final_product, check_final_product_alt)
            end

            check_final_products:add_child(check_final_product)
          end
          if not check_final_products:is_empty() then
            alternative_check:add_child(check_final_products)
          end
        end
      end
    end

    local count_check = MAKE_IN(item, "<", item.ban_item_offset + item.request_count, RED_GREEN(false, true), RED_GREEN(true, true))
    local forward = OR(MAKE_IN(EACH, "=", item, RED_GREEN(true, true), RED_GREEN(true, true)))

    item_tree:add_child(forward, count_check)
    if not alternative_check:is_empty() then
      item_tree:add_child(alternative_check)
    end
    tree:add_child(item_tree)
  end

  local outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, true)) }
  entities.requester_dc:fill_decider_combinator(base.decider_conditions.to_flat_dnf(tree), outputs)
end

local function fill_crafter_dc(entities, requests)
  -- ставим машину на паузу, если рецепт требующий жижу установлен, но жижи достаточно
  local fill_machine_work_signal = { name = "signal-P", type = "virtual", quality = "normal" }

  local tree = OR()
  for _, product, recipe in base.recipes.requests_pairs(requests) do
    -- Начинаем крафт если ингредиентов хватает на два крафта
    local ingredients_check_first = AND()
    for _, ingredient in pairs(recipe.object.ingredients) do
      local count = ingredient.object.ban_item_offset + ingredient.self_craft_threshold + ingredient.fuel_min + 2 * ingredient.one_craft_count
      local ingredient_check = MAKE_IN(ingredient.object, ">=", count, RED_GREEN(false, true), RED_GREEN(true, true))

      if ingredient.object.barrel_object then
        local barrel_check = MAKE_IN(ingredient.object.barrel_object, ">=", ingredient.object.barrel_object.ban_item_offset + min_barrels(2 * ingredient.one_craft_count), RED_GREEN(true, true), RED_GREEN(true, true))
        ingredients_check_first:add_child(OR(ingredient_check, barrel_check))
      else
        ingredients_check_first:add_child(ingredient_check)
      end
    end

    local ingredients_check_second = AND()
    for _, ingredient in pairs(recipe.object.ingredients) do
      local count = ingredient.object.ban_item_offset + ingredient.self_craft_threshold + ingredient.fuel_min + ingredient.one_craft_count
      local ingredient_check = MAKE_IN(ingredient.object, ">=", count, RED_GREEN(false, true), RED_GREEN(false, true))

      if ingredient.object.barrel_object then
        local barrel_check = MAKE_IN(ingredient.object.barrel_object, ">=", ingredient.object.barrel_object.ban_item_offset + min_barrels(ingredient.one_craft_count), RED_GREEN(true, true), RED_GREEN(true, true))
        ingredients_check_second:add_child(OR(ingredient_check, barrel_check))
      else
        ingredients_check_second:add_child(ingredient_check)
      end
    end

    local function make_need_produce(need_produce_count)
      local need_produce = AND()
      need_produce:add_child(MAKE_IN(product.object, "<", product.object.ban_item_offset + need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true)))
      if product.object.barrel_object then
        need_produce:add_child(MAKE_IN(product.object.barrel_object, "<", product.object.barrel_object.ban_item_offset + min_barrels(need_produce_count), RED_GREEN(false, true), RED_GREEN(true, true)))
      end

      -- У промежуточных продуктов не нужно проверять альтернативный
      -- т.к. альтернативный может помешать крафт промежуточного, а он нам нужен
      if recipe.is_final_product and product.object.spoil ~= nil and recipe.is_self_craft then
        local need_produce_alt = MAKE_IN(product.object.spoil, "<", product.object.spoil.ban_item_offset + need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true))
        need_produce:add_child(need_produce_alt)
      end
      return need_produce
    end
    local need_produce_first = make_need_produce(not recipe.is_final_product and product.object.is_ingredient and product.object.ingredient_max_one_craft_count * 4 or recipe.need_produce_count)
    local need_produce_second = make_need_produce(recipe.need_produce_count)

    local check_final_products = OR()
    for _, final_product, final_recipe in base.recipes.requests_pairs(recipe.final_products) do
      local check_final_product = MAKE_IN(final_product.object, "<", final_product.object.ban_item_offset + final_recipe.need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true))

      if final_recipe.is_final_product and final_product.object.spoil ~= nil and final_recipe.is_self_craft then
        local check_final_product_alt = MAKE_IN(final_product.object.spoil, "<", final_product.object.spoil.ban_item_offset + final_recipe.need_produce_count, RED_GREEN(false, true), RED_GREEN(true, true))
        check_final_product = AND(check_final_product, check_final_product_alt)
      end

      check_final_products:add_child(check_final_product)
    end
    if not check_final_products:is_empty() then
      need_produce_first:add_child(check_final_products)
      need_produce_second:add_child(check_final_products)
    end

    local check_forward = MAKE_IN(recipe.object, ">", 0, RED_GREEN(true, false), RED_GREEN(true, false))
    local forward = OR(MAKE_IN(EACH, "=", recipe.object, RED_GREEN(true, false), RED_GREEN(true, false)))

    for _, ingredient in pairs(recipe.object.ingredients) do
      if ingredient.object.barrel_object and ingredient.object.barrel_object.empty_barrel_recipe and ingredient.object.name ~= "water" then
        local forward_barrel = MAKE_IN(EACH, "=", ingredient.object.barrel_object.empty_barrel_recipe, RED_GREEN(true, false), RED_GREEN(true, false))
        forward:add_child(forward_barrel)
        local count = ingredient.object.ban_item_offset + ingredient.self_craft_threshold + ingredient.fuel_min + 2 * ingredient.one_craft_count
        local fluid_check = MAKE_IN(ingredient.object, ">=", count, RED_GREEN(false, true), RED_GREEN(true, true))
        local forward_work_empty = MAKE_IN(EACH, "=", fill_machine_work_signal, RED_GREEN(true, false), RED_GREEN(true, false))
        forward:add_child(AND(fluid_check, forward_work_empty))
      end
    end

    if product.object.barrel_object and product.object.barrel_object.fill_barrel_recipe then
      local forward_barrel = MAKE_IN(EACH, "=", product.object.barrel_object.fill_barrel_recipe, RED_GREEN(true, false), RED_GREEN(true, false))
      forward:add_child(forward_barrel)
    end

    local first_lock = MAKE_IN(EVERYTHING, "<", UNIQUE_RECIPE_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
    local second_lock = MAKE_IN(recipe.object, ">", UNIQUE_RECIPE_ID_START, RED_GREEN(false, true), RED_GREEN(true, true))
    local choice_priority = MAKE_IN(EVERYTHING, "<=", recipe.object.unique_recipe_id, RED_GREEN(false, true), RED_GREEN(true, false))

    tree:add_child(AND(check_forward, forward, ingredients_check_first, need_produce_first, first_lock))
    tree:add_child(AND(check_forward, forward, ingredients_check_second, need_produce_second, second_lock, choice_priority))
  end

  local outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
  entities.crafter_dc:fill_decider_combinator(base.decider_conditions.to_flat_dnf(tree), outputs)
end

local function fill_nutrients_dc(entities)
  assert(nutrients_object)
  local spoil_signal = { name = "nutrients-from-spoilage", type = "recipe", quality = "normal" }

  local tree = AND()
  tree:add_child(MAKE_IN(nutrients_object, "<", nutrients_object.ban_item_offset + MIN_FUEL_TWO_CRAFT, RED_GREEN(false, true), RED_GREEN(true, true)))
  tree:add_child(MAKE_IN(EACH, "=", spoil_signal, RED_GREEN(true, false), RED_GREEN(true, false)))
  local outputs = { MAKE_OUT(EACH, true, RED_GREEN(true, false)) }
  entities.nutrients_dc:fill_decider_combinator(base.decider_conditions.to_flat_dnf(tree), outputs)
end

local function prepare_input(raw_requests)
  return raw_requests
end

function multi_biochamber.run(entities, player)
  local raw_requests = entities.main_cc:read_all_logistic_filters()
  entities.main_cc:set_logistic_filters(raw_requests, { multiplier = -1 })

  local objects = base.recipes.get_machine_objects(entities.crafter_machine.name)
  nutrients_object = base.recipes.get_or_create_object(objects, { name = "nutrients", type = "item" }, "normal")
  base.recipes.make_links(objects)
  local requests = base.recipes.fill_requests_map(prepare_input(raw_requests), objects)

  enrich_with_fuel(requests)
  enrich_with_down_threshold(requests)
  enrich_with_final_products(requests)
  enrich_unique_recipe_id(objects)
  enrich_barrels_recipe_id(objects)
  enrich_request_count(objects)
  enrich_ban_items_offset(objects)

  fill_crafter_dc(entities, requests)
  fill_requester_dc(entities, requests, objects)
  fill_nutrients_dc(entities)

  do
    local ban_item_offset_signals = {}
    local unique_recipe_id_signals = {}
    local recipe_fill_barrel_signals = {}
    local recipe_empty_barrel_signals = {}
    local request_barrel_signals = {}
    local request_count_not_final_signals = {}
    local request_count_final_signals = {}
    for _, object in pairs(objects) do
      if object.ban_item_offset ~= nil then ADD_SIGNAL(ban_item_offset_signals, object, object.ban_item_offset) end
      if object.unique_recipe_id ~= nil then ADD_SIGNAL(unique_recipe_id_signals, object, object.unique_recipe_id) end
      if object.barrel_recipe_id ~= nil and object.is_fill_barrel_recipe then ADD_SIGNAL(recipe_fill_barrel_signals, object, object.barrel_recipe_id) end
      if object.barrel_recipe_id ~= nil and object.is_empty_barrel_recipe then ADD_SIGNAL(recipe_empty_barrel_signals, object, object.barrel_recipe_id) end
      if object.is_barrel_ingredient ~= nil and object.is_barrel then ADD_SIGNAL(request_barrel_signals, object, 10, 50) end
      if object.request_count ~= nil and (object.proto.spoil_result ~= nil or object.proto.spoil_to_trigger_result ~= nil) then
        ADD_SIGNAL(request_count_not_final_signals, object, assert(object.ban_item_offset) + object.request_count)
      end
        if object.request_count ~= nil and not (object.proto.spoil_result ~= nil or object.proto.spoil_to_trigger_result ~= nil) then
        ADD_SIGNAL(request_count_final_signals, object, object.request_count)
      end
    end
    entities.main_cc:set_logistic_filters(ban_item_offset_signals)
    entities.secondary_cc:set_logistic_filters(unique_recipe_id_signals)
    entities.barrels_empty_cc:set_logistic_filters(unique_recipe_id_signals, { multiplier = -1 })
    entities.barrels_fill_cc:set_logistic_filters(unique_recipe_id_signals, { multiplier = -1 })
    entities.secondary_cc:set_logistic_filters(recipe_fill_barrel_signals)
    entities.secondary_cc:set_logistic_filters(recipe_empty_barrel_signals)
    entities.barrels_empty_cc:set_logistic_filters(recipe_fill_barrel_signals, { multiplier = -1 })
    entities.barrels_fill_cc:set_logistic_filters(recipe_empty_barrel_signals, { multiplier = -1 })
    entities.barrels_rc:set_logistic_filters(request_barrel_signals)
    entities.requester_cc:set_logistic_filters(request_count_not_final_signals, { multiplier = -1 })
    entities.requester_rc:set_logistic_filters(request_count_final_signals)
  end

end

return multi_biochamber