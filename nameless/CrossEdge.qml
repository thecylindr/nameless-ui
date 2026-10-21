import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Переход курсора между компьютерами (NameLess Orbit) и эффекты на краях.
//   край: невидимая полоска в 1 px на краю, за которым стоит соседний компьютер (Config.crossing.links). Курсор задержался на ней
//         delay мс — Orbit забирает мышь и клавиатуру и ведёт курсор на соседе (D-Bus CrossTo). Опроса курсора нет — только наведение
//   эффект: Orbit шлёт сигнал Crossing (ушёл / пришёл, край, место) — на нужном мониторе на время эффекта появляется прозрачный
//         слой без ввода и исчезает сам. Работает и на компьютере, куда курсор пришёл
//   Scroll Lock — вернуть курсор домой. Настройки — «Оформление» → «Курсор» (через ipc crossing)
Scope {
    id: cross
    readonly property var cfg: Config.store.crossing || ({})
    readonly property bool on: cfg.enabled === true && OrbitData.enabled && OrbitData.running
    // края, за которыми сейчас есть сосед на связи с поддержкой перехода
    readonly property var links: !on ? [] : (cfg.links || []).filter(function (l) {
        return l.side && l.side !== "off" && OrbitData.connected.some(function (c) {
            return c.deviceId === l.device && (c.remoteCapabilities || []).indexOf("crossing") >= 0;
        });
    })
    readonly property var screens: Quickshell.screens.filter(function (s) { return String(s.name).indexOf("HEADLESS") !== 0; })
    // самый крайний монитор с этой стороны раскладки
    function screenFor(side) {
        var best = null;
        for (var i = 0; i < screens.length; i++) {
            var s = screens[i];
            if (!best || (side === "left" && s.x < best.x) || (side === "right" && s.x + s.width > best.x + best.width)
                      || (side === "top" && s.y < best.y) || (side === "bottom" && s.y + s.height > best.y + best.height)) best = s;
        }
        return best;
    }
    function tintOf(c) {
        if (c === "accent2") return Theme.accent2;
        if (c === "white") return "white";
        if (typeof c === "string" && c.charAt(0) === "#") return c;
        return Theme.accent;
    }

    // ---------- края ----------
    property double coolUntil: 0           // курсор только что вернулся — край не срабатывает сразу снова
    Variants {
        model: cross.links
        PanelWindow {
            id: strip
            required property var modelData
            readonly property string side: modelData.side
            screen: cross.screenFor(side)
            anchors { left: side !== "right"; right: side !== "left"; top: side !== "bottom"; bottom: side !== "top" }
            implicitWidth: 1
            implicitHeight: 1
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "nameless-crossing"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            MouseArea {
                id: edge
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                property real p: 0.5
                onPositionChanged: (m) => p = strip.side === "left" || strip.side === "right" ? m.y / Math.max(1, height) : m.x / Math.max(1, width)
                onEntered: if (Date.now() > cross.coolUntil) dwell.restart()
                onExited: dwell.stop()
            }
            // задержка: случайное касание края (полоса прокрутки, угол экрана) не уводит курсор
            Timer {
                id: dwell
                interval: Math.max(0, cross.cfg.delay === undefined ? 120 : cross.cfg.delay)
                onTriggered: OrbitData.crossTo(strip.modelData.device, strip.side, edge.p, strip.screen ? strip.screen.name : "")
            }
        }
    }

    // ---------- эффекты ----------
    property var fx: []                    // идущие эффекты: { n, dir, side, pos, screen }
    property int fxN: 0
    function show(o) {
        if (o.dir === "in" && o.peer !== undefined) coolUntil = Date.now() + 700;
        if ((cfg.effect || "glow") === "none") return;
        fxN++;
        fx = fx.concat([Object.assign({ n: fxN }, o)]);
    }
    function done(n) { fx = fx.filter(function (f) { return f.n !== n; }); }
    // пример для настроек: ушёл с правого края и пришёл с левого — на мониторе с фокусом
    function preview() {
        var f = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : (screens.length ? screens[0].name : "");
        show({ dir: "out", side: "right", pos: 0.5, screen: f });
        later.restart();
    }
    Timer { id: later; interval: 380; onTriggered: { var f = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""; cross.show({ dir: "in", side: "left", pos: 0.5, screen: f }); } }

    Variants {
        model: cross.fx
        PanelWindow {
            required property var modelData
            screen: { for (var i = 0; i < cross.screens.length; i++) if (cross.screens[i].name === modelData.screen) return cross.screens[i]; return cross.screenFor(modelData.side); }
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.namespace: "nameless-crossing-fx"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            CrossFx {
                anchors.fill: parent
                kind: cross.cfg.effect || "glow"
                side: modelData.side
                pos: modelData.pos
                dir: modelData.dir
                tint: cross.tintOf(cross.cfg.color || "accent")
                duration: cross.cfg.duration || 700
                k: cross.cfg.intensity || 1
                onFinished: cross.done(modelData.n)
            }
        }
    }

    // сигнал Orbit: dbus-monitor печатает строковый аргумент отдельной строкой «string "{…}"»
    Process {
        running: cross.cfg.enabled === true && OrbitData.enabled && OrbitData.running
        command: ["dbus-monitor", "--session", "type='signal',interface='" + OrbitData.svc + "',member='Crossing'"]
        stdout: SplitParser {
            onRead: line => {
                var i = line.indexOf("string \"");
                if (i < 0) return;
                try { cross.show(JSON.parse(line.slice(i + 8, line.lastIndexOf("\"")))); } catch (e) { }
            }
        }
    }
}
