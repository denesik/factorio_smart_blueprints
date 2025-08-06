local Utils = require("utils")

local function get_controler(target)
  if not target or not target.valid then
    error("Invalid object for 'get_controler'")
    return nil
  end

  if target.type == "constant-combinator" or target.type == "decider-combinator" then
    if type(target.get_or_create_control_behavior) ~= "function" then
      error("Invalid object. Can't find 'get_or_create_control_behavior' function")
      return nil
    end

    local control_behavior = target.get_or_create_control_behavior()

    if not control_behavior then
      error("Invalid object. Can't create control behavior")
      return nil
    end
    return control_behavior
  end

  if target.type == "logistic-container" then
    local request_point = target.get_requester_point()

    if not request_point then
      error("Invalid object. Can't get request point")
      return nil
    end
    return request_point
  end

  return nil
end

local function read_all_logistic_filters(target)
  local logistic_filters = {}

  local section_controller = get_controler(target)
  if not section_controller then
    return logistic_filters
  end

  for _, section in ipairs(section_controller.sections) do
    for _, filter in ipairs(section.filters) do
      table.insert(logistic_filters, filter)
    end
  end

  return logistic_filters
end

local function set_logistic_filters(target, logistic_filters)
  local section_controller = get_controler(target)
  if not section_controller then
    return
  end

  local MAX_SECTION_SIZE = 1000
  local filters = {}

  local function set_filters_in_new_section()
    if #filters > 0 then
      local current_section = section_controller.add_section()
      if not current_section then
        error("Can't create new section")
        return
      end
      current_section.filters = filters
      filters = {}
    end
  end

  for _, filter in ipairs(logistic_filters) do
    table.insert(filters, filter)
    if #filters >= MAX_SECTION_SIZE then
      set_filters_in_new_section()
    end
  end
  set_filters_in_new_section()
end

-- Оставляет рецепты, которые может скрафтить машина

local function filter_recipes(recipes, filter)
  out = {}

  for recipe_name, recipe in pairs(recipes) do
    if filter(recipe_name, recipe) then
      out[recipe_name] = recipe
    end
  end

  return out
end

local function filter_parameter_recipes(recipe_name, recipe)
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
  return not is_param
end

local function filter_hidden_recipes(recipe_name, recipe)
  return not recipe.hidden
end

local function filter_recipes_by_items(recipe_name, recipe)
  return prototypes.item[recipe_name] ~= nil
end

local function filter_recipes_by_main_product(recipe_name, recipe)
  if not recipe.main_product then
    return false
  end
  return prototypes.item[recipe.main_product.name] ~= nil or prototypes.fluid[recipe.main_product.name] ~= nil
end

local function filter_recipes_from_machine(recipe_name, recipe, machine)
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

local function get_type_by_name(name)
  if prototypes.item[name] ~= nil then
    return "item"
  end
  if prototypes.fluid[name] ~= nil then
    return "fluid"
  end
  return ""
end

local function decomposition_element(recipe_index, item)
  local out = {}
  if item.min <= 0 then
    return out
  end

  local recipe = recipe_index[item.value.name]
  if not recipe then
    return out
  end

  local multiplier = item.min / recipe.main_product.amount
  for _, ingredient in ipairs(recipe.ingredients) do
    table.insert(out, {
      value = {
        name = ingredient.name,
        type = ingredient.type,
        quality = item.value.quality
      },
      min = ingredient.amount * multiplier
    })
  end

  return out
end

local function decomposition(recipes, items)
  local recipe_index = (function()
    local index = {}
    for _, recipe in pairs(recipes) do
      if recipe.main_product and recipe.main_product.name then
        index[recipe.main_product.name] = recipe
      end
    end
    return index
  end)()

  local out = {}

  while #items ~= 0 do
    local results = {}
    for _, filter in ipairs(items) do
      table.extend(results, decomposition_element(recipe_index, filter))
    end
    items = results
    table.extend(out, results)
  end

  return out
end

function table.extend(dest, source)
  for _, v in ipairs(source) do
    table.insert(dest, v)
  end
end

local function process_decider_combinator(target)
  local controller = get_controler(target)

  i = {}
end






local function shallow_copy(tbl)
  local t = {}
  for k,v in pairs(tbl) do t[k] = v end
  return t
end

local function cartesian_product(list1, list2)
  local result = {}
  for _, l1 in ipairs(list1) do
    for _, l2 in ipairs(list2) do
      local combined = {}
      for _, cond in ipairs(l1) do table.insert(combined, cond) end
      for _, cond in ipairs(l2) do table.insert(combined, cond) end
      table.insert(result, combined)
    end
  end
  return result
end

local function flatten_and_clauses(clauses)
  local flat = {}
  for _, clause in ipairs(clauses) do
    for _, cond in ipairs(clause) do
      table.insert(flat, cond)
    end
  end
  return flat
end

local function to_dnf(tree)
  if type(tree) ~= "table" then
    return { { tree } }
  end

  if tree.operator == "_or" then
    local clauses = {}
    for _, child in ipairs(tree.children) do
      local child_clauses = to_dnf(child)
      for _, clause in ipairs(child_clauses) do
        table.insert(clauses, clause)
      end
    end
    return clauses

  elseif tree.operator == "_and" then
    local clauses = { {} }
    for _, child in ipairs(tree.children) do
      local child_clauses = to_dnf(child)
      clauses = cartesian_product(clauses, child_clauses)
    end
    return clauses

  else
    return { { shallow_copy(tree) } }
  end
end

local function set_compare_types(clauses)
  for _, clause in ipairs(clauses) do
    for i, cond in ipairs(clause) do
      cond.compare_type = (i == 1) and "_or" or "_and"
    end
  end
end

local Condition = {}
Condition.__index = Condition

function Condition._and(...)
  return setmetatable({operator = "_and", children = {...}}, Condition)
end

function Condition._or(...)
  return setmetatable({operator = "_or", children = {...}}, Condition)
end

function Condition:add_child(child)
  table.insert(self.children, child)
  return self
end






--- Удаляет дубликаты по ключу, создаваемому key_fn
-- @param entries: массив с элементами { value = ..., min = число }
-- @param merge_fn: функция (existing_min, new_min) → новое значение min
-- @param key_fn: функция (value) → строковый ключ
local function merge_duplicates(entries, merge_fn, key_fn)
  local map = {}

  for _, entry in ipairs(entries) do
    local key = key_fn(entry.value)

    if not map[key] then
      -- Копируем структуру
      map[key] = {
        value = entry.value,
        min = entry.min
      }
    else
      map[key].min = merge_fn(map[key].min, entry.min)
    end
  end

  -- Преобразуем результат в массив
  local result = {}
  for _, v in pairs(map) do
    table.insert(result, v)
  end

  return result
end

local function main()


  local a = { first_signal={type="item",name="a"}, comparator="=", second_signal={type="virtual",name="signal-A"}, first_signal_networks={}, second_signal_networks={} }
  local b = { first_signal={type="item",name="b"}, comparator="=", second_signal={type="virtual",name="signal-B"}, first_signal_networks={}, second_signal_networks={} }
  local c = { first_signal={type="item",name="c"}, comparator="<", second_signal={type="virtual",name="signal-C"}, first_signal_networks={}, second_signal_networks={} }
  local d = { first_signal={type="item",name="d"}, comparator="<", second_signal={type="virtual",name="signal-D"}, first_signal_networks={}, second_signal_networks={} }
  local e = { first_signal={type="item",name="e"}, comparator="<", second_signal={type="virtual",name="signal-E"}, first_signal_networks={}, second_signal_networks={} }
  local f = { first_signal={type="item",name="f"}, comparator="<", second_signal={type="virtual",name="signal-F"}, first_signal_networks={}, second_signal_networks={} }
  local j = { first_signal={type="item",name="j"}, comparator="<", second_signal={type="virtual",name="signal-J"}, first_signal_networks={}, second_signal_networks={} }

  local tree = Condition._and(
    a, b, c,
    Condition._or(d, Condition._and(e, f), j)
  )

  local dnf_clauses = to_dnf(tree)
  set_compare_types(dnf_clauses)
  local flat_conditions = flatten_and_clauses(dnf_clauses)

  --local conditions = convert_tree_to_factorio_conditions(tree)



  local search_area = {}
  if area == nil then
    search_area = { { 0, 0 }, { 100, 100 } }
  else
    search_area = area
  end

  local recipes = prototypes.recipe
  local entities = prototypes.entity

  if entities["assembling-machine-3"] then
    machine = entities["assembling-machine-3"]
    recipes = filter_recipes(recipes, function(recipe_name, recipe)
      return filter_hidden_recipes(recipe_name, recipe) and
             filter_parameter_recipes(recipe_name, recipe) and
             filter_recipes_by_main_product(recipe_name, recipe) and
             filter_recipes_from_machine(recipe_name, recipe, machine)
    end)
  end

  local src = Utils.findSpecialEntity("<src_logistic_filters>", search_area)
  local dst = Utils.findSpecialEntity("<dst_logistic_filters>", search_area)
  local decider_combinator = Utils.findSpecialEntity("<decider_combinator>", search_area)

  process_decider_combinator(decider_combinator)

  local filters = read_all_logistic_filters(src)

  local items = {}
  for recipe_name, recipe in pairs(recipes) do
    name = recipe.main_product.name
    table.insert(items, {value = { name = name, type = get_type_by_name(name), quality = "normal" }, min = 0.1})
  end

  items = decomposition(recipes, filters)
  local key_fn = function(v)
    return v.name .. "|" .. v.type .. "|" .. v.quality
  end
  local merged = merge_duplicates(items, function(a, b) return a + b end, key_fn)
  for _, entry in ipairs(merged) do
    if entry.min < 1 then
      entry.min = 1
    end
  end
  table.sort(merged, function(a, b) return a.min > b.min end)

  set_logistic_filters(dst, merged)

  game.print("Finish!")
end

return main