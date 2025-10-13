local TestEntityLogger = {}
TestEntityLogger.__index = TestEntityLogger

local EntityController = require("entity_controller")
require("util")

function TestEntityLogger.new(real_entity)
  local self = setmetatable({}, TestEntityLogger)
  self.name = real_entity.name
  self.type = real_entity.type
  self.entity = real_entity
  self.call_log = {}
  self.method_counts = {} -- отдельный счётчик для каждого метода
  return self
end

function TestEntityLogger:log_call(method_name, params, result)
  self.method_counts[method_name] = (self.method_counts[method_name] or 0) + 1
  table.insert(self.call_log, {
    call_number = self.method_counts[method_name],
    method = method_name,
    params = util.table.deepcopy(params),
    result = util.table.deepcopy(result)
  })
end

---------------------------------------------------------------------
-- Автогенерация методов на основе EntityController
---------------------------------------------------------------------
for method_name, fn in pairs(EntityController) do
  if type(fn) ~= "function" then goto continue end

  -- пропускаем статические методы (__no_inherit)
  local raw_field = rawget(EntityController, method_name)
  if type(raw_field) == "table" and raw_field.__no_inherit then
    goto continue
  end

  -- создаём экземплярный метод
  TestEntityLogger[method_name] = function(self, ...)
    local args = { ... }

    -- вызов оригинального метода на entity
    local result = self.entity[method_name](self.entity, ...)

    self:log_call(method_name, args, result)
    return result
  end

  ::continue::
end

function TestEntityLogger:get_data()
  return {
    name = self.name,
    type = self.type,
    calls = self.call_log
  }
end

return TestEntityLogger
