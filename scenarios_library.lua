local ScenariosLibrary = {}
ScenariosLibrary.__index = ScenariosLibrary

local self = setmetatable({ _scenarios = {} }, ScenariosLibrary)

-- подключение и регистрация сценариев
local scenario_files = {
    "make_simple_rolling",
}
for _, file in ipairs(scenario_files) do
    local ok, scenario = pcall(require, "scenarios." .. file)
    if ok then
        assert(scenario.name and scenario.run, "Scenario '" .. file .. "' must have 'name' and 'run' fields")
        self._scenarios[scenario.name] = scenario.run
    else
        log("Failed to load scenario: " .. file .. " Error: " .. tostring(scenario))
    end
end

function ScenariosLibrary:run(name, ...)
    local scenario = self._scenarios[name]
    if not scenario then error("Scenario '" .. name .. "' not found") end
    return scenario(...)
end

return self
