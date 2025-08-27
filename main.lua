local make_simple_rolling = require("scenarios/make_simple_rolling.lua")


local function main()
  local search_area = {}
  if area == nil then
    search_area = { { 0, 0 }, { 100, 100 } }
  else
    search_area = area
  end

  make_simple_rolling(search_area)

  game.print("Finish!")
end

return main