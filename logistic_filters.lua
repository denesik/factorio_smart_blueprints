local entity_control = require("entity_control")

local logistic_filters = {}

--- Считывает все логистические фильтры из секций управления сущности.
-- Если объект невалиден или интерфейс управления отсутствует — возвращает пустой список.
--
-- @param target LuaEntity Целевая сущность с логистическими секциями.
-- @return table Список всех фильтров из всех секций.
function logistic_filters.read_all_filters(target)
  if not target or not target.valid then
    error("Invalid object for 'read_all_logistic_filters'")
    return {}
  end

  local filters = {}

  local section_controller = entity_control.get_control_interface(target)
  if not section_controller then
    return filters
  end

  for _, section in ipairs(section_controller.sections) do
    for _, filter in ipairs(section.filters) do
      table.insert(filters, filter)
    end
  end

  return filters
end

--- Устанавливает логистические фильтры для сущности, разбивая их на секции.
-- Создаёт новые секции по мере необходимости, по максимуму до 1000 фильтров в секции.
-- Если объект невалиден или интерфейс управления отсутствует — функция завершится с ошибкой или без действий.
--
-- @param target LuaEntity Целевая сущность для установки фильтров.
-- @param logistic_filters table Список фильтров для установки.
function logistic_filters.set_filters(target, filters)
  if not target or not target.valid then
    error("Invalid object for 'set_logistic_filters'")
    return
  end

  local section_controller = entity_control.get_control_interface(target)
  if not section_controller then
    return
  end

  local MAX_SECTION_SIZE = 1000
  local filters_batch = {}

  local function set_filters_in_new_section()
    if #filters_batch > 0 then
      local current_section = section_controller.add_section()
      if not current_section then
        error("Can't create new section")
        return
      end
      current_section.filters = filters_batch
      filters_batch = {}
    end
  end

  for _, filter in ipairs(filters) do
    table.insert(filters_batch, filter)
    if #filters_batch >= MAX_SECTION_SIZE then
      set_filters_in_new_section()
    end
  end
  set_filters_in_new_section()
end

return logistic_filters
