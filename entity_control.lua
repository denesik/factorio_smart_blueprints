local entity_control = {}

function entity_control.get_name(entity)
  return entity.name
end

function entity_control.get_type(entity)
  return entity.type
end

function entity_control.read_all_logistic_filters(entity)
  return entity:read_all_logistic_filters()
end

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
