local game_utils = {}

local algorithm = require("llib.algorithm")
require("util")

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

local quality_prototypes = nil
local quality_index_map = nil

local function init_quality_order()
  local qualities_proto = {}

  for _, proto in pairs(prototypes.quality) do
    if not proto.hidden then
      table.insert(qualities_proto, proto)
    end
  end

  table.sort(qualities_proto, function(a, b)
    return a.order < b.order
  end)

  local index_map = {}
  for i, proto in ipairs(qualities_proto) do
    index_map[proto.name] = i
  end

  return qualities_proto, index_map
end

function game_utils.get_all_qualities()
  if not quality_prototypes then
    quality_prototypes, index_map = init_quality_order()
  end
  return quality_prototypes, index_map
end

function game_utils.get_quality_index(quality_name)
  if not quality_index_map then
    quality_prototypes, quality_index_map = init_quality_order()
  end
  local index = quality_index_map[quality_name]
  assert(index)
  return index
end

function game_utils.get_all_better_qualities(quality_name)
  local qualities, index_map = game_utils.get_all_qualities()

  local index = index_map[quality_name]
  assert(index)

  local betters = {}
  for i = index + 1, #qualities do
    table.insert(betters, qualities[i])
  end

  return betters
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
