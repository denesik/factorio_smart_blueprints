local table_utils = require "table_utils"
--- Модуль для работы с интерфейсами управления сущностей Factorio.
local entity_control = {}

local GENERATED_LABEL = {
  value = {
    name = "deconstruction-planner",
    type = "item",
    quality = "legendary"
  },
  min = 0
}

--- Получает интерфейс управления для заданного объекта.
-- Для комбинаторов (constant-combinator, decider-combinator) возвращает control_behavior.
-- Для logistic-container возвращает requester_point.
-- Выбрасывает ошибку, если объект невалиден или требуемый интерфейс получить нельзя.
--
-- @param target LuaEntity Объект Factorio для получения интерфейса управления.
-- @return LuaControlBehavior|LuaLogisticRequesterPoint|nil Интерфейс управления или nil, если тип не поддерживается.
-- @raise Ошибка если объект невалиден или отсутствует необходимый метод/данные.
function entity_control.get_control_interface(target)
  if not target or not target.valid then
    game.print("Invalid object for 'get_control_interface'")
    return nil
  end

  if target.type == "constant-combinator" or target.type == "decider-combinator" or target.type == "inserter" then
    if type(target.get_or_create_control_behavior) ~= "function" then
      game.print("Invalid object. Can't find 'get_or_create_control_behavior' function")
      return nil
    end

    local control_behavior = target.get_or_create_control_behavior()

    if not control_behavior then
      game.print("Invalid object. Can't create control behavior")
      return nil
    end
    return control_behavior
  end

  if target.type == "logistic-container" then
    local request_point = target.get_requester_point()

    if not request_point then
      game.print("Invalid object. Can't get request point")
      return nil
    end
    return request_point
  end

  return nil
end


--- Считывает все логистические фильтры из секций управления сущности.
-- Если объект невалиден или интерфейс управления отсутствует — возвращает пустой список.
--
-- @param target LuaEntity Целевая сущность с логистическими секциями.
-- @return table Список всех фильтров из всех секций.
function entity_control.read_all_logistic_filters(target)
  if not target or not target.valid then
    game.print("Invalid object for 'read_all_logistic_filters'")
    return {}
  end

  local filters = {}

  local section_controller = entity_control.get_control_interface(target)
  if not section_controller then
    return filters
  end

  for _, section in ipairs(section_controller.sections) do
    for _, filter in ipairs(section.filters) do
      if next(filter) then
        filter.min = filter.min * section.multiplier
        table.insert(filters, filter)
      end
    end
  end

  return filters
end

function entity_control.read_logistic_filters(target, section_index)
  if not target or not target.valid then
    game.print("Invalid object for 'read_all_logistic_filters'")
    return {}
  end

  local filters = {}

  local section_controller = entity_control.get_control_interface(target)
  if not section_controller then
    return filters
  end

  local section = section_controller.get_section(section_index)
  if section then
    for _, filter in ipairs(section.filters) do
      if next(filter) then
        filter.min = filter.min * section.multiplier
        table.insert(filters, filter)
      end
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
function entity_control.set_logistic_filters(target, filters, settings)
  local multiplier = 1
  local active = true
  if settings and settings.multiplier ~= nil then
    multiplier = settings.multiplier
  end
  if settings and settings.active ~= nil then
    active = settings.active
  end

  if not target or not target.valid then
    game.print("Invalid object for 'set_logistic_filters'")
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
        game.print("Can't create new section")
        return
      end
      current_section.filters = filters_batch
      current_section.multiplier = multiplier
      current_section.active = active
      filters_batch = {}
    end
  end

  local out_filters = table_utils.deep_copy(filters)
  table.insert(out_filters, 1, GENERATED_LABEL)
  for _, filter in ipairs(out_filters) do
    table.insert(filters_batch, filter)
    if #filters_batch >= MAX_SECTION_SIZE then
      set_filters_in_new_section()
    end
  end
  set_filters_in_new_section()
end

function entity_control.clear_generated_logistic_filters(target)
  local ignore_list = {}

  if not target or not target.valid then
    game.print("Invalid object for 'clear_logistic_filters'")
    return
  end

  local section_controller = entity_control.get_control_interface(target)
  if not section_controller then
    return
  end

  local indexes = {}
  local ok, sections = pcall(function() return section_controller.sections end)
  if ok and sections then
    for i, section in ipairs(sections) do
      local first_filter = section.filters and section.filters[1]
      if first_filter
        and first_filter.value
        and first_filter.value.name == GENERATED_LABEL.value.name
        and first_filter.value.type == GENERATED_LABEL.value.type
        and first_filter.value.quality == GENERATED_LABEL.value.quality
        and first_filter.min == GENERATED_LABEL.min
      then
        table.insert(indexes, 1, i) -- вставляем в начало, чтобы удалять с конца
      end
    end
  end

  for _, i in ipairs(indexes) do
    section_controller.remove_section(i)
  end
end

function entity_control.fill_decider_combinator(target, conditions, outputs)
  if not target or not target.valid then
    game.print("Invalid object for 'fill_decider_combinator'")
    return
  end

  local controller = entity_control.get_control_interface(target)
  if not controller then
    game.print("Invalid object. Can't get control interface")
    return
  end

  outputs = outputs or controller.parameters.outputs
  conditions = conditions or controller.parameters.conditions
  controller.parameters = { conditions = conditions, outputs = outputs }
end

return entity_control
