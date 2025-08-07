--- Модуль фильтрации рецептов.
-- Предоставляет функции для фильтрации таблицы рецептов по различным критериям.
local recipe_selector = {}

--- Фильтрует таблицу рецептов по заданной функции-фильтру.
-- @param recipes table Таблица рецептов в формате `{ [recipe_name] = recipe }`.
-- @param filter function Функция-фильтр, принимающая `(recipe_name, recipe)` и возвращающая `boolean`.
-- @return table Таблица с отфильтрованными рецептами.
function recipe_selector.filter_by(recipes, filter)
  local out = {}
  for recipe_name, recipe in pairs(recipes) do
    if filter(recipe_name, recipe) then
      out[recipe_name] = recipe
    end
  end
  return out
end

--- Проверяет, содержит ли рецепт параметр или ингредиенты с параметрами.
-- Используется для исключения параметрических рецептов.
-- @param recipe_name string Имя рецепта.
-- @param recipe table Таблица с данными рецепта.
-- @return boolean `true`, если рецепт содержит параметр или ингредиенты с параметром; `false` в противном случае.
function recipe_selector.has_parameter(recipe_name, recipe)
  local function has_parameter_item_ingredient(recipe)
    if not recipe.ingredients then return false end
    for _, ing in pairs(recipe.ingredients) do
      if ing.type == "item" then
        local proto = prototypes.item[ing.name]
        if proto and proto.parameter then
          return true
        end
      end
    end
    return false
  end

  local is_param = recipe.parameter or has_parameter_item_ingredient(recipe)
  return is_param
end

--- Фильтр, пропускающий только скрытые рецепты.
-- @param recipe_name string Имя рецепта.
-- @param recipe table Таблица с данными рецепта.
-- @return boolean `true`, если рецепт скрыт; `false`, если он видим.
function recipe_selector.is_hidden(recipe_name, recipe)
  return recipe.hidden
end

--- Фильтр, пропускающий только рецепты, у которых есть соответствующий прототип предмета.
-- Используется для фильтрации рецептов, результат которых — предметы с существующим прототипом.
-- @param recipe_name string Имя рецепта.
-- @param recipe table Таблица с данными рецепта.
-- @return boolean `true`, если существует прототип предмета с именем рецепта; `false` — иначе.
function recipe_selector.recipes_by_items_filter(recipe_name, recipe)
  return prototypes.item[recipe_name] ~= nil
end

--- Фильтр по основному продукту рецепта.
-- Пропускает только те рецепты, у которых указан основной продукт и он является предметом или жидкостью.
-- @param recipe_name string Имя рецепта.
-- @param recipe table Таблица с данными рецепта.
-- @return boolean `true`, если основной продукт — предмет или жидкость; `false` — иначе.
function recipe_selector.has_main_product(recipe_name, recipe)
  if not recipe.main_product then
    return false
  end
  return prototypes.item[recipe.main_product.name] ~= nil or prototypes.fluid[recipe.main_product.name] ~= nil
end

--- Проверяет, может ли рецепт быть приготовлен на указанной машине.
-- Учитывает категории крафта и фиксированные рецепты.
-- @param recipe_name string Имя рецепта.
-- @param recipe table Таблица с данными рецепта.
-- @param machine table Машина, содержащая поля:
--   - `crafting_categories` (table): список поддерживаемых категорий крафта.
--   - `fixed_recipe` (string или nil): фиксированный рецепт, если есть.
-- @return boolean `true`, если машина может приготовить рецепт; `false` — иначе.
function recipe_selector.can_craft_from_machine(recipe_name, recipe, machine)
  if machine == nil then
    return false
  end

  if next(machine.crafting_categories) == nil and machine.fixed_recipe == nil then
    return false
  end

  if machine.fixed_recipe == recipe_name then
    return true
  end

  if recipe.category and machine.crafting_categories[recipe.category] then
    return true
  end

  return false
end

return recipe_selector
