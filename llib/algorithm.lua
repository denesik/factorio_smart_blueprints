local algorithm = {}

function algorithm.extend(dest, source)
  for _, v in ipairs(source) do
    table.insert(dest, v)
  end
end

function algorithm.append(dest, source)
  for _, v in pairs(source) do
    table.insert(dest, v)
  end
end

function algorithm.merge(map1, map2)
  local result = {}

  for k, v in pairs(map1) do
    result[k] = v
  end

  for k, v in pairs(map2) do
    result[k] = v
  end

  return result
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

function algorithm.count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function algorithm.remove_if(tbl, predicate)
    local j = 1
    for i = 1, #tbl do
        local v = tbl[i]
        if not predicate(v) then
            tbl[j] = v
            j = j + 1
        end
    end
    -- очищаем хвост
    for k = j, #tbl do
        tbl[k] = nil
    end
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

function algorithm.unique(sequence, key_selector)
  key_selector = key_selector or function(x) return x end
  local out = {}
  local prev_key = nil

  for _, val in ipairs(sequence) do
    local key = key_selector(val)
    if key ~= prev_key then
      table.insert(out, val)
      prev_key = key
    end
  end

  return out
end

return algorithm
