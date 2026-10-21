import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Мониторы: разрешение и частота, масштаб, счётчик кадров.
// Изменение применяется сразу (hyprctl eval) с отсчётом «Оставить?» — без подтверждения через 15 с вернётся прежний режим.
// «Сохранить» пишет ~/.config/hypr/monitors.lua — его подключает hyprland.lua при запуске
PanelWindow {
    id: w
    property var shell: null
    readonly property bool open: shell ? shell.displayOpen : false
    function close() { if (shell) shell.displayOpen = false; }
    property real progress: 0
    Component.onCompleted: {
        progress = Qt.binding(function () { return w.open ? 1 : 0; });
        reload();
    }
    Behavior on progress { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    visible: progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-display"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    onOpenChanged: if (open) reload()

    // ---------- данные ----------
    property var monitors: []
    property int sel: 0
    readonly property var mon: monitors.length > 0 ? monitors[Math.min(sel, monitors.length - 1)] : null
    Process {
        id: monProc
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector { onStreamFinished: { try { w.monitors = JSON.parse(text); } catch (e) { w.monitors = []; } } }
    }
    function reload() { if (Compositor.hyprland && !monProc.running) monProc.running = true; }

    function modeOf(m) { return m.width + "x" + m.height + "@" + m.refreshRate.toFixed(2); }
    function rule(m, mode, scale) {
        return "hl.monitor({ output = \"" + m.name + "\", mode = \"" + mode + "\", position = \"" + m.x + "x" + m.y + "\", scale = " + scale + " })";
    }

    // ---------- применение с подтверждением ----------
    property string pendingRevert: ""      // правило прежнего режима
    property int countdown: 0
    Timer {
        id: tick
        interval: 1000; repeat: true
        onTriggered: { w.countdown--; if (w.countdown <= 0) w.revert(); }
    }
    function apply(mode, scale) {
        if (!mon) return;
        pendingRevert = rule(mon, modeOf(mon), mon.scale);
        Quickshell.execDetached(["hyprctl", "eval", rule(mon, mode, scale)]);
        countdown = 15; tick.restart();
        refreshT.restart();
    }
    function keep() { tick.stop(); pendingRevert = ""; countdown = 0; }
    function revert() {
        tick.stop();
        if (pendingRevert !== "") Quickshell.execDetached(["hyprctl", "eval", pendingRevert]);
        pendingRevert = ""; countdown = 0;
        refreshT.restart();
    }
    Timer { id: refreshT; interval: 600; onTriggered: w.reload() }

    // сохранить текущие режимы всех мониторов в monitors.lua
    function save() {
        var lines = [Tr.t("-- Мониторы (сохранено NameLess UI → Мониторы)")];
        for (var i = 0; i < monitors.length; i++) lines.push(rule(monitors[i], modeOf(monitors[i]), monitors[i].scale));
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$@\" > \"$HOME/.config/hypr/monitors.lua\"", "sh"].concat(lines));
        savedNote.restart();
    }
    property bool saved: savedNote.running
    Timer { id: savedNote; interval: 2500 }

    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * 0.6 * w.progress }
    MouseArea { anchors.fill: parent; onClicked: w.close() }

    Surface {
        id: panel
        width: 420
        height: col.implicitHeight + 32
        x: parent.width - width - 10
        y: 48 + (1 - w.progress) * -20
        opacity: w.progress
        radius: Theme.ios ? 30 : 22
        alpha: Theme.overlayAlpha
        MouseArea { anchors.fill: parent }
        MoveArea { win: panel; anchors { left: parent.left; right: parent.right; top: parent.top } height: 56 }
        focus: w.open
        Keys.onEscapePressed: w.close()

        Column {
            id: col
            x: 16; y: 16
            width: parent.width - 32
            spacing: 14

            Row {
                width: parent.width
                Text {
                    width: parent.width - backBtn.width
                    text: Tr.t("Мониторы")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.ios ? 22 : 19
                    font.weight: Font.Bold
                }
                GTile {
                    id: backBtn
                    ui: Theme
                    width: 32; height: 32; radius: 16
                    Text { anchors.centerIn: parent; text: "✕"; color: Theme.text; font.pixelSize: 12 }
                    onClicked: w.close()
                }
            }

            Text {
                visible: !Compositor.hyprland
                width: parent.width
                wrapMode: Text.WordWrap
                text: Tr.t("Настройка мониторов здесь — для Hyprland. В ") + Compositor.name + Tr.t(" мониторы задаются его конфигом.")
                color: Theme.sub
                font.family: Theme.font
                font.pixelSize: 12
            }

            // выбор монитора
            GSegment {
                visible: w.monitors.length > 1
                ui: Theme
                options: w.monitors.map(function (m, i) { return { v: String(i), t: m.name }; })
                value: String(w.sel)
                onPicked: (v) => w.sel = Number(v)
            }

            // текущий монитор
            Item {
                visible: w.mon !== null
                width: parent.width
                height: 64
                Rectangle { anchors.fill: parent; radius: Theme.r(18); color: Theme.fill(0.07); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.14) }
                Row {
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "󰍹"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 26 }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: w.mon ? w.mon.name + " · " + (w.mon.description || "") : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text {
                            text: w.mon ? w.mon.width + "×" + w.mon.height + " · " + Math.round(w.mon.refreshRate) + Tr.t(" Гц · масштаб ") + w.mon.scale.toFixed(2) : ""
                            color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 }
                        }
                    }
                }
            }

            // режимы: разрешение и частота
            Text { visible: w.mon !== null; text: Tr.t("Разрешение и частота"); color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
            Flow {
                visible: w.mon !== null
                width: parent.width
                spacing: 8
                Repeater {
                    model: w.mon ? w.mon.availableModes : []
                    GTile {
                        id: mt
                        required property string modelData
                        readonly property string mode: modelData.replace("Hz", "")
                        ui: Theme
                        width: modeText.implicitWidth + 24
                        height: 34
                        radius: 17
                        on: w.mon && Math.abs(parseFloat(mode.split("@")[1]) - w.mon.refreshRate) < 0.5
                            && mode.split("@")[0] === (w.mon.width + "x" + w.mon.height)
                        Text {
                            id: modeText
                            anchors.centerIn: parent
                            text: mt.mode.split("@")[0].replace("x", "×") + " · " + Math.round(parseFloat(mt.mode.split("@")[1])) + Tr.t(" Гц")
                            color: mt.on ? "white" : Theme.text
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.features: { "tnum": 1 }
                        }
                        onClicked: if (!on) w.apply(mode, w.mon.scale)
                    }
                }
            }

            // масштаб
            Text { visible: w.mon !== null; text: Tr.t("Масштаб"); color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
            GSegment {
                visible: w.mon !== null
                ui: Theme
                options: [1, 1.25, 1.5, 1.75, 2].map(function (s) { return { v: String(s), t: Math.round(s * 100) + " %" }; })
                value: w.mon ? String([1, 1.25, 1.5, 1.75, 2].reduce(function (a, b) { return Math.abs(b - w.mon.scale) < Math.abs(a - w.mon.scale) ? b : a; })) : ""
                onPicked: (v) => w.apply(w.modeOf(w.mon), Number(v))
            }

            // подтверждение нового режима
            Item {
                visible: w.countdown > 0
                width: parent.width
                height: 54
                Rectangle { anchors.fill: parent; radius: Theme.r(18); color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18); border.width: 1; border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5) }
                Text {
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    text: Tr.t("Оставить? Вернётся через ") + w.countdown + Tr.t(" с")
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                Row {
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    GButton { ui: Theme; label: Tr.t("Вернуть"); implicitHeight: 34; onClicked: w.revert() }
                    GButton { ui: Theme; label: Tr.t("Оставить"); on: true; implicitHeight: 34; onClicked: w.keep() }
                }
            }

            GSwitch {
                ui: Theme
                width: parent.width
                label: Tr.t("Счётчик кадров в баре")
                sub: Tr.t("частота монитора и FPS; бар перерисовывается каждый кадр")
                checked: Theme.th.fps_counter === true
                onToggled: (v) => Quickshell.execDetached([Theme.script, "set", ".fps_counter", v ? "true" : "false"])
            }

            Row {
                visible: Compositor.hyprland
                spacing: 8
                GButton { ui: Theme; icon: "󰆓"; label: w.saved ? Tr.t("Сохранено") : Tr.t("Сохранить"); onClicked: w.save() }
                GButton { ui: Theme; icon: "󰑓"; label: Tr.t("Обновить"); onClicked: w.reload() }
            }
        }
    }
}
