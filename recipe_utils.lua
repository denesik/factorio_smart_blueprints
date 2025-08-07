local recipe_utils = {}

function recipe_utils.get_all_products(recipes, quality)
  quality = quality or "normal"

  local out = {}
  for recipe_name, recipe in pairs(recipes) do
    for _, product in ipairs(recipe.products) do
      table.insert(out, {
        value = {
          name = product.name,
          type = product.type,
          quality = quality
        },
        min = product.amount
      })
    end
  end
  return out
end

function recipe_utils.get_recipe_products(recipes, quality)
  quality = quality or "normal"

  local out = {}
  for recipe_name, recipe in pairs(recipes) do
    if recipe.main_product ~= nil then
      table.insert(out, {
        value = {
          name = recipe_name,
          type = "recipe",
          quality = quality
        },
        min = recipe.main_product.amount
      })
    end
  end
  return out
end

return recipe_utils
