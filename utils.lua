local Utils = {}

--- Определяет реальный тип прототипа по имени или возвращает первый допустимый.
--- @param name string --[[ Имя прототипа (сигнала, жидкости, предмета или рецепта). ]]
--- @param expected_type? string --[[ Если указано "recipe", сначала проверять только рецепты. ]]
--- @return "recipe"|"virtual"|"fluid"|"item"|nil --[[ Тип прототипа или nil, если не найден ]]
function Utils.get_type(name, expected_type)
  if expected_type == "recipe" then
    if prototypes.recipe[name] then
      return "recipe"
    end
  end

  if prototypes.virtual_signal[name] then
    return "virtual"
  end

  if prototypes.fluid[name] then
    return "fluid"
  end

  if prototypes.item[name] then
    return "item"
  end

  game.print("Внимание, обнаружен неизвестный тип для объекта: " .. tostring(name))
  return nil
end

--- Добавляет сигнал в целевое хранилище
-- @param storage table — хранилище вида [name][quality][type] = min
-- @param norm {name=string, quality=string, type=string, min=number}
function Utils.add_signal_to_storage(storage, norm)
  local n, q, t, m = norm.name, norm.quality, norm.type, norm.min
  storage[n]       = storage[n] or {}
  storage[n][q]    = storage[n][q] or {}
  storage[n][q][t] = (storage[n][q][t] or 0) + m
end


--- Ищет в области area сущности по имени метки.
--- @param label string --[[ Метка: ищется в combinator_description и group секций ]]
function Utils.findSpecialEntity(label, search_area)
  local surface = game.player.surface
  search_params = {}
  search_params.area = search_area

  local entities = surface.find_entities_filtered(search_params)
  label = string.lower(label)

  for _, entity in ipairs(entities) do
    -- 📌 1. combinator_description (если есть)
    local success, desc = pcall(function()
      return entity.combinator_description
    end)
    if success and desc and string.lower(desc):find(label, 1, true) then
      return entity
    end

    -- 📌 2. get_logistic_sections с деактивированной секцией и подходящей group
    if entity.get_logistic_sections then
      local sections = entity.get_logistic_sections()
      if sections and sections.sections then
        for _, section in pairs(sections.sections) do
          if not section.active and section.group and type(section.group) == "string" then
            if string.lower(section.group) == label then
              return entity
            end
          end
        end
      end
    end
  end

  return nil
end

-- Функция, которая по таблице рецептов возвращает три группы объектов (items/fluids) и для каждого объекта
-- вычисляет «максимальное поглощение» (максимальное количество, требуемое в одном цикле крафта):
--   1) exclusively_ingredients: объекты, которые встречаются только в качестве ингредиента (ни разу не являются продуктом);
--   2) ingredients_and_products: объекты, которые одновременно встречаются как ингредиент и как продукт;
--   3) exclusively_products: объекты, которые встречаются только в качестве продукта (ни разу не используются как ингредиент).
-- Для объектов из группы «exclusively_products» значение «максимального поглощения» будет 0, так как они не потребляются.
--
-- @param recipes table Таблица всех рецептов в формате:
--                     {
--                       ["iron-plate"]    = <прототип рецепта iron-plate LuaPrototype>,
--                       ["copper-cable"]  = <прототип рецепта copper-cable LuaPrototype>,
--                       …
--                     }
--                     Где каждый <прототип рецепта> — это LuaPrototype с полем .ingredients
--                     (список таблиц { name=string, type="item"/"fluid", amount=number }) и
--                     полем .products / .results / .result.
-- @return table Таблица с полями:
--               exclusively_ingredients   = { [имя_объекта] = <макс. потребление>, … },
--               ingredients_and_products  = { [имя_объекта] = <макс. потребление>, … },
--               exclusively_products      = { [имя_объекта] = 0, … }
function Utils.get_classify_ingredients(recipes)
  -- Результирующие подтаблицы
  local ingredient_groups  = {
    exclusively_ingredients  = {}, -- объекты, которые встречаются только в ingredients
    ingredients_and_products = {}, -- объекты, которые и там, и там
    exclusively_products     = {}, -- объекты, которые встречаются только в products
  }

  -- Шаг 0: вспомогательные структуры
  -- max_consumption[name] = максимальное количество этого объекта, требуемое в одном ремесле (из поля .ingredients)
  local max_consumption    = {}

  -- seen_as_ingredient[name] = true, если объект хотя бы раз встречался в ingredients
  local seen_as_ingredient = {}
  -- seen_as_product[name] = true, если объект хотя бы раз встречался в products
  local seen_as_product    = {}

  -- Шаг 1: Собираем информацию о потреблении и продукции из каждого рецепта
  for _, recipe_proto in pairs(recipes) do
    -- 1.1 Обрабатываем ingredients
    if recipe_proto.ingredients then
      for _, ing in ipairs(recipe_proto.ingredients) do
        local obj_name = ing.name
        local obj_type = ing.type -- может быть "item" или "fluid"
        local amount = ing.amount or 0
        -- Обновляем максимальное потребление
        if not max_consumption[obj_name] or amount > max_consumption[obj_name] then
          max_consumption[obj_name] = amount
        end
        -- Отмечаем, что объект встречался как ингредиент
        seen_as_ingredient[obj_name] = true
      end
    end

    -- 1.2 Обрабатываем products / results / result
    if recipe_proto.products then
      for _, prod in ipairs(recipe_proto.products) do
        local obj_name = prod.name
        seen_as_product[obj_name] = true
        -- Обратите внимание: продукты не влияют на max_consumption,
        -- т.к. это метрика только для потребления.
        -- Но если вдруг в других рецептах этот объект будет ингредиентом,
        -- его max_consumption уже учтён выше.
      end
    elseif recipe_proto.results then
      for _, prod in ipairs(recipe_proto.results) do
        local obj_name = prod.name
        seen_as_product[obj_name] = true
      end
    elseif recipe_proto.result then
      local obj_name = recipe_proto.result
      seen_as_product[obj_name] = true
    end
  end

  -- Шаг 2: Определяем группы и заполняем итоговые таблицы
  -- 2.1 Те объекты, которые встречались в ingredients
  for name, _ in pairs(seen_as_ingredient) do
    if seen_as_product[name] then
      -- Если встречался и там, и там
      ingredient_groups.ingredients_and_products[name] = max_consumption[name] or 0
      -- Убираем из seen_as_product, чтобы потом не учитывать в exclusively_products
      seen_as_product[name] = nil
    else
      -- Только как ингредиент
      ingredient_groups.exclusively_ingredients[name] = max_consumption[name] or 0
    end
  end

  -- 2.2 Оставшиеся в seen_as_product — те, которые никогда не встречались в ingredients
  for name, _ in pairs(seen_as_product) do
    -- Для них максимальное потребление = 0
    ingredient_groups.exclusively_products[name] = 0
  end

  return ingredient_groups
end

--- Возвращает размер стака для item/fluid, с учётом фолбэка.
--- @param name string Имя ресурса
--- @param fluid_default number? Размер по умолчанию для жидкости
--- @param zero_fallback number? Значение, если stack_size == 0
--- @return number stack_size Размер стака или zero_fallback
function Utils.get_stack_size(name, fluid_default, zero_fallback)
  local stack_size = 0

  if prototypes.item[name] then
    stack_size = prototypes.item[name].stack_size
  elseif prototypes.fluid[name] then
    stack_size = fluid_default or 1000
  else
    game.print("Сигнал не обладает значением стака: " .. tostring(name))
  end

  if stack_size == 0 and zero_fallback then
    return zero_fallback
  end

  return stack_size
end

--- Вычисляет количество занятых слотов для всех item-ингредиентов рецепта.
--- @param recipe LuaRecipePrototype — рецепт
--- @param multiplier number? — множитель количества (по умолчанию 1)
--- @param add number? — слагаемое, прибавляемое к каждому количеству перед расчётом (по умолчанию 0)
--- @return integer — количество занятых слотов (fluid ингредиенты игнорируются)
function Utils.calculate_ingredient_slot_usage(recipe, multiplier, add)
  multiplier = multiplier or 1
  add = add or 0

  if not recipe or not recipe.ingredients then
    return 0
  end

  local slot_count = 0
  for _, ing in ipairs(recipe.ingredients) do
    if ing.type == "item" then
      local amount = (ing.amount or 0) * multiplier + add
      local stack_size = Utils.get_stack_size(ing.name)
      slot_count = slot_count + math.ceil(amount / stack_size)
    end
  end

  return slot_count
end

return Utils
