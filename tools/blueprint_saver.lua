local BlueprintSaver = {}

function BlueprintSaver.create_blueprint_string(player, area)
  -- Сохранить текущий курсор
  local cursor_backup = player.cursor_stack
  local backup_name = nil
  local backup_count = 0
  if cursor_backup.valid_for_read then
    backup_name = cursor_backup.name
    backup_count = cursor_backup.count
  end
  
  -- Создать blueprint
  player.cursor_stack.set_stack{name="blueprint", count=1}
  local blueprint = player.cursor_stack
  
  local bp_string = nil
  if blueprint and blueprint.valid_for_read and blueprint.is_blueprint then
    blueprint.create_blueprint{
      surface = player.surface,
      force = player.force,
      area = area
    }
    bp_string = blueprint.export_stack()
  end
  
  -- Восстановить курсор
  player.cursor_stack.clear()
  if backup_name then
    player.cursor_stack.set_stack{name=backup_name, count=backup_count}
  end
  
  return bp_string
end

return BlueprintSaver
