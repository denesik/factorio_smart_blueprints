local EntityFinder = require("entity_finder")
local TestEntity = require("test_entity")

local TestEntityFinder = {}

TestEntityFinder.__index = function(self, key)
  local val = rawget(TestEntityFinder, key)
  if val ~= nil then return val end
  return self.entities[key]
end

function TestEntityFinder.new(surface, area, definitions)
  local real_finder = EntityFinder.new(surface, area, definitions)

  local self = setmetatable({}, TestEntityFinder)
  self.entities = {}

  for name, ent in pairs(real_finder:all()) do
    if type(ent) == "table" then
      assert(#ent > 0)
      local fakes = {}
      for _, e in ipairs(ent) do
        table.insert(fakes, TestEntity.new(e))
      end
      self.entities[name] = fakes
    else
      self.entities[name] = TestEntity.new(ent)
    end
  end

  return self
end

return TestEntityFinder
