local recipe_utils = require("recipe_utils")
local signal_utils = require("signal_utils")

local recipe_decomposer = {}

function recipe_decomposer.deep_strategy(recipe, product, ingredient)
  return ingredient.amount * (product.min / recipe.main_product.amount)
end

function recipe_decomposer.shallow_strategy(recipe, product, ingredient)
  return ingredient.amount
end

local function decomposition_element(recipes_for_product, product, strategy)
  local out = {}
  for _, recipe in ipairs(recipes_for_product) do
    for _, ingredient in ipairs(recipe.ingredients) do
      table.insert(out, {
        value = {
          name = ingredient.name,
          type = ingredient.type,
          quality = product.value.quality
        },
        min = strategy(recipe, product, ingredient)
      })
    end
  end
  return out
end

local function collect_depths(recipes, product, strategy, visited_path, depth_map)
  local key = signal_utils.items_key_fn(product.value)

  if depth_map[key] then
    -- Если глубина уже вычислена, ставим ее в продукт и возвращаем
    product.depth = depth_map[key]
    return depth_map[key]
  end

  if visited_path[key] then
    -- Цикл найден, ставим depth = 0, чтобы глубина не росла бесконечно
    product.depth = 0
    return 0
  end

  visited_path[key] = true

  local recipes_for_product = recipe_utils.get_recipes_for_signal(recipes, product)
  local ingredients = decomposition_element(recipes_for_product, product, strategy)

  local max_depth = 0
  for _, ing in ipairs(ingredients) do
    local ing_depth = collect_depths(recipes, ing, strategy, visited_path, depth_map)
    if ing_depth > max_depth then
      max_depth = ing_depth
    end
  end

  local product_depth = max_depth + 1
  depth_map[key] = product_depth
  product.depth = product_depth

  visited_path[key] = nil

  return product_depth
end


local function build_out(recipes, product, strategy, visited_path, depth_map, out)
  local key = signal_utils.items_key_fn(product.value)
  if visited_path[key] then
    return
  end
  visited_path[key] = true

  local recipes_for_product = recipe_utils.get_recipes_for_signal(recipes, product)
  local ingredients = decomposition_element(recipes_for_product, product, strategy)

  for _, ing in ipairs(ingredients) do
    local ing_key = signal_utils.items_key_fn(ing.value)
    ing.depth = depth_map[ing_key] or 1
    table.insert(out, ing)
    build_out(recipes, ing, strategy, visited_path, depth_map, out)
  end

  visited_path[key] = nil
end

function recipe_decomposer.decompose(recipes, products, strategy)
  local out = {}
  local depth_map = {}

  -- Шаг 1 — вычисляем максимальную глубину для каждого продукта
  for _, p in ipairs(products) do
    collect_depths(recipes, p, strategy, {}, depth_map)
  end

  -- Шаг 2 — строим результат
  for _, p in ipairs(products) do
    build_out(recipes, p, strategy, {}, depth_map, out)
  end

  return out
end

return recipe_decomposer
