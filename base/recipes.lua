local recipes = {}

local algorithm = require("llib.algorithm")
local base = {
  barrel = require("base.barrel"),
  quality = require("base.quality")
}

local machine_recipes_cache = {}
local machine_products_cache = {}
local machine_ingredients_cache = {}
local machine_objects_cache = {}
local barrels_map_cache = nil
local all_barrels_cache = nil

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

function recipes.get_machine_recipes(machine_name)
  local found = machine_recipes_cache[machine_name]
  if found then
    -- TODO: делать копию
    return found.product_recipes, found.machine_recipes
  end

  local machine_prototype = prototypes.entity[machine_name]
  assert(machine_prototype)

  local product_recipes = {}
  local machine_recipes = {}
  for name, recipe in pairs(prototypes.recipe) do
    if check_recipe(recipe) and can_craft_from_machine(recipe, machine_prototype) then
      for _, product in ipairs(recipe.products) do
        local key = recipes.make_key(product)
        if not product_recipes[key] then
          product_recipes[key] = {}
        end
        table.insert(product_recipes[key], recipe)
      end
      machine_recipes[name] = recipe
    end
  end

  machine_recipes_cache[machine_name] = {
    product_recipes = product_recipes,
    machine_recipes = machine_recipes
  }
  return product_recipes, machine_recipes
end

function recipes.get_machine_products(machine_name)
  if machine_products_cache[machine_name] then
    -- TODO: делать копию
    return machine_products_cache[machine_name]
  end

  local all_qualities = base.quality.get_all_qualities()
  local normal_quality = all_qualities[1].name
  assert(#all_qualities > 0)
  local machine_recipes = recipes.get_machine_recipes(machine_name)
  local results = {}

  for _, recipe_list in pairs(machine_recipes) do
    for _, recipe in ipairs(recipe_list) do
      if recipe.products then
        for _, product in ipairs(recipe.products) do
          if product.type == "item" then
            for _, quality in ipairs(all_qualities) do
              local key = recipes.make_key(product, quality.name)
              if results[key] == nil then
                results[key] = { value = recipes.make_value(product, quality.name, key) }
              end
              local spoil_result = prototypes.item[product.name].spoil_result
              if spoil_result then
                local alt_key = recipes.make_key(spoil_result, quality.name)
                if results[alt_key] == nil then
                  results[alt_key] = { value = recipes.make_value(spoil_result, quality.name, alt_key) }
                end
              end
            end
          elseif product.type == "fluid" then
            local key = recipes.make_key(product, normal_quality)
            if results[key] == nil then
              results[key] = { value = recipes.make_value(product, normal_quality, key) }
            end
          end
        end
      end
    end
  end

  machine_products_cache[machine_name] = results
  return results
end

function recipes.get_machine_ingredients(machine_name)
  if machine_ingredients_cache[machine_name] then
    -- TODO: делать копию
    return machine_ingredients_cache[machine_name]
  end

  local all_qualities = base.quality.get_all_qualities()
  local normal_quality = all_qualities[1].name
  assert(#all_qualities > 0)
  local machine_recipes = recipes.get_machine_recipes(machine_name)
  local results = {}

  -- TODO: альтернативные ингредиенты (продукты гниения) как минимум нужно банить
  for _, recipe_list in pairs(machine_recipes) do
    for _, recipe in ipairs(recipe_list) do
      if recipe.ingredients then
        for _, ingredient in ipairs(recipe.ingredients) do
          if ingredient.type == "item" then
            for _, quality in ipairs(all_qualities) do
              local key = recipes.make_key(ingredient, quality.name)
              if results[key] == nil then
                results[key] = { value = recipes.make_value(ingredient, quality.name, key) }
              end
            end
          elseif ingredient.type == "fluid" then
            local key = recipes.make_key(ingredient, normal_quality)
            if results[key] == nil then
              results[key] = { value = recipes.make_value(ingredient, normal_quality, key) }
            end
          end
        end
      end
    end
  end

  machine_ingredients_cache[machine_name] = results
  return results
end

-- На выходе каждому предмету соответствует его прямой рецепт. 
-- А для каждого рецепта мы эмулируем запросы предметов которые являются продуктами этого рецепта.
-- Т.е. у нас может оказаться несколько одинаковых предметов разного количества и с разными рецептами.
-- Если один предмет будет в двух рецептах, получится две записи (продукт A - рецепт B, продукт A - рецепт C).
-- Если В одном рецепте есть два продукта, получится две записи (продукт A - рецепт C, продукт B - рецепт C).
function recipes.enrich_with_recipes(input, machine_name)
  local machine_recipes = recipes.get_machine_recipes(machine_name)
  local out = {}

  local machine_prototype = prototypes.entity[machine_name]
  assert(machine_prototype)

  local recipe_signals = {}

  local function make_recipe_signal(recipe, quality)
    local key = recipes.make_key(recipe, quality)
    if recipe_signals[key] == nil then
      recipe_signals[key] = {
        value = recipes.make_value(recipe, quality, key),
        recipe = recipe,
      }
    end
    return recipe_signals[key]
  end

  for _, item in ipairs(input) do
    item.value.key = recipes.make_key(item.value, item.value.quality)
    if item.value.type == "recipe" then
      -- Если сигнал рецепта, эмулируем, как будто заказали каждого предмета этого рецепта
      local recipe_proto = prototypes.recipe[item.value.name]
      if check_recipe(recipe_proto) and can_craft_from_machine(recipe_proto, machine_prototype) then
        for _, product in ipairs(recipe_proto.products) do
          -- TODO: probability
          local extended_item = {
            value = recipes.make_value(product, item.value.quality),
            min = item.min
          }
          extended_item.recipe_signal = {
            value = make_recipe_signal(recipe_proto, item.value.quality).value,
          }
          extended_item.recipe_proto = recipe_proto
          extended_item.proto = prototypes[extended_item.value.type][extended_item.value.name]
          table.insert(out, extended_item)
        end
      end
    else
      for _, recipe_proto in ipairs(machine_recipes[recipes.make_key(item.value)] or {}) do
        -- TODO: может быть несколько продуктов
        if recipe_proto.name == item.value.name then
          local extended_item = util.table.deepcopy(item)
          extended_item.recipe_signal = {
            value = make_recipe_signal(recipe_proto, item.value.quality).value,
          }
          extended_item.recipe_proto = recipe_proto
          extended_item.proto = prototypes[extended_item.value.type][extended_item.value.name]
          table.insert(out, extended_item)
        end
      end
    end
  end
  return out, recipe_signals
end

function recipes.make_ingredients(input)
  local out = {}
  for _, item in ipairs(input) do
    for _, ingredient in ipairs(item.recipe_proto.ingredients) do
      local quality = item.value.quality
      if ingredient.type == "fluid" then quality = "normal" end
      local key = recipes.make_key(ingredient, quality)
      if out[key] == nil then
        out[key] = { value = recipes.make_value(ingredient, quality, key) }
      end
    end
  end
  return out
end

function recipes.enrich_with_ingredients(input, ingredients)
  local function find_product_amount(item)
    for _, product in ipairs(item.recipe_proto.products) do
      if product.name == item.value.name then
        return product.amount
      end
    end
  end

  for _, item in ipairs(input) do
    item.ingredients = {}
    local product_amount = find_product_amount(item)
    for _, ingredient in ipairs(item.recipe_proto.ingredients) do
      local quality = item.value.quality
      if ingredient.type == "fluid" then quality = "normal" end
      local key = recipes.make_key(ingredient, quality)
      assert(ingredients[key])
      local value = ingredients[key].value
      assert(value)

      item.ingredients[key] = {
        value = value,
        recipe_min = ingredient.amount,
        request_min = ingredient.amount * (item.min / product_amount)
      }
    end
    item.request_min = item.min
  end
end

function recipes.enrich_with_barrels(ingredients)
  for _, item in pairs(ingredients) do
    local value = item.value
    assert(value)
    if value.type == "fluid" then
      local fill_recipe, empty_recipe = base.barrel.get_barrel_recipes(value.name)
      if fill_recipe and empty_recipe then
        value.barrel_item = {
          value = recipes.make_value(fill_recipe.main_product, value.quality)
        }
        value.barrel_fill = {
          value = recipes.make_value(fill_recipe, value.quality)
        }
        value.barrel_empty = {
          value = recipes.make_value(empty_recipe, value.quality)
        }
      end
    end
  end
end

recipes.barrel_item = {
  value = recipes.make_value({name = "barrel", type = "item"}, "normal")
}

function recipes.get_all_barrels(quality)
  if all_barrels_cache then
    -- TODO: делать копию
    return all_barrels_cache
  end

  local barrel_recipes = base.barrel.get_all_barrel_recipes()

  local barrels = {}

  table.insert(barrels, recipes.barrel_item)

  for _, entry in pairs(barrel_recipes) do
    assert(entry.barrel_recipe)
    local barrel_value = recipes.make_value(entry.barrel_recipe.main_product, recipes.barrel_item.value.quality)
    table.insert(barrels, { value = barrel_value })
  end

  all_barrels_cache = barrels
  return barrels
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
            obj.is_fill_barrel = true
            obj.barrel_key = recipes.make_key(barrel_object.barrel_proto, quality_proto.name)
            obj.fluid_key = recipes.make_key(barrel_object.fluid_proto, quality_proto.name)
          end
          if barrel_object.empty_proto ~= nil then
            local obj = recipes.get_or_create_object(barrels_recipes, barrel_object.empty_proto, quality_proto.name)
            obj.is_empty_barrel = true
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

    if object.is_fill_barrel or object.is_empty_barrel then
      local barrel = objects[object.barrel_key]
      local fluid = objects[object.fluid_key]
      assert(barrel and fluid)
      barrel.is_barrel = true
      fluid.barrel_object = barrel
      barrel.fluid_object = fluid
      if object.is_fill_barrel then barrel.fill_barrel_recipe = object end
      if object.is_empty_barrel then barrel.empty_barrel_recipe = object end
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
  for _, product, recipe in recipes.requests_pairs(requests) do
    product.object.need_produce_max = math.max(product.object.need_produce_max or 0, recipe.need_produce_count)
    for _, ingredient in pairs(recipe.ingredients) do
      ingredient.object.full_produce_count_max = math.max(ingredient.object.full_produce_count_max or 0, ingredient.full_produce_count)
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

  local order = 1
  local function add_recipe(target, recipe, product, request_count)
    local function find_product_amount()
      for _, entry in ipairs(recipe.proto.products) do
        if entry.name == product.name then
          return entry.amount
        end
      end
    end

    recipe.order = recipe.order or order
    order = order + 1
    local out = {
      object = recipe,
      need_produce_count = request_count,
      ingredients = {}
    }

    local product_amount = find_product_amount()
    assert(product_amount ~= nil)

    for _, ingredient in ipairs(recipe.proto.ingredients) do
      local quality = product.quality
      if ingredient.type == "fluid" then quality = "normal" end
      local ingredient_key = recipes.make_key(ingredient, quality)
      assert(objects[ingredient_key])

      objects[ingredient_key].is_ingredient = true
      out.ingredients[ingredient_key] = {
        object = objects[ingredient_key],
        one_craft_count = ingredient.amount,
        one_produce_count = ingredient.amount / product_amount,
        full_produce_count = ingredient.amount * (request_count / product_amount)
      }
    end

    target[recipe.key] = out
  end

  local out = {}
  for _, request in ipairs(raw_requests) do
    local request_key = recipes.make_key(request.value, request.value.quality)

    if request.value.type == "recipe" then
      -- Если сигнал рецепта, эмулируем, как будто заказали каждого предмета этого рецепта
      local recipe = objects[request_key]
      if recipe ~= nil then
        for _, product in ipairs(recipe.proto.products) do
          local product_key = recipes.make_key(product, request.value.quality)
          assert(objects[product_key])
          local entry = get_or_create_cell(out, product_key)
          entry.object = objects[product_key]
          entry.object.is_product = true
          add_recipe(entry.recipes, recipe, product, request.min)
        end
      end
    else
      local recipe_key = recipes.make_key({ name = request.value.name, type = "recipe" }, request.value.quality)
      local recipe = objects[recipe_key]
      if recipe ~= nil then
        assert(objects[request_key])
        local entry = get_or_create_cell(out, request_key)
        entry.object = objects[request_key]
        entry.object.is_product = true
        add_recipe(entry.recipes, recipe, request.value, request.min)
      end
    end
  end

  fill_objects_max_count(out)
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

