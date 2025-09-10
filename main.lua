local make_simple_rolling = require("scenarios.make_simple_rolling")

local function main(search_area)
  game.print("Start!")
  make_simple_rolling.run(search_area)
  game.print("Finish!")
end

return main