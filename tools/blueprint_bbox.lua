
local function get_entity_prototype_bounding_box(entity_prototype, entity_orientation, position)
  local width = entity_prototype.tile_width
  local height = entity_prototype.tile_height

  -- Swap the height/width if the entity has been rotated by 90 degrees.
  if entity_orientation == defines.direction.east or entity_orientation ==defines.direction.west then
    height, width = width, height
  end

  -- Determine the center position. Depending on whether the height/width are even or odd, it can be either in the
  -- very center of a tile or between two tiles.
  local center = {}
  if width % 2 == 0 then
    center.x = position.x >= 0 and math.floor(position.x + 0.5) or math.ceil(position.x - 0.5)
  else
    center.x = math.floor(position.x) + 0.5
  end

  if height % 2 == 0 then
    center.y = position.y >= 0 and math.floor(position.y + 0.5) or math.ceil(position.y - 0.5)
  else
    center.y = math.floor(position.y) + 0.5
  end

  -- Offset the corners based on width/height, and make sure to encircle entire tiles (just in case).
  local bounding_box = {left_top = {}, right_bottom = {}}

  bounding_box.left_top.x = math.floor(center.x - width / 2)
  bounding_box.left_top.y = math.floor(center.y - height / 2)
  bounding_box.right_bottom.x = math.ceil(center.x + width / 2)
  bounding_box.right_bottom.y = math.ceil(center.y + height / 2)

  return bounding_box
end

local function get_blueprint_dimensions(blueprint, direction)
  local blueprint_entities = blueprint.get_blueprint_entities()

  if table_size(blueprint_entities) == 0 then
    return 0, 0
  end

  -- Use center of the first blueprint entity as a starting point (corners will always expand beyond this).
  local left_top = { x = blueprint_entities[1].position.x, y = blueprint_entities[1].position.y }
  local right_bottom = { x = blueprint_entities[1].position.x, y = blueprint_entities[1].position.y }

  for _, blueprint_entity in pairs(blueprint_entities) do
    local box = get_entity_prototype_bounding_box(prototypes.entity[blueprint_entity.name], blueprint_entity.direction, blueprint_entity.position)
    left_top.x = math.min(box.left_top.x, left_top.x)
    left_top.y = math.min(box.left_top.y, left_top.y)
    right_bottom.x = math.max(box.right_bottom.x, right_bottom.x)
    right_bottom.y = math.max(box.right_bottom.y, right_bottom.y)
  end

  local width = math.ceil(right_bottom.x - left_top.x)
  local height = math.ceil(right_bottom.y - left_top.y)

  -- Swap the height/width if the blueprint has been rotated by 90 degrees.
  if direction == defines.direction.east or direction == defines.direction.west then
    width, height = height, width
  end

  return width, height
end

function get_blueprint_bbox(blueprint, position, direction)
  local width, height = get_blueprint_dimensions(blueprint, direction)

  -- Pick the larger value between blueprint (entity-based) dimensions and snap width and height to be on the safe side.
  if  blueprint.blueprint_snap_to_grid then
    local snap_width, snap_height = blueprint.blueprint_snap_to_grid.x, blueprint.blueprint_snap_to_grid.y

    if direction == defines.direction.east or direction == defines.direction.west then
      snap_width, snap_height = snap_height, snap_width
    end

    -- @TODO: Approve larger area to deal with event.position imprecision when acting upon on_pre_build event
    --   The passed-in position is normally the cursor position, which may not align with blueprint center when dragging
    --   across with tileable (snap-to-grid) blueprints. Therefore assume that the potential bounding box is twice the
    --   size of the blueprint
    width = math.max(width, snap_width * 2)
    height = math.max(height, snap_height * 2)
  end

  -- Determine the center position. Depending on whether the height/width are even or odd, it can be either in the
  -- very center of a tile or between two tiles.
  local center = {}
  if width % 2 == 0 then
    center.x = position.x >= 0 and math.floor(position.x + 0.5) or math.ceil(position.x - 0.5)
  else
    center.x = math.floor(position.x) + 0.5
  end

  if height % 2 == 0 then
    center.y = position.y >= 0 and math.floor(position.y + 0.5) or math.ceil(position.y - 0.5)
  else
    center.y = math.floor(position.y) + 0.5
  end

  -- Offset the corners based on width/height, and make sure to encircle entire tiles (just in case).
  return {
    { math.floor(center.x - width / 2), math.floor(center.y - height / 2) },
    { math.ceil(center.x + width / 2), math.ceil(center.y + height / 2) }
  }
end


return get_blueprint_bbox