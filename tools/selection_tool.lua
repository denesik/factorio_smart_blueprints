local main = require("main")

local selection_tool = {}

function selection_tool.on_lua_shortcut(event)
  if event.prototype_name == "rolling_button" then
    local player = game.get_player(event.player_index)
    if player and player.valid then
      if not player.cursor_stack.valid_for_read then
        player.cursor_stack.set_stack{name = "area-selection-tool"}
        player.print("Выдели область инструментом.")
      end
    end
  end
end

function selection_tool.on_player_selected_area(event)
  if event.item == "area-selection-tool" then
    local area = event.area
    local search_area = {
      {area.left_top.x, area.left_top.y},
      {area.right_bottom.x, area.right_bottom.y}
    }
    main(event.area)
  end
end

return selection_tool
