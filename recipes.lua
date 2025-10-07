local recipes = {}

local barrel = require("barrel")

local cache = {}

function recipes.make_key(name_type, quality)
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
  if not recipe.main_product then return false end
  if recipe.main_product.type ~= "item" and recipe.main_product.type ~= "fluid" then return false end
  return true
end

local function can_craft_from_machine(recipe, machine_prototype)
  if next(machine_prototype.crafting_categories) == nil then return false end

  if machine_prototype.fixed_recipe == recipe.name then return true end
  if machine_prototype.crafting_categories[recipe.category] then return true end

  return false
end

function recipes.get_machine_recipes(machine_name)
  if cache[machine_name] then
    return cache[machine_name]
  end

  local machine_prototype = prototypes.entity[machine_name]
  assert(machine_prototype)

  local result = {}
  for recipe_name, recipe in pairs(prototypes.recipe) do
    if check_recipe(recipe) and can_craft_from_machine(recipe, machine_prototype) then
      local key = recipe.main_product.type .. "|" .. recipe.main_product.name
      if not result[key] then
        result[key] = {}
      end
      table.insert(result[key], recipe)
    end
  end

  cache[machine_name] = result
  return result
end

function recipes.enrich_with_recipes(input, machine_name)
  local machine_recipes = recipes.get_machine_recipes(machine_name)
  local out = {}
  for _, item in ipairs(input) do
    item.value.key = recipes.make_key(item.value, item.value.quality)
    local key = item.value.type .. "|" .. item.value.name
    for _, recipe in ipairs(machine_recipes[key] or {}) do
      local extended_item = util.table.deepcopy(item)
      extended_item.recipe = recipe
      extended_item.recipe_signal = {
        value = recipes.make_value(recipe, item.value.quality)
      }
      table.insert(out, extended_item)
    end
  end
  return out
end

function recipes.make_ingredients(input)
  local out = {}
  for _, item in ipairs(input) do
    for _, ingredient in ipairs(item.recipe.ingredients) do
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
  for _, item in ipairs(input) do
    item.ingredients = {}
    for _, ingredient in ipairs(item.recipe.ingredients) do
      local quality = item.value.quality
      if ingredient.type == "fluid" then quality = "normal" end
      local key = recipes.make_key(ingredient, quality)
      assert(ingredients[key])
      local value = ingredients[key].value
      assert(value)

      item.ingredients[key] = {
        value = value,
        recipe_min = ingredient.amount,
        request_min = ingredient.amount * (item.min / item.recipe.main_product.amount)
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
      local fill_recipe, empty_recipe = barrel.get_barrel_recipes(value.name)
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

return recipes
