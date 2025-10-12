local entity_control = {}

local algorithm = require("llib.algorithm")

local GENERATED_LABEL = {
  value = {
    name = "deconstruction-planner",
    type = "item",
    quality = "legendary"
  },
  min = 0
}

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
  local logistic_sections = entity.get_logistic_sections()
  if not logistic_sections then
    error("Can't get logistic sections for entity " .. entity_control.get_name(entity))
  end

  local filters = {}
  for _, section in ipairs(logistic_sections.sections) do
    if section.active then
      for _, filter in ipairs(section.filters) do
        if filter.value and filter.min then
          filter.min = filter.min * section.multiplier
          table.insert(filters, filter)
        end
      end
    end
  end
  return filters
end

--- Устанавливает фильтры
function entity_control.set_logistic_filters(entity, filters, settings)
  if #filters == 0 then return end

  local logistic_sections = entity.get_logistic_sections()
  if not logistic_sections then
    error("Can't get logistic sections for entity " .. entity_control.get_name(entity))
  end

  local MAX_SECTION_SIZE = 1000
  local filters_batch = {}

  local function set_filters_in_new_section()
    if #filters_batch > 0 then
      local current_section = logistic_sections.add_section()
      if not current_section then
        error("Can't add logistic section for entity " .. entity_control.get_name(entity))
      end
      current_section.filters = filters_batch

      if settings then
        for k, v in pairs(settings) do
          current_section[k] = v
        end
      end

      filters_batch = {}
    end
  end

  for _, filter in ipairs(filters) do
    if #filters_batch == 0 then
      table.insert(filters_batch, 1, GENERATED_LABEL)
    end
    table.insert(filters_batch, filter)
    if #filters_batch >= MAX_SECTION_SIZE then
      set_filters_in_new_section()
    end
  end
  set_filters_in_new_section()
end

function entity_control.clear_generated_logistic_filters(entity)
  local logistic_sections = entity.get_logistic_sections()
  if not logistic_sections then
    error("Can't get logistic sections for entity " .. entity_control.get_name(entity))
    return
  end

  local indexes = {}

  for i, section in ipairs(logistic_sections.sections) do
    local first_filter = section.filters and section.filters[1]
    if first_filter
      and first_filter.value
      and first_filter.value.name == GENERATED_LABEL.value.name
      and first_filter.value.type == GENERATED_LABEL.value.type
      and first_filter.value.quality == GENERATED_LABEL.value.quality
      and first_filter.min == GENERATED_LABEL.min
    then
      table.insert(indexes, 1, i) -- удаляем с конца
    end
  end

  for _, i in ipairs(indexes) do
    logistic_sections.remove_section(i)
  end
end

function entity_control.fill_decider_combinator(entity, conditions, outputs)
  local control_behavior = entity.get_or_create_control_behavior()
  if not control_behavior then
    error("Can't get or create control behavior for entity " .. entity_control.get_name(entity))
  end

  local parameters = control_behavior.parameters

  outputs = outputs or parameters.outputs
  conditions = conditions or parameters.conditions
  control_behavior.parameters = { conditions = conditions, outputs = outputs }
end

function entity_control.get_logistic_sections(entity)
  return entity.get_logistic_sections()
end

function entity_control.set_filters(entity, filters)
  if entity then
    for i, item in ipairs(filters) do
      local filter = {
        name = item.value.name,
      }
      entity.set_filter(i, filter)
    end
    for i = #filters + 1, 5 do
      entity.set_filter(i, {})
    end
  end
end

function entity_control.MAKE_SIGNALS(items, functor)
  local out = {}
  local out1= {}
  functor = functor or function() end
  for i, _, item in algorithm.enumerate(items) do
    local min, value = functor(item, i)
    local new_value = value or item.value
    table.insert(out, {
      value = {
        name = new_value.name,
        type = new_value.type,
        quality = new_value.quality
      },
      min = min or item.min
    })
    table.insert(out1, {
      value = value or item.value,
      min = min or item.min
    })
  end
  return out
end

return entity_control
