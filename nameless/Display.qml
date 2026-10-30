import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Мониторы: разрешение, частота (из тех, что монитор умеет при этом разрешении), масштаб, счётчик кадров.
//   Hyprland — hyprctl (eval); driftwm и другие wlroots-композиторы — wlr-randr (протокол wlr-output-management).
// Изменение применяется сразу с отсчётом «Оставить?» — без подтверждения через 15 с вернётся прежний режим.
// «Сохранить»: Hyprland — ~/.config/hypr/monitors.lua (его подключает hyprland.lua); driftwm — [[outputs]] в ~/.config/driftwm/config.toml
PanelWindow {
    id: w
    screen: Compositor.panelScreen
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
    // мониторы в одном виде для обоих путей: { name, description, width, height, refreshRate, scale, x, y, availableModes: ["WxH@RHz"] }
    Process {
        id: monProc
        command: Compositor.hyprland ? ["hyprctl", "-j", "monitors"] : ["wlr-randr", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = [];
                try { l = JSON.parse(text); } catch (e) { }
                if (!Compositor.hyprland) l = l.filter(function (o) { return o.enabled !== false; }).map(function (o) {
                    var cur = (o.modes || []).filter(function (m) { return m.current; })[0] || (o.modes || [])[0] || { width: 0, height: 0, refresh: 0 };
                    return { name: o.name, description: o.description || ((o.make || "") + " " + (o.model || "")), width: cur.width, height: cur.height, refreshRate: cur.refresh,
                             scale: o.scale || 1, x: (o.position || {}).x || 0, y: (o.position || {}).y || 0,
                             availableModes: (o.modes || []).map(function (m) { return m.width + "x" + m.height + "@" + m.refresh.toFixed(3) + "Hz"; }) };
                });
                w.monitors = l.filter(function (m) { return String(m.name).indexOf("HEADLESS") !== 0; });
            }
        }
    }
    property bool noRandr: false
    Process { id: randrCheck; running: !Compositor.hyprland; command: ["sh", "-c", "command -v wlr-randr >/dev/null || echo no"]; stdout: StdioCollector { onStreamFinished: w.noRandr = text.trim() === "no" } }
    function reload() { if (!monProc.running) monProc.running = true; }

    function modeOf(m) { return m.width + "x" + m.height + "@" + m.refreshRate.toFixed(2); }
    function rule(m, mode, scale) {
        return "hl.monitor({ output = \"" + m.name + "\", mode = \"" + mode + "\", position = \"" + m.x + "x" + m.y + "\", scale = " + scale + " })";
    }
    // команда смены режима: Hyprland — eval правила, иначе — wlr-randr
    function cmdFor(m, mode, scale) {
        if (Compositor.hyprland) return ["hyprctl", "eval", rule(m, mode, scale)];
        return ["wlr-randr", "--output", m.name, "--mode", mode.split("@")[0] + "@" + parseFloat(mode.split("@")[1]).toFixed(3) + "Hz", "--scale", String(scale)];
    }

    // режимы монитора: разрешения (по убыванию) и частоты для выбранного разрешения
    readonly property var resolutions: {
        if (!mon) return [];
        var out = [];
        (mon.availableModes || []).forEach(function (m) { var r = m.split("@")[0]; if (out.indexOf(r) < 0) out.push(r); });
        out.sort(function (a, b) { var A = a.split("x"), B = b.split("x"); return B[0] * B[1] - A[0] * A[1]; });
        return out;
    }
    property string pickRes: ""
    readonly property string curRes: mon ? mon.width + "x" + mon.height : ""
    readonly property string shownRes: pickRes !== "" ? pickRes : curRes
    readonly property var rates: {
        if (!mon) return [];
        var out = [];
        (mon.availableModes || []).forEach(function (m) {
            var p = m.replace("Hz", "").split("@");
            if (p[0] === w.shownRes && out.every(function (r) { return Math.abs(r - parseFloat(p[1])) > 0.05; })) out.push(parseFloat(p[1]));
        });
        return out.sort(function (a, b) { return b - a; });
    }
    onSelChanged: pickRes = ""

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
        pendingRevert = JSON.stringify(cmdFor(mon, modeOf(mon), mon.scale));
        Quickshell.execDetached(cmdFor(mon, mode, scale));
        pickRes = "";
        countdown = 15; tick.restart();
        refreshT.restart();
    }
    function keep() { tick.stop(); pendingRevert = ""; countdown = 0; }
    function revert() {
        tick.stop();
        if (pendingRevert !== "") Quickshell.execDetached(JSON.parse(pendingRevert));
        pendingRevert = ""; countdown = 0;
        refreshT.restart();
    }
    Timer { id: refreshT; interval: 600; onTriggered: w.reload() }

    // сохранить текущие режимы всех мониторов: Hyprland — monitors.lua; driftwm — mode и scale в блоках [[outputs]] его config.toml
    function save() {
        if (Compositor.hyprland) {
            var lines = [Tr.t("-- Мониторы (сохранено NameLess UI → Мониторы)")];
            for (var i = 0; i < monitors.length; i++) lines.push(rule(monitors[i], modeOf(monitors[i]), monitors[i].scale));
            Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$@\" > \"$HOME/.config/hypr/monitors.lua\"", "sh"].concat(lines));
        } else {
            // блок монитора заменяется целиком (name, mode, scale), остальные строки конфига не трогаются
            var args = [];
            monitors.forEach(function (m) { args.push(m.name, m.width + "x" + m.height + "@" + Math.round(m.refreshRate), String(Math.round(m.scale * 100) / 100)); });
            Quickshell.execDetached(["python3", "-c",
                "import re,sys,os\n" +
                "p=os.path.expanduser('~/.config/driftwm/config.toml')\n" +
                "s=open(p).read() if os.path.exists(p) else ''\n" +
                "a=sys.argv[1:]\n" +
                "for i in range(0,len(a),3):\n" +
                "    n,mo,sc=a[i:i+3]\n" +
                "    blk='[[outputs]]\\nname = \"%s\"\\nmode = \"%s\"\\nscale = %s\\n' % (n,mo,sc)\n" +
                "    pat=re.compile(r'\\[\\[outputs\\]\\]\\s*\\nname\\s*=\\s*\"'+re.escape(n)+r'\"[^\\[]*')\n" +
                "    s=pat.sub(lambda m: blk+'\\n', s, count=1) if pat.search(s) else s.rstrip()+'\\n\\n'+blk\n" +
                "open(p,'w').write(s)\n"].concat(args));
        }
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
                visible: !Compositor.hyprland && w.noRandr
                width: parent.width
                wrapMode: Text.WordWrap
                text: Tr.t("В ") + Compositor.name + Tr.t(" мониторы меняются через wlr-randr — поставьте пакет wlr-randr")
                color: Theme.yellow
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

            // разрешение — из тех, что умеет монитор
            Text { visible: w.mon !== null; text: Tr.t("Разрешение"); color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
            Flow {
                visible: w.mon !== null
                width: parent.width
                spacing: 8
                Repeater {
                    model: w.resolutions
                    GTile {
                        id: rt
                        required property string modelData
                        ui: Theme
                        width: resText.implicitWidth + 24; height: 34; radius: 17
                        on: modelData === w.shownRes
                        Text { id: resText; anchors.centerIn: parent; text: (rt.modelData === w.curRes ? "󰄬 " : "") + rt.modelData.replace("x", "×"); color: rt.on ? "white" : Theme.text; font.family: Theme.iconFont; font.pixelSize: 12; font.features: { "tnum": 1 } }
                        onClicked: w.pickRes = modelData === w.curRes ? "" : modelData
                    }
                }
            }
            // частота — только доступные при выбранном разрешении; нажатие применяет режим
            Text { visible: w.mon !== null; text: Tr.t("Частота обновления") + (w.pickRes !== "" ? Tr.t(" для ") + w.pickRes.replace("x", "×") : ""); color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
            Flow {
                visible: w.mon !== null
                width: parent.width
                spacing: 8
                Repeater {
                    model: w.rates
                    GTile {
                        id: ft
                        required property real modelData
                        ui: Theme
                        width: rateText.implicitWidth + 24; height: 34; radius: 17
                        on: w.mon && w.shownRes === w.curRes && Math.abs(modelData - w.mon.refreshRate) < 0.5
                        Text { id: rateText; anchors.centerIn: parent; text: (Math.abs(ft.modelData - Math.round(ft.modelData)) < 0.05 ? Math.round(ft.modelData) : ft.modelData.toFixed(2)) + Tr.t(" Гц"); color: ft.on ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 } }
                        onClicked: if (!on) w.apply(w.shownRes + "@" + modelData.toFixed(3), w.mon.scale)
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

            // подтверждение нового режима: текст сверху (с полосой отсчёта), кнопки ниже на всю ширину — ничего не наезжает при любом масштабе
            Rectangle {
                visible: w.countdown > 0
                width: parent.width
                height: cfCol.implicitHeight + 24
                radius: Theme.r(18)
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16); border.width: 1; border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
                Column {
                    id: cfCol
                    x: 14; y: 12; width: parent.width - 28
                    spacing: 10
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: Tr.t("Оставить новый режим? Без ответа вернётся прежний через ") + w.countdown + Tr.t(" с")
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Rectangle {
                        width: parent.width; height: 4; radius: 2; color: Theme.fill(0.12)
                        Rectangle { width: parent.width * w.countdown / 15; height: parent.height; radius: 2; color: Theme.accent; Behavior on width { NumberAnimation { duration: 900 } } }
                    }
                    Row {
                        width: parent.width; spacing: 8
                        GButton { ui: Theme; width: (parent.width - 8) / 2; implicitWidth: width; label: Tr.t("Вернуть"); icon: "󰑓"; implicitHeight: 36; onClicked: w.revert() }
                        GButton { ui: Theme; width: (parent.width - 8) / 2; implicitWidth: width; label: Tr.t("Оставить"); icon: "󰄬"; on: true; implicitHeight: 36; onClicked: w.keep() }
                    }
                }
            }

            GSwitch {
                ui: Theme
                width: parent.width
                label: Tr.t("Счётчик кадров в баре")
                sub: Tr.t("частота монитора и FPS; замер — секунда из пяти")
                checked: Theme.th.fps_counter === true
                onToggled: (v) => Quickshell.execDetached([Theme.script, "set", ".fps_counter", v ? "true" : "false"])
            }

            Row {
                spacing: 8
                GButton { ui: Theme; icon: "󰆓"; label: w.saved ? Tr.t("Сохранено") : Tr.t("Сохранить"); onClicked: w.save() }
                GButton { ui: Theme; icon: "󰑓"; label: Tr.t("Обновить"); onClicked: w.reload() }
            }
        }
    }
}
