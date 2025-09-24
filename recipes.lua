local recipes = {}

local cache = {}

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
    local key = item.value.type .. "|" .. item.value.name
    for _, recipe in ipairs(machine_recipes[key] or {}) do
      local extended_item = util.table.deepcopy(item)
      extended_item.recipe = recipe
      table.insert(out, extended_item)
    end
  end
  return out
end

return recipes
