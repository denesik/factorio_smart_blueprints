local barrel = {}

local BARREL_ITEM = "barrel"

local recipes_table = nil

local function build_barrel_recipes()
  local result = {}

  -- Этап 1: ищем рецепты наполнения
  for _, recipe in pairs(prototypes.recipe) do
    local fluid_ing
    local has_empty_ing = false

    for _, ing in pairs(recipe.ingredients) do
      if ing.type == "fluid" then
        fluid_ing = ing.name
      elseif ing.type == "item" and ing.name == BARREL_ITEM then
        has_empty_ing = true
      end
    end

    if fluid_ing and has_empty_ing then
      local entry = result[fluid_ing] or { barrel_recipe = nil, empty_barrel_recipe = nil }
      entry.barrel_recipe = recipe
      result[fluid_ing] = entry
    end
  end

  -- Этап 2: ищем рецепты опустошения
  for _, recipe in pairs(prototypes.recipe) do
    local fluid_prod
    local has_empty_prod = false

    for _, prod in pairs(recipe.products) do
      if prod.type == "fluid" then
        fluid_prod = prod.name
      elseif prod.type == "item" and prod.name == BARREL_ITEM then
        has_empty_prod = true
      end
    end

    if fluid_prod and has_empty_prod then
      local entry = result[fluid_prod] or { barrel_recipe = nil, empty_barrel_recipe = nil }
      entry.empty_barrel_recipe = recipe
      result[fluid_prod] = entry
    end
  end

  return result
end

function barrel.get_barrel_recipes(fluid_name)
  if not recipes_table then
    recipes_table = build_barrel_recipes()
  end
  local found = recipes_table[fluid_name]
  if found == nil then return nil end

  return found.barrel_recipe, found.empty_barrel_recipe
end

function barrel.get_all_barrel_recipes()
  if not recipes_table then
    recipes_table = build_barrel_recipes()
  end
  return recipes_table
end

return barrel
