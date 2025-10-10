require("util")

local TestEntityChecker = {}
TestEntityChecker.__index = TestEntityChecker

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
    local msg = string.format(
      "Assertion failed in method '%s' for entity '%s' (type: %s) on call #%d\nTables differ — saved to failed_expected.json and failed_actual.json",
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

  found.call_number = call_number -- чтобы передавать в контекст assert_equal
  return found
end

function TestEntityChecker:read_all_logistic_filters()
  local log = self:_next_call("read_all_logistic_filters")
  return log.result
end

function TestEntityChecker:get_logistic_sections()
  local log = self:_next_call("get_logistic_sections")
  return log.result
end

function TestEntityChecker:set_filter(i, filter)
  local log = self:_next_call("set_filter")
  assert_equal(
    log.params,
    { i = i, filter = filter },
    {
      method_name = "set_filter",
      entity_name = self.name,
      entity_type = self.type,
      call_number = log.call_number
    }
  )
end

function TestEntityChecker:set_logistic_filters(filters, settings)
  local log = self:_next_call("set_logistic_filters")
  assert_equal(
    log.params,
    { filters = filters, settings = settings },
    {
      method_name = "set_logistic_filters",
      entity_name = self.name,
      entity_type = self.type,
      call_number = log.call_number
    }
  )
end

function TestEntityChecker:fill_decider_combinator(conditions, outputs)
  local log = self:_next_call("fill_decider_combinator")
  assert_equal(
    log.params,
    { conditions = conditions, outputs = outputs },
    {
      method_name = "fill_decider_combinator",
      entity_name = self.name,
      entity_type = self.type,
      call_number = log.call_number
    }
  )
end

return TestEntityChecker
