-- <НЕ РЕАЛИЗОВАНО!> Максимум секций 100 ед. в постоянном комбинаторе !!!

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

--- Добавляет массив записей в cc_storage (агрегирует по сумме min)
-- @param entries table[] — каждый элемент: {name=string, min=number?, quality=string?, type=string?}
function ConstantCombinator:add_signals_to_cc_storage(entries)
  for _, entry in ipairs(entries) do
    if not entry.name then
      error("[ConstantCombinator] 'name' must be set")
    end
    local min = entry.min or 0
    if type(min) ~= "number" then
      error("[ConstantCombinator] 'min' must be a number")
    end
    local quality = entry.quality or qualities[1]
    local typ = Utils.get_type(entry.name, entry.type)
    if not typ then
      game.print("[ConstantCombinator] unknown signal name: " .. tostring(entry.name))
    else
      Utils.add_signal_to_storage(self.cc_storage, {
        name = entry.name,
        quality = quality,
        type = typ,
        min = min
      })
    end
  end
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

--- Копирует сигналы из cc_storage по фильтрам и пользовательскому порядку в target
-- @param filters table, где каждый filters[field] может быть:
--    • nil — не фильтровать и без порядка
--    • множество {[value]=true} — фильтровать по ключам, без порядка
--    • массив {"v1","v2",…} — фильтровать по этому списку и именно в этом порядке
-- @param target Section|string|string[] — куда класть сигналы
-- @return Section[] — список получившихся секций
function ConstantCombinator:copy_filtered_signals(filters, target)
  -- 1) Построить include-множества и order-списки
  local include = {}
  local order   = {}
  for _, field in ipairs { "name", "quality", "type" } do
    local f = filters[field]
    if type(f) == "table" then
      if #f > 0 then
        -- массив: фильтр + порядок
        include[field] = {}
        for _, v in ipairs(f) do include[field][v] = true end
        order[field] = f
      else
        -- множество: только фильтр
        include[field] = f
      end
    end
  end

  -- 2) Собрать «matched» в виде matched[name][quality][type] = sum
  local matched = {}
  for name, quals in pairs(self.cc_storage) do
    if not include.name or include.name[name] then
      for quality, types in pairs(quals) do
        if not include.quality or include.quality[quality] then
          for typ, sum_min in pairs(types) do
            if not include.type or include.type[typ] then
              matched[name]               = matched[name] or {}
              matched[name][quality]      = matched[name][quality] or {}
              matched[name][quality][typ] = sum_min
            end
          end
        end
      end
    end
  end
  if not next(matched) then return game.print("[ConstantCombinator] copy_filtered_signals: nothing matched") and {} end
  -- if not next(matched) then error("copy_filtered_signals: nothing matched") end
  local result = {}

  -- 3a) Если target — Section, просто заполняем его storage
  if type(target) == "table" and type(target.add_signals) == "function" then
    for name, quals in pairs(matched) do
      for quality, types in pairs(quals) do
        for typ, sum_min in pairs(types) do
          target.storage[name]               = target.storage[name] or {}
          target.storage[name][quality]      = target.storage[name][quality] or {}
          target.storage[name][quality][typ] = sum_min
        end
      end
    end
    table.insert(result, target)
    return result
  end

  -- 3b) Если target — string, создаём одну новую секцию с этим именем
  if type(target) == "string" then
    local sc = self:add_section(target)
    for name, quals in pairs(matched) do
      for quality, types in pairs(quals) do
        for typ, sum_min in pairs(types) do
          sc.storage[name]               = sc.storage[name] or {}
          sc.storage[name][quality]      = sc.storage[name][quality] or {}
          sc.storage[name][quality][typ] = sum_min
        end
      end
    end
    table.insert(result, sc)
    return result
  end

  -- 3c) Если target — array of strings, авто-распределение по комбинациям этих полей
  if type(target) == "table" then
    -- убедиться, что это именно массив полей
    local is_array = true
    for i = 1, #target do
      if type(target[i]) ~= "string" then
        is_array = false; break
      end
    end
    if is_array then
      -- 3c.1) собрать уникальные комбинации dims[field]=value
      local combos = {}
      local seen   = {}
      for name, quals in pairs(matched) do
        for quality, types in pairs(quals) do
          for typ, sum_min in pairs(types) do
            local dims = {}
            for _, field in ipairs(target) do
              if field == "name" then
                dims[field] = name
              elseif field == "quality" then
                dims[field] = quality
              else
                dims[field] = typ
              end
            end
            -- ключ для уникальности
            local parts = {}
            for _, field in ipairs(target) do parts[#parts + 1] = dims[field] end
            local key = table.concat(parts, "|")
            if not seen[key] then
              seen[key]           = true
              combos[#combos + 1] = dims
            end
          end
        end
      end

      -- 3c.2) отсортировать combos по user-order
      table.sort(combos, function(a, b)
        for _, field in ipairs(target) do
          local va, vb = a[field], b[field]
          local ord    = order[field]
          if ord then
            -- найти индексы в ord
            local ia, ib
            for idx, v in ipairs(ord) do
              if v == va then ia = idx end
              if v == vb then ib = idx end
            end
            if ia and ib and ia ~= ib then return ia < ib end
            if ia and not ib then return true end
            if ib and not ia then return false end
          end
          -- fallback: лексикографический
          if va ~= vb then return va < vb end
        end
        return false
      end)

      -- 3c.3) создать секцию на каждую комбинацию и скопировать туда свои записи
      for _, dims in ipairs(combos) do
        local sc = self:add_section("")
        result[#result + 1] = sc
        for name, quals in pairs(matched) do
          for quality, types in pairs(quals) do
            for typ, sum_min in pairs(types) do
              local ok = true
              for _, field in ipairs(target) do
                local val = (field == "name" and name)
                    or (field == "quality" and quality)
                    or typ
                if dims[field] ~= val then
                  ok = false; break
                end
              end
              if ok then
                sc.storage[name]               = sc.storage[name] or {}
                sc.storage[name][quality]      = sc.storage[name][quality] or {}
                sc.storage[name][quality][typ] = sum_min
              end
            end
          end
        end
      end

      return result
    end
  end

  error("copy_filtered_signals: invalid target")
end

--- Обновляет значения в cc_storage по фильтрам
-- @param filters { name=table?, quality=table?, type=table? }  — nil-поля не фильтруют
-- @param delta   number|function(old_value)->new_value
function ConstantCombinator:update_cc_storage(filters, delta)
  for name, quals in pairs(self.cc_storage) do
    if not filters.name or filters.name[name] then
      for quality, types in pairs(quals) do
        if not filters.quality or filters.quality[quality] then
          for typ, old in pairs(types) do
            if not filters.type or filters.type[typ] then
              local new
              if type(delta) == "function" then
                new = delta(old)
              else
                new = old + delta
              end
              self.cc_storage[name][quality][typ] = new
            end
          end
        end
      end
    end
  end
end

--- Устанавливает накопленные фильтры во все секции
function ConstantCombinator:set_all_signals()
  for _, section in ipairs(self.sections) do
    section:set_signals()
  end
end

--- Поочерёдно применяет fn к подмножествам cc_storage,
--- разбивая по каждому значению в фильтре в том порядке, как задано в literal.
--- Если filter пустой (`{}`), то fn применяется ко всем значениям в cc_storage.
-- @param filter table, где filter[field] может быть:
--    • массив {"v1","v2",…} — фильтрация + пользовательский порядок
--    • множество {[v1]=true, …} — фильтрация без гарантии порядка
-- @param fn     function(old)->new
function ConstantCombinator:update_by_filter(filter, fn)
  -- Если фильтр пуст — обновить всё cc_storage
  if not next(filter) then
    self:update_cc_storage({}, fn)
    return
  end

  for field, values in pairs(filter) do
    local list = {}
    if type(values) == "table" and #values > 0 then
      for _, v in ipairs(values) do
        list[#list + 1] = v
      end
    elseif type(values) == "table" then
      for v in pairs(values) do
        list[#list + 1] = v
      end
    else
      error("update_by_filter: filter[" .. tostring(field) .. "] must be a table")
    end

    for _, val in ipairs(list) do
      self:update_cc_storage({ [field] = { [val] = true } }, fn)
    end
  end
end

--- Возвращает cc_storage в развёрнутом виде
-- @return table[] — массив { name=string, quality=string, type=string, min=number }
function ConstantCombinator:get_cc_storage()
  local result = {}
  for name, qualities in pairs(self.cc_storage) do
    for quality, types in pairs(qualities) do
      for typ, min in pairs(types) do
        table.insert(result, {
          name    = name,
          quality = quality,
          type    = typ,
          min     = min
        })
      end
    end
  end
  return result
end

return ConstantCombinator
