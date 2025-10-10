local TestEntityChecker = {}
TestEntityChecker.__index = TestEntityChecker

function TestEntityChecker.new(call_log)
  local self = setmetatable({}, TestEntityChecker)
  self.call_log = call_log or {}
  self.method_counts = {}
  return self
end

local function assert_equal(a, b)
  if type(a) ~= type(b) then
    error("Type mismatch: " .. type(a) .. " vs " .. type(b))
  end
  if type(a) == "table" then
    for k, v in pairs(a) do
      assert_equal(v, b[k])
    end
    for k, v in pairs(b) do
      assert_equal(v, a[k])
    end
  else
    if a ~= b then
      error("Value mismatch: " .. tostring(a) .. " vs " .. tostring(b))
    end
  end
end

function TestEntityChecker:_check_call(method_name, params, result)
  self.method_counts[method_name] = (self.method_counts[method_name] or 0) + 1
  local call_number = self.method_counts[method_name]
  local log_entry = self.call_log[call_number]
  if not log_entry then
    error("No logged call for " .. method_name .. " #" .. call_number)
  end
  assert_equal(log_entry.method, method_name)
  assert_equal(log_entry.params, params)
  assert_equal(log_entry.result, result)
end

function TestEntityChecker:read_all_logistic_filters()
  local result = {}
  self:_check_call("read_all_logistic_filters", {}, result)
  return result
end

function TestEntityChecker:get_logistic_sections()
  local result = {}
  self:_check_call("get_logistic_sections", {}, result)
  return result
end

function TestEntityChecker:set_filter(i, filter)
  self:_check_call("set_filter", {i=i, filter=filter}, nil)
end

function TestEntityChecker:set_logistic_filters(filters, settings)
  self:_check_call("set_logistic_filters", {filters=filters, settings=settings}, nil)
end

function TestEntityChecker:fill_decider_combinator(conditions, outputs)
  self:_check_call("fill_decider_combinator", {conditions=conditions, outputs=outputs}, nil)
end

return TestEntityChecker
