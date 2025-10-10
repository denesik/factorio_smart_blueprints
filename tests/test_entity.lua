local entity_control = require("entity_control")

local TestEntity = {}
TestEntity.__index = TestEntity

function TestEntity.new(real_entity)
  local self = setmetatable({}, TestEntity)
  self.name = entity_control.get_name(real_entity)
  self.type = entity_control.get_type(real_entity)
  self.entity = real_entity
  return self
end

function TestEntity:read_all_logistic_filters()
  return entity_control.read_all_logistic_filters(self.entity)
end

function TestEntity:get_logistic_sections()
  return entity_control.get_logistic_sections(self.entity)
end

function TestEntity:set_filter(i, filter)
  entity_control.set_filter(self.entity, i, filter)
end

function TestEntity:set_logistic_filters(filters, settings)
  entity_control.set_logistic_filters(self.entity, filters, settings)
end

function TestEntity:fill_decider_combinator(conditions, outputs)
  entity_control.fill_decider_combinator(self.entity, conditions, outputs)
end

return TestEntity
