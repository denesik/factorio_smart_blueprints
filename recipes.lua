local Set = require("set")

local Recipes = {}

function Recipes.global_recipe_filtered()
  -- ☆ Проверяет ингредиенты рецепта на наличие parameter
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

  -- ☆ Все рецепты разделенные по эффектам
  local function get_recipes_by_effects()
    local effect_names = { "productivity", "quality", "speed" }
    for _, effect in ipairs(effect_names) do
      if not prototypes.module_category[effect] then
        error("Отсутствует категория модуля: " .. effect)
      end
    end
    local result = {}
    for _, effect in ipairs(effect_names) do
      result[effect] = {}
    end
    for name, recipe in pairs(prototypes.recipe) do
      local effects = recipe.allowed_effects
      if effects then
        for _, effect in ipairs(effect_names) do
          if effects[effect] then
            result[effect][name] = recipe
          end
        end
      end
    end
    return result
  end

  -- ☆ Удаляет невалидные рецепты из таблицы
  local function filter_invalid_recipes(recipe_table, invalid_recipes)
    for key, value in pairs(recipe_table) do
      if type(value) == "table" then
        -- Рекурсивно применим к вложенным таблицам
        recipe_table[key] = filter_invalid_recipes(value, invalid_recipes)
      end
    end
    return Set.D(recipe_table, invalid_recipes)
  end

  -- Возвращает таблицу зацикленных рецептов. Все рецепты каждой "петли" связанных рецептов
  local function get_cyclic_recipes(recipes_table)
    ------------------------------------------------------------------
    -- 0. Источник рецептов
    ------------------------------------------------------------------
    local source = recipes_table or prototypes.recipe

    ------------------------------------------------------------------
    -- 1. Соберём единую «плоскую» коллекцию recipe-prototype-ов
    ------------------------------------------------------------------
    local recipe_list = {}   -- { <proto>, … } – для итераций массивом
    local name_to_proto = {} -- name → prototype

    for k, v in pairs(source) do
      local proto =
          (type(k) == "table" and k.name and k)             -- Set-множество
          or (type(v) == "table" and v.name and v)          -- обычный массив
          or (type(k) == "string" and prototypes.recipe[k]) -- set с именами
      if proto and not name_to_proto[proto.name] then
        name_to_proto[proto.name] = proto
        recipe_list[#recipe_list + 1] = proto
      end
    end

    ------------------------------------------------------------------
    -- 2. Карты produces / consumes
    --    produces[item]   → {recipe-name,…}
    --    consumes[recipe] → {item-name,…}
    ------------------------------------------------------------------
    local produces, consumes = {}, {}

    local function add_item(tbl, key, val)
      local t = tbl[key]
      if not t then
        t = {}; tbl[key] = t
      end
      t[#t + 1] = val
    end

    for _, recipe in ipairs(recipe_list) do
      local rname = recipe.name
      consumes[rname] = {}

      -- ✦ ингредиенты
      local ingredients = recipe.ingredients or (recipe.get_ingredients and recipe:get_ingredients()) or {}
      for _, ing in pairs(ingredients) do
        local iname = ing.name or ing[1] -- поддержка краткой формы
        if iname then add_item(consumes, rname, iname) end
      end

      -- ✦ продукты
      local products = recipe.products or recipe.results
          or (recipe.get_products and recipe:get_products()) or {}
      for _, prod in pairs(products) do
        local pname = prod.name or prod[1]
        if pname then add_item(produces, pname, rname) end
      end
    end

    ------------------------------------------------------------------
    -- 3. Граф зависимостей: adj[recipe] → {recipe,…}
    ------------------------------------------------------------------
    local adj = {}
    for rname, items in pairs(consumes) do
      local edges = {}
      adj[rname] = edges
      for _, item in ipairs(items) do
        local makers = produces[item]
        if makers then
          for _, maker in ipairs(makers) do
            edges[#edges + 1] = maker
          end
        end
      end
    end

    ------------------------------------------------------------------
    -- 4. Tarjan (SCC) – поиск циклов
    ------------------------------------------------------------------
    local index, stack               = 0, {}
    local indices, lowlink, on_stack = {}, {}, {}
    local cyclic                     = {} -- имя → prototype

    local function strongconnect(v)
      index = index + 1
      indices[v], lowlink[v] = index, index
      stack[#stack + 1] = v
      on_stack[v] = true

      local nbrs = adj[v]
      if nbrs then
        for _, w in ipairs(nbrs) do
          if not indices[w] then
            strongconnect(w)
            if lowlink[w] < lowlink[v] then lowlink[v] = lowlink[w] end
          elseif on_stack[w] and indices[w] < lowlink[v] then
            lowlink[v] = indices[w]
          end
        end
      end

      if lowlink[v] == indices[v] then -- корень SCC
        local comp = {}
        local w
        repeat
          w = stack[#stack]
          stack[#stack] = nil
          on_stack[w] = nil
          comp[#comp + 1] = w
        until w == v

        if #comp > 1 then -- цикл длиной >1
          for _, r in ipairs(comp) do
            cyclic[r] = name_to_proto[r]
          end
        else -- возможная самопетля
          local r = comp[1]
          local e = adj[r]
          if e then
            for _, dst in ipairs(e) do
              if dst == r then -- рецепт ест сам себя
                cyclic[r] = name_to_proto[r]
                break
              end
            end
          end
        end
      end
    end

    for v in pairs(adj) do
      if not indices[v] then strongconnect(v) end
    end

    return cyclic -- { name = proto, … }
  end

  local global_recipe_table = {}

  -- ☆ Все рецепты которые скрыты или являются параметром
  global_recipe_table.invalid_recipes = {}
  global_recipe_table.parameter_recipes = {}
  for name, recipe in pairs(prototypes.recipe) do
    local is_param = recipe.parameter or has_parameter_item_ingredient(recipe)
    if is_param then
      global_recipe_table.parameter_recipes[name] = recipe
    end
    if recipe.hidden or is_param then
      global_recipe_table.invalid_recipes[name] = recipe
    end
  end

  -- ☆☆ Все рецепты у которых ВСЕ ингредиенты имеют тип жидкости
  global_recipe_table.fluid_only_ingredient_recipes = prototypes.get_recipe_filtered {
    {
      filter = "has-ingredient-item",
      invert = true
    },
    {
      filter = "has-ingredient-fluid",
      mode = "and"
    }
  }

  -- ☆☆ Все рецепты у которых ВСЕ продукты имеют тип жидкости
  global_recipe_table.fluid_only_product_recipes = prototypes.get_recipe_filtered {
    {
      filter = "has-product-item",
      invert = true
    },
    {
      filter = "has-product-fluid",
      mode = "and"
    }
  }

  -- ☆ Все рецепты разделенные по эффектам productivity, quality, speed
  global_recipe_table.recipes_by_effect = get_recipes_by_effects()

  -- ☆ Все рецепты разрешенные на всех планетах
  global_recipe_table.all_surface_recipes = {}
  for name, recipe in pairs(prototypes.recipe) do
    if not recipe.surface_conditions then
      global_recipe_table.all_surface_recipes[name] = recipe
    end
  end

  -- Все рецепты с main_product
  global_recipe_table.recipes_with_main = {}
  for name, recipe in pairs(prototypes.recipe) do
    if recipe.main_product then
      global_recipe_table.recipes_with_main[name] = recipe
    end
  end

  -- ☆ Все машины и все рецепты для каждый из них
  global_recipe_table.machines = {}
  for name, entity in pairs(prototypes.entity) do
    if entity.crafting_categories then
      local recipes = {}
      for recipe_name, recipe in pairs(prototypes.recipe) do
        if entity.crafting_categories[recipe.category] then
          recipes[recipe_name] = recipe
        end
      end
      global_recipe_table.machines[name] = recipes
    end
  end

  -- ☆ Все машины в которые можно установить рецепт сигналом
  local machines_ass = {}
  for name, entity in pairs(prototypes.entity) do
    if entity.type == "assembling-machine" and not entity.fixed_recipe then
      machines_ass[name] = entity
    end
  end
  global_recipe_table.machines_ass = Set.I(global_recipe_table.machines, machines_ass)

  -- Все циклические рецепты. Если рецепт производит main_product который сам же потребляет или Если есть от двух рецептов, которые производят "по кругу"
  local recipes = Set.D(global_recipe_table.recipes_with_main, global_recipe_table.invalid_recipes)
  global_recipe_table.cyclic_recipes = get_cyclic_recipes(recipes)

  -- ☆ Все рецепты являющиеся опустошение бочки
  global_recipe_table.empty_barrel = prototypes.get_recipe_filtered {
    { filter = "subgroup", subgroup = "empty-barrel" }
  }

  -- ☆ Все рецепты являющиеся наполнения бочки
  global_recipe_table.fill_barrel = prototypes.get_recipe_filtered {
    { filter = "subgroup", subgroup = "fill-barrel" }
  }

  -- Глобальная таблица машин с рецептами типа assembling_machines
  global_recipe_table.assembling_machines = {}
  -- Общий список всех рецептов от всех машин (вперемешку)
  global_recipe_table.all_assembling_recipes = {}
  for name, entity in pairs(prototypes.entity) do
    if entity.type == "assembling-machine" and entity.crafting_categories and not entity.fixed_recipe then
      local machine_recipes = {}
      for recipe_name, recipe in pairs(prototypes.recipe) do
        if recipe.category and entity.crafting_categories[recipe.category] then
          machine_recipes[recipe_name] = recipe
          global_recipe_table.all_assembling_recipes[recipe_name] = recipe
        end
      end
      if next(machine_recipes) then
        global_recipe_table.assembling_machines[name] = machine_recipes
      end
    end
  end
  global_recipe_table.all_assembling_recipes = Set.I(prototypes.recipe, global_recipe_table.all_assembling_recipes)


  -- Все полезные рецепты:
  -- Могут быть установлены в машине по сигналу ✓
  -- Не пустые ингредиенты/продукты ...
  -- Не рецепты свапов ...
  -- Крафтиться не на платформе ...
  global_recipe_table.usefull_recipes = Set.D(global_recipe_table.all_assembling_recipes, Set.U(
    global_recipe_table.empty_barrel,
    global_recipe_table.fill_barrel))


  -- Все бесполезные рецепты качества 2+:
  -- Производит/Потребляет только жидкость ✓
  -- Не имеет полезных бонусов от качества ...
  global_recipe_table.quality_useless_recipes = Set.U(
    global_recipe_table.fluid_only_ingredient_recipes,
    global_recipe_table.fluid_only_product_recipes)

  -- ☆ Применяем фильтрацию ко всем таблицам, исключая invalid_recipes
  for key, value in pairs(global_recipe_table) do
    if key ~= "invalid_recipes" and key ~= "parameter_recipes" then
      global_recipe_table[key] = filter_invalid_recipes(value, global_recipe_table.invalid_recipes)
    end
  end

  return global_recipe_table
end

return Recipes
