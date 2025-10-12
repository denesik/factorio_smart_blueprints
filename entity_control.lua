local entity_control = {}

function entity_control.get_name(entity)
  if entity.type == "entity-ghost" then
    return entity.ghost_name
  end
  return entity.name
end

function entity_control.get_type(entity)
  if entity.type == "entity-ghost" then
    return entity.ghost_type
  end
  return entity.type
end

-- Работаем с сигналами у которых есть как минимум value и min
function entity_control.read_all_logistic_filters(entity)
  return entity:read_all_logistic_filters()
end

--- Устанавливает фильтры
function entity_control.set_logistic_filters(entity, filters, settings)
  entity:set_logistic_filters(filters, settings)
end

function entity_control.fill_decider_combinator(entity, conditions, outputs)
  entity:fill_decider_combinator(conditions, outputs)
end

function entity_control.get_logistic_sections(entity)
  return entity:get_logistic_sections()
end

function entity_control.set_filters(entity, filters)
  entity:set_filters(filters)
end

return entity_control
