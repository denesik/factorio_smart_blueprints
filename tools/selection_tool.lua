local selection_tool = {}

local EntityFinder = require("entity_finder")
local ScenariosLibrary = require("scenarios_library")
local scenario_name_pattern = require("scenario_name_pattern")

function selection_tool.on_lua_shortcut(event)
  if event.prototype_name == "rolling_button" then
    local player = game.get_player(event.player_index)
    if player then
      player.cursor_stack.set_stack{name = "area-selection-tool"}
    end
  end
end

function selection_tool.on_player_selected_area(event)
  if event.item == "area-selection-tool" then

    local types = {
      "constant-combinator",
      "decider-combinator",
      "arithmetic-combinator",
      "selector-combinator"
    }
    local entities = EntityFinder.find_entities(event.surface, event.area, types)
    for _, ent in pairs(entities) do
      if ent.combinator_description then
        local name = ent.combinator_description:match(scenario_name_pattern)
        if name then
          ScenariosLibrary:run(name, event.surface, event.area)
          return
        end
      end
    end

  end
end

return selection_tool
