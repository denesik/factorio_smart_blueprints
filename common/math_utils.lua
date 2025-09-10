-- math_utils.lua
local math_utils = {}

--- Ограничивает значение в диапазоне [min, max]
function math_utils.clamp(value, min, max)
  if value < min then return min end
  if value > max then return max end
  return value
end

--- Нормализует значение в диапазон [0, 1]
function math_utils.normalize(value, min, max)
  if max == min then return 0 end -- чтобы не было деления на 0
  return (value - min) / (max - min)
end

--- Денормализует (обратная операция) — из [0, 1] в [min, max]
function math_utils.denormalize(norm_value, min, max)
  return min + norm_value * (max - min)
end

return math_utils
