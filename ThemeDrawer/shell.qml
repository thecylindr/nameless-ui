// Шторка оформления: шаблоны, свои темы и полная настройка профилей theme.sh
//
//   qs -c ThemeDrawer                          демон: запускает theme.sh start, живёт постоянно
//   qs -c ThemeDrawer ipc call drawer toggle   открыть / закрыть (SUPER+X, кнопка в waybar, меню MacShell)
//
// При открытии снимается кадр экрана: фон под шторкой затемняется и размывается, а сама панель —
// жидкое стекло, которое преломляет этот кадр. Все изменения идут через ~/.config/hypr/Scripts/theme.sh.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/Scripts/theme.sh"

    // armed — окно на экране (снимок, анимация), open — шторка открыта
    property bool armed: false
    property bool open: false
    property real progress: open ? 1 : 0
    // открытие плавное, закрытие короткое и без «хвоста»: пока окно видно, на весь экран считается шейдер стекла
    Behavior on progress { NumberAnimation { duration: root.open ? 380 : 170; easing.type: root.open ? Easing.OutQuint : Easing.InQuad } }
    // почти скрытое окно выгружается сразу, не дожидаясь последних кадров
    onProgressChanged: if (!open && progress < 0.04) armed = false

    property int tab: 0
    onTabChanged: if (tab === 3 && !crossDevs.running) crossDevs.running = true

    // ---------- переход курсора (NameLess UI + Orbit): читается из nameless.json, пишется через ipc NameLess — один писатель у файла ----------
    property var cross: ({})
    FileView {
        path: Quickshell.env("HOME") + "/.config/glassrice/nameless.json"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.cross = JSON.parse(text()).crossing || {}; } catch (e) { } }
    }
    function crossSet(key, value) {
        var n = Object.assign({}, cross); n[key] = value; cross = n;         // шторка показывает новое значение сразу, файл догонит
        Quickshell.execDetached(["qs", "-c", "nameless", "ipc", "call", "crossing", "set", key, JSON.stringify(value)]);
    }
    function crossSide(dev, name, side) {
        var l = (cross.links || []).filter(function (x) { return x.device !== dev; });
        // одна сторона — один сосед: тот, кто стоял на этом краю, снимается
        if (side !== "off") l = l.filter(function (x) { return x.side !== side; }).concat([{ device: dev, name: name, side: side }]);
        crossSet("links", l);
    }
    function sideOf(dev) { var l = cross.links || []; for (var i = 0; i < l.length; i++) if (l[i].device === dev) return l[i].side; return "off"; }
    // соседи из Orbit: подключённые, у которых есть переход курсора
    property var crossPeers: []
    property bool orbitUp: false
    Process {
        id: crossDevs
        command: ["busctl", "--user", "--json=short", "--", "call", "org.glassrice.NamelessOrbit", "/org/glassrice/NamelessOrbit", "org.glassrice.NamelessOrbit", "Status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var r = JSON.parse(JSON.parse(text).data[0]);
                    root.orbitUp = true;
                    root.crossPeers = (r.connected || []).map(function (c) { return { id: c.deviceId, name: c.name, kind: c.kind, ok: (c.remoteCapabilities || []).indexOf("crossing") >= 0 }; });
                } catch (e) { root.orbitUp = false; root.crossPeers = []; }
            }
        }
        onExited: code => { if (code !== 0) { root.orbitUp = false; root.crossPeers = []; } }
    }

    // ---------- вид шторки: ширина, высота, карточек в ряд — запоминаются ----------
    property var view: ({ style: "desktop", align: "right", wmode: "normal", height: 0, cols: 2 })
    property bool viewOpen: false
    FileView {
        id: viewFile
        path: Quickshell.env("HOME") + "/.config/glassrice/drawer.json"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.view = Object.assign({ style: "desktop", align: "right", wmode: "normal", height: 0, cols: 2 }, JSON.parse(text())); } catch (e) { } }
    }
    function setView(k, v) { var n = Object.assign({}, view); n[k] = v; view = n; viewSave.restart(); }
    Timer { id: viewSave; interval: 400; onTriggered: viewFile.setText(JSON.stringify(root.view, null, 2) + "\n") }

    // ---------- состояние из theme.sh dump ----------

    property var st: ({ current: "", theme: null, themes: [], palettes: [], hasQs: false, dnd: false, seasonal: { seasons: [], auto: false, showAll: false } })
    readonly property var th: st.theme || ({})
    readonly property var hy: th.hypr || ({})
    readonly property var gl: th.glass || ({})
    readonly property var wp: th.wallpaper || ({})
    readonly property var curPal: paletteOf(th.palette)
    readonly property var curInfo: themeInfo(st.current)
    readonly property var templates: [
        { id: "classic", kind: "classic", sub: Tr.t("Мой дизайн") },
        { id: "liquid", kind: "liquid", sub: Tr.t("Всё из стекла") },
        { id: "ios", kind: "ios", sub: Tr.t("Как будто это iOS") },
        { id: "aurora", kind: "aurora", sub: Tr.t("Цвет из обоев, живая рамка") },
        { id: "echostar", kind: "echostar", sub: Tr.t("Ночное небо, падающие звёзды") },
        { id: "newyear", kind: "liquid", sub: Tr.t("Снег, золото, звёздное небо") },
        { id: "valentine", kind: "ios", sub: Tr.t("Розовый вечер, сердечки") },
        { id: "halloween", kind: "liquid", sub: Tr.t("Тыквы, луна, туман") }
    ]

    // праздничные шаблоны появляются в своё окно дат (или всегда, если включено «показывать все»; текущий — всегда)
    function seasonOf(id) { var l = st.seasonal ? st.seasonal.seasons : []; for (var i = 0; i < l.length; i++) if (l[i].id === id) return l[i]; return null; }
    readonly property var visibleTemplates: templates.filter(function (t) {
        var s = seasonOf(t.id);
        return !s || s.active || (st.seasonal && st.seasonal.showAll) || st.current === t.id;
    })
    function paletteOf(id) {
        for (var i = 0; i < st.palettes.length; i++) if (st.palettes[i].id === id) return st.palettes[i];
        return null;
    }
    function themeInfo(id) {
        for (var i = 0; i < st.themes.length; i++) if (st.themes[i].id === id) return st.themes[i];
        return null;
    }
    function accentOf(info) {
        if (!info) return "#0a84ff";
        if (info.accent) return info.accent;
        var p = paletteOf(info.palette);
        return p ? p.colors.blue : "#0a84ff";
    }

    QtObject {
        id: look
        readonly property var c: root.curPal ? root.curPal.colors : null
        readonly property bool dark: root.curPal ? root.curPal.dark : true
        readonly property color base: c ? c.base : "#1c1c1e"
        // комплект оформления: classic — клиент без стекла, liquid — клиент со стеклом, ios — Пункт управления iOS
        readonly property string kit: root.th.kit ? root.th.kit : (root.th.style !== "glass" ? "classic" : (root.th.shell === "macshell" ? "ios" : "liquid"))
        readonly property bool glass: kit !== "classic"
        readonly property bool ios: kit === "ios"
        readonly property color text: dark ? "#ffffff" : "#1d1d1f"
        readonly property color sub: dark ? Qt.rgba(1, 1, 1, 0.58) : Qt.rgba(0, 0, 0, 0.5)
        readonly property color red: c ? c.red : "#ff453a"
        readonly property color accent: root.th.accent ? root.th.accent : (c ? c.blue : "#0a84ff")
        // шрифт: первое доступное семейство, иначе системный
        readonly property string font: {
            var want = ["Inter Variable", "Inter", "SF Pro Display", "Noto Sans"];
            var have = Qt.fontFamilies();
            for (var i = 0; i < want.length; i++) if (have.indexOf(want[i]) >= 0) return want[i];
            return Qt.application.font.family;
        }
        // шкала: заголовок, подзаголовок, основной, подпись; у крупного текста трекинг плотнее (как у SF)
        readonly property int titleSize: ios ? 28 : 24
        readonly property real titleTracking: ios ? -0.6 : -0.3
        readonly property string iconFont: "JetBrainsMono Nerd Font"
        // заливка стеклянных элементов: на тёмном — белая дымка, на светлом — молочно-белая
        // заливка элементов: стекло — дымка, сплошной материал — поверхность палитры, светлее фона панели
        function fill(a) {
            if (!glass) return Qt.tint(base, Qt.rgba(text.r, text.g, text.b, Math.min(0.5, 0.04 + a * 0.8)));
            return dark ? Qt.rgba(1, 1, 1, a) : Qt.rgba(1, 1, 1, Math.min(0.92, 0.32 + a * 2));
        }
        // рамка: классика — цвет текста, стекло клиента — белый кант, iOS — без рамок (объёмный край)
        function line(a) {
            if (kit === "classic") return Qt.rgba(text.r, text.g, text.b, a);
            if (kit === "liquid") return Qt.rgba(1, 1, 1, Math.min(0.5, a + 0.06));
            return "transparent";
        }
        // радиусы: iOS — как заданы, клиент со стеклом — карточки 16 и кнопки 11, без стекла — 16 и 8
        function r(x) {
            if (kit === "ios") return x;
            return x > 20 ? 16 : (kit === "liquid" ? 11 : 8);
        }
    }

    Process {
        id: dumpProc
        command: [root.script, "dump"]
        stdout: StdioCollector {
            onStreamFinished: {
                // пока изменения в очереди, свежее состояние не перетирает их: неприменённые значения — поверх
                try { root.st = root.withPending(JSON.parse(text)); } catch (e) { }
            }
        }
    }
    function refresh() { if (!dumpProc.running) dumpProc.running = true; }

    // применение темы: карточка показывает «Применяю…», состояние перечитывается сразу по окончании
    property string applying: ""
    // этапы применения: theme.sh (THEME_PROGRESS=1) пишет «stage:имя» по ходу работы
    readonly property var applySteps: [
        { id: "colors", t: Tr.t("Цвета и материалы"), icon: "󰏘" },
        { id: "hypr", t: Tr.t("Окна Hyprland"), icon: "󰖲" },
        { id: "shell", t: Tr.t("Панели и оболочка"), icon: "󰍜" },
        { id: "wallpaper", t: Tr.t("Обои"), icon: "󰸉" }
    ]
    property string applyStage: ""
    readonly property int applyIndex: {
        if (applyStage === "done") return applySteps.length;
        for (var i = 0; i < applySteps.length; i++) if (applySteps[i].id === applyStage) return i;
        return 0;
    }
    readonly property bool applyFinished: applyStage === "done"
    Process {
        id: applyProc
        environment: ({ THEME_PROGRESS: "1" })
        stdout: SplitParser {
            onRead: (line) => { if (line.indexOf("stage:") === 0) root.applyStage = line.substring(6).trim(); }
        }
        onRunningChanged: if (!running) { root.applyStage = "done"; applyDone.restart(); root.refresh(); }
    }
    // «Готово» видно чуть меньше секунды: панели успевают перезапуститься
    Timer { id: applyDone; interval: 900; onTriggered: root.applying = "" }
    function applyTheme(id) {
        if (applying !== "" || id === st.current) return;
        applyStage = "";
        applying = id;
        applyProc.command = [root.script, "apply", id];
        applyProc.running = true;
    }
    Timer { id: refreshLater; interval: 300; onTriggered: if (root.queue.length === 0 && !setProc.running) root.refresh() }
    Component.onCompleted: refresh()

    // ---------- команды theme.sh ----------

    function run(args) {
        Quickshell.execDetached([root.script].concat(args));
        refreshLater.restart();
    }

    // сохранение шаблона: список перечитывается сразу по окончании
    property string savedNote: ""
    Process { id: saveProc; onExited: { root.refresh(); noteT.restart(); } }
    Timer { id: noteT; interval: 2500; onTriggered: root.savedNote = "" }

    // очередь set: theme.sh применяет по одному; состояние перечитывается, только когда очередь пуста
    property var queue: []
    Process {
        id: setProc
        onRunningChanged: if (!running) root.nextSet()
    }
    function nextSet() {
        if (setProc.running) return;
        if (queue.length === 0) { refreshLater.restart(); return; }
        var q = queue.slice(), job = q.shift();
        queue = q;
        setProc.command = [root.script, "set", job[0], job[1]];
        setProc.running = true;
    }
    // неприменённые значения (в очереди и ещё не отправленные) поверх прочитанного состояния
    function withPending(state) {
        var all = {}, i;
        for (i = 0; i < queue.length; i++) all[queue[i][0]] = queue[i][1];
        for (var k in pendingSets) all[k] = pendingSets[k];
        if (setProc.running && setProc.command.length > 3) all[setProc.command[2]] = setProc.command[3];
        if (Object.keys(all).length === 0) return state;
        var t = JSON.parse(JSON.stringify(state.theme || {}));
        for (var path in all) {
            var keys = path.split(".").filter(function (x) { return x !== ""; }), o = t;
            for (i = 0; i < keys.length - 1; i++) { if (typeof o[keys[i]] !== "object" || o[keys[i]] === null) o[keys[i]] = {}; o = o[keys[i]]; }
            try { o[keys[keys.length - 1]] = JSON.parse(all[path]); } catch (e) { }
        }
        state.theme = t;
        return state;
    }

    // параметр меняется сразу в шторке, theme.sh применяет его в фоне
    function set(path, value) {
        var t = JSON.parse(JSON.stringify(st.theme || {}));
        var keys = path.split(".").filter(function (k) { return k !== ""; });
        var o = t;
        for (var i = 0; i < keys.length - 1; i++) { if (o[keys[i]] === undefined) o[keys[i]] = {}; o = o[keys[i]]; }
        o[keys[keys.length - 1]] = value;
        var s = Object.assign({}, st);
        s.theme = t;
        st = s;
        // последнее значение параметра уходит в theme.sh через 120 мс: серия кликов — один запуск
        pendingSets[path] = JSON.stringify(value);
        setFlush.restart();
    }
    property var pendingSets: ({})
    Timer {
        id: setFlush
        interval: 120
        onTriggered: {
            var p = root.pendingSets, q = root.queue.slice();
            root.pendingSets = ({});
            // в очереди остаётся последнее значение каждого параметра
            for (var k in p) { q = q.filter(function (j) { return j[0] !== k; }); q.push([k, p[k]]); }
            root.queue = q;
            refreshLater.stop();
            root.nextSet();
        }
    }

    // скриншот, блокировка и прочее — после закрытия шторки
    property string pendingAction: ""
    Timer { id: actionLater; interval: 220; onTriggered: Quickshell.execDetached([root.script, "action", root.pendingAction]) }
    function act(name) { pendingAction = name; hide(); actionLater.restart(); }

    // ---------- открытие: окно → снимок экрана → анимация ----------

    property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    function pickScreen() {
        var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        for (var i = 0; i < Quickshell.screens.length; i++)
            if (Quickshell.screens[i].name === name) { targetScreen = Quickshell.screens[i]; return; }
    }
    function show() {
        if (open) return;
        pickScreen();
        refresh();
        tab = 0;
        armed = true;
        captureT.restart();
    }
    function hide() { open = false; }
    Timer { id: captureT; interval: 50; onTriggered: { snap.captureFrame(); openT.restart(); } }
    Timer { id: openT; interval: 90; onTriggered: root.open = true }

    // шторка живёт постоянно: закрытая — без окна и почти без памяти, зато открывается сразу,
    // без запуска процесса (раньше выгружалась через 90 с, и следующее открытие ждало старта)

    IpcHandler {
        target: "drawer"
        function toggle(): void { if (root.open) root.hide(); else root.show(); }
        function show(): void { root.show(); }
        function hide(): void { root.hide(); }
        // открыть шторку и применить тему с индикатором этапов
        function apply(id: string): void { root.show(); applyLater.themeId = id; applyLater.restart(); }
    }
    Timer { id: applyLater; property string themeId: ""; interval: 450; onTriggered: root.applyTheme(themeId) }

    // ---------- окно ----------

    PanelWindow {
        id: win
        visible: root.armed
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "themedrawer"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // кадр экрана: фон для размытия и для преломления в стекле
        ScreencopyView {
            id: snap
            anchors.fill: parent
            captureSource: root.armed ? win.screen : null
            live: false
            paintCursor: false
        }
        ShaderEffectSource {
            id: snapTex
            anchors.fill: parent
            sourceItem: snap
            hideSource: true
            mipmap: true
            visible: false
        }

        // затемнённый и размытый фон
        MultiEffect {
            anchors.fill: parent
            source: snapTex
            autoPaddingEnabled: false
            blurEnabled: true
            // параметры постоянные: размытие считается один раз, анимируется только прозрачность
            blurMax: 40
            blur: 0.85
            saturation: -0.1
            opacity: Math.min(1, root.progress * 1.6)
            visible: snap.hasContent && look.glass
        }
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: (look.dark ? 0.38 : 0.22) * root.progress
        }
        MouseArea {
            anchors.fill: parent
            enabled: root.open
            onClicked: root.hide()
        }

        Item {
            anchors.fill: parent
            focus: root.open
            Keys.onEscapePressed: root.hide()
            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Tab) { root.tab = (root.tab + 1) % 4; e.accepted = true; }
            }
        }

        // ---------- панель ----------

        Glass {
            id: panel
            ui: look
            backdrop: snap.hasContent && look.glass ? snapTex : null
            winSize: Qt.size(win.width, win.height)
            tint: Math.min(0.85, Math.max(0.26, (root.gl.tint || 0.22) + 0.12))
            strength: root.gl.strength !== undefined ? root.gl.strength : 1.0

            // шторка прижата к верхнему краю и сползает вниз, как на планшете: верх уходит за экран на радиус скругления.
            // Ширина — пресет, высота — по содержимому или ручкой внизу (меньше 320 не действует: панель не пропадёт)
            // стиль: desktop — окно справа/слева/по центру под верхним краем (как раньше); mobile — шторка от самого края экрана
            readonly property bool mobile: root.view.style === "mobile"
            readonly property string align: root.view.align === "left" || root.view.align === "center" ? root.view.align : "right"
            readonly property real sr: mobile ? ui.r(radius) : 0
            readonly property var presets: ({ narrow: 420, normal: 560, wide: 760 })
            readonly property string wmode: presets[root.view.wmode] !== undefined || root.view.wmode === "full" ? root.view.wmode : "normal"
            readonly property real minH: 320
            // «широкий» вид (во всю ширину на большом экране): элементы не растягиваются на всю ширину, а раскладываются по колонкам
            readonly property bool wide: wmode === "full" && width >= 1000
            readonly property int pageCols: wide ? Math.max(1, Math.min(3, Math.floor(width / 640))) : 1
            readonly property real contentCap: wide ? 620 : 100000      // предел ширины рядов в широком виде: ползунки и переключатели не растягиваются на всю колонку      // предел ширины для рядов, которые нельзя разложить по колонкам
            property real dragDy: 0
            readonly property real edge: (mobile && (wmode === "full" || win.width < 700)) ? 0 : 12      // отступ от боков: шторка любой ширины и любого места не выходит за экран
            width: (wmode === "full" || win.width < 700) ? win.width - 2 * edge : Math.min(win.width - 2 * edge, presets[wmode])
            readonly property real wanted: header.height + viewBox.height + tabBar.height + pages.currentHeight + 70
            readonly property real maxH: win.height - (mobile ? 8 : 24)
            readonly property real baseH: (root.view.height || 0) >= minH ? Math.min(maxH, root.view.height) : Math.min(maxH, wanted)
            readonly property real sheetH: Math.max(minH, Math.min(maxH, baseH + dragDy))
            height: sheetH + sr
            Behavior on height { enabled: panel.dragDy === 0; NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            x: align === "left" ? edge : (align === "center" ? (win.width - width) / 2 : win.width - width - edge)
            y: mobile ? -sr - sheetH * (1 - root.progress) : 12 - (sheetH + 40) * (1 - root.progress)
            opacity: Math.min(1, root.progress * 2)

            // клики по панели не закрывают шторку
            MouseArea { anchors.fill: parent }

            Item {
                anchors { fill: parent; margins: 20; topMargin: 20 + panel.sr; bottomMargin: 34 }

                // заголовок
                Item {
                    id: header
                    width: parent.width
                    height: 48
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            text: Tr.t("Оформление")
                            color: look.text
                            font.family: look.font
                            font.pixelSize: look.titleSize
                            font.weight: Font.Bold
                            font.letterSpacing: look.titleTracking
                        }
                        Text {
                            text: root.applying !== "" ? Tr.t("Применяю…") : (root.th.name || "") + ({ classic: "", liquid: Tr.t("  ·  жидкое стекло"), ios: "  ·  iOS" })[look.kit]
                            color: look.sub
                            font.family: look.font
                            font.pixelSize: 13
                        }
                    }
                    GTile {
                        id: closeTile
                        ui: look
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 36; height: 36; radius: 18
                        Text { anchors.centerIn: parent; text: "✕"; color: look.text; font.pixelSize: 14 }
                        onClicked: root.hide()
                    }
                    // вид шторки: размеры и число карточек в ряд
                    GTile {
                        ui: look
                        anchors { right: closeTile.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        width: 36; height: 36; radius: 18
                        on: root.viewOpen
                        Text { anchors.centerIn: parent; text: "󰕮"; color: root.viewOpen ? "white" : look.text; font.family: look.iconFont; font.pixelSize: 15 }
                        onClicked: root.viewOpen = !root.viewOpen
                    }
                }

                // настройки вида: ширина, высота, колонки — сохраняются между запусками
                Flow {
                    id: viewBox
                    // в широком виде четыре группы настроек стоят в ряд, а не растягиваются каждая на всю ширину
                    readonly property int perRow: panel.wide ? 4 : 1
                    readonly property real cellW: (width - spacing * (perRow - 1)) / perRow
                    anchors.top: header.bottom
                    anchors.topMargin: root.viewOpen ? 8 : 0
                    width: parent.width
                    spacing: 14
                    visible: height > 0
                    height: root.viewOpen ? implicitHeight : 0
                    clip: true
                    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Column {
                        width: viewBox.cellW; spacing: 6
                        Text { text: Tr.t("Стиль"); color: look.sub; font.family: look.font; font.pixelSize: 11 }
                        GSegment {
                            ui: look
                            options: [{ v: "desktop", t: Tr.t("Десктопный: окно"), icon: "󰍹" }, { v: "mobile", t: Tr.t("Мобильный: шторка"), icon: "󰏲" }]
                            value: panel.mobile ? "mobile" : "desktop"
                            onPicked: (v) => root.setView("style", v)
                        }
                    }
                    Column {
                        width: viewBox.cellW; spacing: 6
                        Text { text: Tr.t("Где открывается"); color: look.sub; font.family: look.font; font.pixelSize: 11 }
                        GSegment {
                            ui: look
                            options: [{ v: "left", t: Tr.t("Слева") }, { v: "center", t: Tr.t("По центру") }, { v: "right", t: Tr.t("Справа") }]
                            value: panel.align
                            onPicked: (v) => root.setView("align", v)
                        }
                    }
                    Column {
                        width: viewBox.cellW; spacing: 6
                        Text { text: Tr.t("Ширина"); color: look.sub; font.family: look.font; font.pixelSize: 11 }
                        GSegment {
                            ui: look
                            options: [{ v: "narrow", t: Tr.t("Узкая") }, { v: "normal", t: Tr.t("Обычная") }, { v: "wide", t: Tr.t("Широкая") }, { v: "full", t: Tr.t("Во всю ширину") }]
                            value: panel.wmode
                            onPicked: (v) => root.setView("wmode", v)
                        }
                    }
                    Column {
                        width: viewBox.cellW; spacing: 6
                        Text { text: Tr.t("Карточек в ряд"); color: look.sub; font.family: look.font; font.pixelSize: 11 }
                        GSegment { ui: look; options: [{ v: "1", t: "1" }, { v: "2", t: "2" }, { v: "3", t: "3" }]; value: String(root.view.cols || 2); onPicked: (v) => root.setView("cols", Number(v)) }
                    }
                    Text { width: viewBox.width; wrapMode: Text.WordWrap; text: Tr.t("Высоту меняет ручка внизу шторки: тяните вниз или вверх, двойное нажатие — по содержимому"); color: look.sub; font.family: look.font; font.pixelSize: 11 }
                }

                GSegment {
                    id: tabBar
                    ui: look
                    anchors.top: viewBox.bottom
                    anchors.topMargin: 12
                    options: [{ v: "0", t: Tr.t("Темы"), icon: "󰏘" }, { v: "1", t: Tr.t("Окна"), icon: "󰖲" }, { v: "2", t: Tr.t("Система"), icon: "󰒓" }, { v: "3", t: Tr.t("Курсор"), icon: "󰆿" }]
                    value: String(root.tab)
                    onPicked: (v) => root.tab = Number(v)
                }

                // страницы: сдвиг и проявление при смене вкладки
                Item {
                    id: pages
                    anchors { top: tabBar.bottom; topMargin: 16; left: parent.left; right: parent.right; bottom: parent.bottom }
                    clip: true
                    readonly property real currentHeight: [pageThemes, pageWindows, pageSystem, pageCursor][root.tab].implicitHeight + 12

                    Page { index: 0; tab: root.tab; body: pageThemes }
                    Page { index: 1; tab: root.tab; body: pageWindows }
                    Page { index: 2; tab: root.tab; body: pageSystem }
                    Page { index: 3; tab: root.tab; body: pageCursor }
                }
            }

            // ручка: тянуть вниз — выше, вверх — ниже, до конца вверх — закрыть; двойное нажатие — высота по содержимому
            Item {
                id: grip
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 34
                Rectangle { anchors.centerIn: parent; width: 52; height: 5; radius: 2.5; color: look.text; opacity: gma.containsMouse || gdrag.active ? 0.7 : 0.35 }
                MouseArea { id: gma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.SizeVerCursor; acceptedButtons: Qt.NoButton }
                TapHandler { onDoubleTapped: { root.setView("height", 0); panel.dragDy = 0; } }
                DragHandler {
                    id: gdrag
                    target: null
                    xAxis.enabled: false
                    onTranslationChanged: if (active) panel.dragDy = translation.y
                    onActiveChanged: if (!active) {
                        var h = panel.baseH + panel.dragDy;
                        if (h < panel.minH - 80) root.hide();
                        else root.setView("height", Math.round(Math.max(panel.minH, Math.min(panel.maxH, h))));
                        panel.dragDy = 0;
                    }
                }
            }
        }

        // ---------- применение шаблона: весь экран размыт, по центру — индикатор ----------
        Item {
            id: applyingLayer
            anchors.fill: parent
            opacity: root.applying !== "" ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            // клики не проходят к шторке, пока идёт применение
            MouseArea { anchors.fill: parent; hoverEnabled: true }
            MultiEffect {
                anchors.fill: parent
                source: snapTex
                visible: snap.hasContent
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 48
                blur: 1.0
                saturation: -0.2
            }
            Rectangle { anchors.fill: parent; color: "black"; opacity: 0.35 }

            GTile {
                ui: look
                anchors.centerIn: parent
                width: 360
                height: card.implicitHeight + 48
                radius: 32
                fillAlpha: 0.16
                scale: applyingLayer.visible ? 1 : 0.96
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                Column {
                    id: card
                    anchors.centerIn: parent
                    width: parent.width - 56
                    spacing: 18

                    // кольцо: заполняется по этапам; в центре — номер шага или галочка
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 108; height: 108
                        ProgressRing {
                            anchors.fill: parent
                            thickness: 7
                            color: look.accent
                            track: look.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
                            progress: (root.applyIndex + (root.applyFinished ? 0 : 0.5)) / root.applySteps.length
                            spinning: !root.applyFinished
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !root.applyFinished
                            text: Math.min(root.applyIndex + 1, root.applySteps.length) + "/" + root.applySteps.length
                            color: look.text
                            font.family: look.font
                            font.pixelSize: 20
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "󰄬"
                            color: look.accent
                            font.family: look.iconFont
                            font.pixelSize: 46
                            opacity: root.applyFinished ? 1 : 0
                            scale: root.applyFinished ? 1 : 0.4
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                        }
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 4
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.applyFinished ? Tr.t("Готово") : Tr.t("Применяю оформление")
                            color: look.text
                            font.family: look.font
                            font.pixelSize: 19
                            font.weight: Font.Bold
                            font.letterSpacing: look.ios ? -0.3 : 0
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: { var t = root.themeInfo(root.applying); return t ? "«" + t.name + "»" : ""; }
                            color: look.sub
                            font.family: look.font
                            font.pixelSize: 13
                        }
                    }

                    // шаги
                    Column {
                        width: parent.width
                        spacing: 10
                        Repeater {
                            model: root.applySteps
                            Item {
                                id: step
                                required property var modelData
                                required property int index
                                readonly property bool done: index < root.applyIndex
                                readonly property bool active: index === root.applyIndex && !root.applyFinished
                                width: parent.width
                                height: 26

                                // состояние: точка → кольцо → галочка
                                Item {
                                    id: mark
                                    width: 22; height: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: step.done ? 22 : 8
                                        height: width
                                        radius: width / 2
                                        color: step.done ? look.accent : look.fill(0.25)
                                        visible: !step.active
                                        Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: step.done
                                            text: "󰄬"
                                            color: "white"
                                            font.family: look.iconFont
                                            font.pixelSize: 13
                                        }
                                    }
                                    ProgressRing {
                                        anchors.fill: parent
                                        visible: step.active
                                        thickness: 2.5
                                        progress: 0.3
                                        color: look.accent
                                        track: "transparent"
                                    }
                                }
                                Text {
                                    anchors { left: mark.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                    text: step.modelData.t
                                    color: step.done || step.active ? look.text : look.sub
                                    font.family: look.font
                                    font.pixelSize: 14
                                    font.weight: step.active ? Font.DemiBold : Font.Normal
                                }
                                Text {
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    text: step.modelData.icon
                                    color: step.active ? look.accent : look.sub
                                    opacity: step.done || step.active ? 1 : 0.5
                                    font.family: look.iconFont
                                    font.pixelSize: 15
                                }
                            }
                        }
                    }
                }
            }
        }

        // ================= Темы =================
        Item {
            id: pageThemes
            visible: false
            width: panel.width - 52
            // широкий вид: слева шаблоны и сохранённые шаблоны, справа остальное; узкий — одной колонкой друг под другом
            readonly property real gap: 24
            readonly property int cols: !panel.wide ? 1 : (width >= 1500 ? 3 : 2)        // очень широкий экран — три колонки
            readonly property real colW: (width - gap * (cols - 1)) / cols
            implicitHeight: cols === 3 ? Math.max(themesLeft.implicitHeight, themesRight.implicitHeight, themesThird.implicitHeight)
                          : (cols === 2 ? Math.max(themesLeft.implicitHeight, themesRight.implicitHeight + 18 + themesThird.implicitHeight)
                                        : themesLeft.implicitHeight + 18 + themesRight.implicitHeight + 18 + themesThird.implicitHeight)

            Column {
                id: themesLeft
                width: pageThemes.colW
                spacing: 18

                Text { text: Tr.t("Шаблоны"); color: look.sub; font.family: look.font; font.pixelSize: 12; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.8; leftPadding: 4 }
                Grid {
                    id: tplGrid
                    readonly property int cols: panel.wide ? Math.max(1, Math.min(root.view.cols || 2, 6,  Math.floor(themesLeft.width / 300))) : Math.max(1, root.view.cols || 2)
                    columns: cols
                    spacing: 10
                    Repeater {
                        model: root.visibleTemplates
                        TemplateCard {
                            required property var modelData
                            readonly property var info: root.themeInfo(modelData.id)
                            ui: look
                            width: (themesLeft.width - 10 * (tplGrid.cols - 1)) / tplGrid.cols
                            height: 140
                            kind: modelData.kind
                            title: info ? info.name : modelData.id
                            sub: modelData.sub
                            scheme: info ? root.paletteOf(info.palette) : null
                            tAccent: root.accentOf(info)
                            current: root.st.current === modelData.id
                            busy: root.applying === modelData.id
                            active: root.applying === "" || busy
                            onClicked: root.applyTheme(modelData.id)
                        }
                    }
                }

                // праздничные шаблоны: когда появляются; показывать все; включать самим
                Column {
                    width: Math.min(parent.width, panel.contentCap)
                    spacing: 8
                    Text { text: Tr.t("Праздничные шаблоны"); color: look.sub; font.family: look.font; font.pixelSize: 12; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.8; leftPadding: 4 }
                    Repeater {
                        model: root.st.seasonal ? root.st.seasonal.seasons : []
                        Row {
                            required property var modelData
                            width: parent.width; spacing: 8; leftPadding: 4
                            Text { text: modelData.active ? "●" : "○"; color: modelData.active ? look.accent : look.sub; font.pixelSize: 11 }
                            Text {
                                width: parent.width - 30; wrapMode: Text.WordWrap
                                text: modelData.name + Tr.t(" — с ") + modelData.fromText + Tr.t(" по ") + modelData.toText + (modelData.active ? Tr.t("  ·  сейчас доступен") : "")
                                color: modelData.active ? look.text : look.sub; font.family: look.font; font.pixelSize: 12
                            }
                        }
                    }
                    GSwitch {
                        ui: look; label: Tr.t("Показывать все праздничные"); sub: Tr.t("иначе шаблон виден только в свои даты")
                        checked: root.st.seasonal && root.st.seasonal.showAll === true
                        onToggled: (v) => root.run(["seasonal", "set", "showAll", v ? "true" : "false"])
                    }
                    GSwitch {
                        ui: look; label: Tr.t("Включать в праздник сами"); sub: Tr.t("в начале праздника — шаблон, по окончании — прежняя тема")
                        checked: root.st.seasonal && root.st.seasonal.auto === true
                        onToggled: (v) => root.run(["seasonal", "set", "auto", v ? "true" : "false"])
                    }
                }

                // мои шаблоны: свои темы карточками — применить, сделать копию, удалить (с подтверждением)
                Item {
                    width: Math.min(parent.width, panel.contentCap)
                    height: 22
                    Text { anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Мои шаблоны · ") + root.st.themes.filter(function (t) { return !t.preset; }).length; color: look.sub; font.family: look.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7 }
                }
                // сохранить текущие настройки как новый шаблон
                Row {
                    width: Math.min(parent.width, panel.contentCap)
                    spacing: 8
                    GField {
                        id: newName
                        ui: look
                        icon: "󰆓"
                        width: parent.width - createBtn.width - 8
                        placeholder: Tr.t("название шаблона")
                        onAccepted: createBtn.clicked()
                    }
                    GButton {
                        id: createBtn
                        ui: look
                        label: Tr.t("Сохранить")
                        icon: "󰆓"
                        on: true
                        onClicked: {
                            // без названия — «Моя тема N»: раньше пустое поле молча ничего не сохраняло
                            var n = newName.text.trim();
                            if (n === "") n = Tr.t("Моя тема ") + (root.st.themes.filter(function (t) { return !t.preset; }).length + 1);
                            saveProc.command = [root.script, "new", n];
                            saveProc.running = true;
                            root.savedNote = Tr.t("Сохранено: «") + n + "»";
                            newName.clear();
                        }
                    }
                }
                Text {
                    visible: root.savedNote !== ""
                    text: "󰄬  " + root.savedNote
                    color: look.accent; font.family: look.iconFont; font.pixelSize: 12
                }
                Text {
                    visible: root.st.themes.filter(function (t) { return !t.preset; }).length === 0
                    width: parent.width; wrapMode: Text.WordWrap
                    text: Tr.t("Пока пусто. Настройте тему как нравится и сохраните — шаблон появится здесь, его можно применить в один клик, скопировать или удалить.")
                    color: look.sub; font.family: look.font; font.pixelSize: 12
                }
                Grid {
                    id: mine
                    width: parent.width
                    readonly property int cols: panel.wide ? Math.max(1, Math.min(root.view.cols || 2, 6,  Math.floor(themesLeft.width / 300))) : Math.max(1, root.view.cols || 2)
                    columns: cols
                    spacing: 8
                    readonly property real cw: (width - spacing * (cols - 1)) / cols
                    Repeater {
                        model: root.st.themes.filter(function (t) { return !t.preset; })
                        Item {
                            id: mt
                            required property var modelData
                            readonly property bool cur: root.st.current === modelData.id
                            property bool armed: false
                            width: mine.cw; height: 78
                            Rectangle {
                                anchors.fill: parent
                                radius: look.r(18)
                                color: mt.cur ? Qt.rgba(look.accent.r, look.accent.g, look.accent.b, 0.18) : look.fill(mtMa.containsMouse ? 0.12 : 0.07)
                                border.width: mt.cur ? 1.5 : (look.ios ? 0 : 1)
                                border.color: mt.cur ? look.accent : look.line(0.16)
                            }
                            MouseArea { id: mtMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (!mt.cur) root.applyTheme(mt.modelData.id) }
                            Rectangle {
                                id: sw
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                width: 40; height: 40; radius: look.r(12)
                                gradient: Gradient {
                                    GradientStop { position: 0; color: root.accentOf(mt.modelData) }
                                    GradientStop { position: 1; color: Qt.darker(root.accentOf(mt.modelData), 1.8) }
                                }
                            }
                            Column {
                                anchors { left: sw.right; leftMargin: 12; right: acts.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                Text { width: parent.width; elide: Text.ElideRight; text: mt.modelData.name; color: look.text; font.family: look.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                                Text { width: parent.width; elide: Text.ElideRight; text: mt.cur ? Tr.t("применён") : ({ classic: Tr.t("Классика"), liquid: Tr.t("Жидкое стекло"), ios: "iOS" })[mt.modelData.kit] || (mt.modelData.palette || ""); color: look.sub; font.family: look.font; font.pixelSize: 11 }
                            }
                            Row {
                                id: acts
                                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                spacing: 2
                                // копия: применить и сохранить под новым именем
                                GTile {
                                    ui: look; width: 30; height: 30; radius: 15
                                    Text { anchors.centerIn: parent; text: "󰆏"; color: look.text; font.family: look.iconFont; font.pixelSize: 14 }
                                    onClicked: root.run(["copy", mt.modelData.id, mt.modelData.name + Tr.t(" — копия")])
                                }
                                // удаление: первое нажатие — «точно?», второе — удалить
                                GTile {
                                    ui: look; width: mt.armed ? 74 : 30; height: 30; radius: 15
                                    on: mt.armed
                                    onColor: look.red
                                    Text { anchors.centerIn: parent; text: mt.armed ? Tr.t("Удалить") : "󰆴"; color: mt.armed ? "white" : look.red; font.family: mt.armed ? look.font : look.iconFont; font.pixelSize: mt.armed ? 11 : 14 }
                                    onClicked: { if (mt.armed) root.run(["delete", mt.modelData.id]); else { mt.armed = true; disarm.restart(); } }
                                    Timer { id: disarm; interval: 3000; onTriggered: mt.armed = false }
                                }
                            }
                        }
                    }
                }

            }

            Column {
                id: themesRight
                x: pageThemes.cols >= 2 ? pageThemes.colW + pageThemes.gap : 0
                y: pageThemes.cols >= 2 ? 0 : themesLeft.implicitHeight + 18
                width: pageThemes.colW
                spacing: 18
                GSegment {
                    width: Math.min(parent.width, panel.contentCap)
                    ui: look
                    options: [{ v: "dark", t: Tr.t("Тёмное"), icon: "󰖔" }, { v: "light", t: Tr.t("Светлое"), icon: "󰖨" }]
                    value: look.dark ? "dark" : "light"
                    onPicked: (v) => { if (root.curPal && root.curPal.pair) root.set(".palette", root.curPal.pair); }
                }

                // космос вместо обоев: звёздное небо или небо с солнечной системой (подробности — «Рабочий стол» → «Космос»)
                Column {
                    width: Math.min(parent.width, panel.contentCap)
                    spacing: 6
                    opacity: root.th.shell === "nameless" ? 1 : 0.4
                    readonly property string mode: root.th.sky === true || root.th.sky === "solar" ? "solar" : (root.th.sky === "stars" || root.th.sky === "apps" ? root.th.sky : "off")
                    Text { width: parent.width; wrapMode: Text.WordWrap; text: Tr.t("Вместо обоев: звёздное небо (вид с Земли) или космос (солнечная система)"); color: look.text; font.family: look.font; font.pixelSize: 13 }
                    GSegment {
                        ui: look
                        options: [{ v: "off", t: Tr.t("Обои"), icon: "󰸉" }, { v: "stars", t: Tr.t("Звёздное небо"), icon: "󰖔" }, { v: "solar", t: Tr.t("Астрономия"), icon: "󰖨" }, { v: "apps", t: Tr.t("Орбиты окон"), icon: "󰍹" }]
                        value: parent.mode
                        onPicked: (v) => { if (root.th.shell === "nameless") root.set(".sky", v === "off" ? false : v); }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: Tr.t("обои выключаются целиком; звёзды, туманности, Луна и планеты настраиваются в «Рабочий стол» → «Космос» (SUPER+W)")
                        color: look.sub; font.family: look.font; font.pixelSize: 11
                    }
                }
                GSwitch {
                    width: Math.min(parent.width, panel.contentCap)
                    ui: look
                    label: Tr.t("Цвет из обоев")
                    sub: Tr.t("акцент и второй цвет подбираются под каждые обои")
                    checked: root.th.accent_from_wallpaper === true
                    onToggled: (v) => root.set(".accent_from_wallpaper", v)
                }
                AccentPicker {
                    width: Math.min(parent.width, panel.contentCap)
                    ui: look
                    visible: root.th.accent_from_wallpaper !== true
                    value: root.th.accent || ""
                    autoColor: look.c ? look.c.blue : "#0a84ff"
                    onPicked: (v) => root.set(".accent", v)
                }

                Column {
                    width: Math.min(parent.width, panel.contentCap)
                    spacing: 10
                    PillSlider {
                        ui: look; width: parent.width
                        icon: "󰂵"; label: Tr.t("Матовость стекла")
                        from: 0; to: 0.8; value: root.gl.tint !== undefined ? root.gl.tint : 0.22
                        display: 100; suffix: " %"
                        active: root.th.style === "glass"
                        onCommitted: (v) => root.set(".glass.tint", v)
                    }
                    PillSlider {
                        ui: look; width: parent.width
                        icon: "󰢡"; label: Tr.t("Скругление")
                        from: 0; to: 30; stepSize: 1; decimals: 0; value: root.hy.rounding || 0
                        onCommitted: (v) => root.set(".hypr.rounding", v)
                    }
                    PillSlider {
                        ui: look; width: parent.width
                        icon: "󰕰"; label: Tr.t("Отступы")
                        from: 0; to: 40; stepSize: 1; decimals: 0; value: root.hy.gaps_out || 0
                        onCommitted: (v) => { root.set(".hypr.gaps_out", v); root.set(".hypr.gaps_in", Math.round(v * 0.45)); }
                    }
                }

            }

            // третья колонка (на очень широком экране): быстрые переключатели и действия
            Column {
                id: themesThird
                x: pageThemes.cols === 3 ? 2 * (pageThemes.colW + pageThemes.gap) : (pageThemes.cols === 2 ? pageThemes.colW + pageThemes.gap : 0)
                y: pageThemes.cols === 3 ? 0 : (pageThemes.cols === 2 ? themesRight.implicitHeight + 18 : themesLeft.implicitHeight + 18 + themesRight.implicitHeight + 18)
                width: pageThemes.colW
                spacing: 18

                // быстрые переключатели: «Вид» — что включено сейчас, «Действия» — разовые команды
                Text { text: Tr.t("Вид"); color: look.sub; font.family: look.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.8; leftPadding: 4 }
                Grid {
                    id: quick
                    width: parent.width
                    // чем шире шторка, тем больше плиток в ряду
                    readonly property int cols: width > 900 ? 6 : (width > 420 ? 4 : 3)
                    columns: cols
                    spacing: 10
                    readonly property real cell: (width - spacing * (cols - 1)) / cols
                readonly property real tileH: panel.wide ? 76 : cell * 0.92
                    GToggleTile {
                        ui: look; width: quick.cell; height: quick.tileH
                        icon: "󰂵"; label: Tr.t("Стекло"); sub: on ? Tr.t("Вкл.") : Tr.t("Выкл.")
                        on: root.th.style === "glass"
                        onClicked: root.set(".style", on ? "solid" : "glass")
                    }
                    GToggleTile {
                        ui: look; width: quick.cell; height: quick.tileH
                        icon: "󰃞"; label: Tr.t("Размытие"); sub: on ? Tr.t("Вкл.") : Tr.t("Выкл.")
                        on: root.hy.blur === true
                        onClicked: root.set(".hypr.blur", !on)
                    }
                    GToggleTile {
                        ui: look; width: quick.cell; height: quick.tileH
                        icon: "󰐊"; label: Tr.t("Анимации"); sub: on ? Tr.t("Вкл.") : Tr.t("Выкл.")
                        on: root.hy.animations === true
                        onClicked: root.set(".hypr.animations", !on)
                    }
                    GToggleTile {
                        ui: look; width: quick.cell; height: quick.tileH
                        icon: "󰕮"; label: Tr.t("Док"); sub: on ? Tr.t("Вкл.") : Tr.t("Выкл.")
                        on: root.th.dock === true
                        active: root.th.shell === "macshell" || root.th.shell === "nameless"
                        onClicked: root.set(".dock", !on)
                    }
                }
                Text { text: Tr.t("Действия"); color: look.sub; font.family: look.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.8; leftPadding: 4 }
                Grid {
                    id: acts2
                    width: parent.width
                    columns: quick.cols
                    spacing: 10
                    readonly property real cell: quick.cell
                    GToggleTile {
                        ui: look; width: acts2.cell; height: quick.tileH
                        icon: root.st.dnd === true ? "󰂛" : "󰂚"; label: Tr.t("Тишина"); sub: on ? Tr.t("Не беспокоить: вкл.") : Tr.t("Не беспокоить")
                        on: root.st.dnd === true
                        onClicked: { root.run(["action", "notif-dnd"]); dndRefresh.restart(); }
                        Timer { id: dndRefresh; interval: 900; onTriggered: root.refresh() }
                    }
                    GToggleTile { ui: look; width: acts2.cell; height: quick.tileH; icon: "󰹑"; label: Tr.t("Скриншот"); onClicked: root.act("screenshot") }
                    GToggleTile { ui: look; width: acts2.cell; height: quick.tileH; icon: "󰌾"; label: Tr.t("Блокировка"); onClicked: root.act("lock") }
                    GToggleTile { ui: look; width: acts2.cell; height: quick.tileH; icon: "󰸉"; label: Tr.t("Обои"); sub: Tr.t("Мастер обоев"); onClicked: root.act("wallpapers") }
                    GToggleTile { ui: look; width: acts2.cell; height: quick.tileH; icon: "󰒝"; label: Tr.t("Следующие"); sub: Tr.t("обои"); onClicked: root.run(["action", "wallpaper-next"]) }
                    GToggleTile { ui: look; width: acts2.cell; height: quick.tileH; icon: "󰓅"; label: Tr.t("Диспетчер"); sub: Tr.t("задач"); onClicked: root.act("tasks") }
                }
            }
        }

        // ================= Окна =================
        Grid {
            id: pageWindows
            visible: false
            width: panel.width - 52
            columns: panel.pageCols
            columnSpacing: 18
            rowSpacing: 18

            GSection {
                ui: look; title: Tr.t("Форма")
                GSlider { ui: look; label: Tr.t("Отступы между окнами"); to: 30; value: root.hy.gaps_in || 0; onCommitted: (v) => root.set(".hypr.gaps_in", v) }
                GSlider { ui: look; label: Tr.t("Отступы от краёв"); to: 60; value: root.hy.gaps_out || 0; onCommitted: (v) => root.set(".hypr.gaps_out", v) }
                GSlider { ui: look; label: Tr.t("Скругление"); to: 30; value: root.hy.rounding || 0; onCommitted: (v) => root.set(".hypr.rounding", v) }
                GSlider { ui: look; label: Tr.t("Толщина рамки"); to: 6; value: root.hy.border_size || 0; onCommitted: (v) => root.set(".hypr.border_size", v) }
            }
            GSection {
                ui: look; title: Tr.t("Прозрачность")
                GSlider {
                    ui: look; label: Tr.t("Активные окна"); from: 50; to: 100; suffix: " %"
                    value: Math.round((root.hy.active_opacity || 1) * 100)
                    onCommitted: (v) => root.set(".hypr.active_opacity", v / 100)
                }
                GSlider {
                    ui: look; label: Tr.t("Неактивные окна"); from: 50; to: 100; suffix: " %"
                    value: Math.round((root.hy.inactive_opacity || 1) * 100)
                    onCommitted: (v) => root.set(".hypr.inactive_opacity", v / 100)
                }
            }
            // правила оформления окон по приложениям (прозрачность): тема хранит значения, theme.sh пишет их правилами Hyprland
            GSection {
                id: rulesSec
                ui: look; title: Tr.t("Правила окон")
                readonly property var ar: root.th.app_rules || ({})
                GSwitch {
                    ui: look; label: Tr.t("Свои правила по приложениям"); sub: Tr.t("терминал, Telegram, Code и Dolphin — своя прозрачность")
                    checked: rulesSec.ar.on !== false
                    onToggled: (v) => root.set(".app_rules.on", v)
                }
                GSlider { ui: look; label: Tr.t("Терминал (kitty)"); from: 50; to: 100; suffix: " %"; value: Math.round((rulesSec.ar.kitty !== undefined ? rulesSec.ar.kitty : 0.92) * 100); active: rulesSec.ar.on !== false; onCommitted: (v) => root.set(".app_rules.kitty", v / 100) }
                GSlider { ui: look; label: "Telegram"; from: 50; to: 100; suffix: " %"; value: Math.round((rulesSec.ar.telegram !== undefined ? rulesSec.ar.telegram : 0.95) * 100); active: rulesSec.ar.on !== false; onCommitted: (v) => root.set(".app_rules.telegram", v / 100) }
                GSlider { ui: look; label: "Code"; from: 50; to: 100; suffix: " %"; value: Math.round((rulesSec.ar.code !== undefined ? rulesSec.ar.code : 0.93) * 100); active: rulesSec.ar.on !== false; onCommitted: (v) => root.set(".app_rules.code", v / 100) }
                GSlider { ui: look; label: "Dolphin"; from: 50; to: 100; suffix: " %"; value: Math.round((rulesSec.ar.dolphin !== undefined ? rulesSec.ar.dolphin : 0.90) * 100); active: rulesSec.ar.on !== false; onCommitted: (v) => root.set(".app_rules.dolphin", v / 100) }
            }
            GSection {
                ui: look; title: Tr.t("Размытие и эффекты")
                GSwitch { ui: look; label: Tr.t("Размытие"); checked: root.hy.blur === true; onToggled: (v) => root.set(".hypr.blur", v) }
                GSlider { ui: look; label: Tr.t("Сила"); from: 1; to: 16; value: root.hy.blur_size || 1; active: root.hy.blur === true; onCommitted: (v) => root.set(".hypr.blur_size", v) }
                GSlider { ui: look; label: Tr.t("Проходы"); from: 1; to: 6; value: root.hy.blur_passes || 1; active: root.hy.blur === true; onCommitted: (v) => root.set(".hypr.blur_passes", v) }
                GSwitch { ui: look; label: Tr.t("Тени"); checked: root.hy.shadow === true; onToggled: (v) => root.set(".hypr.shadow", v) }
                GSwitch { ui: look; label: Tr.t("Анимации"); checked: root.hy.animations === true; onToggled: (v) => root.set(".hypr.animations", v) }
                GSwitch {
                    ui: look; label: Tr.t("Переливающаяся рамка"); sub: Tr.t("градиент акцентов бежит по рамке активного окна")
                    checked: root.th.border_anim === true
                    active: root.hy.animations === true
                    onToggled: (v) => root.set(".border_anim", v)
                }
            }
            GSection {
                ui: look; title: Tr.t("Жидкое стекло")
                GSwitch {
                    ui: look; label: Tr.t("Стеклянные панели"); sub: Tr.t("waybar, уведомления, rofi, MacShell")
                    checked: root.th.style === "glass"
                    onToggled: (v) => root.set(".style", v ? "glass" : "solid")
                }
                // стекло выключено — стеклянным панелям неоткуда браться: подсказка и отключённые ползунки
                Text {
                    visible: root.th.style !== "glass"
                    width: parent.width; wrapMode: Text.WordWrap
                    text: Tr.t("Стекло выключено: панели, уведомления, rofi и MacShell сплошные, матовость и преломление не действуют")
                    color: look.sub; font.family: look.font; font.pixelSize: 11
                }
                GSlider {
                    ui: look; label: Tr.t("Матовость"); from: 0; to: 80; suffix: " %"
                    value: Math.round((root.gl.tint !== undefined ? root.gl.tint : 0.22) * 100)
                    active: root.th.style === "glass"
                    onCommitted: (v) => root.set(".glass.tint", v / 100)
                }
                GSlider {
                    ui: look; label: Tr.t("Преломление"); from: 0; to: 200; suffix: " %"
                    value: Math.round((root.gl.strength !== undefined ? root.gl.strength : 1) * 100)
                    active: root.th.style === "glass"
                    onCommitted: (v) => root.set(".glass.strength", v / 100)
                }
            }
            GSection {
                ui: look; title: Tr.t("Второй цвет рамки")
                AccentPicker {
                    ui: look
                    value: root.th.accent2 || ""
                    autoColor: look.c ? look.c.lavender : "#5e5ce6"
                    colors: ["#5e5ce6", "#bf5af2", "#ff375f", "#ff9f0a", "#30d158", "#64d2ff", "#b7bdf8", "#94e2d5"]
                    onPicked: (v) => root.set(".accent2", v)
                }
            }
        }

        // ================= Курсор: переход между компьютерами =================
        Grid {
            id: pageCursor
            visible: false
            width: panel.width - 52
            columns: panel.pageCols
            columnSpacing: 18
            rowSpacing: 18

            GSection {
                ui: look; title: Tr.t("Переход курсора")
                GSwitch {
                    ui: look; label: Tr.t("Курсор переходит на соседний компьютер")
                    sub: Tr.t("упёрся в край — мышь и клавиатура управляют компьютером за этим краем (NameLess Orbit). Обратно — тем же краем или Scroll Lock")
                    checked: root.cross.enabled === true
                    onToggled: (v) => root.crossSet("enabled", v)
                }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: !root.orbitUp ? Tr.t("Orbit не запущен: соседи появятся, когда он будет на связи") : (root.crossPeers.length === 0 ? Tr.t("Нет подключённых компьютеров. На соседнем должен быть свежий Orbit и разрешена «Демонстрация экрана» для этого компьютера") : Tr.t("Где стоит каждый сосед относительно этого экрана:"))
                    color: look.sub; font.family: look.font; font.pixelSize: 12
                }
                Repeater {
                    model: root.crossPeers
                    Column {
                        required property var modelData
                        width: parent.width
                        spacing: 6
                        Text { text: modelData.name + (modelData.ok ? "" : Tr.t(" — нет перехода курсора (старый Orbit или не Hyprland)")); color: modelData.ok ? look.text : look.sub; font.family: look.font; font.pixelSize: 13 }
                        GSegment {
                            ui: look
                            visible: modelData.ok
                            options: [{ v: "off", t: Tr.t("Нет") }, { v: "left", t: Tr.t("Слева"), icon: "󰁍" }, { v: "right", t: Tr.t("Справа"), icon: "󰁔" }, { v: "top", t: Tr.t("Сверху"), icon: "󰁝" }, { v: "bottom", t: Tr.t("Снизу"), icon: "󰁅" }]
                            value: root.sideOf(modelData.id)
                            onPicked: (v) => root.crossSide(modelData.id, modelData.name, v)
                        }
                    }
                }
                GButton { ui: look; height: 34; icon: "󰑐"; label: Tr.t("Обновить список"); onClicked: if (!crossDevs.running) crossDevs.running = true }
            }

            GSection {
                ui: look; title: Tr.t("Эффект на краях")
                Text { width: parent.width; wrapMode: Text.WordWrap; text: Tr.t("где курсор ушёл и где пришёл — на обоих компьютерах"); color: look.sub; font.family: look.font; font.pixelSize: 12 }
                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: [{ v: "glow", t: Tr.t("Свечение"), i: "󰛨" }, { v: "ripple", t: Tr.t("Волна"), i: "󰖟" }, { v: "sparks", t: Tr.t("Искры"), i: "󰸞" },
                                { v: "line", t: Tr.t("Линия"), i: "󰕞" }, { v: "portal", t: Tr.t("Портал"), i: "󰕰" }, { v: "none", t: Tr.t("Без эффекта"), i: "󰜺" }]
                        GTile {
                            required property var modelData
                            ui: look
                            width: 104; height: 70
                            on: (root.cross.effect || "glow") === modelData.v
                            onClicked: { root.crossSet("effect", modelData.v); if (modelData.v !== "none") prevT.restart(); }
                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.i; color: look.text; font.family: look.iconFont; font.pixelSize: 20 }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.t; color: look.text; font.family: look.font; font.pixelSize: 11 }
                            }
                        }
                    }
                }
                // показ после выбора: ipc доходит до NameLess раньше, чем он применит значение, поэтому — с задержкой
                Timer { id: prevT; interval: 350; onTriggered: Quickshell.execDetached(["qs", "-c", "nameless", "ipc", "call", "crossing", "preview"]) }
                Text { text: Tr.t("Цвет"); color: look.text; font.family: look.font; font.pixelSize: 13 }
                GSegment {
                    ui: look
                    options: [{ v: "accent", t: Tr.t("Акцент") }, { v: "accent2", t: Tr.t("Второй акцент") }, { v: "white", t: Tr.t("Белый") }]
                    value: root.cross.color || "accent"
                    onPicked: (v) => { root.crossSet("color", v); prevT.restart(); }
                }
                PillSlider {
                    ui: look; width: parent.width
                    icon: "󰔛"; label: Tr.t("Длительность")
                    from: 300; to: 1600; stepSize: 50; decimals: 0; suffix: Tr.t(" мс")
                    value: root.cross.duration || 700
                    onCommitted: (v) => { root.crossSet("duration", Math.round(v)); prevT.restart(); }
                }
                PillSlider {
                    ui: look; width: parent.width
                    icon: "󰃠"; label: Tr.t("Сила")
                    from: 0.5; to: 2; stepSize: 0.1; decimals: 1
                    value: root.cross.intensity || 1
                    onCommitted: (v) => { root.crossSet("intensity", v); prevT.restart(); }
                }
                PillSlider {
                    ui: look; width: parent.width
                    icon: "󰥔"; label: Tr.t("Задержка на краю")
                    from: 0; to: 500; stepSize: 10; decimals: 0; suffix: Tr.t(" мс")
                    value: root.cross.delay === undefined ? 120 : root.cross.delay
                    onCommitted: (v) => root.crossSet("delay", Math.round(v))
                }
                GButton { ui: look; height: 34; icon: "󰐊"; label: Tr.t("Показать эффект"); onClicked: prevT.restart() }
            }
        }

        // ================= Система =================
        Grid {
            id: pageSystem
            visible: false
            width: panel.width - 52
            columns: panel.pageCols
            columnSpacing: 18
            rowSpacing: 18

            GSection {
                ui: look; title: Tr.t("Оболочка")
                Text { text: Tr.t("Панель"); color: look.text; font.family: look.font; font.pixelSize: 13 }
                GSegment {
                    ui: look
                    options: [{ v: "nameless", t: "NameLess" }, { v: "waybar", t: "Waybar" }, { v: "macshell", t: "MacShell", on: root.st.hasQs }]
                    value: root.th.shell || "waybar"
                    onPicked: (v) => root.set(".shell", v)
                }
                Text { text: Tr.t("Экран блокировки"); color: look.text; font.family: look.font; font.pixelSize: 13 }
                GSegment {
                    ui: look
                    options: [{ v: "nameless", t: "NameLess" }, { v: "hyprlock", t: "Hyprlock" }, { v: "maclock", t: "MacLock", on: root.st.hasQs }]
                    value: root.th.lock || "hyprlock"
                    onPicked: (v) => root.set(".lock", v)
                }
                Text { text: Tr.t("Лаунчер"); color: look.text; font.family: look.font; font.pixelSize: 13 }
                GSegment {
                    ui: look
                    options: [{ v: "nameless", t: "NameLess", on: root.th.shell === "nameless" }, { v: "rofi", t: "Rofi" }, { v: "spotlight", t: "Spotlight", on: root.th.shell === "macshell" }]
                    value: root.th.launcher || "rofi"
                    onPicked: (v) => root.set(".launcher", v)
                }
                Text { text: Tr.t("Вид лаунчера"); color: look.text; font.family: look.font; font.pixelSize: 13 }
                GSegment {
                    ui: look
                    options: [{ v: "list", t: Tr.t("Список"), icon: "󰉹" }, { v: "grid", t: Tr.t("Сетка"), icon: "󰕰" }, { v: "spot", t: "Spotlight", icon: "󰍉" }]
                    value: root.th.launcher_style || "list"
                    onPicked: (v) => root.set(".launcher_style", v)
                }
                GSwitch {
                    ui: look; label: Tr.t("Док"); sub: Tr.t("закреплённые и запущенные приложения внизу экрана")
                    checked: root.th.dock === true
                    active: root.th.shell === "macshell" || root.th.shell === "nameless"
                    onToggled: (v) => root.set(".dock", v)
                }
                GSwitch {
                    ui: look; label: Tr.t("Мини-приложения"); sub: Tr.t("часы, «пришло», система и плеер слева сверху")
                    checked: root.th.widgets === true
                    active: root.th.shell === "nameless"
                    onToggled: (v) => root.set(".widgets", v)
                }
                GSwitch {
                    ui: look; label: Tr.t("Счётчик кадров"); sub: Tr.t("FPS и частота монитора в баре")
                    checked: root.th.fps_counter === true
                    active: root.th.shell === "nameless"
                    onToggled: (v) => root.set(".fps_counter", v)
                }
            }
            GSection {
                ui: look; title: Tr.t("Палитра")
                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: root.st.palettes
                        GTile {
                            id: chip
                            required property var modelData
                            ui: look
                            width: palRow.implicitWidth + 26
                            height: 36
                            radius: 18
                            on: modelData.id === root.th.palette
                            Row {
                                id: palRow
                                anchors.centerIn: parent
                                spacing: 6
                                Repeater {
                                    model: ["base", "blue", "mauve", "green"]
                                    Rectangle {
                                        required property string modelData
                                        width: 10; height: 10; radius: 5
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: chip.modelData.colors[modelData]
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.4)
                                    }
                                }
                                Text { text: chip.modelData.name; color: chip.on ? "white" : look.text; font.family: look.font; font.pixelSize: 12 }
                            }
                            onClicked: if (!on) root.set(".palette", modelData.id)
                        }
                    }
                }
            }
            GSection {
                ui: look; title: Tr.t("Обои")
                GField {
                    ui: look
                    icon: "󰉋"
                    value: root.wp.dir || ""
                    placeholder: Tr.t("Папка с обоями и Enter")
                    onAccepted: (v) => { if (v.trim() !== "") root.set(".wallpaper.dir", v.trim()); }
                }
                GSlider {
                    ui: look; label: Tr.t("Смена обоев"); from: 5; to: 180; stepSize: 5; suffix: Tr.t(" мин")
                    value: root.wp.interval || 30
                    onCommitted: (v) => root.set(".wallpaper.interval", v)
                }
                GButton { ui: look; icon: "󰸉"; label: Tr.t("Следующие обои"); onClicked: root.run(["action", "wallpaper-next"]) }
                // мастер обоев: альбомы, поиск и загрузка из интернета; папка темы — та, что указана выше
                GButton { ui: look; icon: "󰖟"; label: Tr.t("Мастер обоев: альбомы и интернет"); onClicked: root.act("wallpapers") }
            }
            GSection {
                ui: look; title: Tr.t("Тема")
                Row {
                    spacing: 8
                    GButton {
                        ui: look
                        visible: root.curInfo !== null && root.curInfo.preset
                        icon: "󰑓"; label: Tr.t("Сбросить шаблон")
                        onClicked: root.run(["reset"])
                    }
                    GButton {
                        ui: look
                        visible: root.curInfo !== null && !root.curInfo.preset
                        icon: "󰆴"; label: Tr.t("Удалить тему"); danger: true
                        onClicked: root.run(["delete", root.st.current])
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Tr.t("SUPER+X — шторка · Tab — вкладки · Esc — закрыть\nПравый клик по 󰏘 в waybar — следующий шаблон")
                    color: look.sub
                    font.family: look.font
                    font.pixelSize: 12
                    lineHeight: 1.3
                }
            }
        }
    }

    // страница вкладки: прокрутка, сдвиг и проявление при переключении
    component Page: Flickable {
        id: pg
        required property int index
        required property Item body
        property int tab: 0
        width: parent.width
        height: parent.height
        contentHeight: body.implicitHeight + 12
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        readonly property bool current: tab === index
        opacity: current ? 1 : 0
        x: current ? 0 : (index < tab ? -40 : 40)
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        // отступ 6 px: кольцо выбранного шаблона и цветовых кружков выходит за край и не должно срезаться
        Component.onCompleted: { body.parent = pg.contentItem; body.x = 6; body.y = 6; body.visible = true; }
    }
}
