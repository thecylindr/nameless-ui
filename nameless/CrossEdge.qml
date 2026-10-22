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
//   сценарии эффектов (Config.crossing.scenes): out — курсор ушёл, in — пришёл, deny — переход не удался (красный крест), link — сосед появился или пропал
//         на своём краю, hint — курсор у края, за которым есть сосед (лёгкая подсказка). Эффект ухода и прихода можно выбрать отдельно (effectOut / effectIn)
//   расстановка соседей: подключённые без места (нет записи в links) сами получают край — справа, слева, сверху, снизу; «Нет» в шторке запоминается и не меняется
//   Scroll Lock — вернуть курсор домой. Настройки — «Оформление» → «Курсор» (через ipc crossing)
Scope {
    id: cross
    readonly property var cfg: Config.store.crossing || ({})
    // links в файле мог оказаться объектом вместо массива — тогда filter/slice падали и переход не работал
    function asList(v) { return Array.isArray(v) ? v : (v && typeof v === "object" ? (v.device !== undefined ? [v] : Object.keys(v).map(function (k) { return v[k]; })) : []); }
    readonly property var linkList: asList(cfg.links)
    readonly property bool on: cfg.enabled === true && OrbitData.enabled && OrbitData.running
    // стороны, где стоит виртуальный монитор «второго экрана»: там уже есть продолжение рабочего стола, переход курсора на этот край не нужен
    readonly property var virtualSides: {
        var real = Quickshell.screens.filter(function (s) { return String(s.name).indexOf("HEADLESS") !== 0; });
        var out = {};
        if (real.length === 0) return out;
        var l = Math.min.apply(null, real.map(function (s) { return s.x; })), t = Math.min.apply(null, real.map(function (s) { return s.y; }));
        var r = Math.max.apply(null, real.map(function (s) { return s.x + s.width; })), b = Math.max.apply(null, real.map(function (s) { return s.y + s.height; }));
        Quickshell.screens.forEach(function (s) {
            if (String(s.name).indexOf("HEADLESS") !== 0) return;
            if (s.x + s.width <= l) out.left = true;
            else if (s.x >= r) out.right = true;
            else if (s.y + s.height <= t) out.top = true;
            else if (s.y >= b) out.bottom = true;
        });
        return out;
    }
    // края, за которыми сейчас есть сосед на связи с поддержкой перехода
    readonly property var links: !on ? [] : linkList.filter(function (l) {
        return l.side && l.side !== "off" && !virtualSides[l.side] && OrbitData.connected.some(function (c) {
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
                onEntered: if (Date.now() > cross.coolUntil) { dwell.restart(); cross.hint(strip.side, edge.p, strip.screen ? strip.screen.name : ""); }
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
    property var fx: []                    // идущие эффекты: { n, dir, side, pos, screen, kind, kk }
    property int fxN: 0
    function scene(name) { return !cfg.scenes || cfg.scenes[name] !== false; }
    // «Авто»: эффект выбирается по случаю, а не один на все: уход — комета, приход — эхо (если сразу после ухода — линия, чтобы не рябило), подсказка — свечение,
    // сосед — сияние, отказ — красный крест. Тише или совсем без эффекта: на полноэкранном окне (игра, видео), во время записи экрана, на низком заряде
    // без зарядки. Размер подстраивается под монитор — на 4K крупнее, на малом экране мельче
    readonly property bool calm: {
        var t = Hyprland.activeToplevel;
        var fs = t && t.lastIpcObject && t.lastIpcObject.fullscreen > 0;
        return fs === true || Recorder.recording === true;
    }
    readonly property bool saving: Sys.hasBattery && !Sys.charging && Sys.batPct <= 20
    property double lastOut: 0
    function autoKind(dir) {
        if (dir === "deny") return "deny";
        if (saving) return dir === "hint" ? "none" : "line";
        if (calm) return dir === "hint" || dir === "link" ? "none" : "line";
        if (dir === "hint") return "glow";
        if (dir === "out") return "comet";
        if (dir === "link") return "aurora";
        return Date.now() - lastOut < 2500 ? "line" : "echo";
    }
    function sizeK(screenName) {
        for (var i = 0; i < screens.length; i++) if (screens[i].name === screenName) return Math.max(0.7, Math.min(1.6, Math.min(screens[i].width, screens[i].height) / 1080));
        return 1;
    }
    function kindFor(dir) {
        if (dir === "deny") return "deny";
        var own = dir === "out" ? cfg.effectOut : (dir === "in" ? cfg.effectIn : "");
        var eff = own || (dir === "hint" ? "glow" : (cfg.effect || "auto"));
        return eff === "auto" ? autoKind(dir) : eff;
    }
    // o: { dir: out | in | deny | hint, side, pos, screen, peer?, soft? }; soft — тише обычного (подсказка, появление соседа)
    function show(o) {
        if (o.dir === "in" && o.peer !== undefined) coolUntil = Date.now() + 700;
        if (cfg.effect === "none" && !cfg.effectOut && !cfg.effectIn && o.dir !== "deny") return;
        if (!scene(o.link ? "link" : o.dir)) return;
        var kind = kindFor(o.dir);
        if (kind === "none") return;
        fxN++;
        if (o.dir === "out" && !o.link) lastOut = Date.now();
        fx = fx.concat([Object.assign({ n: fxN, kind: kind, kk: (o.dir === "hint" ? 0.45 : (o.soft ? 0.7 : 1)) * ((cfg.effect || "auto") === "auto" ? sizeK(o.screen) : 1) }, o)]);
    }
    property double hintUntil: 0           // подсказка у края не чаще раза в 1,5 с: курсор у кромки легко дрожит
    function hint(side, pos, screen) {
        if (Date.now() < hintUntil) return;
        hintUntil = Date.now() + 1500;
        show({ dir: "hint", side: side, pos: pos, screen: screen });
    }
    function done(n) { fx = fx.filter(function (f) { return f.n !== n; }); }
    // пример для настроек: сцена scene — out (уход и приход подряд), deny, hint, link
    function preview(scene) {
        var f = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : (screens.length ? screens[0].name : "");
        if (scene === "deny") { show({ dir: "deny", side: "right", pos: 0.5, screen: f }); return; }
        if (scene === "hint") { show({ dir: "hint", side: "right", pos: 0.5, screen: f }); return; }
        if (scene === "link") { show({ dir: "in", side: "right", pos: 0.5, screen: f, soft: true, link: true }); return; }
        show({ dir: "out", side: "right", pos: 0.5, screen: f });
        later.restart();
    }
    Timer { id: later; interval: 380; onTriggered: { var f = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""; cross.show({ dir: "in", side: "left", pos: 0.5, screen: f }); } }

    // ---------- расстановка соседей ----------
    // подключённые с переходом курсора, которым ещё не назначен край (записи нет совсем — «Нет» из шторки запоминается как side: "off")
    function autoPlace(reset) {
        if (!cfg.enabled) return;
        var links = reset ? [] : linkList.slice();
        var peers = OrbitData.connected.filter(function (c) { return (c.remoteCapabilities || []).indexOf("crossing") >= 0; });
        var taken = {};
        links.forEach(function (l) { if (l.side && l.side !== "off") taken[l.side] = true; });
        var free = ["right", "left", "top", "bottom"].filter(function (x) { return !taken[x] && !virtualSides[x]; });
        var changed = reset === true;
        peers.forEach(function (c) {
            if (links.some(function (l) { return l.device === c.deviceId; }) || free.length === 0) return;
            links.push({ device: c.deviceId, name: c.name, side: free.shift() });
            changed = true;
        });
        if (changed) Config.set("crossing.links", links);
    }
    Timer { id: placeT; interval: 1500; onTriggered: cross.autoPlace(false) }
    Connections { target: OrbitData; function onConnectedChanged() { if (cross.on) placeT.restart(); } }
    onOnChanged: if (on) placeT.restart()

    // сосед появился или пропал на своём краю — короткая вспышка (первые секунды после запуска не считаются)
    property var seen: ({})
    property bool ready: false
    Timer { running: true; interval: 4000; onTriggered: cross.ready = true }
    onLinksChanged: {
        var now = {};
        links.forEach(function (l) { now[l.device] = l; });
        if (ready) {
            for (var d in now) if (!seen[d]) show({ dir: "in", side: now[d].side, pos: 0.5, screen: (screenFor(now[d].side) || {}).name || "", soft: true, link: true });
            for (var o in seen) if (!now[o]) show({ dir: "out", side: seen[o].side, pos: 0.5, screen: (screenFor(seen[o].side) || {}).name || "", soft: true, link: true });
        }
        seen = now;
    }

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
                kind: modelData.kind
                side: modelData.side
                pos: modelData.pos
                dir: modelData.dir === "deny" ? "out" : modelData.dir
                tint: modelData.dir === "deny" ? "#ff4d5e" : cross.tintOf(cross.cfg.color || "accent")
                duration: modelData.dir === "hint" ? 450 : (cross.cfg.duration || 700)
                k: (cross.cfg.intensity || 1) * (modelData.kk || 1)
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
