local Utils = require("utils")
local Set = require("set")
local ConstantCombinator = require("constant_combinator")
local Initial = require("initial")

local function main()
  --#region ▼ Вызовы инициализации

  if area == nil then
    area = { { 0, 0 }, { 100, 100 } }
  end

  area = area

  qualities = {} -- ☆ Список всех имен существующих качеств в виде строки
  for _, proto in pairs(prototypes.quality) do
    if proto.hidden == false then
      table.insert(qualities, proto.name)
    end
  end

  global_recipe_table = Initial.global_recipe_filtered()
  global_resource_table = Initial.global_item_or_fluid_filtered()

  --#endregion ▲ Вызовы инициализации

  local usefull_recipes = Set.I(global_recipe_table.usefull_recipes, global_recipe_table.machines
    ["assembling-machine-3"], global_recipe_table.recipes_with_main)

  -- Списки И, ИП, П
  local classify_ingredients = Utils.get_classify_ingredients(usefull_recipes)

  local function process_all_resource_limit(cc)
    local all_resource_am = Set.U(classify_ingredients.exclusively_ingredients,
      classify_ingredients.ingredients_and_products, classify_ingredients.exclusively_products)
    local section = cc:add_section("")
    for resource_name, _ in pairs(all_resource_am) do
      section:add_signals({ { name = resource_name, quality = qualities[1], min = -2 ^ 31 } })
    end
    cc:set_all_signals()
  end

  local found = Utils.findSpecialEntity("<all_resource_limit>", { name = { "constant-combinator" } })
  if #found ~= 0 then
    process_all_resource_limit(ConstantCombinator:new(found[1]))
  end

  game.print("Finish!")
end

return main