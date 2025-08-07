local entity_finder = {}

--- Ищет сущность в заданной области по метке или числовому условию.
-- Если label — строка, ищет сущность, у которой:
--   • в combinator_description содержится эта метка (без учёта регистра), либо
--   • в get_logistic_sections есть деактивированная секция с group, совпадающей с меткой.
-- Если label — число, ищет сущность с выключенным условием включения, где условие содержит константу, равную label.
--
-- @param label string|number Метка для поиска (строка) или число-константа для условия включения.
-- @param search_area table Область поиска в формате {left_top = {x, y}, right_bottom = {x, y}}.
-- @return LuaEntity|nil Найденная сущность или nil, если не найдено.
function entity_finder.find(label, search_area)
  local surface = game.player.surface
  local search_params = {}
  search_params.area = search_area

  local entities = surface.find_entities_filtered(search_params)

  if type(label) == "string" then
    local label_lower = string.lower(label)

    for _, entity in ipairs(entities) do
      -- 1. combinator_description (если есть)
      local success, desc = pcall(function()
        return entity.combinator_description
      end)
      if success and desc and string.lower(desc):find(label_lower, 1, true) then
        return entity
      end

      -- 2. get_logistic_sections с деактивированной секцией и подходящей group
      if entity.get_logistic_sections then
        local sections = entity.get_logistic_sections()
        if sections and sections.sections then
          for _, section in pairs(sections.sections) do
            if not section.active and section.group and type(section.group) == "string" then
              if string.lower(section.group) == label_lower then
                return entity
              end
            end
          end
        end
      end
    end

  elseif type(label) == "number" then
    -- Ищем машину с выключенным условием включения, где константа совпадает с label
    for _, entity in ipairs(entities) do
      if entity.get_control_behavior then
        local control = entity.get_control_behavior()
        if control then
          local success, condition = pcall(function()
            return control.circuit_condition
          end)
          if success and condition and condition.constant then
            if not condition.enabled and condition.constant == label then
              return entity
            end
          end
        end
      end
    end
  end

  return nil
end

return entity_finder
