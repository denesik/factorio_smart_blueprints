local Utils = require("utils")

local Section = {}

Section.__index = function(self, key)
  if Section[key] then return Section[key] end
  local first = self._sections and self._sections[1]
  if first and first[key] then
    if type(first[key]) == "function" then
      return function(tbl, ...) return first[key](first, ...) end
    else
      return first[key]
    end
  end
  return nil
end

--- Конструктор «абстрактной» секции
-- @param control_behavior LuaConstantCombinatorombinatorControlBehavior
-- @param group_key string?
-- @param parent ConstantCombinator?
function Section:new(control_behavior, group_key, parent)
  local obj = {
    _control  = control_behavior,
    group_key = group_key or "",
    storage   = {},
    _parent   = parent,
    _sections = {} -- множество real-секций
  }
  setmetatable(obj, Section)
  return obj
end

--- Нормализует одну запись
-- @param entry {name=string, min=number?, quality=string?, type=string?}
-- @return {name, quality, type, min} или nil
function Section:normalize(entry)
  if not entry.name then error("[Section] 'name' must be set") end
  local min = entry.min or 0
  if type(min) ~= "number" then error("[Section] 'min' must be a number") end
  local quality = entry.quality or qualities[1]
  local typ = Utils.get_type(entry.name, entry.type)
  if not typ then
    game.print("[Section] unknown signal name: " .. tostring(entry.name))
    return nil
  end
  return { name = entry.name, quality = quality, type = typ, min = min }
end

--- Добавляет массив записей в storage (аггрегирует по сумме min)
-- @param entries table[]
function Section:add_signals(entries)
  for _, entry in ipairs(entries) do
    local norm = self:normalize(entry)
    if norm then
      Utils.add_signal_to_storage(self.storage, norm)
    end
  end
end

--- Создаёт real-секцию один раз и обновляет её фильтры
function Section:set_signals()
  local control = self._control
  if not control.valid then
    game.print("[Section] combinator not valid")
    return
  end

  -- Собираем flat_signals из storage
  local flat_signals = {}
  for name, quals in pairs(self.storage) do
    for quality, types in pairs(quals) do
      for typ, sum_min in pairs(types) do
        table.insert(flat_signals, {
          value = { name = name, type = typ, quality = quality },
          min   = sum_min
        })
      end
    end
  end

  if #flat_signals == 0 then
    -- Нет сигналов — ничего не делаем, существующая секция остаётся как есть
    return
  end

  local MAX_PER_SECTION = 1000
  local total = #flat_signals
  local i = 1

  -- ⬇ Используем уже привязанную секцию, если она есть и стоит на первой позиции ⬇
  if self._section then
    local count = math.min(total, MAX_PER_SECTION)
    local slice = {}
    for j = 1, count do
      slice[j] = flat_signals[j]
    end
    self._section.filters = slice
    i = count + 1
  end

  -- ⬇ Добавляем дополнительные секции только при переполнении ⬇
  while i <= total do
    local slice = {}
    for j = i, math.min(i + MAX_PER_SECTION - 1, total) do
      slice[#slice + 1] = flat_signals[j]
    end

    local section
    -- Для новых секций используем любой способ создания
    if self.group_key and #self._sections == 0 then
      section = control.add_section(self.group_key)
    else
      section = control.add_section()
    end

    section.filters = slice
    table.insert(self._sections, section)
    i = i + MAX_PER_SECTION
  end
end

return Section