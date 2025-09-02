local SignalPicker = require("signal_picker")

-- Открыть окно по команде
commands.add_command("inv", "Открыть окно выбора сигнала", function(cmd)
    local player = game.get_player(cmd.player_index)
    SignalPicker.open_1(player)
end)

-- Подписка на клики
script.on_event(defines.events.on_gui_click, SignalPicker.on_gui_click)

