local test_entity_control = {}

function test_entity_control.get_name(entity)
  return entity.name
end

function test_entity_control.read_all_logistic_filters(entity)
  return entity:read_all_logistic_filters()
end

function test_entity_control.set_logistic_filters(entity, filters, settings)
  entity:set_logistic_filters(filters, settings)
end

function test_entity_control.fill_decider_combinator(entity, conditions, outputs)
  entity:fill_decider_combinator(conditions, outputs)
end

function test_entity_control.get_logistic_sections(entity)
  return entity:get_logistic_sections()
end

function test_entity_control.set_filter(entity, i, filter)
  entity:set_filter(i, filter)
end

return test_entity_control
