local product_selector = {}

function product_selector.filter_by(products, filter)
  local out = {}
  for _, product in ipairs(products) do
    if filter(product) then
      table.insert(out, product)
    end
  end
  return out
end

function product_selector.is_filtered_by_recipe(product, recipe_filter)
  local recipe_name = product.value.name
  local recipe = prototypes.recipe[recipe_name]
  if recipe then
    if recipe_filter(recipe_name, recipe) then
      return true
    end
  end
  return false
end

return product_selector
