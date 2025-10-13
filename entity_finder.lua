local EntityFinder = {}

local EntityController = require("entity_controller")

EntityFinder.__index = function(self, key)
  local val = rawget(EntityFinder, key)
  if val ~= nil then return val end
  return self.entities and self.entities[key]
end

function EntityFinder.find_entities(surface, area, types)
    local out = {}

    local real_entities = surface.find_entities_filtered{
      area = area,
      type = types
    }
    for _, e in ipairs(real_entities) do table.insert(out, e) end

    local ghosts = surface.find_entities_filtered{
      area = area,
      type = "entity-ghost"
    }
    if type(types) == "table" then
      local type_set = {}
      for _, t in ipairs(types) do type_set[t] = true end

      for _, g in ipairs(ghosts) do
        if type_set[g.ghost_type] then
          table.insert(out, g)
        end
      end
    else
      for _, g in ipairs(ghosts) do
        if g.ghost_type == types then
          table.insert(out, g)
        end
      end
    end

    return out
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

  local type_set = {}
  for _, def in ipairs(definitions) do
    type_set[def.type] = true
  end
  local all_types = {}
  for t in pairs(type_set) do
    table.insert(all_types, t)
  end

  local function try_insert(found, entity, def)
    if not def.multiple and #found > 0 then
      error("Multiple entities found for name '" .. def.name .. "' with label '" .. tostring(def.label) .. "'")
    end
    table.insert(found, entity)
  end

  local founds = EntityFinder.find_entities(surface, area, all_types)

  for _, def in ipairs(definitions) do
    local found = {}

    if type(def.label) == "string" then
      for _, element in ipairs(founds) do
        if check_description(element, def.label) then
          try_insert(found, element, def)
        end
      end

    elseif type(def.label) == "number" then
      for _, element in ipairs(founds) do
        if check_id(element, def.label) then
          try_insert(found, element, def)
        end
      end
    else
      assert("Invalid label type for definition " .. def.name)
    end

    if #found == 0 then
      error("No entity (or ghost) found for name '" .. def.name .. "' with label '" .. tostring(def.label) .. "'")
    end

    local controllers = {}
    for _, ent in ipairs(found) do
      table.insert(controllers, EntityController.new(ent))
    end
    self.entities[def.name] = def.multiple and controllers or controllers[1]
  end
end

function EntityFinder:get(name)
  return self.entities[name]
end

function EntityFinder:all()
  return self.entities
end

return EntityFinder
