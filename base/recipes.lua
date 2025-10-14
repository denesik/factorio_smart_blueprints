local recipes = {}

local base = {
  barrel = require("base.barrel"),
  quality = require("base.quality")
}

local machine_recipes_cache = {}
local machine_products_cache = {}
local machine_ingredients_cache = {}
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
  if machine_recipes_cache[machine_name] then
    return machine_recipes_cache[machine_name]
  end

  local machine_prototype = prototypes.entity[machine_name]
  assert(machine_prototype)

  local result = {}
  for recipe_name, recipe in pairs(prototypes.recipe) do
    if check_recipe(recipe) and can_craft_from_machine(recipe, machine_prototype) then
      for _, product in ipairs(recipe.products) do
        local key = recipes.make_key(product)
        if not result[key] then
          result[key] = {}
        end
        table.insert(result[key], recipe)
      end
    end
  end

  machine_recipes_cache[machine_name] = result
  return result
end

function recipes.get_machine_products(machine_name)
  if machine_products_cache[machine_name] then
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
    return machine_ingredients_cache[machine_name]
  end

  local all_qualities = base.quality.get_all_qualities()
  local normal_quality = all_qualities[1].name
  assert(#all_qualities > 0)
  local machine_recipes = recipes.get_machine_recipes(machine_name)
  local results = {}

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
      local recipe = prototypes.recipe[item.value.name]
      if check_recipe(recipe) and can_craft_from_machine(recipe, machine_prototype) then
        for _, product in ipairs(recipe.products) do
          -- TODO: probability
          local extended_item = {
            value = recipes.make_value(product, item.value.quality),
            min = item.min * product.amount
          }
          local recipe_signal = make_recipe_signal(recipe, item.value.quality)
          extended_item.recipe_signal = {
            value = recipe_signal.value,
            recipe = recipe_signal.recipe
          }
          table.insert(out, extended_item)
        end
      end
    else
      for _, recipe in ipairs(machine_recipes[recipes.make_key(item.value)] or {}) do
        if recipe.main_product and recipes.make_key(recipe.main_product, item.value.quality) == item.value.key then
          local extended_item = util.table.deepcopy(item)
          local recipe_signal = make_recipe_signal(recipe, item.value.quality)
          extended_item.recipe_signal = {
            value = recipe_signal.value,
            recipe = recipe_signal.recipe
          }
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
    for _, ingredient in ipairs(item.recipe_signal.recipe.ingredients) do
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
    for _, product in ipairs(item.recipe_signal.recipe.products) do
      if product.name == item.value.name then
        return product.amount
      end
    end
  end

  for _, item in ipairs(input) do
    item.ingredients = {}
    local product_amount = find_product_amount(item)
    for _, ingredient in ipairs(item.recipe_signal.recipe.ingredients) do
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

return recipes
