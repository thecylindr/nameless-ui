import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Док NameLess UI (dock = true в теме). Стиль — Config.dock.style:
//   mac — стеклянная полка, значки «волной» увеличиваются под курсором;
//   ios — широкая плашка, значки на одинаковых плитках, без увеличения по умолчанию.
// Слева — закреплённые и запущенные приложения, справа за разделителем — «Загрузки» и корзина.
//   клик          — запуск или следующее окно приложения, средний — новое окно
//   правый клик   — меню: окна, новое окно, закрепить / убрать, закрыть; у «Загрузок» — последние файлы, у корзины — очистить
//   перетаскивание — переставить закреплённый значок; вытянуть вверх и отпустить — убрать из дока
// Значки растрируются один раз в наибольшем размере; ячейки строятся по числу значков и при изменении настроек
// переиспользуются (значки не загружаются заново)
PanelWindow {
    id: w
    property var shell: null
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    visible: Theme.th.dock === true
    anchors { bottom: true; left: true; right: true }

    readonly property bool ios: Config.dock.style === "ios"
    readonly property int size: Math.max(36, Math.min(80, Config.dock.size || 54))
    readonly property real zoom: Config.dock.magnify === false ? 1 : Math.max(1, Math.min(2.4, Config.dock.zoom || 1.7))
    readonly property bool tiles: Config.dock.tiles === true || ios
    readonly property int pad: Math.round(size * (ios ? 0.3 : 0.16))
    readonly property int gap: Math.round(size * (ios ? 0.32 : 0.12))
    readonly property int boxH: size + pad * 2
    readonly property int margin: ios ? 14 : 8
    // запас сверху: увеличенный значок и подпись над ним
    implicitHeight: boxH + margin + Math.ceil(size * (zoom - 1)) + 48
    exclusiveZone: Config.dock.autohide ? 0 : boxH + margin
    color: "transparent"
    WlrLayershell.namespace: "nameless-dock"
    WlrLayershell.layer: WlrLayer.Top
    mask: Region { item: zone }

    // ---------- приложения ----------
    // зависимость от списка ярлыков: при старте он пуст, без неё док остался бы без ярлыков (клик не запускал)
    readonly property var apps: DesktopEntries.applications.values
    function entryFor(id) { return apps.length >= 0 ? (DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id)) : null; }
    function norm(s) { return (s || "").toLowerCase().replace(/\.desktop$/, ""); }
    function iconOf(e, id) {
        var n = e ? e.icon : norm(id);
        if (n && n.charAt(0) === "/") return "file://" + n;
        return Quickshell.iconPath(n || "", true) || Quickshell.iconPath("application-x-executable", true);
    }
    // окна приложения: по appId окна, id ярлыка и StartupWMClass
    function windowsOf(id, e, app) {
        var out = [], ts = ToplevelManager.toplevels.values, keys = [norm(id)];
        if (app) keys.push(norm(app));
        if (e) { keys.push(norm(e.id)); if (e.startupClass) keys.push(norm(e.startupClass)); }
        for (var i = 0; i < ts.length; i++) {
            var t = norm(ts[i].appId);
            if (t === "") continue;
            for (var k = 0; k < keys.length; k++)
                if (t === keys[k] || (t.length > 3 && keys[k].indexOf(t) >= 0)) { out.push(ts[i]); break; }
        }
        return out;
    }
    function launch(item) {
        if (item.entry) AppRun.run(item.entry);
        else Quickshell.execDetached(["sh", "-c", "command -v gtk-launch >/dev/null && gtk-launch \"$1\" || exec \"$1\"", "sh", item.id]);
    }
    function focusNext(wins) {
        var cur = -1;
        for (var i = 0; i < wins.length; i++) if (wins[i].activated) cur = i;
        wins[(cur + 1) % wins.length].activate();
    }

    // значки: закреплённые, затем запущенные без закрепления
    readonly property var items: {
        var out = [], seen = {}, pinned = Config.dock.pinned || [];
        for (var i = 0; i < pinned.length; i++) {
            var e = entryFor(pinned[i]);
            out.push({ id: pinned[i], entry: e, pinned: true });
            seen[norm(pinned[i])] = true;
            if (e) { seen[norm(e.id)] = true; if (e.startupClass) seen[norm(e.startupClass)] = true; }
        }
        if (Config.dock.running !== false) {
            var ts = ToplevelManager.toplevels.values;
            for (var j = 0; j < ts.length; j++) {
                var k = norm(ts[j].appId);
                if (k === "" || seen[k]) continue;
                seen[k] = true;
                var re = entryFor(ts[j].appId);
                if (re) seen[norm(re.id)] = true;
                out.push({ id: re ? re.id : ts[j].appId, entry: re, pinned: false, app: ts[j].appId });
            }
        }
        return out;
    }
    readonly property int pinnedCount: (Config.dock.pinned || []).length
    // правая часть: папки
    readonly property var extras: (Config.store.orbit.indock === true && OrbitData.enabled ? ["orbit"] : []).concat(Config.dock.downloads !== false ? ["downloads"] : []).concat(Config.dock.trash !== false ? ["trash"] : [])

    // ---------- увеличение: «волна» по положению курсора ----------
    // считается по несдвинутой раскладке, иначе значки «убегали» бы из-под курсора
    property real mx: -1
    readonly property int count: items.length + extras.length + 1     // + «+»
    readonly property real baseW: count * size + (count - 1) * gap + (extras.length > 0 ? gap + 1 : 0)
    function mag(i) {
        if (mx < 0 || zoom <= 1 || dragId !== "") return 1;
        var left = width / 2 - baseW / 2;
        var cx = left + i * (size + gap) + (i > items.length ? gap + 1 : 0) + size / 2;
        var d = Math.abs(mx - cx) / (size * 2.6);
        if (d >= 1) return 1;
        var c = Math.cos(d * Math.PI / 2);
        return 1 + (zoom - 1) * c * c;
    }

    // ---------- показ ----------
    property int hovered: -1
    property bool overExtra: false      // курсор над «+», «Загрузками» или корзиной
    // курсор над каким-то значком: значок сам ведёт mx — зона под ним в этот момент может считать, что курсор ушёл
    property int overCells: 0
    function track(handler, on) {
        overCells = Math.max(0, overCells + (on ? 1 : -1));
        if (on) clearT.stop(); else clearT.restart();
    }
    // сброс увеличения — только когда курсора нет ни над зоной, ни над значками
    Timer { id: clearT; interval: 220; onTriggered: if (!zoneHover.hovered && w.overCells === 0) { w.mx = -1; w.hovered = -1; w.overExtra = false; } }
    property var menuItem: null
    readonly property bool menuOpen: menu.visible
    readonly property bool inside: zoneHover.hovered || overCells > 0 || hovered >= 0 || overExtra || dragId !== ""
    property bool stay: false
    onInsideChanged: { if (inside) { stay = true; leaveT.stop(); } else leaveT.restart(); }
    Timer { id: leaveT; interval: 450; onTriggered: w.stay = false }
    readonly property bool shown: !Config.dock.autohide || stay || menuOpen || peek.running
    // после изменения настроек док показывается на пару секунд, даже со скрытием
    Timer { id: peek; interval: 1800 }
    Connections { target: Config; function onStoreChanged() { peek.restart(); } }

    // ---------- перетаскивание ----------
    property string dragId: ""
    property real dragX: 0
    property real dragY: 0
    readonly property bool dragOut: dragId !== "" && dragY < -size * 1.1
    // куда встанет перетаскиваемый: индекс среди закреплённых
    readonly property int dropIndex: {
        if (dragId === "") return -1;
        var left = width / 2 - baseW / 2, i = Math.round((dragX - left - size / 2) / (size + gap));
        return Math.max(0, Math.min(pinnedCount - 1, i));
    }

    // ---------- корзина и загрузки ----------
    readonly property string home: Quickshell.env("HOME")
    property bool trashFull: false
    property var recent: []
    property string downloadsDir: home + "/Downloads"
    Process {
        id: trashProc
        command: ["sh", "-c", "ls -A \"$HOME/.local/share/Trash/files\" 2>/dev/null | head -n1"]
        stdout: StdioCollector { onStreamFinished: w.trashFull = text.trim() !== "" }
    }
    Timer { interval: 15000; repeat: true; triggeredOnStart: true; running: w.visible && Config.dock.trash !== false; onTriggered: if (!trashProc.running) trashProc.running = true }
    Process {
        id: recentProc
        command: ["sh", "-c", "d=\"$(xdg-user-dir DOWNLOAD 2>/dev/null || echo \"$HOME/Downloads\")\"; echo \"$d\"; " +
                  "find \"$d\" -maxdepth 1 -type f -printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -n 8 | cut -f2"]
        stdout: StdioCollector { onStreamFinished: { var l = text.split("\n").filter(function (x) { return x !== ""; }); w.downloadsDir = l.shift() || (w.home + "/Downloads"); w.recent = l; } }
    }

    // зона ввода: док с запасом под увеличенный значок; скрытый док — полоска у нижнего края
    Item {
        id: zone
        readonly property real lift: w.stay ? Math.ceil(w.size * (w.zoom - 1)) + 40 : 0
        x: dockBox.x - 12
        width: dockBox.width + 24
        y: w.shown ? dockBox.y - lift : w.height - 3
        height: w.shown ? dockBox.height + lift + w.margin : 3
        HoverHandler {
            id: zoneHover
            onPointChanged: if (hovered) { w.mx = point.position.x + zone.x; clearT.stop(); }
            // уход курсора — с задержкой: при расширении зоны ввода Hyprland на миг шлёт «ушёл–пришёл»,
            // и мгновенный сброс гасил увеличение сразу после появления
            onHoveredChanged: { if (hovered) clearT.stop(); else if (w.overCells === 0) clearT.restart(); }
        }
        // правый клик по пустому месту дока — настройки; по значку — только его меню
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: if (w.shell && w.hovered < 0 && !w.overExtra && !w.menuOpen) w.shell.openDesktop(1)
        }
    }

    // ---------- полка ----------
    Item {
        id: dockBox
        anchors.horizontalCenter: parent.horizontalCenter
        width: row.width + w.pad * 2
        height: w.boxH
        y: w.shown ? w.height - height - w.margin : w.height + 6
        Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        Surface {
            anchors.fill: parent
            radius: w.ios ? Math.round(w.boxH * 0.42) : Math.round(w.boxH * 0.3)
            alpha: Theme.glass ? Math.max(0.36, Theme.panelAlpha - 0.08) : Theme.panelAlpha
        }
        // кант полки: светлая линия сверху, как у стекла
        Rectangle {
            visible: !w.ios && Theme.glass
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14 }
            height: 1
            color: Qt.rgba(1, 1, 1, 0.28)
        }

        Row {
            id: row
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: w.pad }
            spacing: w.gap

            Repeater {
                // по числу значков: изменения настроек и окон не пересоздают ячейки
                model: w.items.length
                Item {
                    id: cell
                    required property int index
                    readonly property var it: w.items[index] || ({ id: "", pinned: false })
                    readonly property var wins: w.windowsOf(it.id, it.entry, it.app)
                    readonly property bool running: wins.length > 0
                    readonly property bool focused: { for (var i = 0; i < wins.length; i++) if (wins[i].activated) return true; return false; }
                    readonly property string title: it.entry ? it.entry.name : it.id
                    readonly property bool dragging: w.dragId !== "" && w.dragId === it.id
                    readonly property real m: w.mag(index)
                    // место вставки при перетаскивании
                    readonly property bool dropBefore: w.dragId !== "" && !w.dragOut && it.pinned === true && index === w.dropIndex && !dragging

                    width: w.size * m
                    height: w.size
                    Behavior on width { enabled: w.mx < 0; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    // разделитель перед первым незакреплённым
                    Rectangle {
                        visible: cell.it.pinned !== true && cell.index === w.pinnedCount && cell.index > 0
                        x: -w.gap / 2 - 0.5
                        anchors { bottom: parent.bottom; bottomMargin: w.size * 0.08 }
                        width: 1; height: w.size * 0.84
                        color: Theme.glass ? Qt.rgba(1, 1, 1, 0.25) : Theme.line(0.3)
                    }
                    Rectangle {
                        visible: cell.dropBefore
                        x: -w.gap / 2 - 1.5
                        anchors.bottom: parent.bottom
                        width: 3; height: w.size; radius: 1.5
                        color: Theme.accent
                    }

                    DockIcon {
                        id: icon
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                        s: w.size * cell.m
                        source: w.iconOf(cell.it.entry, cell.it.id)
                        pressed: tap.pressed
                        opacity: cell.dragging ? 0.25 : 1
                        transform: Translate { id: hop }
                        SequentialAnimation {
                            id: bounce
                            loops: 2
                            NumberAnimation { target: hop; property: "y"; to: -w.size * 0.32; duration: 230; easing.type: Easing.OutQuad }
                            NumberAnimation { target: hop; property: "y"; to: 0; duration: 270; easing.type: Easing.OutBounce }
                        }
                    }

                    // запущено: точка, у активного — цветом акцента
                    Rectangle {
                        visible: cell.running
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: Math.max(2, w.pad * 0.28) }
                        width: 4; height: 4; radius: 2
                        color: cell.focused ? Theme.accent : Theme.text
                        opacity: cell.focused ? 1 : 0.65
                    }

                    // подпись над значком
                    Tip {
                        visible: Config.dock.labels !== false && w.hovered === cell.index && !w.menuOpen && w.dragId === ""
                        anchors { horizontalCenter: icon.horizontalCenter; bottom: icon.top; bottomMargin: 12 }
                        text: cell.title + (cell.wins.length > 1 ? "  ·  " + cell.wins.length : "")
                    }

                    // наведённый сбрасывается не сразу (clearT), а при переходе на другой значок или уходе из дока
                    // ячейка, удалённая под курсором, не оставляет «висящий» счётчик наведения
                    Component.onDestruction: if (cellHov.hovered) w.track(null, false)
                    HoverHandler {
                        id: cellHov
                        cursorShape: Qt.PointingHandCursor
                        onHoveredChanged: { w.track(this, hovered); if (hovered) { w.hovered = cell.index; w.overExtra = false; } }
                        onPointChanged: if (hovered) w.mx = point.scenePosition.x
                    }
                    TapHandler {
                        id: tap
                        // захват на всё нажатие: правый клик не доходит до зоны дока (иначе открывались и настройки)
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        onTapped: (ev, button) => {
                            if (button === Qt.RightButton) { w.menuItem = { kind: "app", data: cell.it, wins: cell.wins, title: cell.title }; menu.anchor.item = icon; menu.visible = true; return; }
                            if (button === Qt.MiddleButton || !cell.running) { w.launch(cell.it); if (!cell.running) bounce.restart(); return; }
                            w.focusNext(cell.wins);
                        }
                    }
                    // перетаскивание закреплённых
                    DragHandler {
                        enabled: cell.it.pinned === true
                        target: null
                        onActiveChanged: {
                            if (active) { w.dragId = cell.it.id; return; }
                            var id = w.dragId, out = w.dragOut, to = w.dropIndex;
                            w.dragId = "";
                            if (out) Config.unpin(id); else if (to >= 0) Config.movePinTo(id, to);
                        }
                        onCentroidChanged: if (active) { var p = cell.mapToItem(null, centroid.position.x, centroid.position.y); w.dragX = p.x; w.dragY = p.y - dockBox.y; }
                    }
                    onRunningChanged: if (running) { bounce.stop(); hop.y = 0; }
                }
            }

            // добавить приложение
            Item {
                id: addCell
                readonly property real m: w.mag(w.items.length)
                width: w.size * m
                height: w.size
                visible: w.shell !== null
                Rectangle {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: w.size * addCell.m * 0.07 }
                    width: w.size * addCell.m * 0.86; height: width
                    radius: w.tiles ? width * 0.26 : width / 2
                    color: addHover.hovered ? Theme.fill(0.2) : Theme.fill(0.08)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.18)
                    Text { anchors.centerIn: parent; text: "󰐕"; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: parent.width * 0.42 }
                }
                Tip {
                    visible: addHover.hovered && w.dragId === ""
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 12 }
                    text: Tr.t("Добавить приложение")
                }
                HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: { w.track(this, hovered); if (hovered) { w.hovered = -1; w.overExtra = true; } } onPointChanged: if (hovered) w.mx = point.scenePosition.x }
                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onTapped: (ev, button) => { if (button === Qt.RightButton) w.shell.openDesktop(1); else w.shell.pickForDock(); }
                }
            }

            // разделитель и папки
            Rectangle {
                visible: w.extras.length > 0
                anchors { bottom: parent.bottom; bottomMargin: w.size * 0.08 }
                width: 1; height: w.size * 0.84
                color: Theme.glass ? Qt.rgba(1, 1, 1, 0.25) : Theme.line(0.3)
            }
            Repeater {
                model: w.extras
                Item {
                    id: ex
                    required property string modelData
                    required property int index
                    readonly property bool trash: modelData === "trash"
                    readonly property bool orbit: modelData === "orbit"
                    readonly property real m: w.mag(w.items.length + 1 + index)
                    width: w.size * m
                    height: w.size
                    // Orbit: значок устройств; зелёная ссылка в углу — есть подключённое устройство (перенесённая сюда верхняя таблетка)
                    Item {
                        id: exOrbit
                        visible: ex.orbit
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                        width: w.size * ex.m; height: width
                        Rectangle {
                            anchors.fill: parent; radius: width * 0.26
                            color: OrbitData.connected.length > 0 ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
                            Text { anchors.centerIn: parent; text: OrbitData.connected.length > 0 ? OrbitData.kindIcon(OrbitData.connected[0].kind) : "󰟀"; color: "white"; font.family: Theme.iconFont; font.pixelSize: parent.width * 0.48 }
                        }
                        LinkBadge {
                            linked: OrbitData.connected.length > 0
                            width: parent.width * 0.36; height: width
                            x: parent.width - width * 0.85; y: parent.height - height * 0.85
                            key: OrbitData.connected.length + ":" + (OrbitData.connected.length > 0 ? OrbitData.connected[0].deviceId : "")
                            hover: exHover.hovered
                        }
                    }
                    DockIcon {
                        id: exIcon
                        visible: !ex.orbit
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                        s: w.size * ex.m
                        source: Quickshell.iconPath(ex.trash ? (w.trashFull ? "user-trash-full" : "user-trash") : "folder-download", true)
                                || Quickshell.iconPath(ex.trash ? "user-trash" : "folder", true)
                        pressed: exTap.pressed
                    }
                    Tip {
                        visible: exHover.hovered && !w.menuOpen && w.dragId === ""
                        anchors { horizontalCenter: exIcon.horizontalCenter; bottom: exIcon.top; bottomMargin: 12 }
                        text: ex.orbit ? (OrbitData.connected.length > 0 ? Tr.t("Подключено: ") + OrbitData.connected.map(function (c) { return c.name; }).join(", ") : Tr.t("Orbit: нет подключённых устройств"))
                                       : (ex.trash ? (w.trashFull ? Tr.t("Корзина") : Tr.t("Корзина пуста")) : Tr.t("Загрузки"))
                    }
                    HoverHandler { id: exHover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: { w.track(this, hovered); if (hovered) { w.hovered = -1; w.overExtra = true; } } onPointChanged: if (hovered) w.mx = point.scenePosition.x }
                    TapHandler {
                        id: exTap
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onTapped: (ev, button) => {
                            if (ex.orbit) {      // левый клик — лента устройств, правый — включить или выключить Orbit
                                if (button === Qt.RightButton) OrbitData.toggleEnabled();
                                else if (OrbitData.panelOpen) OrbitData.panelOpen = false;
                                else w.shell.openOrbit();
                                return;
                            }
                            if (button === Qt.RightButton) {
                                if (!ex.trash) recentProc.running = true;
                                w.menuItem = { kind: ex.modelData, title: ex.trash ? Tr.t("Корзина") : Tr.t("Загрузки") };
                                menu.anchor.item = exIcon; menu.visible = true;
                                return;
                            }
                            Quickshell.execDetached(ex.trash ? ["dolphin", "trash:/"] : ["sh", "-c", "xdg-open \"$(xdg-user-dir DOWNLOAD 2>/dev/null || echo \"$HOME/Downloads\")\""]);
                        }
                    }
                }
            }
        }
    }

    // перетаскиваемый значок следует за курсором; вверх за порог — «убрать»
    DockIcon {
        visible: w.dragId !== ""
        x: w.dragX - s / 2
        y: dockBox.y + w.dragY - s / 2
        s: w.size * 1.08
        source: { for (var i = 0; i < w.items.length; i++) if (w.items[i].id === w.dragId) return w.iconOf(w.items[i].entry, w.items[i].id); return ""; }
        opacity: w.dragOut ? 0.55 : 0.95
        Rectangle {
            visible: w.dragOut
            anchors { right: parent.right; top: parent.top; margins: -6 }
            width: 22; height: 22; radius: 11
            color: Theme.red
            Text { anchors.centerIn: parent; text: "󰅖"; color: "white"; font.family: Theme.iconFont; font.pixelSize: 13 }
        }
    }

    // ---------- меню ----------
    PopupWindow {
        id: menu
        visible: false
        grabFocus: true
        color: "transparent"
        anchor.edges: Edges.Top
        anchor.gravity: Edges.Top
        implicitWidth: 250
        implicitHeight: menuCol.implicitHeight + 16
        onVisibleChanged: if (!visible) w.menuItem = null

        readonly property var it: w.menuItem
        readonly property bool app: it !== null && it.kind === "app"
        function run(f) { menu.visible = false; f(); }

        Rectangle {
            anchors.fill: parent
            radius: Theme.r(16)
            color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, Theme.glass ? 0.95 : 0.98)
            border.width: 1
            border.color: Theme.glass ? Qt.rgba(1, 1, 1, 0.16) : Theme.line(0.22)
        }
        Column {
            id: menuCol
            x: 8; y: 8
            width: parent.width - 16
            spacing: 2

            Text {
                width: parent.width
                leftPadding: 10; topPadding: 4; bottomPadding: 6
                text: menu.it ? menu.it.title : ""
                color: Theme.sub
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            // ----- приложение -----
            Repeater {
                model: menu.app ? menu.it.wins.slice(0, 6) : []
                MenuRow {
                    required property var modelData
                    icon: modelData.activated ? "󰄬" : "󰖯"
                    label: modelData.title || modelData.appId
                    onClicked: menu.run(function () { modelData.activate(); })
                }
            }
            Rectangle { visible: menu.app && menu.it.wins.length > 0; width: parent.width; height: 1; color: Theme.fill(0.12) }
            MenuRow {
                visible: menu.app
                icon: "󰐕"; label: menu.app && menu.it.wins.length > 0 ? Tr.t("Новое окно") : Tr.t("Открыть")
                onClicked: { var d = menu.it.data; menu.run(function () { w.launch(d); }); }
            }
            MenuRow {
                visible: menu.app
                icon: menu.app && Config.isPinned(menu.it.data.id) ? "󰐄" : "󰐃"
                label: menu.app && Config.isPinned(menu.it.data.id) ? Tr.t("Убрать из дока") : Tr.t("Оставить в доке")
                onClicked: { var id = menu.it.data.id; menu.run(function () { Config.togglePin(id); }); }
            }
            MenuRow {
                visible: menu.app && menu.it.wins.length > 0
                icon: "󰅖"; danger: true
                label: menu.app && menu.it.wins.length > 1 ? Tr.t("Закрыть все окна (") + menu.it.wins.length + ")" : Tr.t("Закрыть окно")
                onClicked: { var ws = menu.it.wins.slice(); menu.run(function () { for (var i = 0; i < ws.length; i++) ws[i].close(); }); }
            }
            // ----- загрузки: последние файлы -----
            Repeater {
                model: menu.it && menu.it.kind === "downloads" ? w.recent : []
                MenuRow {
                    required property string modelData
                    icon: "󰈔"
                    label: modelData.split("/").pop()
                    onClicked: { var f = modelData; menu.run(function () { Quickshell.execDetached(["xdg-open", f]); }); }
                }
            }
            MenuRow {
                visible: menu.it !== null && menu.it.kind === "downloads"
                icon: "󰉋"; label: Tr.t("Открыть папку")
                onClicked: menu.run(function () { Quickshell.execDetached(["xdg-open", w.downloadsDir]); })
            }
            // ----- корзина -----
            MenuRow {
                visible: menu.it !== null && menu.it.kind === "trash"
                icon: "󰉋"; label: Tr.t("Открыть корзину")
                onClicked: menu.run(function () { Quickshell.execDetached(["dolphin", "trash:/"]); })
            }
            MenuRow {
                visible: menu.it !== null && menu.it.kind === "trash" && w.trashFull
                icon: "󰩹"; danger: true; label: Tr.t("Очистить корзину")
                onClicked: menu.run(function () {
                    Quickshell.execDetached(["sh", "-c", "gio trash --empty 2>/dev/null || rm -rf \"$HOME/.local/share/Trash/files/\"* \"$HOME/.local/share/Trash/info/\"*"]);
                    w.trashFull = false;
                })
            }
            Rectangle { width: parent.width; height: 1; color: Theme.fill(0.12) }
            MenuRow {
                icon: "󰒓"; label: Tr.t("Настроить док…")
                onClicked: menu.run(function () { if (w.shell) w.shell.openDesktop(1); })
            }
        }
    }

    // ---------- части ----------
    // значок: картинка один раз в наибольшем размере; tiles — на одинаковой плитке-«сквиркле»
    component DockIcon: Item {
        id: di
        property real s: 48
        property alias source: img.source
        property bool pressed: false
        width: s; height: s
        Rectangle {
            visible: w.tiles
            anchors.fill: parent
            radius: width * 0.26
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.95) }
                GradientStop { position: 1.0; color: Theme.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0.9, 0.92, 0.96, 0.95) }
            }
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, Theme.dark ? 0.18 : 0.6)
        }
        Image {
            id: img
            anchors.centerIn: parent
            width: w.tiles ? di.s * 0.72 : di.s
            height: width
            sourceSize: Qt.size(Math.ceil(w.size * w.zoom), Math.ceil(w.size * w.zoom))
            smooth: true
            mipmap: true
            asynchronous: true
        }
        // нажатие — значок темнеет
        Rectangle {
            anchors.fill: parent
            visible: di.pressed
            radius: w.tiles ? width * 0.26 : width * 0.22
            color: Qt.rgba(0, 0, 0, 0.3)
        }
    }

    // подпись: плашка со стрелкой вниз
    component Tip: Item {
        property alias text: tipText.text
        width: tipText.implicitWidth + 22
        height: 28
        z: 3
        Rectangle {
            anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.bottom }
            width: 9; height: 9
            rotation: 45
            color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.94)
        }
        Rectangle {
            anchors.fill: parent
            radius: Theme.r(10)
            color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.94)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, Theme.dark ? 0.14 : 0.4)
        }
        Text { id: tipText; anchors.centerIn: parent; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
    }
}
