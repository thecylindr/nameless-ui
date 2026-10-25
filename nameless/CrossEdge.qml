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
//   мониторы: переход курсора между своими мониторами (и на виртуальный монитор второго экрана) — тот же эффект ухода и прихода, без Orbit
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
    // links без учёта виртуального монитора: по ней считаются вспышки «сосед появился/пропал» — иначе включение второго экрана выглядело как уход соседа
    readonly property var linksAll: !on ? [] : linkList.filter(function (l) {
        return l.side && l.side !== "off" && OrbitData.connected.some(function (c) {
            return c.deviceId === l.device && (c.remoteCapabilities || []).indexOf("crossing") >= 0;
        });
    })
    readonly property var links: linksAll.filter(function (l) { return !virtualSides[l.side]; })
    readonly property var screens: Quickshell.screens.filter(function (s) { return String(s.name).indexOf("HEADLESS") !== 0; })
    // экран для эффекта по имени: настоящие и открытый виртуальный монитор второго экрана (Compositor.screens). Раньше на виртуальном
    // эффект не рисовался — окно на нём роняло Quickshell при удалении монитора; теперь Orbit заранее шлёт «closing», и монитор
    // пропадает из списка до удаления. Без этого на устройстве-втором экране эффекта перехода не было видно (он в его картинке)
    function screenByName(n) {
        var all = Compositor.screens;
        for (var i = 0; i < all.length; i++) if (all[i].name === n) return all[i];
        return null;
    }
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
        var kind = cfg.reducedMotion === true ? "line" : kindFor(o.dir);
        if (kind === "none") return;
        fxN++;
        if (o.dir === "out" && !o.link) lastOut = Date.now();
        // Один эффект на монитор, максимум четыре: быстрые переходы не накапливают слои размытия.
        var keep = fx.filter(function (f) { return f.screen !== o.screen; });
        if (keep.length >= 4) keep = keep.slice(keep.length - 3);
        fx = keep.concat([Object.assign({ n: fxN, t0: Date.now(), kind: kind, kk: (o.dir === "hint" ? 0.45 : (o.soft ? 0.7 : 1)) * ((cfg.effect || "auto") === "auto" ? sizeK(o.screen) : 1) }, o)]);
    }
    property double hintUntil: 0           // подсказка у края не чаще раза в 1,5 с: курсор у кромки легко дрожит
    function hint(side, pos, screen) {
        if (Date.now() < hintUntil) return;
        hintUntil = Date.now() + 1500;
        show({ dir: "hint", side: side, pos: pos, screen: screen });
    }
    // страховка: слой эффекта, чей монитор пропал посреди анимации, не доигрывает и не вызывает finished — без этого он оставался на экране
    Timer {
        running: cross.fx.length > 0; repeat: true; interval: 1000
        onTriggered: { var lim = (cross.cfg.duration || 700) + 1500, now = Date.now(); cross.fx = cross.fx.filter(function (f) { return now - f.t0 < lim; }); }
    }
    function done(n) { fx = fx.filter(function (f) { return f.n !== n; }); }
    // пример для настроек: сцена scene — out (уход и приход подряд), deny, hint, link
    function preview(scene) {
        var parts = scene.split(":");
        scene = parts[0];
        var side = ["left", "right", "top", "bottom"].indexOf(parts[1]) >= 0 ? parts[1] : "right";
        var f = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : (screens.length ? screens[0].name : "");
        if (scene === "deny") { show({ dir: "deny", side: "right", pos: 0.5, screen: f }); return; }
        if (scene === "hint") { show({ dir: "hint", side: "right", pos: 0.5, screen: f }); return; }
        if (scene === "link") { show({ dir: "in", side: "right", pos: 0.5, screen: f, soft: true, link: true }); return; }
        show({ dir: "out", side: side, pos: 0.5, screen: f });
        later.targetScreen = f; later.targetSide = ({ left: "right", right: "left", top: "bottom", bottom: "top" })[side];
        later.interval = Math.max(180, Math.round((cfg.duration || 700) * 0.55));
        later.restart();
    }
    Timer { id: later; property string targetScreen: ""; property string targetSide: "left"; interval: 380; onTriggered: cross.show({ dir: "in", side: targetSide, pos: 0.5, screen: targetScreen }) }

    // ---------- переход между мониторами ----------
    // курсор или фокус ушёл на другой монитор этого компьютера (в том числе на виртуальный «второй экран» Orbit): уход — на краю старого монитора,
    // приход — на краю нового. Работает и без Orbit, когда мониторов больше одного; выключается в настройках (crossing.monitors).
    // Место на краю — по положению курсора: один запрос hyprctl на переход, без опроса
    readonly property bool monOn: Compositor.hyprland && cfg.monitors !== false && Quickshell.screens.length > 1
    property string monPrev: ""
    property string monFrom: ""
    property string monTo: ""
    property double monQuiet: 0
    property string monLastFrom: ""
    property string monLastTo: ""
    property double monLastAt: 0            // мониторы только что поменялись (создан или снят второй экран): Orbit сам гоняет фокус — без вспышек
    Component.onCompleted: monPrev = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    Connections {
        target: Quickshell
        function onScreensChanged() { cross.monQuiet = Date.now() + 2500; }
    }
    Connections {
        target: Compositor.hyprland ? Hyprland : null
        function onRawEvent(e) {
            if (e.name !== "focusedmon") return;
            var to = String(e.data).split(",")[0], from = cross.monPrev;
            cross.monPrev = to;
            if (!cross.monOn || !from || from === to || Date.now() < cross.monQuiet) return;
            // курсор дрожит на стыке мониторов: обратный переход быстрее 300 мс — без эффектов (иначе они сыпались подряд)
            if (from === cross.monLastTo && to === cross.monLastFrom && Date.now() - cross.monLastAt < 300) { cross.monLastAt = Date.now(); return; }
            cross.monLastFrom = from; cross.monLastTo = to; cross.monLastAt = Date.now();
            cross.monFrom = from;
            cross.monTo = to;
            if (!monPos.running) monPos.running = true;
        }
    }
    Process {
        id: monPos
        property string fromScreen: ""
        property string toScreen: ""
        onRunningChanged: if (running) { fromScreen = cross.monFrom; toScreen = cross.monTo; }
        command: ["hyprctl", "-j", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                var c = null;
                try { c = JSON.parse(text); } catch (e) { }
                cross.monCross(monPos.fromScreen, monPos.toScreen, c);
            }
        }
    }
    // c — положение курсора на общей раскладке (логические пиксели) или null
    function monCross(from, to, c) {
        // геометрия — по всем мониторам; рисуется — на настоящих и на открытом виртуальном (screenByName)
        function geo(n) { var all = Quickshell.screens; for (var i = 0; i < all.length; i++) if (all[i].name === n) return all[i]; return null; }
        var a = geo(from), b = geo(to);
        if (!a || !b) return;
        // край — по взаимному положению мониторов; перекрытые (повтор экрана) пропускаются
        var side = b.x >= a.x + a.width ? "right" : (b.x + b.width <= a.x ? "left" : (b.y >= a.y + a.height ? "bottom" : (b.y + b.height <= a.y ? "top" : "")));
        if (!side) return;
        var opp = ({ left: "right", right: "left", top: "bottom", bottom: "top" })[side];
        var vert = side === "left" || side === "right";
        function along(s) {
            if (!c) return 0.5;
            var v = vert ? (c.y - s.y) / Math.max(1, s.height) : (c.x - s.x) / Math.max(1, s.width);
            return Math.max(0.05, Math.min(0.95, v));
        }
        if (screenByName(from)) show({ dir: "out", side: side, pos: along(a), screen: from });
        if (screenByName(to)) show({ dir: "in", side: opp, pos: along(b), screen: to });
    }

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
    onLinksAllChanged: {
        var now = {};
        linksAll.forEach(function (l) { now[l.device] = l; });
        if (ready) {
            for (var d in now) if (!seen[d]) show({ dir: "in", side: now[d].side, pos: 0.5, screen: (screenFor(now[d].side) || {}).name || "", soft: true, link: true });
            // сосед пропал — разрыв: красный эффект с крестом, а не обычный «уход» курсора
            for (var o in seen) if (!now[o]) show({ dir: "deny", side: seen[o].side, pos: 0.5, screen: (screenFor(seen[o].side) || {}).name || "", soft: true, link: true });
        }
        seen = now;
    }

    Variants {
        model: cross.fx
        PanelWindow {
            required property var modelData
            screen: cross.screenByName(modelData.screen) || cross.screenFor(modelData.side)
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
                duration: cross.cfg.reducedMotion === true ? 180 : (modelData.dir === "hint" ? 450 : Math.max(200, Math.min(2000, cross.cfg.duration || 700)))
                k: Math.max(0.4, Math.min(1.8, (cross.cfg.intensity || 1) * (modelData.kk || 1)))
                bloom: cross.cfg.bloom !== false && !cross.saving && !cross.calm
                particles: cross.cfg.particles !== false && !cross.saving
                portalDepth: Math.max(0.5, Math.min(1.5, cross.cfg.portalDepth || 1))
                motion: cross.cfg.motion || "smooth"
                reducedMotion: cross.cfg.reducedMotion === true
                onFinished: cross.done(modelData.n)
            }
        }
    }

    // ---------- вспомогательные действия при переходе (Config.crossing.actions) ----------
    //   clipboard — буфер обмена уходит вслед за курсором (сразу можно вставить на том компьютере)
    //   badge     — пока курсор там: у края светится полоска, плашка с именем компьютера и подсказкой Scroll Lock
    //   quiet     — на это время всплывающие уведомления молчат («не беспокоить»), потом прежний режим
    readonly property var acts: cfg.actions || ({})
    property var away: null                 // { side, peer, screen, device } — курсор сейчас на другом компьютере
    property bool dndBefore: false
    function deviceFor(side) { for (var i = 0; i < linkList.length; i++) if (linkList[i].side === side) return linkList[i].device; return ""; }
    function handleSignal(o) {
        if (o.dir === "out" && o.peer !== undefined && !o.link) {
            var dev = deviceFor(o.side);
            away = { side: o.side, peer: o.peer, screen: o.screen, device: dev };
            if (acts.clipboard !== false && dev !== "") OrbitData.sendClipboard(dev);
            if (acts.quiet === true) { dndBefore = Notifs.dnd; Notifs.dnd = true; }
            badgeT.restart();
        } else if ((o.dir === "in" || o.dir === "deny") && o.peer !== undefined && away !== null) {
            if (acts.quiet === true) Notifs.dnd = dndBefore;
            away = null;
        }
        show(o);
    }
    Timer { id: badgeT; interval: 2600 }
    // курсор на другом компьютере: тихая полоска у края (без анимации) и плашка на 2,6 с
    Variants {
        model: cross.away !== null && cross.acts.badge !== false ? [cross.away] : []
        PanelWindow {
            required property var modelData
            screen: cross.screenByName(modelData.screen) || cross.screenFor(modelData.side)
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.namespace: "nameless-crossing-fx"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            readonly property bool vert: modelData.side === "left" || modelData.side === "right"
            Rectangle {
                x: modelData.side === "right" ? parent.width - width : 0
                y: modelData.side === "bottom" ? parent.height - height : 0
                width: parent.vert ? 4 : parent.width; height: parent.vert ? parent.height : 4
                color: cross.tintOf(cross.cfg.color || "accent"); opacity: 0.55
            }
            Rectangle {
                visible: badgeT.running
                anchors.centerIn: parent
                width: badgeRow.implicitWidth + 36; height: 48; radius: 24
                color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.88)
                border.width: 1; border.color: cross.tintOf(cross.cfg.color || "accent")
                Row {
                    id: badgeRow
                    anchors.centerIn: parent; spacing: 10
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "󰍽"; color: cross.tintOf(cross.cfg.color || "accent"); font.family: Theme.iconFont; font.pixelSize: 18 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Курсор на «") + modelData.peer + Tr.t("»") + (cross.acts.clipboard !== false ? Tr.t(" · буфер отправлен") : ""); color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Scroll Lock — вернуть"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
                }
            }
        }
    }

    // сигнал Orbit: dbus-monitor печатает строковый аргумент отдельной строкой «string "{…}"»
    // слушается всегда, пока Orbit запущен: на компьютере, куда курсор пришёл, переход часто не включён (он включается там, откуда уходят),
    // и эффект прихода раньше не показывался вовсе
    Process {
        running: OrbitData.enabled && OrbitData.running
        command: ["dbus-monitor", "--session", "type='signal',interface='" + OrbitData.svc + "',member='Crossing'"]
        stdout: SplitParser {
            onRead: line => {
                var i = line.indexOf("string \"");
                if (i < 0) return;
                try { cross.handleSignal(JSON.parse(line.slice(i + 8, line.lastIndexOf("\"")))); } catch (e) { }
            }
        }
    }
}
