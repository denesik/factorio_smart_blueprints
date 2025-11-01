local TestEntityChecker = require("test_entity_checker")

local TestEntityLoader = {}
TestEntityLoader.__index = function(self, key)
  local val = rawget(TestEntityLoader, key)
  if val ~= nil then return val end
  return self.entities[key]
end

function TestEntityLoader.new(test_data)
  local self = setmetatable({}, TestEntityLoader)
  
  -- Новый формат: {data = "...", blueprint = "..."}
  if type(test_data) ~= "table" or not test_data.data then
    error("Invalid test_data: expected a table with 'data' field")
  end
  
  local entities_data = helpers.json_to_table(helpers.decode_string(test_data.data) or "")
  if type(entities_data) ~= "table" then
    error("Invalid data: expected a table after decoding")
  end

  self.entities = {}
  self.blueprint_string = test_data.blueprint

  for name, ents in pairs(entities_data) do
    if type(ents) == "table" and #ents > 0 and type(ents[1]) == "table" then
      local arr = {}
      for _, log in ipairs(ents) do
        table.insert(arr, TestEntityChecker.new(log))
      end
      self.entities[name] = arr
    else
      self.entities[name] = TestEntityChecker.new(ents)
    end
  end

  return self
end

return TestEntityLoader
