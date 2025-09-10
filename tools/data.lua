-- Инструмент выделения области
local selection_tool = {
  type = "selection-tool",
  name = "area-selection-tool",
  icons = {
    {
      icon = "__CombinatorFiller__/graphics/icons/selection-tool.png",
      icon_size = 64
    }
  },
  select = {
    mode = {"any-entity"},
    entities = nil,
    border_color = {r = 0, g = 1, b = 0},
    cursor_box_type = "entity"
  },
  alt_select = {
    mode = {"any-entity"},
    entities = nil,
    border_color = {r = 1, g = 0, b = 0},
    cursor_box_type = "entity"
  },
  stack_size = 1,
  spawnable = true
}

-- Shortcut для инструмента (правильный формат)
local rolling_shortcut = {
  type = "shortcut",
  name = "rolling_button",
  action = "lua",
  toggleable = true,
  associated_control_input = "rolling_button_input",
  icon = "__CombinatorFiller__/graphics/icons/selection-tool.png", -- большая иконка
  small_icon = "__CombinatorFiller__/graphics/icons/selection-tool.png" -- маленькая иконка для интерфейса
}

-- Control input для shortcut
local rolling_input = {
  type = "custom-input",
  name = "rolling_button_input",
  key_sequence = "", -- пусто, игрок сам может назначить
  consuming = "none"
}

data:extend{selection_tool, rolling_shortcut, rolling_input}
