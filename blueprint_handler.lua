local BlueprintHandler = {}
local TARGET_BLUEPRINT_NAME = "<make_simple_rolling>"

local active_bboxes = {}

local Scheduler = require("scheduler")
local entity_control = require("entity_control")
local entity_finder = require("entity_finder")
local main = require("main")

local function get_blueprint_bbox(stack, position, direction, flip_horizontal, flip_vertical)
  if not (stack and stack.valid and stack.valid_for_read) then return nil end

  --position.x = math.floor(position.x)
  --position.y = math.floor(position.y)

  local entities = nil
  local ok, result = pcall(function()
    return stack.get_blueprint_entities and stack.get_blueprint_entities()
  end)
  if ok then entities = result end
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
  if not (bbox and #bbox == 2 and player and player.valid) then return end
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

  if object.valid then
    Scheduler.schedule(duration_ticks, function(data)
      if object.valid then
        object.destroy()
      end
    end)
  end
end

function BlueprintHandler.on_pre_build(event)
  if not (event and event.player_index and event.position) then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  local stack = player.cursor_stack
  if not (stack and stack.valid and stack.valid_for_read) then return end
  if stack.label ~= TARGET_BLUEPRINT_NAME then return end

  local bbox = get_blueprint_bbox(stack, event.position, event.direction, event.flip_horizontal, event.flip_vertical)
  if not bbox then return end
  draw_bbox(player, bbox, 180)

  active_bboxes[event.player_index] = bbox

  Scheduler.schedule(1, function(data)
    local p = game.get_player(data.player_index)
    if p and p.valid then
      local comb = remote.call("virtual_entity", "get_or_create_entity", p, "constant-combinator", "test")
      remote.call("virtual_entity", "open_gui", p, comb)
    end
  end, { player_index = event.player_index })
end

function BlueprintHandler.on_virtual_entity_gui_close(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  if not active_bboxes[event.player_index] then return end

  local bbox = active_bboxes[event.player_index]
  active_bboxes[event.player_index] = nil
  draw_bbox(player, bbox, 180)

  --game.print("BBox чертежа: " .. serpent.line(bbox))
  local defs = {
    {name = "simple_rolling_main_cc_dst",       label = "<simple_rolling_main_cc>",       type = "constant-combinator"},
  }

  local entities = entity_finder.new(bbox, defs)

  local src = entity_control.get_control_interface(event.entity)
  local dst = entity_control.get_control_interface(entities.simple_rolling_main_cc_dst)
  dst.enabled = src.enabled
  while dst.sections_count > 0 do
      dst.remove_section(1)
  end
  for _, src_section in ipairs(src.sections) do
    local dst_section = dst.add_section(src_section.group)
    dst_section.filters = src_section.filters
    dst_section.active = src_section.active
    dst_section.multiplier = src_section.multiplier
  end
  main(bbox)
end

return BlueprintHandler
