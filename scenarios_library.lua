local EntityFinder = require("entity_finder")
local entity_control = require("entity_control")
local test_entity_control = require("tests.test_entity_control")
local TestEntityFinder = require("tests.test_entity_finder")
local TestEntityLoader = require("tests.test_entity_loader")

local test_data = require("tests.multi_assembler_json")

local ScenariosLibrary = {}
ScenariosLibrary.__index = ScenariosLibrary

local self = setmetatable({ _scenarios = {} }, ScenariosLibrary)

-- подключение и регистрация сценариев
local scenario_files = {
  "quality_rolling",
  "multi_assembler",
}

for _, file in ipairs(scenario_files) do
  local ok, scenario = pcall(require, "scenarios." .. file)
  if ok then
    assert(scenario.name and scenario.run and scenario.defines, "Scenario '" .. file .. "' must have 'name' and 'run' and 'defines' fields")
    self._scenarios[scenario.name] = scenario
  else
    log("Failed to load scenario: " .. file .. " Error: " .. tostring(scenario))
  end
end

function ScenariosLibrary:run(name, player, area)
  local scenario = self._scenarios[name]
  if not scenario then error("Scenario '" .. name .. "' not found") end
  local entities = TestEntityLoader.new(test_data)
  scenario.run(test_entity_control, entities, player)
  entities:save_all_entities_to_file(scenario.name .. ".json")
end

function ScenariosLibrary:run1(name, player, area)
  local scenario = self._scenarios[name]
  if not scenario then error("Scenario '" .. name .. "' not found") end
  local entities = TestEntityFinder.new(player.surface, area, scenario.defines)
  scenario.run(test_entity_control, entities, player)
  entities:save_all_entities_to_file(scenario.name .. ".json")
end

function ScenariosLibrary:test_run(name, player, area)
  local scenario = self._scenarios[name]
  if not scenario then error("Scenario '" .. name .. "' not found") end
  local entities = EntityFinder.new(player.surface, area, scenario.defines)
  scenario.run(entity_control, entities, player)
end

return self
