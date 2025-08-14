import os
import re

ROOT_DIR = os.getcwd()
processed_modules = {}

# Паттерн для поиска require
require_pattern = re.compile(r'^\s*(local\s+\w+\s*=\s*)?require\s*\(?["\']([\w\.]+)["\']\)?', re.MULTILINE)

def find_lua_file(module_name):
    """Ищем lua файл по имени модуля"""
    relative_path = module_name.replace('.', os.sep) + '.lua'
    abs_path = os.path.join(ROOT_DIR, relative_path)
    if os.path.isfile(abs_path):
        return abs_path
    return None

def comment_requires(content):
    """Закомментировать все require(...) в тексте Lua"""
    def replacer(match):
        return '-- ' + match.group(0)
    return require_pattern.sub(replacer, content)

def comment_return_module(module_name, content):
    """Закомментировать return <module_name> в конце модуля"""
    lines = content.splitlines()
    if lines and re.match(rf'\s*return\s+{re.escape(module_name)}\s*$', lines[-1]):
        lines[-1] = '-- ' + lines[-1]
    return '\n'.join(lines)

def process_module(module_name):
    """Рекурсивно обрабатываем модуль и его зависимости"""
    if module_name in processed_modules:
        return ''

    file_path = find_lua_file(module_name)
    if not file_path:
        print(f"Module {module_name} not found!")
        return ''

    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Найти require внутри модуля
    requires = require_pattern.findall(content)
    requires = [m[1] for m in requires]

    # Рекурсивно вставляем зависимости
    merged = ''
    for req in requires:
        merged += process_module(req)

    # Закомментировать все require в модуле
    content = comment_requires(content)

    # Закомментировать return <module>
    content = comment_return_module(module_name, content)

    merged += f"\n-- Модуль {module_name}\n{content}\n"
    processed_modules[module_name] = True
    return merged

def extract_main_function_name(content):
    """Ищем название главной функции в главном файле"""
    match = re.search(r'function\s+(\w+)\s*\(', content)
    if match:
        return match.group(1)
    return None

def merge_lua_project(entry_file):
    """Объединяем проект в один Lua файл"""
    with open(entry_file, 'r', encoding='utf-8') as f:
        main_content = f.read()

    # Найти все require в главном файле и рекурсивно вставить их
    requires = require_pattern.findall(main_content)
    requires = [m[1] for m in requires]

    merged_code = ''
    for req in requires:
        merged_code += process_module(req)

    # Закомментировать все require в главном файле
    main_content = comment_requires(main_content)

    # Закомментировать return <имя_главного_файла>
    main_module_name = os.path.splitext(os.path.basename(entry_file))[0]
    main_content = comment_return_module(main_module_name, main_content)

    merged_code += f"\n-- Главный файл {entry_file}\n{main_content}\n"

    # Найти главную функцию
    main_func_name = extract_main_function_name(main_content)
    if main_func_name:
        main_block = f"""
-- Автоматический вызов главной функции
local function main()
  local search_area = {{}}
  if area == nil then
    search_area = {{ {{ 0, 0 }}, {{ 100, 100 }} }}
  else
    search_area = area
  end

  game.print("Start!")
  {main_func_name}(search_area)

  game.print("Finish!")
end

main()
"""
        merged_code += main_block

    return merged_code

if __name__ == "__main__":
    import sys
    if len(sys.argv) < 2:
        print("Usage: python merge_lua.py <entry_file> [<output_file>]")
        sys.exit(1)

    entry_file = sys.argv[1]

    if len(sys.argv) >= 3:
        output_file = sys.argv[2]
    else:
        # Генерируем имя автоматически: <entry_file_name>.generated.lua
        base_name = os.path.splitext(os.path.basename(entry_file))[0]
        folder = os.path.dirname(entry_file)
        output_file = os.path.join(folder, f"{base_name}.generated.lua")

    merged_code = merge_lua_project(entry_file)

    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(merged_code)

    print(f"Project successfully merged into {output_file}")
