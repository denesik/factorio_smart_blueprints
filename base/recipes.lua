local recipes = {}

local algorithm = require("llib.algorithm")
local base = {
  quality = require("base.quality")
}

local machine_objects_cache = {}
local barrels_map_cache = nil

function recipes.make_key(name_type, quality)
  if quality == nil then 
    return name_type.name .. "|" .. name_type.type
  end
  return name_type.name .. "|" .. name_type.type .. "|" .. quality
end

function recipes.make_value(name_type, quality, key)
  return {
    name = name_type.name,
    type = name_type.type,
    quality = quality,
    key = key or recipes.make_key(name_type, quality)
  }
end

local function check_recipe(recipe)
  if recipe.hidden then return false end
  if recipe.is_parameter then return false end
  return true
end

local function can_craft_from_machine(recipe, machine_prototype)
  if next(machine_prototype.crafting_categories) == nil then return false end

  if machine_prototype.fixed_recipe == recipe.name then return true end
  if machine_prototype.crafting_categories[recipe.category] then return true end

  return false
end

function recipes.get_stack_size(name_type)
  return prototypes[name_type.type][name_type.name].stack_size
end

-- Возвращаем таблицу прототипов на жидкость
-- "fluid_name": { barrel_proto, empty_proto, fill_proto, fluid_proto }
local function get_barrels_map()
  if barrels_map_cache then
    return barrels_map_cache
  end

  local BARREL_ITEM_NAME = "barrel"

  local function get_fluid_name(a, b)
    if a.name == BARREL_ITEM_NAME and a.type == "item" and b.type == "fluid" then
      return b.name
    end
  end

  local function get_or_create(objects, name)
    local found = objects[name]
    if found == nil then
      found = {}
      objects[name] = found
    end
    return found
  end

  local result = {}
  for _, recipe_proto in pairs(prototypes.recipe) do
    if check_recipe(recipe_proto) then
      if recipe_proto.ingredients ~= nil and #recipe_proto.ingredients == 2 and
        recipe_proto.products ~= nil and #recipe_proto.products == 1 then
        local fluid_name = get_fluid_name(recipe_proto.ingredients[1], recipe_proto.ingredients[2])
          or get_fluid_name(recipe_proto.ingredients[2], recipe_proto.ingredients[1])
        if fluid_name and recipe_proto.products[1].type == "item" then
          local object = get_or_create(result, fluid_name)
          object.fill_proto = recipe_proto
          object.barrel_proto = prototypes.item[recipe_proto.products[1].name]
          object.fluid_proto = prototypes.fluid[fluid_name]
          assert(object.barrel_proto)
          assert(object.fluid_proto)
        end
      end

      if recipe_proto.products ~= nil and #recipe_proto.products == 2 and
        recipe_proto.ingredients ~= nil and #recipe_proto.ingredients == 1 then
        local fluid_name = get_fluid_name(recipe_proto.products[1], recipe_proto.products[2])
          or get_fluid_name(recipe_proto.products[2], recipe_proto.products[1])
        if fluid_name and recipe_proto.ingredients[1].type == "item" then
          local object = get_or_create(result, fluid_name)
          object.empty_proto = recipe_proto
          object.barrel_proto = prototypes.item[recipe_proto.ingredients[1].name]
          object.fluid_proto = prototypes.fluid[fluid_name]
          assert(object.barrel_proto)
          assert(object.fluid_proto)
        end
      end
    end
  end


  barrels_map_cache = result
  return result
end

function recipes.get_or_create_object(objects, name_type, quality)
  local key = recipes.make_key(name_type, quality)
  local found = objects[key]
  if found == nil then
    found = recipes.make_value(name_type, quality, key)
    objects[key] = found
  end
  return found
end

-- Получить все рецепты, и объекты (продукты и ингредиенты) машины.
-- Для объектов добавить результат гниения и сжигания
-- Для жидких объектов добавить бочки с жидкостью и рецепты опустошения/заполнения
-- Если добавлены бочки с жидкостью добавить объект пустой бочки
function recipes.get_machine_objects(machine_name)
  if machine_objects_cache[machine_name] then
    return util.table.deepcopy(machine_objects_cache[machine_name])
  end

  local machine_prototype = prototypes.entity[machine_name]
  assert(machine_prototype)

  local all_qualities = base.quality.get_all_qualities()

  -- Заполняем рецепты
  local recipe_objects = {}
  for _, recipe_proto in pairs(prototypes.recipe) do
    if check_recipe(recipe_proto) and can_craft_from_machine(recipe_proto, machine_prototype) then
      for _, quality_proto in ipairs(all_qualities) do
        recipes.get_or_create_object(recipe_objects, recipe_proto, quality_proto.name)
      end
    end
  end

  -- Заполняем продукты и ингредиенты
  local objects = {}
  for _, recipe in pairs(recipe_objects) do
    local recipe_proto = prototypes.recipe[recipe.name]
    assert(recipe_proto)
    for _, product in ipairs(recipe_proto.products) do
      recipes.get_or_create_object(objects, product, recipe.quality)
    end
    for _, ingredient in ipairs(recipe_proto.ingredients) do
      recipes.get_or_create_object(objects, ingredient, recipe.quality)
    end
  end

  -- Заполняем продукты гниения и сгорания
  -- TODO: нет рекурсии. Вдруг продукт гниения сгорает, а продукт сгорания гниет?
  local spoil_and_burnt_objects = {}
  for _, object in pairs(objects) do
    if object.type == "item" then
      local object_proto = prototypes.item[object.name]
      assert(object_proto)
      if object_proto.spoil_result then
        local obj = recipes.get_or_create_object(spoil_and_burnt_objects, object_proto.spoil_result, object.quality)
        object.spoil_key = obj.key
      end
      if object_proto.burnt_result then
        local obj = recipes.get_or_create_object(spoil_and_burnt_objects, object_proto.burnt_result, object.quality)
        object.burnt_key = obj.key
      end
    end
  end

  -- Заполняем рецепты бочек
  local barrels_recipes = {}
  local barrels_map = get_barrels_map()
  for _, object in pairs(objects) do
    if object.type == "fluid" then
      local barrel_object = barrels_map[object.name]
      if barrel_object then
        for _, quality_proto in ipairs(all_qualities) do
          if barrel_object.fill_proto ~= nil then
            local obj = recipes.get_or_create_object(barrels_recipes, barrel_object.fill_proto, quality_proto.name)
            obj.is_fill_barrel_recipe = true
            obj.barrel_key = recipes.make_key(barrel_object.barrel_proto, quality_proto.name)
            obj.fluid_key = recipes.make_key(barrel_object.fluid_proto, quality_proto.name)
          end
          if barrel_object.empty_proto ~= nil then
            local obj = recipes.get_or_create_object(barrels_recipes, barrel_object.empty_proto, quality_proto.name)
            obj.is_empty_barrel_recipe = true
            obj.barrel_key = recipes.make_key(barrel_object.barrel_proto, quality_proto.name)
            obj.fluid_key = recipes.make_key(barrel_object.fluid_proto, quality_proto.name)
          end
        end
      end
    end
  end

    -- Заполняем продукты и ингредиенты бочек
  local barrels_objects = {}
  for _, recipe in pairs(barrels_recipes) do
    local recipe_proto = prototypes.recipe[recipe.name]
    assert(recipe_proto)
    for _, product in ipairs(recipe_proto.products) do
      recipes.get_or_create_object(barrels_objects, product, recipe.quality)
    end
    for _, ingredient in ipairs(recipe_proto.ingredients) do
      recipes.get_or_create_object(barrels_objects, ingredient, recipe.quality)
    end
  end

  local result = algorithm.merge(objects, spoil_and_burnt_objects, recipe_objects, barrels_recipes, barrels_objects)
  machine_objects_cache[machine_name] = result
  return util.table.deepcopy(result)
end

-- Создает связи между объектами и заполняет объекты прототипами
-- Связывает продукты гниения и горения
-- Связывает бочки, жижи и их рецепты
-- Создает связь на объект следующего качества
function recipes.make_links(objects)
  local qualities, qualities_index_map = base.quality.get_all_qualities()

  for _, object in pairs(objects) do
    object.proto = prototypes[object.type][object.name]
    assert(object.proto)

    if object.spoil_key then assert(objects[object.spoil_key]) object.spoil = objects[object.spoil_key] end
    if object.burnt_key then assert(objects[object.burnt_key]) object.burnt = objects[object.burnt_key] end

    if object.is_fill_barrel_recipe or object.is_empty_barrel_recipe then
      local barrel = objects[object.barrel_key]
      local fluid = objects[object.fluid_key]
      assert(barrel and fluid)
      barrel.is_barrel = true
      fluid.barrel_object = barrel
      barrel.fluid_object = fluid
      if object.is_fill_barrel_recipe then barrel.fill_barrel_recipe = object end
      if object.is_empty_barrel_recipe then barrel.empty_barrel_recipe = object end
    end

    local current_quality_index = qualities_index_map[object.quality]
    assert(current_quality_index)
    local next_quality_proto = qualities[current_quality_index + 1]
    if next_quality_proto then
      local key = recipes.make_key(object, next_quality_proto.name)
      assert(objects[key])
      object.next_quality_object = objects[key]
    end
  end
end

local function fill_objects_max_count(requests)
  -- ставим в объекты бочки и в их рецепты флаги is_barrel_product и is_barrel_ingredient
  local function set_barrel_flags(object, flag_name)
    if object.barrel_object == nil then return end
    object.barrel_object[flag_name] = object.barrel_object[flag_name] or true
    if object.barrel_object.fill_barrel_recipe then
      object.barrel_object.fill_barrel_recipe[flag_name] = true
    end
    if object.barrel_object.empty_barrel_recipe then
      object.barrel_object.empty_barrel_recipe[flag_name] = true
    end
  end

  for _, product, recipe in recipes.requests_pairs(requests) do
    product.object.product_max_count = math.max(product.object.product_max_count or 0, recipe.need_produce_count)
    product.object.is_product = true
    set_barrel_flags(product.object, "is_barrel_product")
    for _, ingredient in pairs(recipe.object.ingredients) do
      ingredient.object.ingredient_max_count = math.max(ingredient.object.ingredient_max_count or 0, ingredient.max_request_count)
      ingredient.object.ingredient_max_one_craft_count = math.max(ingredient.object.ingredient_max_one_craft_count or 0, ingredient.one_craft_count)
      ingredient.object.is_ingredient = true
      set_barrel_flags(ingredient.object, "is_barrel_ingredient")
    end
  end
end

-- Функция подсчета количества разных рецептов для ингредиентов, продуктов и self-craft продуктов
function count_usage(objects)
  for _, obj in pairs(objects) do
    if obj.type == "recipe" and obj.recipe_order then
      -- Подсчет для ингредиентов
      local seen_ingredients = {}
      for _, ingredient in pairs(obj.ingredients) do
        local ing_obj = ingredient.object
        -- Инициализация полей, если их ещё нет
        ing_obj.as_ingredient_count = ing_obj.as_ingredient_count or 0
        ing_obj.as_product_count = ing_obj.as_product_count or 0
        ing_obj.as_self_craft_product_count = ing_obj.as_self_craft_product_count or 0

        if not seen_ingredients[ing_obj] then
          seen_ingredients[ing_obj] = true
          ing_obj.as_ingredient_count = ing_obj.as_ingredient_count + 1
        end
      end

      -- Подсчет для продуктов
      local seen_products = {}
      for _, product in pairs(obj.products) do
        local prod_obj = product.object
        -- Инициализация полей, если их ещё нет
        prod_obj.as_ingredient_count = prod_obj.as_ingredient_count or 0
        prod_obj.as_product_count = prod_obj.as_product_count or 0
        prod_obj.as_self_craft_product_count = prod_obj.as_self_craft_product_count or 0

        if not seen_products[prod_obj] then
          seen_products[prod_obj] = true
          prod_obj.as_product_count = prod_obj.as_product_count + 1

          -- Проверяем self-craft (продукт также используется как ингредиент в этом рецепте)
          if obj.ingredients[prod_obj.key] then
            prod_obj.as_self_craft_product_count = prod_obj.as_self_craft_product_count + 1
          end
        end
      end
    end
  end
end

-- Создаем таблицу продукт - рецепты
-- На входе может быть объект (item или fluid) или рецепт
-- Если на входе объект, в таблицу добавляется его прямой рецепт (имя рецепта совпадает с именем объекта), если он есть
-- Если на входе рецепт, в таблицу добавляется этот рецепт на каждый продукт этого рецепта
-- Таким образом, одному рецепту может соответствовать несколько продуктов (переработка желеореха == желе + семечко)
-- А также одному продукту может соответствовать несколько рецептов (питательные вещества == из гнили или из биофлюса)
function recipes.fill_requests_map(raw_requests, objects)

  local function get_or_create_cell(target, key)
    local found = target[key]
    if found == nil then
      found = { recipes = {} }
      target[key] = found
    end
    return found
  end

  local function add_recipe(target, recipe, request_count)
    local function find_product_amount()
      for _, entry in ipairs(recipe.proto.products) do
        if entry.name == target.object.name then
          return entry.amount
        end
      end
      assert(false)
    end

    local out = {
      object = recipe,
      need_produce_count = request_count,
      one_craft_product_output = find_product_amount(),
      is_self_craft = recipe.ingredients[target.object.key] ~= nil
    }

    target.recipes[recipe.key] = out
  end

  local recipe_order = 1
  local function fill_recipe(recipe, request_count)
    -- Нам не может прийти один рецепт с разным количеством запроса
    assert(recipe.recipe_order == nil)
    recipe.recipe_order = recipe_order
    recipe_order = recipe_order + 1

    recipe.products = {}
    recipe.ingredients = {}

    for _, product in ipairs(recipe.proto.products) do
      local quality = product.type == "fluid" and "normal" or recipe.quality
      local key = recipes.make_key(product, quality)
      recipe.products[key] = { object = assert(objects[key]) }
    end

    local max_product_amount = 0
    for _, entry in ipairs(recipe.proto.products) do
      max_product_amount = math.max(max_product_amount, entry.amount)
    end

    for _, ingredient in ipairs(recipe.proto.ingredients) do
      local quality = ingredient.type == "fluid" and "normal" or recipe.quality
      local key = recipes.make_key(ingredient, quality)
      recipe.ingredients[key] = {
        object = assert(objects[key]),
        one_craft_count = ingredient.amount,
        max_request_count = ingredient.amount * (request_count / max_product_amount)
      }
    end
  end

  local out = {}
  for _, request in ipairs(raw_requests) do
    local request_key = recipes.make_key(request.value, request.value.quality)

    if request.value.type == "recipe" then
      -- Если сигнал рецепта, эмулируем, как будто заказали каждого предмета этого рецепта
      local recipe = objects[request_key]
      if recipe ~= nil then
        fill_recipe(recipe, request.min)
        for _, product in ipairs(recipe.proto.products) do
          local product_key = recipes.make_key(product, request.value.quality)
          assert(objects[product_key])
          local entry = get_or_create_cell(out, product_key)
          entry.object = objects[product_key]
          add_recipe(entry, recipe, request.min)
        end
      end
    else
      local recipe_key = recipes.make_key({ name = request.value.name, type = "recipe" }, request.value.quality)
      local recipe = objects[recipe_key]
      if recipe ~= nil then
        assert(objects[request_key])
        fill_recipe(recipe, request.min)
        local entry = get_or_create_cell(out, request_key)
        entry.object = objects[request_key]
        add_recipe(entry, recipe, request.min)
      end
    end
  end

  fill_objects_max_count(out)
  count_usage(objects)
  return out
end

-- итератор одновременно по продуктам и их рецептам
function recipes.requests_pairs(map)
  local product_key, product_entry
  local recipe_key, recipe_entry
  local recipe_table

  return function()
    while true do
      -- если нет активного набора рецептов — переходим к следующему продукту
      if recipe_table == nil then
        product_key, product_entry = next(map, product_key)
        if not product_key then
          return nil -- всё пройдено
        end

        assert(product_entry and product_entry.recipes, "invalid map entry: expected { recipes = {} }")

        recipe_table = product_entry.recipes
        recipe_key = nil
      end

      recipe_key, recipe_entry = next(recipe_table, recipe_key)
      if not recipe_key then
        recipe_table = nil -- рецепты закончились, переходим к следующему продукту
      else
        return product_key, product_entry, recipe_entry
      end
    end
  end
end



return recipes

