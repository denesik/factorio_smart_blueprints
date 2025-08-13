local fill_all_recipes = require("scenarios/fill_all_recipes")
local make_recipes_converter = require("scenarios/make_recipes_converter")
local make_rolling_machine = require("scenarios/make_rolling_machine.lua")
local fill_all_items = require("scenarios/fill_all_items")
local game_utils = require("game_utils")


local function main()
  local search_area = {}
  if area == nil then
    search_area = { { 0, 0 }, { 100, 100 } }
  else
    search_area = area
  end

  local all_items_filler = function(e, i)
    local quality_num = game_utils.get_quality_index(e.value.quality) - 1
    local quality_offset = 10000 * quality_num
    e.min = 1000000 + i + quality_offset
  end

  --fill_all_items(search_area, "<cc_all_items>", all_items_filler)
  --fill_all_recipes(search_area, "<cc_all_recipes>", all_items_filler)

  --make_recipes_converter(search_area, "<cc_recipes_converter>", "<dc_recipes_converter>", 1000000)

  --make_simple_crafter(search_area, "<cc_simple_crafter>", "<dc_simple_crafter>", 
  --                    "<rc_simple_crafter>", "<cc_decompose_simple_crafter>", "<dc_recycler_simple_crafter>", 999)

  make_rolling_machine(search_area, "<cc_simple_crafter>", "<dc_simple_crafter>", 
                      "<rc_simple_crafter>", "<cc_decompose_simple_crafter>", "<dc_recycler_simple_crafter>", 999)

  game.print("Finish!")
end

return main