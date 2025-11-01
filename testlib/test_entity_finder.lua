local EntityFinder = require("entity_finder")
local TestEntityLogger = require("test_entity_logger")

local TestEntityLoggerFinder = {}
TestEntityLoggerFinder.__index = function(self, key)
  local val = rawget(TestEntityLoggerFinder, key)
  if val ~= nil then return val end
  return self.entities[key]
end

function TestEntityLoggerFinder.new(surface, area, definitions)
  local real_finder = EntityFinder.new(surface, area, definitions)
  local self = setmetatable({}, TestEntityLoggerFinder)
  self.entities = {}

  for name, ent in pairs(real_finder:all()) do
    if getmetatable(ent) == nil then
      local fakes = {}
      for _, e in ipairs(ent) do
        table.insert(fakes, TestEntityLogger.new(e))
      end
      self.entities[name] = fakes
    else
      self.entities[name] = TestEntityLogger.new(ent)
    end
  end

  return self
end

function TestEntityLoggerFinder:save_all_entities_to_file(filename, blueprint_string)
  local output = {}

  for name, ent in pairs(self.entities) do
    if getmetatable(ent) == nil then
      output[name] = {}
      for _, e in ipairs(ent) do
        table.insert(output[name], e:get_data())
      end
    else
      output[name] = ent:get_data()
    end
  end

  local json_str = helpers.table_to_json(output)
  local data_str = "return {\n  data = \"" .. helpers.encode_string(json_str) .. "\""
  if blueprint_string then
    data_str = data_str .. ",\n  blueprint = \"" .. blueprint_string .. "\"\n}"
  else
    data_str = data_str .. ",\n  blueprint = nil\n}"
  end
  helpers.write_file(filename, data_str)
end

return TestEntityLoggerFinder
