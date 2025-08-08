--- Модуль для работы с интерфейсами управления сущностей Factorio.
local entity_control = {}

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

  if target.type == "constant-combinator" or target.type == "decider-combinator" then
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
function entity_control.set_logistic_filters(target, filters)
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
