local table_utils = require "common.table_utils"
--- Модуль для работы с интерфейсами управления сущностей Factorio (включая призраки).
local entity_control = {}

local GENERATED_LABEL = {
  value = {
    name = "deconstruction-planner",
    type = "item",
    quality = "legendary"
  },
  min = 0
}

function entity_control.get_name(target)
  if not target or not target.valid then
    error("Invalid object for 'get_name'")
  end

  if target.type == "entity-ghost" then
    return target.ghost_name
  end

  return target.name
end

function entity_control.get_type(target)
  if not target or not target.valid then
    error("Invalid object for 'get_type'")
  end

  if target.type == "entity-ghost" then
    return target.ghost_type
  end

  return target.type
end

--- Получает интерфейс управления для заданного объекта.
-- Работает как с реальными сущностями, так и с призраками.
function entity_control.get_control_interface(target)
  if not target or not target.valid then
    error("Invalid object for 'get_control_interface'")
  end

  local target_type = entity_control.get_type(target)
  if target_type == "constant-combinator"
    or target_type == "decider-combinator"
    or target_type == "inserter"
    or target_type == "assembling-machine"
  then
    if type(target.get_or_create_control_behavior) ~= "function" then
      error("Invalid object. Can't find 'get_or_create_control_behavior' function")
    end

    local control_behavior = target.get_or_create_control_behavior()
    if not control_behavior then
      error("Invalid object. Can't create control behavior")
    end
    return control_behavior
  end

  if target_type == "logistic-container" then
    local logistic_sections = nil

    if target.type == "entity-ghost" then
      logistic_sections = target.get_logistic_sections()
    else
      logistic_sections = target.get_requester_point()
    end
    if not logistic_sections then
      error("Invalid object. Can't get request point")
    end
    return logistic_sections
  end

  error("Unsupported entity type '" .. target_type .. "' in 'get_control_interface'")
end

--- Считывает все логистические фильтры
function entity_control.read_all_logistic_filters(target)
  if not target or not target.valid then
    error("Invalid object for 'read_all_logistic_filters'")
  end

  local section_controller = entity_control.get_control_interface(target)
  if not section_controller then
    error("Can't get section controller in 'read_all_logistic_filters'")
  end

  local filters = {}
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
    error("Invalid object for 'read_logistic_filters'")
  end

  local section_controller = entity_control.get_control_interface(target)
  if not section_controller then
    error("Can't get section controller in 'read_logistic_filters'")
  end

  local section = section_controller.get_section(section_index)
  if not section then
    error("Invalid section index " .. tostring(section_index) .. " in 'read_logistic_filters'")
  end

  local filters = {}
  for _, filter in ipairs(section.filters) do
    if next(filter) then
      filter.min = filter.min * section.multiplier
      table.insert(filters, filter)
    end
  end
  return filters
end

--- Устанавливает фильтры
function entity_control.set_logistic_filters(target, filters, settings)
  local multiplier = (settings and settings.multiplier) or 1
  local active = (settings and settings.active) ~= false

  if not target or not target.valid then
    error("Invalid object for 'set_logistic_filters'")
  end

  local section_controller = entity_control.get_control_interface(target)
  if not section_controller then
    error("Can't get section controller in 'set_logistic_filters'")
  end

  local MAX_SECTION_SIZE = 1000
  local filters_batch = {}

  local function set_filters_in_new_section()
    if #filters_batch > 0 then
      local current_section = section_controller.add_section()
      if not current_section then
        error("Can't create new section in 'set_logistic_filters'")
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
  if not target or not target.valid then
    error("Invalid object for 'clear_generated_logistic_filters'")
  end

  local section_controller = entity_control.get_control_interface(target)
  if not section_controller then
    --error("Can't get section controller in 'clear_generated_logistic_filters'")
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
        table.insert(indexes, 1, i) -- удаляем с конца
      end
    end
  end

  for _, i in ipairs(indexes) do
    section_controller.remove_section(i)
  end
end

function entity_control.fill_decider_combinator(target, conditions, outputs)
  if not target or not target.valid then
    error("Invalid object for 'fill_decider_combinator'")
  end

  local controller = entity_control.get_control_interface(target)
  if not controller then
    error("Can't get control interface in 'fill_decider_combinator'")
  end

  outputs = outputs or controller.parameters.outputs
  conditions = conditions or controller.parameters.conditions
  controller.parameters = { conditions = conditions, outputs = outputs }
end

return entity_control
