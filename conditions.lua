--- Модуль для работы с логическими условиями.
-- Поддерживает построение деревьев условий с операторами `_and`, `_or`,
-- преобразование в дизъюнктивную нормальную форму (DNF), а также разметку условий типом сравнения.

local conditions = {}

--- Выполняет неглубокое копирование таблицы.
-- @param tbl table Исходная таблица.
-- @return table Копия таблицы.
local function shallow_copy(tbl)
  local t = {}
  for k, v in pairs(tbl) do
    t[k] = v
  end
  return t
end

--- Вычисляет декартово произведение двух списков условий.
-- Используется для комбинирования `_and`-веток.
-- @param list1 table Первый список условий.
-- @param list2 table Второй список условий.
-- @return table Результат декартова произведения.
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

--- "Выпрямляет" вложенные `_and`-клаузы в один список.
-- @param clauses table Список списков условий.
-- @return table Единый список условий.
function conditions.flatten_and_clauses(clauses)
  local flat = {}
  for _, clause in ipairs(clauses) do
    for _, cond in ipairs(clause) do
      table.insert(flat, cond)
    end
  end
  return flat
end

--- Рекурсивно преобразует логическое выражение в дизъюнктивную нормальную форму (DNF).
-- Пример результата: `{{cond1, cond2}, {cond3}}`, где каждый подсписок — это `_and`, а вся структура — `_or`.
-- @param tree table Логическое выражение в виде дерева.
-- @return table Список списков условий в DNF.
function conditions.to_dnf(tree)
  if type(tree) ~= "table" then
    return { { tree } }
  end

  if tree.operator == "_or" then
    local clauses = {}
    for _, child in ipairs(tree.children) do
      local child_clauses = conditions.to_dnf(child)
      for _, clause in ipairs(child_clauses) do
        table.insert(clauses, clause)
      end
    end
    return clauses

  elseif tree.operator == "_and" then
    local clauses = { {} }
    for _, child in ipairs(tree.children) do
      local child_clauses = conditions.to_dnf(child)
      clauses = cartesian_product(clauses, child_clauses)
    end
    return clauses

  else
    return { { shallow_copy(tree) } }
  end
end

--- Устанавливает поле `compare_type` для каждого условия в клауза.
-- Первый элемент получает `_or`, последующие — `_and`.
-- @param clauses table DNF-клаузы.
function conditions.set_compare_types(clauses)
  for _, clause in ipairs(clauses) do
    for i, cond in ipairs(clause) do
      cond.compare_type = (i == 1) and "_or" or "_and"
    end
  end
end

--- Преобразует дерево условий в "плоский" список условий DNF.
-- Объединяет шаги: to_dnf → set_compare_types → flatten_and_clauses.
-- @param tree table Дерево условий.
-- @return table Плоский список условий (список всех конъюнктивных условий).
function conditions.to_flat_dnf(tree)
  local dnf_clauses = conditions.to_dnf(tree)
  conditions.set_compare_types(dnf_clauses)
  return conditions.flatten_and_clauses(dnf_clauses)
end

--- Структура и вспомогательные методы для построения дерева условий.
local Condition = {}
Condition.__index = Condition

--- Создаёт условие типа `_and`.
-- @vararg table Дочерние условия.
-- @return table Новое условие.
function Condition._and(...)
  return setmetatable({operator = "_and", children = {...}}, Condition)
end

--- Создаёт условие типа `_or`.
-- @vararg table Дочерние условия.
-- @return table Новое условие.
function Condition._or(...)
  return setmetatable({operator = "_or", children = {...}}, Condition)
end

--- Добавляет дочернее условие к текущему дереву условий.
-- @param self table Объект Condition.
-- @param child table Новое дочернее условие.
-- @return table Тот же объект Condition (для цепочек).
function Condition:add_child(child)
  table.insert(self.children, child)
  return self
end

conditions.Condition = Condition

return conditions
