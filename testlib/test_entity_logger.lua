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
  local result = self.entity:read_all_logistic_filters()
  self:log_call("read_all_logistic_filters", {}, result)
  return result
end

function TestEntityLogger:has_logistic_sections()
  local result = self.entity:has_logistic_sections()
  self:log_call("has_logistic_sections", {}, result ~= nil)
  return result
end

function TestEntityLogger:set_filters(filters)
  self.entity:set_filters(filters)
  self:log_call("set_filters", {filters=filters}, nil)
end

function TestEntityLogger:set_logistic_filters(filters, settings)
  self.entity:set_logistic_filters(filters, settings)
  self:log_call("set_logistic_filters", {filters=filters, settings=settings}, nil)
end

function TestEntityLogger:fill_decider_combinator(conditions, outputs)
  self.entity:fill_decider_combinator(conditions, outputs)
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
