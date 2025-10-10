local game_utils = {}

local algorithm = require("llib.algorithm")

function game_utils.items_key_fn(v)
  return v.value.name .. "|" .. v.value.type .. "|" .. v.value.quality
end

function game_utils.merge_max(a, b)
  a.min = math.max(a.min, b.min)
end

function game_utils.merge_min(a, b)
  a.min = math.min(a.min, b.min)
end

function game_utils.merge_sum(a, b)
  a.min = a.min + b.min
end

function game_utils.merge_duplicates(array, merge_fn, key_fn)
  key_fn = key_fn or game_utils.items_key_fn

  local map = {}
  local result = {}

  for _, element in ipairs(array) do
    local key = key_fn(element)
    local idx = map[key]

    if not idx then
      table.insert(result, util.table.deepcopy(element))
      map[key] = #result
    else
      merge_fn(result[idx], element)
    end
  end

  return result
end

function game_utils.is_fluid(item)
  return item.value.type == "fluid"
end

function game_utils.make_logistic_signals(items, functor)
  local out = {}
  for i, _, item in algorithm.enumerate(items) do
    local min, value = functor(item, i)
    table.insert(out, { value = value or item.value, min = min})
  end
  return out
end

function game_utils.make_signal(recipe_part, quality_name)
  return {
    value = {
      name = recipe_part.name,
      type = recipe_part.type,
      quality = quality_name
    },
    min = recipe_part.amount
  }
end

function game_utils.recipe_as_signal(recipe, quality_name)
  assert(recipe.main_product)
  return {
    value = {
      name = recipe.name,
      type = "recipe",
      quality = quality_name
    }
  }
end

return game_utils
