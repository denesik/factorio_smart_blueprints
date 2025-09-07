local make_simple_rolling = require("scenarios/make_simple_rolling.lua")
local table_utils         = require("table_utils")


local function main(search_area)
  game.print("Start!")
  make_simple_rolling(search_area)
  game.print("Finish!")
end

return main