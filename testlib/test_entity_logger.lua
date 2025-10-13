local entity_control = require("entity_control")

local TestEntityLogger = {}
TestEntityLogger.__index = TestEntityLogger

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

function TestEntityLogger:read_all_logistic_filters()
  local result = entity_control.read_all_logistic_filters(self.entity)
  self:log_call("read_all_logistic_filters", {}, result)
  return result
end

function TestEntityLogger:get_logistic_sections()
  local result = entity_control.get_logistic_sections(self.entity)
  self:log_call("get_logistic_sections", {}, result ~= nil)
  return result
end

function TestEntityLogger:set_filters(filters)
  entity_control.set_filters(self.entity, filters)
  self:log_call("set_filters", {filters=filters}, nil)
end

function TestEntityLogger:set_logistic_filters(filters, settings)
  entity_control.set_logistic_filters(self.entity, filters, settings)
  self:log_call("set_logistic_filters", {filters=filters, settings=settings}, nil)
end

function TestEntityLogger:fill_decider_combinator(conditions, outputs)
  entity_control.fill_decider_combinator(self.entity, conditions, outputs)
  self:log_call("fill_decider_combinator", {conditions=conditions, outputs=outputs}, nil)
end

function TestEntityLogger:get_data()
  return {
    name = self.name,
    type = self.type,
    calls = self.call_log
  }
end

return TestEntityLogger
