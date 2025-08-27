local EntityFinder = {}
EntityFinder.__index = function(self, key)
  -- Сначала ищем обычные методы/поля
  local val = rawget(EntityFinder, key)
  if val ~= nil then return val end
  -- Потом ищем в entities
  if self.entities then
    return self.entities[key]
  end
end

--- Создаёт новый EntityFinder
-- @param search_area table {left_top = {x, y}, right_bottom = {x, y}}
-- @param definitions table список { {name = string, label = string|number, type = string}, ... }
-- @return EntityFinder
function EntityFinder.new(search_area, definitions)
  local self = setmetatable({}, EntityFinder)

  -- Проверка уникальности имён
  local names = {}
  for _, def in ipairs(definitions) do
    if names[def.name] then
      error("Duplicate name in EntityFinder definitions: " .. def.name)
    end
    names[def.name] = true
  end

  self.search_area = search_area
  self.entities = {}  -- публичный словарь найденных сущностей
  self:initialize(definitions)

  return self
end

--- Получение surface игрока (в том числе наблюдателя)
local function get_player_surface()
  local player = game.player or game.get_player(1)
  if not player or not player.valid then
    error("No valid player found to determine surface")
  end
  if not player.surface or not player.surface.valid then
    error("Player has no valid surface (maybe no active camera?)")
  end
  return player.surface
end

--- Внутренняя инициализация поиска всех сущностей
function EntityFinder:initialize(definitions)
  local surface = get_player_surface()

  for _, def in ipairs(definitions) do
    local entities = surface.find_entities_filtered{
      area = self.search_area,
      type = def.type
    }

    local found = nil

    if type(def.label) == "string" then
      local label_lower = def.label:lower()

      for _, entity in ipairs(entities) do
        local ok, desc = pcall(function() return entity.combinator_description end)
        if ok and desc and desc:lower():find(label_lower, 1, true) then
          if found then
            error("Multiple entities found for name '" .. def.name .. "' with label '" .. def.label .. "'")
          end
          found = entity
        end
      end

    elseif type(def.label) == "number" then
      for _, entity in ipairs(entities) do
        if entity.get_control_behavior then
          local control = entity.get_control_behavior()
          if control then
            -- Безопасная проверка, что circuit_condition.constant == def.label
            local constant_equal = false
            pcall(function()
              local cond = control.circuit_condition
              if cond and cond.constant == def.label then
                constant_equal = true
              end
            end)

            -- Безопасная проверка disabled
            local disabled = false
            pcall(function()
              if control.circuit_enable_disable == false then
                disabled = true
              end
            end)
            pcall(function()
              if control.circuit_condition_enabled == false then
                disabled = true
              end
            end)

            if constant_equal and disabled then
              if found then
                error("Multiple entities found for name '" .. def.name .. "' with label '" .. tostring(def.label) .. "'")
              end
              found = entity
            end
          end
        end
      end
    else
      error("Invalid label type for definition " .. def.name)
    end

    if not found then
      error("No entity found for name '" .. def.name .. "' with label '" .. tostring(def.label) .. "'")
    end

    self.entities[def.name] = found  -- сохраняем в публичный словарь
  end
end

--- Получить сущность по имени (для совместимости)
-- @param name string
-- @return LuaEntity
function EntityFinder:get(name)
  return self.entities[name]
end

--- Получить все сущности (словaрём name -> entity)
function EntityFinder:all()
  return self.entities
end

return EntityFinder
