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
    error("Invalid object for 'get_control_interface'")
    return nil
  end

  if target.type == "constant-combinator" or target.type == "decider-combinator" then
    if type(target.get_or_create_control_behavior) ~= "function" then
      error("Invalid object. Can't find 'get_or_create_control_behavior' function")
      return nil
    end

    local control_behavior = target.get_or_create_control_behavior()

    if not control_behavior then
      error("Invalid object. Can't create control behavior")
      return nil
    end
    return control_behavior
  end

  if target.type == "logistic-container" then
    local request_point = target.get_requester_point()

    if not request_point then
      error("Invalid object. Can't get request point")
      return nil
    end
    return request_point
  end

  return nil
end

return entity_control
