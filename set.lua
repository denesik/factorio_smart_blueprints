local Set = {}

function Set.U(a, b, ...) -- объединение (union ∪)
  local res = {}
  for k, v in pairs(a) do res[k] = v end
  for k, v in pairs(b or {}) do res[k] = v end
  if ... then return Set.U(res, ...) end
  return res
end

function Set.I(a, b, ...) -- пересечение (intersection ∩)
  local res = {}
  for k, v in pairs(a) do if b[k] then res[k] = v end end
  if ... then return Set.I(res, ...) end
  return res
end

function Set.D(a, b, ...) -- разность (difference -)
  local res = {}
  for k, v in pairs(a) do if not b[k] then res[k] = v end end
  if ... then return Set.D(res, ...) end
  return res
end

function Set.S(a, b, ...) -- симметричная разность (symmetric difference Δ)
  local res = {}
  for k, v in pairs(a) do if not b[k] then res[k] = v end end
  for k, v in pairs(b) do if not a[k] then res[k] = v end end
  if ... then return Set.S(res, ...) end
  return res
end

return Set
