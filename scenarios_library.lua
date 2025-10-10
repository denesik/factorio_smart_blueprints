local EntityFinder = require("entity_finder")
local entity_control = require("entity_control")
local test_entity_control = require("tests.test_entity_control")
local TestEntityFinder = require("tests.test_entity_finder")
local TestEntityLoader = require("tests.test_entity_loader")

local ScenariosLibrary = {}
ScenariosLibrary.__index = ScenariosLibrary

local self = setmetatable({ _scenarios = {} }, ScenariosLibrary)

local scenario_files = {
  { name = "quality_rolling", test = "quality_rolling_test" },
  { name = "multi_assembler", test = "multi_assembler_test" },
}

for _, info in ipairs(scenario_files) do
  local ok, scenario = pcall(require, "scenarios." .. info.name)
  if ok then
    assert(scenario.name and scenario.run and scenario.defines)
    local entry = { scenario = scenario }
    if info.test then
      local ok_data, data = pcall(require, "tests." .. info.test)
      if ok_data then
        entry.test_data = data
      end
    end
    self._scenarios[scenario.name] = entry
  else
    game.print("Failed to load scenario: " .. info.name .. " Error: " .. tostring(scenario))
  end
end

function ScenariosLibrary:run(name, player, area)
  local entry = self._scenarios[name]
  if not entry then error("Scenario '" .. name .. "' not found") end
  local entities = EntityFinder.new(player.surface, area, entry.scenario.defines)
  entry.scenario.run(entity_control, entities, player)
end

function ScenariosLibrary:make_test(name, player, area)
  local entry = self._scenarios[name]
  if not entry then error("Scenario '" .. name .. "' not found") end
  local entities = TestEntityFinder.new(player.surface, area, entry.scenario.defines)
  entry.scenario.run(test_entity_control, entities, player)
  local filename = entry.scenario.name .. ".json"
  entities:save_all_entities_to_file(filename)
  game.print("Test entities for scenario '" .. name .. "' saved to file: " .. filename)
end

function ScenariosLibrary:run_test(name, player)
  local entry = self._scenarios[name]
  if not entry or not entry.test_data then
    return
  end

  local ok, err = pcall(function()
    local entities = TestEntityLoader.new(entry.test_data)
    entry.scenario.run(test_entity_control, entities, player)
  end)

  if ok then
    game.print("Test for scenario '" .. name .. "' passed")
  else
    game.print("Test for scenario '" .. name .. "' failed: " .. tostring(err))
  end
end

function ScenariosLibrary:run_tests(player)
  for name, _ in pairs(self._scenarios) do
    self:run_test(name, player)
  end
end

return self
