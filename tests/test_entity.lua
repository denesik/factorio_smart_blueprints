local entity_control = require("entity_control")

local TestEntity = {}
TestEntity.__index = TestEntity

function TestEntity.new(real_entity)
    local self = setmetatable({}, TestEntity)
    self.name = entity_control.get_name(real_entity)
    self.type = entity_control.get_type(real_entity)
    self.entity = real_entity
    self.call_log = {}
    return self
end

function TestEntity:log_call(method_name, params, result)
    table.insert(self.call_log, {
        method = method_name,
        params = params,
        result = result,
        timestamp = game.tick
    })
end

function TestEntity:read_all_logistic_filters()
    local result = entity_control.read_all_logistic_filters(self.entity)
    self:log_call("read_all_logistic_filters", {}, result)
    return result
end

function TestEntity:get_logistic_sections()
    local result = entity_control.get_logistic_sections(self.entity)
    self:log_call("get_logistic_sections", {}, result)
    return result
end

function TestEntity:set_filter(i, filter)
    entity_control.set_filter(self.entity, i, filter)
    self:log_call("set_filter", {i=i, filter=filter}, nil)
end

function TestEntity:set_logistic_filters(filters, settings)
    entity_control.set_logistic_filters(self.entity, filters, settings)
    self:log_call("set_logistic_filters", {filters=filters, settings=settings}, nil)
end

function TestEntity:fill_decider_combinator(conditions, outputs)
    entity_control.fill_decider_combinator(self.entity, conditions, outputs)
    self:log_call("fill_decider_combinator", {conditions=conditions, outputs=outputs}, nil)
end

function TestEntity:get_log_json()
    return helpers.table_to_json(self.call_log)
end

return TestEntity
