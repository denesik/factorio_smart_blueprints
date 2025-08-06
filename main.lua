local Utils = require("utils")

local function get_section_controler(target)
  if not target or not target.valid then
    error("Invalid object for 'get_section_controler'")
    return nil
  end

  if target.type == "constant-combinator" then
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

local function read_all_logistic_filters(target)
  local section_controller = get_section_controler(target)
  if not section_controller then
    return
  end

  local logistic_filters = {}
  for _, section in ipairs(section_controller.sections) do
    for _, filter in ipairs(section.filters) do
      table.insert(logistic_filters, filter)
    end
  end

  return logistic_filters
end

local function set_logistic_filters(target, logistic_filters)
  local section_controller = get_section_controler(target)
  if not section_controller then
    return
  end

  local MAX_SECTION_SIZE = 1000
  local filters = {}

  local function set_filters_in_new_section()
    if #filters > 0 then
      local current_section = section_controller.add_section()
      if not current_section then
        error("Can't create new section")
        return
      end
      current_section.filters = filters
      filters = {}
    end
  end

  for _, filter in ipairs(logistic_filters) do
    table.insert(filters, filter)
    if #filters >= MAX_SECTION_SIZE then
      set_filters_in_new_section()
    end
  end
  set_filters_in_new_section()
end

local function main()

  local search_area = {}
  if area == nil then
    search_area = { { 0, 0 }, { 100, 100 } }
  else
    search_area = area
  end

  local src = Utils.findSpecialEntity("<src_logistic_filters>", search_area)
  local dst = Utils.findSpecialEntity("<dst_logistic_filters>", search_area)

  local filters = read_all_logistic_filters(src)
  set_logistic_filters(dst, filters)
  
  game.print("Finish!")
end

return main