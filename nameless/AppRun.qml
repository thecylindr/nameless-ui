pragma Singleton
import QtQuick
import Quickshell

// Запуск программ из лаунчера, дока и мастера программ. Через qs-app.sh: программа получает окружение сессии, а не
// облегчённое окружение самого Quickshell (qs-light.sh). Без скрипта или для приложений в терминале — обычный execute()
Singleton {
    readonly property string wrapper: Quickshell.env("HOME") + "/.config/hypr/Scripts/qs-app.sh"
    function run(e) {
        if (!e) return;
        if (e.runInTerminal || !e.command || e.command.length === 0) { e.execute(); return; }
        Quickshell.execDetached({ command: [wrapper].concat(e.command), workingDirectory: e.workingDirectory || Quickshell.env("HOME") });
    }
}
