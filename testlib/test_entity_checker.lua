local TestEntityChecker = {}
TestEntityChecker.__index = TestEntityChecker

local EntityController = require("entity_controller")

local SAVE_TO_FILES = true

function TestEntityChecker.new(data)
  local self = setmetatable({}, TestEntityChecker)
  self.name = data.name
  self.type = data.type
  self.call_log = data.calls or {}
  self.method_counts = {}
  return self
end

-- Улучшенная проверка равенства с контекстом
local function assert_equal(a, b, context)
  if not util.table.compare(a, b) then
    if SAVE_TO_FILES then
      helpers.write_file("failed_expected.json", helpers.table_to_json(a))
      helpers.write_file("failed_actual.json", helpers.table_to_json(b))
    end
    local msg = string.format(
      "Assertion failed in method '%s' for entity '%s' (type: %s) on call #%d\nTables differ — saved to failed_expected.json и failed_actual.json",
      context.method_name, context.entity_name, context.entity_type, context.call_number
    )
    error(msg)
  end
end

function TestEntityChecker:_next_call(method_name)
  self.method_counts[method_name] = (self.method_counts[method_name] or 0) + 1
  local call_number = self.method_counts[method_name]

  local found = nil
  for _, log_entry in ipairs(self.call_log) do
    if log_entry.method == method_name and log_entry.call_number == call_number then
      found = log_entry
      break
    end
  end

  if not found then
    error(string.format(
      "No logged call for method '%s' in entity '%s' (type: %s) on call #%d",
      method_name, self.name, self.type, call_number
    ))
  end

  found.call_number = call_number
  return found
end

---------------------------------------------------------------------
-- Автогенерация всех нестатических методов EntityController
---------------------------------------------------------------------
---
for method_name, fn in pairs(EntityController) do
  -- Пропускаем статические или служебные поля
  if type(fn) ~= "function" then goto continue end

  -- Пропускаем статические методы, созданные через static()
  if rawget(EntityController, method_name)
     and type(rawget(EntityController, method_name)) == "table"
     and rawget(EntityController, method_name).__no_inherit
  then
    goto continue
  end

  -- Создаём метод как экземплярный (аналог function TestEntityChecker:method(...))
  TestEntityChecker[method_name] = function(self, ...)
    local log = self:_next_call(method_name)
    local args = { ... }

    -- Если метод возвращает результат — вернуть
    if log.result ~= nil then
      return log.result
    end

    -- Если метод имеет параметры — сверить с логом
    assert_equal(
      log.params,
      args,
      {
        method_name = method_name,
        entity_name = self.name,
        entity_type = self.type,
        call_number = log.call_number
      }
    )
  end

  ::continue::
end

---------------------------------------------------------------------

return TestEntityChecker
