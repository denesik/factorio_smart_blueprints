local blueprint_handler = {}

local EntityFinder = require("entity_finder")
local scheduler = require("common.scheduler")
local entity_finder = require("entity_finder")
local ScenariosLibrary = require("scenarios_library")

local TARGET_BLUEPRINT_NAME = "<blueprint_handler>"
local ENTITY_TO_CONFIGURE_ID = "blueprint_handler"

local active_blueprints = {}

local function get_blueprint_bbox(blueprint, position, direction, flip_horizontal, flip_vertical)
  local entities = blueprint.get_blueprint_entities()
  if not entities or #entities == 0 then return nil end

  local x_min, x_max, y_min, y_max = nil, nil, nil, nil
  for _, ent in pairs(entities) do
    if ent and ent.position then
      if ent.position.x and ent.position.y then
        local x = ent.position.x
        local y = ent.position.y
        x_min = (x_min == nil or x < x_min) and x or x_min
        x_max = (x_max == nil or x > x_max) and x or x_max
        y_min = (y_min == nil or y < y_min) and y or y_min
        y_max = (y_max == nil or y > y_max) and y or y_max
      end
    end
  end

  if not (x_min and x_max and y_min and y_max) then return nil end

  local center_x = (x_min + x_max) / 2
  local center_y = (y_min + y_max) / 2

  local corners = {
    {x_min - center_x, y_min - center_y},
    {x_min - center_x, y_max - center_y},
    {x_max - center_x, y_min - center_y},
    {x_max - center_x, y_max - center_y},
  }

  direction = direction or defines.direction.north
  flip_horizontal = flip_horizontal or false
  flip_vertical = flip_vertical or false

  local x_min_r, x_max_r, y_min_r, y_max_r = nil, nil, nil, nil

  for _, corner in pairs(corners) do
    local x, y = corner[1], corner[2]
    if flip_horizontal then x = -x end
    if flip_vertical then y = -y end

    local x_rot, y_rot
    if direction == defines.direction.north then
      x_rot, y_rot = x, y
    elseif direction == defines.direction.east then
      x_rot, y_rot = y, -x
    elseif direction == defines.direction.south then
      x_rot, y_rot = -x, -y
    elseif direction == defines.direction.west then
      x_rot, y_rot = -y, x
    end

    x_min_r = (x_min_r == nil or x_rot < x_min_r) and x_rot or x_min_r
    x_max_r = (x_max_r == nil or x_rot > x_max_r) and x_rot or x_max_r
    y_min_r = (y_min_r == nil or y_rot < y_min_r) and y_rot or y_min_r
    y_max_r = (y_max_r == nil or y_rot > y_max_r) and y_rot or y_max_r
  end

  -- TODO: костыль, считать правильно ббокс
  return {
    {x_min_r + position.x - 0.5, y_min_r + position.y - 0.5},
    {x_max_r + position.x + 0.5, y_max_r + position.y + 0.5}
  }
end

local function draw_bbox(player, bbox, duration_ticks)
  local left_top, right_bottom = bbox[1], bbox[2]
  local color = {r=0, g=1, b=0, a=0.5}

  local object = rendering.draw_rectangle{
    color = color,
    width = 0.05,
    filled = false,
    left_top = {left_top[1], left_top[2]},
    right_bottom = {right_bottom[1], right_bottom[2]},
    surface = player.surface,
    players = {player.index}
  }

  scheduler.schedule(duration_ticks, function(data)
    if object.valid then
      object.destroy()
    end
  end)
end

local function find_entity_to_configure(blueprint, tag)
  local entities = blueprint.get_blueprint_entities()
  if not entities or #entities == 0 then return nil end

  for _, ent in pairs(entities) do
    if ent.player_description then
      if ent.player_description:find(tag, 1, true) then return ent end
    end
  end
  return nil
end

local function find_scenario_name(blueprint)
  local entities = blueprint.get_blueprint_entities()
  if not entities or #entities == 0 then return nil end

  for _, ent in pairs(entities) do
    if ent.player_description then
      local name = ent.player_description:match("<<scenario=(.-)>>")
      if name then return name end
    end
  end
  return nil
end

local function copy_entity_description(target, source)
  if source.combinator_description then
    target.combinator_description = source.combinator_description
    return true
  end
  if source.player_description then
    target.combinator_description = source.player_description
    return true
  end
  return false
end

local function find_real_entity(surface, search_area, type, tag)
  if not surface then return nil end
  local entities = EntityFinder.find_entities(surface, search_area, type)
  for _, entity in ipairs(entities) do
    if entity.combinator_description then
      if entity.combinator_description:find(tag, 1, true) then
        return entity
      end
    end
  end
  return nil
end

function blueprint_handler.on_pre_build(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  if player.is_cursor_empty() then return end

  local blueprint = (function()
    local stack = player.cursor_stack
    if stack and stack.valid_for_read and stack.type == "blueprint" then return stack end

    if not player.is_cursor_blueprint() then return end

    local record = player.cursor_record
    if record and record.type == "blueprint" then return record end
    return nil
  end)()
  if not blueprint or not blueprint.is_blueprint_setup() then return end
  if not blueprint.blueprint_description:find(TARGET_BLUEPRINT_NAME, 1, true) then return end

  local scenario_name = find_scenario_name(blueprint)
  if not scenario_name then return end

  local entity_to_configure_tag = "<<scenario=" .. scenario_name .. ">>"
  local bp_entity_to_configure = find_entity_to_configure(blueprint, entity_to_configure_tag)
  if not bp_entity_to_configure then return end

  local bbox = get_blueprint_bbox(blueprint, event.position, event.direction, event.flip_horizontal, event.flip_vertical)
  if not bbox then return end

  local real_entity_to_configure = find_real_entity(player.surface, bbox, bp_entity_to_configure.name, entity_to_configure_tag)

  active_blueprints[event.player_index] = {
    bbox = bbox,
    scenario_name = scenario_name,
    entity_to_configure_name = bp_entity_to_configure.name,
    entity_to_configure_tag = entity_to_configure_tag,
    real_entity = real_entity_to_configure
  }

  local virtual_entity = remote.call("virtual_entity", "get_or_create_entity", player, bp_entity_to_configure.name, ENTITY_TO_CONFIGURE_ID)
  if not virtual_entity then return end

  if real_entity_to_configure then
    virtual_entity.copy_settings(real_entity_to_configure)
  else
    remote.call("virtual_entity", "reset_entity_settings", player, virtual_entity)
    copy_entity_description(virtual_entity, bp_entity_to_configure)
  end

  scheduler.schedule(1, function()
    if player.valid and virtual_entity then
      remote.call("virtual_entity", "open_gui", player, virtual_entity)
    end
  end)
end

function blueprint_handler.on_virtual_entity_gui_close(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  if not active_blueprints[event.player_index] then return end
  local data = active_blueprints[event.player_index]
  active_blueprints[event.player_index] = nil

  local target_entity = data.real_entity
  if not target_entity or not target_entity.valid then
    target_entity = find_real_entity(player.surface, data.bbox, data.entity_to_configure_name, data.entity_to_configure_tag)
  end
  if not target_entity then return end

  target_entity.copy_settings(event.entity)
  copy_entity_description(target_entity, event.entity)

  ScenariosLibrary:run(data.scenario_name, data.bbox)
end

return blueprint_handler
