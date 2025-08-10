--- Модуль с дополнительными утилитами для работы с таблицами.
-- Включает функции расширения массивов и другие вспомогательные операции с таблицами.

local table_utils = {}

--- Расширяет массив, добавляя все элементы из другой таблицы.
-- Работает аналогично `table.move` в режиме вставки в конец.
-- @param dest table Целевая таблица (массив), в которую будут добавлены элементы.
-- @param source table Источник (массив), элементы которого будут скопированы в `dest`.
function table_utils.extend(dest, source)
  for _, v in ipairs(source) do
    table.insert(dest, v)
  end
end

--- Применяет функцию fn к каждому элементу массива tbl
-- @param tbl table Массив элементов
-- @param fn function Функция обработки элемента, принимает элемент tbl[i]
function table_utils.for_each(tbl, fn)
  for i, v in ipairs(tbl) do
    fn(v, i, tbl)
  end
end

function table_utils.find_if(array, predicate)
  for i, v in ipairs(array) do
    if predicate(v, i) then
      return v, i
    end
  end
  return nil, nil
end

function table_utils.deep_copy(orig, copies)
  copies = copies or {}
  if type(orig) ~= "table" then
    return orig
  elseif copies[orig] then
    return copies[orig]
  end

  local copy = {}
  copies[orig] = copy
  for k, v in pairs(orig) do
    copy[table_utils.deep_copy(k, copies)] = table_utils.deep_copy(v, copies)
  end
  return copy
end

function table_utils.table_to_string(t, indent, visited)
  indent = indent or 0
  visited = visited or {}
  if visited[t] then
    return "<cycle>"
  end
  visited[t] = true

  local prefix = string.rep("  ", indent)
  local parts = {"{\n"}

  for k, v in pairs(t) do
    local keyStr
    if type(k) == "string" then
      keyStr = string.format("%q", k)
    else
      keyStr = tostring(k)
    end

    local valueStr
    if type(v) == "table" then
      valueStr = table_utils.table_to_string(v, indent + 1, visited)
    elseif type(v) == "string" then
      valueStr = string.format("%q", v)
    else
      valueStr = tostring(v)
    end

    table.insert(parts, prefix .. "  [" .. keyStr .. "] = " .. valueStr .. ",\n")
  end

  table.insert(parts, prefix .. "}")
  return table.concat(parts)
end

return table_utils
