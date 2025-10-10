local TestEntityChecker = require("test_entity_checker")

local TestEntityLoader = {}
TestEntityLoader.__index = function(self, key)
  local val = rawget(TestEntityLoader, key)
  if val ~= nil then return val end
  return self.entities[key]
end

function TestEntityLoader.new(data)
  local self = setmetatable({}, TestEntityLoader)
  local entities_data = helpers.json_to_table(helpers.decode_string(data) or "")
  if type(entities_data) ~= "table" then
    error("Invalid data: expected a table after decoding")
  end

  self.entities = {}

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
