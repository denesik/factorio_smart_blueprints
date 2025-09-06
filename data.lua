-- Fire Armor
local fireArmor = table.deepcopy(data.raw["armor"]["heavy-armor"])
fireArmor.name = "fire-armor"
fireArmor.icons = {
    {
        icon = fireArmor.icon,
        icon_size = fireArmor.icon_size,
        tint = {r=1,g=0,b=0,a=0.3}
    }
}
fireArmor.resistances = {
    { type = "physical", decrease = 6, percent = 10 },
    { type = "explosion", decrease = 10, percent = 30 },
    { type = "acid", decrease = 5, percent = 30 },
    { type = "fire", decrease = 0, percent = 100 }
}

-- Рецепт Fire Armor
local recipe = {
    type = "recipe",
    name = "fire-armor",
    enabled = true,
    energy_required = 8,
    ingredients = {
        {type = "item", name = "coal", amount = 17},
        {type = "item", name = "iron-plate", amount = 19},
        {type = "item", name = "iron-ore", amount = 23},
        {type = "item", name = "copper-plate", amount = 29},
        {type = "item", name = "steel-plate", amount = 31}
    },
    results = {{type = "item", name = "fire-armor", amount = 1}}
}

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

data:extend{fireArmor, recipe, selection_tool, rolling_shortcut, rolling_input}
