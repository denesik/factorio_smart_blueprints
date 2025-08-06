local Section = require("section")

ConstantCombinator = {}
ConstantCombinator.__index = function(self, key)
  if ConstantCombinator[key] then return ConstantCombinator[key] end
  local beh = rawget(self, "_behavior")
  if beh and beh[key] then
    if type(beh[key]) == "function" then
      return function(tbl, ...) return beh[key](beh, ...) end
    else
      return beh[key]
    end
  end
  return nil
end

--- Конструктор ConstantCombinator
-- @param obj LuaEntity
function ConstantCombinator:new(obj)
  if not obj or type(obj.get_or_create_control_behavior) ~= "function" then
    error("[ConstantCombinator] invalid object")
  end
  local behavior = obj:get_or_create_control_behavior()
  local self = {
    _behavior  = behavior,
    sections   = {},
    cc_storage = {}
  }
  setmetatable(self, ConstantCombinator)
  return self
end

--- Добавляет новую секцию сразу в игре и в sections[]
-- @param group_key string?
-- @return Section
function ConstantCombinator:add_section(group_key)
  if not self._behavior.valid then
    game.print("[ConstantCombinator] combinator not valid")
    return
  end
  local real
  if group_key and group_key ~= "" then
    real = self._behavior.add_section(group_key)
  else
    real = self._behavior.add_section()
  end
  local sc = Section:new(self._behavior, group_key, self) -- ← передаём self как parent
  rawset(sc, "_section", real)
  table.insert(self.sections, sc)
  return sc
end

--- Устанавливает накопленные фильтры во все секции
function ConstantCombinator:set_all_signals()
  for _, section in ipairs(self.sections) do
    section:set_signals()
  end
end

return ConstantCombinator
