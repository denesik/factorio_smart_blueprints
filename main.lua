local fill_all_recipes = require("scenarios/fill_all_recipes")
local make_recipes_converter = require("scenarios/make_recipes_converter")
local make_simple_crafter = require("scenarios/make_simple_crafter")
local fill_all_items = require("scenarios/fill_all_items")


local function main()
  local search_area = {}
  if area == nil then
    search_area = { { 0, 0 }, { 100, 100 } }
  else
    search_area = area
  end

  fill_all_recipes(search_area, "<cc_all_recipes>", function(e, i) e.min = i + 1000000 end)
  fill_all_items(search_area, "<cc_all_items>", function(e, i) e.min = -1000000 end)
  make_recipes_converter(search_area, "<cc_recipes_converter>", "<dc_recipes_converter>", 1000000)
  make_simple_crafter(search_area, "<cc_simple_crafter>", "<dc_simple_crafter>", "<rc_simple_crafter>", "<cc_decompose_simple_crafter>", 999)

  game.print("Finish!")
end

return main