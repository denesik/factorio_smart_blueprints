local algorithm = {}

function algorithm.extend(dest, source)
  for _, v in ipairs(source) do
    table.insert(dest, v)
  end
end

function algorithm.for_each(tbl, fn)
  for i, v in ipairs(tbl) do
    fn(v, i, tbl)
  end
end

function algorithm.map(sequence, transformation)
  local out = {}
  for key, val in pairs(sequence) do
    out[key] = transformation(val)
  end
  return out
end

function algorithm.filter(sequence, predicate)
  local out = {}
  for key, val in pairs(sequence) do
    if predicate(val) then
      out[key] = val
    end
  end
  return out
end

function algorithm.partition(sequence, predicate)
  local left = {}
  local right = {}
  for key, val in pairs(sequence) do
    if (predicate(val)) then
      left[key] = val
    else
      right[key] = val
    end
  end
  return left, right
end

function algorithm.reduce(sequence, operator)
  local out = nil
  for _, val in pairs(sequence) do
      out = operator(out, val)
  end
  return out
end

function algorithm.count_if(sequence, predicate)
  local c = 0
  for _, v in pairs(sequence) do
    if predicate(v) then c = c + 1 end
  end
  return c
end

function algorithm.enumerate(map, start)
  local iter, tbl, key = pairs(map)
  local index = (start or 1) - 1
  local val
  return function()
    key, val = iter(tbl, key)
    if key == nil then return nil end
    index = index + 1
    return index, key, val
  end
end

function algorithm.find(map, predicate)
  for key, val in pairs(map) do
    if predicate(val) then
      return key, val
    end
  end
  return nil
end

function algorithm.to_map(array, functor)
  local map = {}
  for _, value in ipairs(array) do
    map[functor(value)] = value
  end
  return map
end

return algorithm
