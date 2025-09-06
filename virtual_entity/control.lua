local SURFACE_NAME = "virtual_entity_hidden_surface"
local PER_PLAYER_SPACING = 5

local opening_entity = {}

-- max size surface == 2'000'000 x 2'000'000
local function string_hash(str)
  local hash = 0
  for i = 1, #str do
    hash = (hash * 19 + str:byte(i)) % 2^20
  end
  return hash - 2^19
end

local function get_hidden_surface()
  local surface = game.surfaces[SURFACE_NAME]
  if surface and surface.valid then return surface end

  surface = game.create_surface(SURFACE_NAME)
  for _, f in pairs(game.forces) do
    f.set_surface_hidden(surface, true)
  end
  return surface
end

local function get_or_create_entity(player, name, id, extra_params)
  local surface = get_hidden_surface()

  local pos = { x = string_hash(name .. "-" .. id), y = player.index * PER_PLAYER_SPACING }
  for _, e in pairs(surface.find_entities_filtered{
    area = {{pos.x - 0.5, pos.y - 0.5}, {pos.x + 0.5, pos.y + 0.5}},
    name = name
  }) do
    if e.valid then
      return e
    end
  end

  local params = {}
  if extra_params then
    for k, v in pairs(extra_params) do
      params[k] = v
    end
  end
  params.name = name
  params.position = pos
  params.force = player.force

  local entity = surface.create_entity(params)
  entity.minable = false
  entity.destructible = false
  entity.operable = true
  entity.rotatable = false
  return entity
end

local function open_gui(player, entity)
  if not (player and player.valid) then return end
  if not (entity and entity.valid) then return end

  local state = {
    old_mode = player.controller_type,
    old_character = player.character,
    old_zoom = player.zoom
  }
  opening_entity[player.index] = state

  player.set_controller{ type = defines.controllers.remote }
  player.zoom = state.old_zoom

  player.opened = entity
end

local function close_gui(ev)
  local player_index = ev.player_index
  local state = opening_entity[player_index]
  if not state then return end

  local player = game.get_player(player_index)
  if not (player and player.valid) then return end

  player.set_controller{ type = state.old_mode, character = state.old_character }
  player.zoom = state.old_zoom

  opening_entity[player_index] = nil
end

script.on_event(defines.events.on_gui_closed, close_gui)
script.on_event(defines.events.on_player_changed_surface, close_gui)
script.on_event(defines.events.on_player_died, close_gui)

commands.add_command("open-hidden-comb", "Open your hidden personal combinator", function(cmd)
  local player = game.get_player(cmd.player_index)
  if player and player.valid then
    local comb = get_or_create_entity(player, "constant-combinator", "test")
    open_gui(player, comb)
  end
end)
