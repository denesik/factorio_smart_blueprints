local quality = {}


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

function quality.get_all_qualities()
  if not quality_prototypes then
    quality_prototypes, index_map = init_quality_order()
  end
  return quality_prototypes, index_map
end

function quality.get_quality_index(quality_name)
  if not quality_index_map then
    quality_prototypes, quality_index_map = init_quality_order()
  end
  local index = quality_index_map[quality_name]
  assert(index)
  return index
end

function quality.get_all_better_qualities(quality_name)
  local qualities, index_map = quality.get_all_qualities()

  local index = index_map[quality_name]
  assert(index)

  local betters = {}
  for i = index + 1, #qualities do
    table.insert(betters, qualities[i])
  end

  return betters
end

return quality