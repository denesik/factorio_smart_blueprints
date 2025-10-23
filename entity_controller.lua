local EntityController = {}

local algorithm = require("llib.algorithm")

local GENERATED_LABEL = {
  value = {
    name = "deconstruction-planner",
    type = "item",
    quality = "legendary"
  },
  min = 0
}

-- Вспомогательные локальные функции
local function get_name(entity)
  if entity.type == "entity-ghost" then
    return entity.ghost_name
  end
  return entity.name
end

local function get_type(entity)
  if entity.type == "entity-ghost" then
    return entity.ghost_type
  end
  return entity.type
end

local function clear_generated_logistic_filters(controller)
  if controller.entity.get_logistic_sections() then
    local logistic_sections = controller.entity.get_logistic_sections()
    if not logistic_sections then
      error("Can't get logistic sections for entity " .. controller.name)
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
end

EntityController.__index = EntityController

local function static(fn)
  return setmetatable({
    fn = fn,
    __no_inherit = true
  }, {
    __call = function(t, ...)
      return t.fn(...)
    end
  })
end

-- Статические функции
EntityController.new = static(function(real_entity)
  local self = setmetatable({}, EntityController)
  self.entity = real_entity
  self.name = get_name(real_entity)
  self.type = get_type(real_entity)
  clear_generated_logistic_filters(self)
  return self
end)

EntityController.ADD_SIGNAL = static(function(entry, object, count, max_count)
  local element = {
    value = {
      name = object.name,
      type = object.type,
      quality = object.quality
    },
    min = count
  }
  if max_count ~= nil then element.max = max_count end
  table.insert(entry, element)
end)

EntityController.ADD_FILTER = static(function(entry, object)
  table.insert(entry, {
    value = {
      name = object.name,
    },
  })
end)

EntityController.MAKE_SIGNALS = static(function(items, functor)
  local out = {}
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
  end
  return out
end)

EntityController.MAKE_FILTERS = static(function(items)
  local out = {}
  for _, item in pairs(items) do
    table.insert(out, {
      value = {
        name = item.value.name,
      }
    })
  end
  return out
end)

-- Нестатические методы (экземплярные)
function EntityController:read_all_logistic_filters()
  local logistic_sections = self.entity.get_logistic_sections()
  if not logistic_sections then
    error("Can't get logistic sections for entity " .. self.name)
  end

  local filters = {}
  for _, section in ipairs(logistic_sections.sections) do
    if section.active then
      for _, filter in ipairs(section.filters) do
        if filter.value and filter.min then
          table.insert(filters, {
            value = {
              name = filter.value.name,
              type = filter.value.type,
              quality = filter.value.quality
            },
            min = filter.min * section.multiplier
          })
        end
      end
    end
  end
  return filters
end

function EntityController:has_logistic_sections()
  return self.entity.get_logistic_sections() ~= nil
end

function EntityController:set_filters(filters)
  if self.entity then
    for i, item in ipairs(filters) do
      local filter = {
        name = item.value.name,
      }
      self.entity.set_filter(i, filter)
    end
    for i = #filters + 1, 5 do
      self.entity.set_filter(i, {})
    end
  end
end

function EntityController:set_logistic_filters(filters, settings)
  if #filters == 0 then return end

  local logistic_sections = self.entity.get_logistic_sections()
  if not logistic_sections then
    error("Can't get logistic sections for entity " .. self.name)
  end

  local MAX_SECTION_SIZE = 1000
  local filters_batch = {}

  local function set_filters_in_new_section()
    if #filters_batch > 0 then
      local current_section = logistic_sections.add_section()
      if not current_section then
        error("Can't add logistic section for entity " .. self.name)
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

function EntityController:fill_decider_combinator(conditions, outputs)
  local control_behavior = self.entity.get_or_create_control_behavior()
  if not control_behavior then
    error("Can't get or create control behavior for entity " .. self.name)
  end

  local parameters = control_behavior.parameters

  outputs = outputs or parameters.outputs
  conditions = conditions or parameters.conditions
  control_behavior.parameters = { conditions = conditions, outputs = outputs }
end

return EntityController
