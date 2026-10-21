pragma Singleton
import QtQuick
import Quickshell

// Режим производительности. Экономный: частота живых фонов 30 кадров вместо 60, без мерцания звёзд и метеоров,
// реже опрос нагрузки и диспетчера. «Авто» включает его, пока ноутбук работает от батареи (Config.store.perf.mode: auto | normal | eco)
Singleton {
    readonly property string mode: Config.store.perf.mode || "auto"
    readonly property bool eco: mode === "eco" || (mode === "auto" && Sys.hasBattery && !Sys.charging)
    readonly property int fps: eco ? 30 : 60
}
