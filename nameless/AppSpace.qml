import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

// «Приложения на орбитах» (космос темы — apps): планеты — мониторы, орбиты вокруг — рабочие столы,
// спутники — открытые окна со значком приложения. Активный стол — яркая орбита, окно в фокусе — со свечением.
//   клик по спутнику — перейти к окну; перетащить спутник на другую орбиту (или пустую «новый стол») — перенести окно;
//   правый клик по спутнику — меню: перейти, плавающее, на стол N, закрыть; наведение — карточка окна
//   клик по подписи орбиты — перейти на рабочий стол; колесо — масштаб, перетаскивание фона — обзор, двойной клик — исходный вид
// Скорость — общая с солнечной системой (Config.store.space.speed); шаг — раз в кадр, не чаще 60 раз в секунду
Item {
    id: as
    readonly property real speed: Config.store.space.speed === undefined ? 1 : Config.store.space.speed
    readonly property var monitors: Compositor.hyprland ? Hyprland.monitors.values : []
    readonly property var workspaces: Compositor.hyprland ? Hyprland.workspaces.values.filter(function (w) { return w.id > 0; }) : []
    readonly property var toplevels: Compositor.hyprland ? Hyprland.toplevels.values : []

    property real t: 0
    property real zoom: 1
    property real zoomT: 1
    property real panX: 0
    property real panY: 0
    property real cx: 0
    property real cy: 0
    property double last: 0
    // стол закрыт окнами — орбиты стоят и сцена не перерисовывается; шаг по таймеру с частотой Perf.fps, а не на каждом кадре монитора
    Timer {
        interval: Math.round(1000 / Perf.fps)
        repeat: true
        running: as.visible && !Compositor.covered
        onRunningChanged: as.last = Date.now()
        onTriggered: {
            var now = Date.now(), dt = Math.min(0.1, (now - as.last) / 1000), k = 1 - Math.exp(-dt * 9);
            as.last = now;
            as.t += dt * as.speed;
            as.zoom += (as.zoomT - as.zoom) * k;
            as.cx += (as.panX - as.cx) * k;
            as.cy += (as.panY - as.cy) * k;
        }
    }

    // планеты по горизонтали: середина экрана — середина ряда
    readonly property real gapX: 760
    function planetX(i) { return (i - (monitors.length - 1) / 2) * gapX; }
    function wsOf(mon) {
        return workspaces.filter(function (w) { return w.monitor && w.monitor.name === mon.name; }).sort(function (a, b) { return a.id - b.id; });
    }
    function iconOf(tl) {
        var app = tl.wayland ? (tl.wayland.appId || "") : "", e = app !== "" ? (DesktopEntries.byId(app) || DesktopEntries.heuristicLookup(app)) : null;
        return Icons.app(e ? e.icon : app.toLowerCase());
    }
    // свободный номер для нового стола
    readonly property int nextWs: workspaces.reduce(function (m, w) { return Math.max(m, w.id); }, 0) + 1
    function addr(tl) { return "address:0x" + tl.address; }
    function moveTo(tl, ws) {
        if (!tl || (tl.workspace && tl.workspace.id === ws)) return;
        Hyprland.dispatch("hl.dsp.window.move({ workspace = " + ws + ", window = \"" + addr(tl) + "\", follow = false })");
    }
    function toggleFloat(tl) { Hyprland.dispatch("hl.dsp.window.float({ action = \"toggle\", window = \"" + addr(tl) + "\" })"); }
    function closeWin(tl) { if (tl.wayland) tl.wayland.close(); }
    // куда брошен спутник: ближайшая планета, затем орбита по радиусу эллипса; за последней — новый стол
    function dropAt(tl, px, py) {
        if (monitors.length === 0) return;
        var j = 0;
        for (var i = 1; i < monitors.length; i++) if (Math.abs(px - planetX(i)) < Math.abs(px - planetX(j))) j = i;
        var dx = px - planetX(j), d = Math.sqrt(dx * dx + (py / 0.62) * (py / 0.62)), ws = wsOf(monitors[j]);
        if (d < 70) { if (monitors[j].activeWorkspace) moveTo(tl, monitors[j].activeWorkspace.id); return; }
        var k = Math.max(0, Math.min(ws.length, Math.round((d - 130) / 62)));
        moveTo(tl, k < ws.length ? ws[k].id : nextWs);
    }
    // меню спутника и карточка наведения — поверх сцены, без масштаба
    property var menuFor: null
    property point menuAt: Qt.point(0, 0)
    property var hoverFor: null
    property point hoverAt: Qt.point(0, 0)
    property bool dragging: false

    function focus(tl) {
        if (tl.workspace) Hyprland.dispatch("hl.dsp.focus({ workspace = " + tl.workspace.id + " })");
        if (tl.wayland) tl.wayland.activate();
    }

    MouseArea {
        anchors.fill: parent
        property real sx: 0
        property real sy: 0
        property bool moved: false
        onPressed: (m) => { sx = m.x; sy = m.y; moved = false; as.menuFor = null; }
        onPositionChanged: (m) => {
            if (!pressed) return;
            if (!moved && Math.abs(m.x - sx) + Math.abs(m.y - sy) < 4) return;
            moved = true;
            as.panX += m.x - sx; as.panY += m.y - sy; as.cx = as.panX; as.cy = as.panY; sx = m.x; sy = m.y;
        }
        onDoubleClicked: { as.panX = 0; as.panY = 0; as.zoomT = 1; }
        onWheel: (wh) => {
            var nz = Math.max(0.3, Math.min(3, as.zoomT * (wh.angleDelta.y > 0 ? 1.15 : 1 / 1.15)));
            var mx = wh.x - as.width / 2, my = wh.y - as.height / 2, k = nz / as.zoomT;
            as.panX = mx - (mx - as.panX) * k; as.panY = my - (my - as.panY) * k;
            as.zoomT = nz;
        }
    }

    Item {
        x: as.width / 2 + as.cx
        y: as.height / 2 + as.cy
        scale: as.zoom
        transformOrigin: Item.TopLeft

        Repeater {
            model: as.monitors
            Item {
                id: pl
                required property var modelData
                required property int index
                readonly property var wss: as.wsOf(modelData)
                readonly property bool focusedMon: modelData.focused
                x: as.planetX(index)

                // орбиты-рабочие столы и спутники-окна
                Repeater {
                    model: pl.wss
                    Item {
                        id: orb
                        required property var modelData
                        required property int index
                        readonly property real r: 130 + index * 62
                        readonly property bool active: pl.modelData.activeWorkspace !== null && pl.modelData.activeWorkspace.id === modelData.id
                        readonly property var wins: as.toplevels.filter(function (t) { return t.workspace && t.workspace.id === orb.modelData.id; })
                        Rectangle {
                            width: orb.r * 2; height: orb.r * 2 * 0.62
                            x: -width / 2; y: -height / 2
                            radius: width / 2
                            color: "transparent"
                            border.width: orb.active ? 2 : 1
                            border.color: orb.active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7) : Qt.rgba(1, 1, 1, 0.1)
                        }
                        // подпись орбиты — сверху: подписи соседних орбит не налезают друг на друга; клик — перейти
                        Rectangle {
                            x: -width / 2; y: -orb.r * 0.62 - 11
                            width: wsT.implicitWidth + 16; height: 22; radius: 11
                            color: orb.active ? Theme.accent : Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.8)
                            Text { id: wsT; anchors.centerIn: parent; text: Tr.t("стол ") + orb.modelData.id + (orb.wins.length ? " · " + orb.wins.length : ""); color: orb.active ? "white" : Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + orb.modelData.id + " })") }
                        }
                        Repeater {
                            model: orb.wins
                            Item {
                                id: sat
                                required property var modelData
                                required property int index
                                readonly property real a: as.t / (14 + orb.index * 6) * 2 * Math.PI + index * 2 * Math.PI / Math.max(1, orb.wins.length) + orb.index
                                readonly property bool cur: modelData.activated
                                // при перетаскивании орбита замирает, спутник идёт за курсором
                                property real a0: 0
                                property point off: Qt.point(0, 0)
                                readonly property bool held: drag.active
                                z: held ? 10 : 0
                                x: (held ? Math.cos(a0) * orb.r : Math.cos(a) * orb.r) + off.x
                                y: (held ? Math.sin(a0) * orb.r * 0.62 : Math.sin(a) * orb.r * 0.62) + off.y
                                scale: held ? 1.15 : 1
                                // свечение у окна в фокусе
                                Rectangle { visible: sat.cur; width: 64; height: 64; radius: 32; x: -32; y: -32; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) }
                                Rectangle {
                                    width: 42; height: 42; radius: 21; x: -21; y: -21
                                    color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.85)
                                    border.width: sat.cur ? 2 : 1
                                    border.color: sat.cur ? Theme.accent : Qt.rgba(1, 1, 1, 0.2)
                                    Image { anchors.centerIn: parent; width: 28; height: 28; sourceSize: Qt.size(28, 28); asynchronous: true; source: as.iconOf(sat.modelData) }
                                }
                                Text {
                                    visible: sat.cur && !satHov.hovered && !sat.held
                                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 26 }
                                    width: 180; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                    text: sat.modelData.title || ""
                                    color: Qt.rgba(1, 1, 1, 0.85); font.family: Theme.font; font.pixelSize: 11
                                }
                                Item {
                                    width: 46; height: 46; x: -23; y: -23
                                    HoverHandler {
                                        id: satHov; cursorShape: sat.held ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                        onHoveredChanged: {
                                            if (hovered) { as.hoverFor = sat.modelData; as.hoverAt = sat.mapToItem(as, 0, 0); }
                                            else if (as.hoverFor === sat.modelData) as.hoverFor = null;
                                        }
                                    }
                                    TapHandler { onTapped: as.focus(sat.modelData) }
                                    TapHandler {
                                        acceptedButtons: Qt.RightButton
                                        onTapped: (ev) => { as.menuAt = sat.mapToItem(as, 0, 0); as.menuFor = sat.modelData; }
                                    }
                                    // смещение — по экранным координатам, делённым на масштаб: сама точка захвата не «плывёт»
                                    DragHandler {
                                        id: drag
                                        target: null
                                        property point start: Qt.point(0, 0)
                                        onActiveChanged: {
                                            if (active) {
                                                sat.a0 = sat.a; start = centroid.scenePosition; as.dragging = true; as.hoverFor = null; as.menuFor = null;
                                            } else {
                                                as.dropAt(sat.modelData, pl.x + sat.x, sat.y);
                                                sat.off = Qt.point(0, 0); as.dragging = false;
                                            }
                                        }
                                        onCentroidChanged: if (active) sat.off = Qt.point((centroid.scenePosition.x - start.x) / as.zoom, (centroid.scenePosition.y - start.y) / as.zoom)
                                    }
                                }
                            }
                        }
                    }
                }

                // пустая орбита: сюда можно бросить окно — оно уйдёт на новый стол
                Item {
                    visible: as.dragging
                    readonly property real r: 130 + pl.wss.length * 62
                    Repeater {
                        model: 48
                        Rectangle {
                            required property int index
                            readonly property real a: index / 48 * 2 * Math.PI
                            x: Math.cos(a) * parent.r - 2; y: Math.sin(a) * parent.r * 0.62 - 2
                            width: 4; height: 4; radius: 2
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
                        }
                    }
                    Rectangle {
                        x: -width / 2; y: -parent.r * 0.62 - 11
                        width: nwT.implicitWidth + 16; height: 22; radius: 11
                        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.85)
                        border.width: 1; border.color: Theme.accent
                        Text { id: nwT; anchors.centerIn: parent; text: Tr.t("+ новый стол ") + as.nextWs; color: Theme.accent; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
                    }
                }

                // планета-монитор: название, разрешение
                Rectangle {
                    width: 120; height: 120; radius: 60; x: -60; y: -60
                    // второй экран Orbit — планета-устройство своего цвета, подписанная именем телефона или компьютера
                    readonly property var vs: OrbitData.virtualScreens[pl.modelData.name] || null
                    readonly property bool virt: String(pl.modelData.name).indexOf("HEADLESS") === 0
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(parent.virt ? Theme.teal : Theme.accent, 1.3) }
                        GradientStop { position: 1; color: Qt.darker(parent.virt ? Theme.accent : Theme.accent2, 2.2) }
                    }
                    border.width: pl.focusedMon ? 3 : 0
                    border.color: Qt.rgba(1, 1, 1, 0.6)
                    // ночная сторона
                    Rectangle {
                        anchors.fill: parent; radius: width / 2; rotation: 35
                        gradient: Gradient { GradientStop { position: 0.45; color: "transparent" } GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.7) } }
                    }
                    Column {
                        anchors.centerIn: parent
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: !parent.parent.virt ? "󰍹" : (({ phone: "󰏲", tablet: "󰓷", laptop: "󰌢" })[(parent.parent.vs || {}).kind] || "󰍺")
                            color: "white"; font.family: Theme.iconFont; font.pixelSize: 26
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; width: 104; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                            text: parent.parent.virt ? (parent.parent.vs ? parent.parent.vs.peer : Tr.t("Второй экран")) : pl.modelData.name
                            color: "white"; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Bold
                        }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: pl.modelData.width + "×" + pl.modelData.height; color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.font; font.pixelSize: 10 }
                    }
                }
            }
        }
    }

    // карточка окна при наведении
    Rectangle {
        visible: as.hoverFor !== null && as.menuFor === null && !as.dragging
        x: Math.min(as.width - width - 8, as.hoverAt.x + 30)
        y: Math.max(8, as.hoverAt.y - height / 2)
        width: Math.min(320, Math.max(cardCol.implicitWidth, 160) + 24); height: cardCol.implicitHeight + 20
        radius: Theme.r(14)
        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.92)
        border.width: 1; border.color: Theme.line(0.2)
        Column {
            id: cardCol
            x: 12; y: 10
            width: parent.width - 24
            spacing: 3
            readonly property var tl: as.hoverFor
            Text { width: parent.width; elide: Text.ElideRight; text: cardCol.tl ? (cardCol.tl.title || "") : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: cardCol.tl ? (cardCol.tl.wayland ? cardCol.tl.wayland.appId : "") + Tr.t(" · стол ") + (cardCol.tl.workspace ? cardCol.tl.workspace.id : "?") : ""
                color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
            }
            Text { text: Tr.t("клик — перейти · тянуть — на другой стол · ПКМ — меню"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10; opacity: 0.8 }
        }
    }

    // меню спутника
    Rectangle {
        id: menu
        visible: as.menuFor !== null
        readonly property var tl: as.menuFor
        x: Math.min(as.width - width - 8, as.menuAt.x + 26)
        y: Math.min(as.height - height - 8, Math.max(8, as.menuAt.y - 20))
        width: 240; height: mCol.implicitHeight + 16
        radius: Theme.r(16)
        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.95)
        border.width: 1; border.color: Theme.line(0.22)
        MouseArea { anchors.fill: parent }
        Column {
            id: mCol
            x: 8; y: 8
            width: parent.width - 16
            spacing: 2
            Text { width: parent.width; leftPadding: 8; elide: Text.ElideRight; text: menu.tl ? (menu.tl.title || "") : ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; bottomPadding: 4 }
            Repeater {
                model: [{ i: "󰁔", t: Tr.t("Перейти к окну"), k: "focus" }, { i: "󰉧", t: Tr.t("Плавающее / в сетке"), k: "float" }, { i: "󰅖", t: Tr.t("Закрыть окно"), k: "close" }]
                Rectangle {
                    required property var modelData
                    width: mCol.width; height: 32; radius: Theme.r(9)
                    color: mi.containsMouse ? (modelData.k === "close" ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.2) : Theme.fill(0.12)) : "transparent"
                    Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: modelData.i + "  " + modelData.t; color: modelData.k === "close" ? Theme.red : Theme.text; font.family: Theme.iconFont; font.pixelSize: 12 }
                    MouseArea {
                        id: mi; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var t = menu.tl; as.menuFor = null;
                            if (modelData.k === "focus") as.focus(t); else if (modelData.k === "float") as.toggleFloat(t); else as.closeWin(t);
                        }
                    }
                }
            }
            Text { leftPadding: 8; topPadding: 6; text: Tr.t("Перенести на стол"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
            Flow {
                width: mCol.width
                spacing: 4
                padding: 4
                Repeater {
                    model: as.workspaces.map(function (w) { return w.id; }).sort(function (a, b) { return a - b; }).concat([as.nextWs])
                    Rectangle {
                        required property int modelData
                        readonly property bool here: menu.tl && menu.tl.workspace && menu.tl.workspace.id === modelData
                        width: Math.max(28, wl.implicitWidth + 14); height: 26; radius: 13
                        color: here ? Theme.accent : (wma.containsMouse ? Theme.fill(0.16) : Theme.fill(0.08))
                        Text { id: wl; anchors.centerIn: parent; text: modelData === as.nextWs ? "+ " + modelData : String(modelData); color: parent.here ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 11 }
                        MouseArea { id: wma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { as.moveTo(menu.tl, modelData); as.menuFor = null; } }
                    }
                }
            }
        }
    }

    Text {
        visible: as.monitors.length === 0
        anchors.centerIn: parent
        text: Tr.t("Режим «Приложения на орбитах» работает в Hyprland")
        color: Theme.sub; font.family: Theme.font; font.pixelSize: 14
    }
    // подсказка
    Rectangle {
        anchors { left: parent.left; leftMargin: 24; bottom: parent.bottom; bottomMargin: 28 }
        width: hint.implicitWidth + 24; height: 36; radius: 18
        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.7)
        Text { id: hint; anchors.centerIn: parent; text: Tr.t("󰍹 планеты — мониторы · орбиты — рабочие столы · спутники — окна; клик — перейти, тянуть — перенести, ПКМ — меню"); color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 11 }
    }
}
