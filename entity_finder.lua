local EntityFinder = {}

local entity_control = require("entity_control")

EntityFinder.__index = function(self, key)
  local val = rawget(EntityFinder, key)
  if val ~= nil then return val end
  return self.entities and self.entities[key]
end

function EntityFinder.find_entities(surface, area, types)
    local entities = {}

    local real_entities = surface.find_entities_filtered{
      area = area,
      type = types
    }
    for _, e in ipairs(real_entities) do table.insert(entities, e) end

    local ghosts = surface.find_entities_filtered{
      area = area,
      type = "entity-ghost"
    }
    if type(types) == "table" then
      local type_set = {}
      for _, t in ipairs(types) do type_set[t] = true end

      for _, g in ipairs(ghosts) do
        if type_set[g.ghost_type] then
          table.insert(entities, g)
        end
      end
    else
      for _, g in ipairs(ghosts) do
        if g.ghost_type == types then
          table.insert(entities, g)
        end
      end
    end

    return entities
end

function EntityFinder.new(surface, area, definitions)
  local self = setmetatable({}, EntityFinder)

  local names = {}
  for _, def in ipairs(definitions) do
    if names[def.name] then
      error("Duplicate name in EntityFinder definitions: " .. def.name)
    end
    names[def.name] = true
  end

  self.entities = {}
  self:initialize(surface, area, definitions)

  return self
end

local function check_description(entity, tag)
  local ok, desc = pcall(function() return entity.combinator_description end)
  if ok and desc and desc:find(tag, 1, true) then
    return true
  end
  return false
end

local function check_id(entity, id)
  local control = entity.get_or_create_control_behavior()
  if control then
    local constant_equal = false
    pcall(function()
      local cond = control.circuit_condition
      if cond and cond.constant == id then
        constant_equal = true
      end
    end)

    local disabled = false
    pcall(function()
      -- machines
      if control.circuit_enable_disable == false then
        disabled = true
      end
    end)
    pcall(function()
      -- containers
      if control.circuit_condition_enabled == false then
        disabled = true
      end
    end)

    if constant_equal and disabled then
      return true
    end
  end
  return false
end

--- Внутренняя инициализация поиска всех сущностей и их призраков
function EntityFinder:initialize(surface, area, definitions)
  for _, def in ipairs(definitions) do
    local entities = EntityFinder.find_entities(surface, area, def.type)

    local found = nil

    if type(def.label) == "string" then
      for _, entity in ipairs(entities) do
        if check_description(entity, def.label) then
          if found then
            error("Multiple entities found for name '" .. def.name .. "' with label '" .. def.label .. "'")
          end
          found = entity
        end
      end

    elseif type(def.label) == "number" then
      for _, entity in ipairs(entities) do
        if check_id(entity, def.label) then
          if found then
            error("Multiple entities found for name '" .. def.name .. "' with label '" .. tostring(def.label) .. "'")
          end
          found = entity
        end
      end
    else
      assert("Invalid label type for definition " .. def.name)
    end

    if not found then
      error("No entity (or ghost) found for name '" .. def.name .. "' with label '" .. tostring(def.label) .. "'")
    end

    if found.get_logistic_sections() then
      entity_control.clear_generated_logistic_filters(found)
    end

    self.entities[def.name] = found
  end
end

function EntityFinder:get(name)
  return self.entities[name]
end

function EntityFinder:all()
  return self.entities
end

return EntityFinder
