--- Модуль с дополнительными утилитами для работы с таблицами.
-- Включает функции расширения массивов и другие вспомогательные операции с таблицами.

local table_utils = {}

--- Расширяет массив, добавляя все элементы из другой таблицы.
-- Работает аналогично `table.move` в режиме вставки в конец.
-- @param dest table Целевая таблица (массив), в которую будут добавлены элементы.
-- @param source table Источник (массив), элементы которого будут скопированы в `dest`.
function table_utils.extend(dest, source)
  for _, v in ipairs(source) do
    table.insert(dest, v)
  end
end

--- Применяет функцию fn к каждому элементу массива tbl
-- @param tbl table Массив элементов
-- @param fn function Функция обработки элемента, принимает элемент tbl[i]
function table_utils.for_each(tbl, fn)
  for i, v in ipairs(tbl) do
    fn(v, i, tbl)
  end
end

return table_utils
