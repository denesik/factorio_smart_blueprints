local blueprint_handler = {}

local scheduler = require("common.scheduler")
local EntityFinder = require("entity_finder")
local ScenariosLibrary = require("scenarios_library")
local scenario_name_pattern = require("scenario_name_pattern")
local get_blueprint_bbox = require("blueprint_bbox")

local TARGET_BLUEPRINT_NAME = "<<smart_blueprints>>"
local ENTITY_TO_CONFIGURE_ID = "blueprint_handler"

local active_blueprints = {}

script.on_init(function()
  storage.blueprints_inventories = storage.blueprints_inventories or {}
end)

local function save_cursor_blueprint(player, blueprint)
  if not storage.blueprints_inventories[player.index] then
    storage.blueprints_inventories[player.index] = game.create_inventory(1)
  end
  local virtual_stack = storage.blueprints_inventories[player.index][1]

  if blueprint.object_name == "LuaItemStack" then
    if blueprint.blueprint_description and blueprint.blueprint_description:match("<<smart_blueprints_virtual_stack>>$") then
      player.cursor_stack.clear()
      return
    end
    virtual_stack.set_stack(blueprint)
    virtual_stack.blueprint_description = virtual_stack.blueprint_description .. "<<smart_blueprints_virtual_stack>>"
  end
  player.clear_cursor()
end

local function restore_cursor_blueprint(player)
  if not storage.blueprints_inventories[player.index] then return end
  local virtual_stack = storage.blueprints_inventories[player.index][1]

  player.cursor_stack.set_stack(virtual_stack)
  player.cursor_stack_temporary = true
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
      local name = ent.player_description:match(scenario_name_pattern)
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

  local bbox = get_blueprint_bbox(blueprint, event.position, event.direction)
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
      if blueprint.valid then
        save_cursor_blueprint(player, blueprint)
      end
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

  local success, error = pcall(function()
    ScenariosLibrary:run(data.scenario_name, player, data.bbox)
  end)
  if not success then
    game.print("Script execution error. " .. error)
  end
  restore_cursor_blueprint(player)
end

return blueprint_handler
