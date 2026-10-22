pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Общий слой над композитором: NameLess UI работает и в Hyprland, и в driftwm.
// Hyprland — рабочие столы и команды через его IPC; другие (driftwm: бесконечный холст) — без рабочих столов,
// окна — через общий протокол wlr-foreign-toplevel
Singleton {
    id: c

    readonly property bool hyprland: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== ""
    readonly property string name: hyprland ? "Hyprland" : (Quickshell.env("XDG_CURRENT_DESKTOP") || "Wayland")

    // рабочие столы (только Hyprland): обычные, по порядку
    readonly property var workspaces: {
        if (!hyprland) return [];
        var out = [], ws = Hyprland.workspaces.values;
        for (var i = 0; i < ws.length; i++) if (ws[i].id > 0) out.push(ws[i]);
        out.sort(function (a, b) { return a.id - b.id; });
        return out;
    }
    readonly property int activeWorkspace: hyprland && Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0

    // стол закрыт окнами: живой фон (небо, космос) останавливает анимацию — по модели Hyprland, без вызовов hyprctl
    readonly property bool covered: hyprland && Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.toplevels.values.length > 0

    readonly property var activeWindow: ToplevelManager.activeToplevel
    readonly property string rawTitle: activeWindow ? (activeWindow.title || activeWindow.appId || "") : ""
    // Заголовок в баре. Терминалы и Claude Code крутят в начале заголовка значок «занят» (◐ ◑ ◒ ◓, ⠋…) по нескольку раз в секунду:
    // каждая смена перерисовывала бар вместе с размытием под ним (~20 % ядра у NameLess и ~50 % iGPU у Hyprland).
    // Значок убирается, а оставшееся обновляется не чаще раза в 0,7 с
    property string activeTitle: ""
    function cleanTitle(t) { return t.replace(/^[\u2190-\u21FF\u2500-\u27BF\u2800-\u28FF\u2B00-\u2BFF\u25CF\u2022]+\s*/, ""); }
    onRawTitleChanged: {
        var c = cleanTitle(rawTitle);
        if (c === activeTitle) return;
        if (activeTitle === "" || c === "") activeTitle = c; else titleT.restart();
    }
    onActiveWindowChanged: activeTitle = cleanTitle(rawTitle)
    Timer { id: titleT; interval: 700; onTriggered: activeTitle = cleanTitle(c.rawTitle) }

    // раскладка клавиатуры: Hyprland — через hyprctl, driftwm — через его IPC (`driftwm msg layout` и действие switch-layout)
    readonly property string layoutQuery: hyprland
        ? "hyprctl -j devices 2>/dev/null | jq -r '[.keyboards[] | select(.main)][0].active_keymap // empty' 2>/dev/null"
        : "driftwm msg layout 2>/dev/null"
    function nextLayout() {
        if (hyprland) Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"]);
        else Quickshell.execDetached(["driftwm", "msg", "action", "switch-layout", "next"]);
    }

    function focusWorkspace(id) {
        if (hyprland) Hyprland.dispatch("hl.dsp.focus({ workspace = " + id + " })");
    }
    // шаг по столам своего монитора («m»): «e» шёл по столам всех мониторов и по пути заскакивал на стол виртуального монитора второго экрана —
    // фокус и курсор улетали на невидимый экран, а следующий стол открывался уже на нём и вытеснял показ
    function stepWorkspace(dir) {
        if (hyprland) Hyprland.dispatch("hl.dsp.focus({ workspace = \"m" + (dir > 0 ? "+1" : "-1") + "\" })");
    }
    function logout() {
        if (hyprland) Hyprland.dispatch("hl.dsp.exit()");
        else Quickshell.execDetached(["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\""]);
    }
}
