import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Шторка NameLess: плитки (крупные и малые — свой набор и порядок, Config.store.control), громкость и яркость,
// плеер, питание (опасные действия — двойным нажатием). Режим правки — карандаш в шапке: × убрать, ⇅ сменить размер,
// нажатие на две плитки — поменять местами, «Добавить» — плитки, которых нет. Во весь экран — кнопка рядом
PanelWindow {
    id: w
    property var shell: null
    // открыт/закрыт — состояние оболочки (shell.qml): закрытие изнутри не обрывает привязку
    readonly property bool open: shell ? shell.controlOpen : false
    function close() { if (shell) shell.controlOpen = false; }
    property real progress: 0
    Component.onCompleted: {
        progress = Qt.binding(function () { return w.open ? 1 : 0; });
        if (open) { Sys.refresh(); nightProc.running = true; }
        // у тех, кто настраивал шторку раньше, плитка Orbit один раз встаёт в конец малых — дальше её можно переставлять и убирать, как любую
        var cc = Config.store.control;
        if (cc.orbitSeeded !== true) {
            if ((cc.big || []).indexOf("orbit") < 0 && (cc.small || []).indexOf("orbit") < 0) {
                var a = (cc.small || []).slice(); a.push("orbit"); Config.set("control.small", a);
            }
            Config.set("control.orbitSeeded", true);
        }
    }
    Behavior on progress { NumberAnimation { duration: Theme.dur(w.open); easing.type: Easing.OutCubic } }

    visible: progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    // во весь экран, как шторка оформления: затемнение накрывает и бар
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-control"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    onOpenChanged: { if (open) { Sys.refresh(); nightProc.running = true; } armed = ""; editing = false; dragDy = 0; }

    readonly property var c: Config.store.control
    // вид шторки (стиль, место, ширина, высота) общий с шторкой «Оформление» (ThemeDrawer): один файл, обе шторки перечитывают его при изменении
    property var sv: ({ style: "desktop", align: "right", wmode: "normal", height: 0 })
    FileView {
        id: svFile
        path: Quickshell.env("HOME") + "/.config/glassrice/drawer.json"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { w.sv = Object.assign({ style: "desktop", align: "right", wmode: "normal", height: 0 }, JSON.parse(text())); } catch (e) { } }
    }
    function setShared(k, v) {
        var n = Object.assign({}, sv); n[k] = v; sv = n;
        var all = {}; try { all = JSON.parse(svFile.text()); } catch (e) { }       // чужие ключи файла (число карточек шторки «Оформление») не теряются
        all[k] = v; svFile.setText(JSON.stringify(all, null, 2) + "\n");
    }
    readonly property bool full: c.full === true
    property bool editing: false
    property bool viewOpen: false
    // широкая раскладка: «во весь экран» или «Во всю ширину» на большом экране — плитки слева, ползунки, плеер и уведомления справа
    readonly property bool wideL: full || (wmode === "full" && width >= 1000)

    // ---------- реестр плиток ----------
    readonly property var all: ["wifi", "bt", "dnd", "airplane", "theme", "desktop", "display", "cosmos", "programs", "rgb",
                                "audio", "tasks", "mic", "screenshot", "record", "recordArea", "picker", "night", "caffeine",
                                "wallpaper", "wallpapers", "clipboard", "ocr", "profiles", "agents", "orbit", "features", "notifs", "keys", "lock"]
    readonly property var audioNames: ({ none: Tr.t("без звука"), desktop: Tr.t("звук ПК"), mic: Tr.t("микрофон"), both: Tr.t("ПК + микрофон") })
    // свойства плитки: i — значок, t — подпись, sub — состояние, on — включена, f — нажатие, rf — правый клик
    function info(id) {
        var sh = w.shell;
        switch (id) {
        case "wifi": return { i: Sys.wifiIcon, t: "Wi-Fi", sub: !Sys.wifiOn ? Tr.t("Выкл.") : (Sys.ssid || Tr.t("Не подключено")), on: Sys.wifiOn,
                              f: function () { Sys.toggleWifi(); }, rf: function () { w.close(); Sys.wifiMenu(); } };
        case "bt": return { i: Sys.btOn ? "󰂯" : "󰂲", t: "Bluetooth", sub: !Sys.btOn ? Tr.t("Выкл.") : (Sys.btDevice || Tr.t("Вкл.")), on: Sys.btOn,
                            f: function () { Sys.toggleBt(); }, rf: function () { w.close(); Quickshell.execDetached(["blueman-manager"]); } };
        case "dnd": return { i: Notifs.dnd ? "󰂛" : "󰂚", t: Tr.t("Не беспокоить"), sub: Notifs.dnd ? Tr.t("Вкл.") : Tr.t("Выкл."), on: Notifs.dnd,
                             f: function () { Notifs.dnd = !Notifs.dnd; } };
        case "airplane": return { i: "󰀝", t: Tr.t("Режим полёта"), sub: Sys.airplane ? Tr.t("радио выкл.") : Tr.t("Выкл."), on: Sys.airplane,
                                  f: function () { Sys.toggleAirplane(); } };
        case "theme": return { i: "󰏘", t: Tr.t("Оформление"), sub: Theme.th.name || "", f: function () { w.act("drawer"); } };
        case "desktop": return { i: "󰕰", t: Tr.t("Рабочий стол"), sub: Tr.t("виджеты и док"), f: function () { if (sh) sh.openDesktop(0); } };
        case "display": return { i: "󰍹", t: Tr.t("Экран"), sub: Tr.t("разрешение, частота"), f: function () { if (sh) sh.openDisplay(); } };
        case "cosmos": return { i: "󰽥", t: Tr.t("Космос"), sub: ({ off: Tr.t("Выкл."), stars: Tr.t("звёздное небо"), solar: Tr.t("астрономия"), apps: Tr.t("орбиты окон") })[Theme.cosmos],
                                on: Theme.cosmos !== "off", f: function () { if (sh) sh.openDesktop(2); } };
        case "programs": return { i: "󰏖", t: Tr.t("Программы"), sub: Tr.t("пакеты и патчи"), f: function () { if (sh) sh.openPrograms(); } };
        case "rgb": return { i: "󰌌", t: Tr.t("Подсветка"), sub: Tr.t("клавиатура, RGB"), f: function () { if (sh) sh.openPrograms(5); } };
        case "audio": return { i: Sound.icon, t: Tr.t("Звук"), sub: Tr.t("устройства, проверка"), f: function () { w.close(); if (sh) sh.toggleAudio(); } };
        case "tasks": return { i: "󰓅", t: Tr.t("Диспетчер"), sub: Tr.t("нагрузка, процессы"), f: function () { w.close(); if (sh) sh.openTasks(); } };
        case "mic": return { i: Sound.micMuted ? "󰍭" : "󰍬", t: Tr.t("Микрофон"), sub: Sound.micMuted ? Tr.t("Выкл.") : Tr.t("Вкл."), on: !Sound.micMuted,
                             f: function () { Sound.toggleMic(); } };
        case "screenshot": return { i: "󰹑", t: Tr.t("Скриншот"), sub: Tr.t("область"), f: function () { w.act("screenshot"); } };
        case "record": return { i: Recorder.recording ? "󰻃" : "󰑋", t: Recorder.recording ? Tr.t("Стоп") : Tr.t("Запись"), on: Recorder.recording, onColor: Theme.red,
                                sub: Recorder.recording ? Recorder.clock() : (Recorder.opt("fmt", "mp4") === "gif" ? "GIF" : Tr.t("экран · ") + (w.audioNames[Recorder.opt("audio", w.c.recAudio || "desktop")] || "")) + Tr.t(" · ПКМ"),
                                f: function () { if (Recorder.recording) Recorder.stop(); else { w.close(); recDelay.mode = "screen"; recDelay.restart(); } },
                                rf: function () { w.close(); if (w.shell) w.shell.toggleRecorder(); } };
        case "recordArea": return { i: "󰩭", t: Tr.t("Запись области"), sub: w.audioNames[w.c.recAudio || "desktop"], on: Recorder.recording, onColor: Theme.red,
                                    f: function () { if (Recorder.recording) Recorder.stop(); else { w.close(); recDelay.mode = "area"; recDelay.restart(); } },
                                    rf: function () { w.close(); if (w.shell) w.shell.toggleRecorder(); } };
        case "picker": return { i: "󰈊", t: Tr.t("Пипетка"), sub: Tr.t("цвет в буфер"),
                                f: function () { w.close(); Quickshell.execDetached(["sh", "-c", "sleep 0.3; c=$(hyprpicker -a) && [ -n \"$c\" ] && notify-send -a Пипетка \"$c\" \"скопирован в буфер\""]); } };
        case "night": return { i: "󰖔", t: Tr.t("Ночь"), sub: w.night ? "4500 K" : Tr.t("Выкл."), on: w.night, f: function () { w.toggleNight(); } };
        case "caffeine": return { i: Sys.caffeine ? "󰅶" : "󰛊", t: Tr.t("Кофеин"), sub: Sys.caffeine ? Tr.t("не засыпать") : Tr.t("Выкл."), on: Sys.caffeine,
                                  f: function () { Sys.toggleCaffeine(); } };
        case "wallpaper": return { i: "󰸉", t: Tr.t("Обои"), sub: Tr.t("следующие"), f: function () { Quickshell.execDetached([Theme.script, "action", "wallpaper-next"]); },
                                   rf: function () { w.close(); if (sh) sh.openWallpapers(); } };
        case "wallpapers": return { i: "󰸉", t: Tr.t("Мастер обоев"), sub: Tr.t("мои и из интернета"), f: function () { w.close(); if (sh) sh.openWallpapers(); } };
        case "clipboard": return { i: "󰅌", t: Tr.t("Буфер обмена"), sub: Tr.t("история и закреплённое"), f: function () { w.close(); if (sh) sh.toggleClipboard(); } };
        case "profiles": return { i: Profiles.current ? Profiles.current.icon : "󰣆", t: Tr.t("Профили"), sub: Profiles.current ? Profiles.current.name : "", f: function () { w.close(); if (sh) sh.openProfiles(); }, rf: function () { Profiles.next(); } };
        case "agents": return { i: "󰚩", t: Tr.t("Помощники"), sub: AgentsData.util5 >= 0 ? Tr.t("лимит 5 ч: ") + Math.round(AgentsData.util5) + " %" : Tr.t("лимиты и расход"), f: function () { w.close(); if (sh) sh.openAgents(); } };
        case "orbit": return { i: "󰟀", t: "Orbit", on: OrbitData.enabled,
                               sub: !OrbitData.enabled ? Tr.t("Выкл.") : (!OrbitData.running ? Tr.t("запускается…") : (OrbitData.requests > 0 ? Tr.t("ждёт сопряжение") : (OrbitData.connected.length > 0 ? Tr.t("Подключено: ") + OrbitData.connected.length : Tr.t("ищет устройства")))),
                               f: function () { OrbitData.toggleEnabled(); },
                               rf: function () { if (OrbitData.enabled) { w.close(); if (sh) sh.openOrbit(); } } };
        case "features": return { i: "󰒓", t: Tr.t("Функции"), sub: Perf.eco ? Tr.t("экономный режим") : Tr.t("технологии и установка"), f: function () { w.close(); if (sh) sh.openFeatures(); } };
        case "ocr": return { i: "󰗊", t: Tr.t("Текст с экрана"), sub: Tr.t("выделить и скопировать"), f: function () { w.act("ocr"); } };
        case "notifs": return { i: "󰂚", t: Tr.t("Уведомления"), sub: Notifs.count > 0 ? String(Notifs.count) : Tr.t("нет"), f: function () { w.close(); Notifs.centerOpen = true; } };
        case "keys": return { i: "󰌌", t: Tr.t("Клавиши"), sub: Tr.t("сочетания"), f: function () { if (sh) sh.openKeys(); } };
        case "lock": return { i: "󰌾", t: Tr.t("Блокировка"), sub: Tr.t("экран"), f: function () { w.act("lock"); } };
        }
        return { i: "?", t: id, sub: "", f: function () { } };
    }
    // запись начинается после закрытия шторки — её не видно на видео
    Timer { id: recDelay; property string mode: "screen"; interval: 350; onTriggered: Recorder.start(mode) }
    function cycleAudio() {
        var order = ["desktop", "mic", "none"];
        Config.set("control.recAudio", order[(order.indexOf(c.recAudio || "desktop") + 1) % order.length]);
    }

    // ---------- правка ----------
    readonly property var unused: all.filter(function (id) { return (c.big || []).indexOf(id) < 0 && (c.small || []).indexOf(id) < 0; })
    function listOf(n) { return (c[n] || []).slice(); }
    function removeTile(n, i) { var a = listOf(n); a.splice(i, 1); Config.set("control." + n, a); }
    function addTile(id) { var a = listOf("small"); a.push(id); Config.set("control.small", a); }
    // ---------- перетаскивание плиток (режим правки) ----------
    // плитку берут и несут: на другую плитку — встанет на её место, на другую группу — станет крупной или малой,
    // на «корзину» — уберётся со шторки. dropAt подсвечивает, куда плитка встанет
    property var dragTile: null
    property var dropAt: null              // { list, index } или { trash: true }
    function targetOf(t) {
        var c = t.mapToItem(col, t.width / 2, t.height / 2);
        var boxes = [["big", bigBox, big], ["small", smallBox, small]];
        for (var n = 0; n < boxes.length; n++) {
            var bp = col.mapToItem(boxes[n][1], c.x, c.y);
            if (bp.x < -6 || bp.x > boxes[n][1].width + 6 || bp.y < -10 || bp.y > boxes[n][1].height + 10) continue;
            var g = boxes[n][2], gp = col.mapToItem(g, c.x, c.y), idx = listOf(boxes[n][0]).length;
            for (var k = 0; k < g.children.length; k++) {
                var ch = g.children[k];
                if (ch === t || ch.index === undefined || ch.list === undefined) continue;
                if (gp.x >= ch.x && gp.x <= ch.x + ch.width && gp.y >= ch.y && gp.y <= ch.y + ch.height) { idx = ch.index; break; }
            }
            return { list: boxes[n][0], index: idx };
        }
        var tp = col.mapToItem(trash, c.x, c.y);
        if (trash.visible && tp.x >= 0 && tp.x <= trash.width && tp.y >= 0 && tp.y <= trash.height) return { trash: true };
        return null;
    }
    function dropTile(t) {
        var tg = targetOf(t);
        if (!tg) return;
        var src = t.list, a = listOf(src), id = a.splice(t.index, 1)[0];
        if (tg.trash) { Config.set("control." + src, a); return; }
        if (tg.list === src) { a.splice(Math.min(tg.index, a.length), 0, id); Config.set("control." + src, a); }
        else { var b = listOf(tg.list); b.splice(Math.min(tg.index, b.length), 0, id); Config.set("control." + src, a); Config.set("control." + tg.list, b); }
    }
    function resetTiles() {
        Config.set("control.big", ["wifi", "bt", "dnd", "theme", "desktop", "display"]);
        Config.set("control.small", ["programs", "mic", "screenshot", "record", "night", "wallpaper"]);
        w.setShared("height", 0);
    }

    readonly property string script: Theme.script
    function act(name) { close(); Quickshell.execDetached([script, "action", name]); }

    // ночной режим (hyprsunset)
    property bool night: false
    Process {
        id: nightProc
        command: ["sh", "-c", "pgrep -x hyprsunset >/dev/null && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: w.night = text.trim() === "on" }
    }
    function toggleNight() {
        Quickshell.execDetached(["sh", "-c", night ? "pkill -x hyprsunset" : "command -v hyprsunset >/dev/null && setsid -f hyprsunset -t 4500 >/dev/null 2>&1"]);
        night = !night;
    }

    // питание: первое нажатие — «нажмите ещё раз», второе — выполнить
    property string armed: ""
    Timer { id: disarm; interval: 3000; onTriggered: w.armed = "" }
    function power(kind) {
        if (kind === "lock") { act("lock"); return; }
        if (armed !== kind) { armed = kind; disarm.restart(); return; }
        close();
        if (kind === "logout") Compositor.logout();
        else Quickshell.execDetached(["systemctl", kind === "reboot" ? "reboot" : "poweroff"]);
    }

    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * 0.6 * w.progress }
    MouseArea { anchors.fill: parent; onClicked: w.close() }

    // ---------- шторка: прижата к верхнему краю и сползает вниз, как на планшете ----------
    // ширина — пресет (узкая / обычная / широкая / во весь экран); на узком экране всегда во всю ширину.
    // Высота — по содержимому или та, что задана ручкой внизу (тянуть вниз/вверх, двойное нажатие — вернуть по содержимому).
    // Тянуть ручку вверх до конца — закрыть
    readonly property real r: Theme.ios ? 30 : 22
    readonly property var presets: ({ narrow: 420, normal: 560, wide: 760 })
    readonly property string wmode: presets[sv.wmode] !== undefined || sv.wmode === "full" ? sv.wmode : "normal"
    readonly property bool mobile: sv.style === "mobile"
    readonly property string align: sv.align === "left" || sv.align === "center" ? sv.align : "right"
    // запас по высоте: у мобильной шторки — до края экрана, у десктопной окно висит под баром
    readonly property real maxH: height - (mobile ? 8 : 58)
    readonly property real minH: 300
    readonly property real edge: 10          // отступ от боков экрана: шторка любой ширины не выходит за него
    property real dragDy: 0
    readonly property real autoH: col.implicitHeight + 16 + 12 + 34
    readonly property real baseH: (sv.height || 0) >= minH ? Math.min(sv.height, maxH) : Math.min(autoH, maxH)
    readonly property real sheetH: full ? height : Math.max(minH, Math.min(maxH, baseH + dragDy))

    Surface {
        id: panel
        // во весь экран фон плотнее: окна под шторкой не просвечивают
        alpha: w.full ? Math.max(0.985, Theme.overlayAlpha) : Theme.overlayAlpha
        width: w.full ? w.width : ((w.wmode === "full" || w.width < 700) ? w.width - 2 * w.edge : Math.min(w.width - 2 * w.edge, w.presets[w.wmode] || 560))
        // мобильная: верх шторки уходит за край экрана на радиус скругления, видны только нижние углы
        height: w.sheetH + (w.mobile && !w.full ? w.r : 0)
        x: w.full ? 0 : (w.align === "left" ? w.edge : (w.align === "center" ? (w.width - width) / 2 : w.width - width - w.edge))
        Behavior on width { enabled: w.visible; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        y: w.full ? 0 : (w.mobile ? -w.r - w.sheetH * (1 - w.progress) : 48 - 20 * (1 - w.progress))
        opacity: w.mobile ? Math.min(1, w.progress * 3) : w.progress
        radius: w.r
        MouseArea { anchors.fill: parent }
        focus: w.open
        Keys.onEscapePressed: w.close()

        Flickable {
            anchors { fill: parent; leftMargin: 16; rightMargin: 16; topMargin: w.mobile && !w.full ? w.r + 12 : 16; bottomMargin: 34 }
            contentHeight: col.implicitHeight + 16
            interactive: !w.dragTile
            clip: true
            boundsBehavior: Flickable.StopAtBounds
        // поля 8 px вокруг колонки: кнопки «×» и «⇅» в режиме правки выступают за плитку и не должны обрезаться
        Column {
            id: col
            x: 8; y: 8
            width: parent.width - 16
            spacing: 14

            // шапка: знак и тема
            Item {
                width: parent.width
                height: 30
                // знак и «справка»: клик — окно справки
                Row {
                    id: brand
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Logo { size: 26; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰋗"
                        color: Theme.accent
                        font.family: Theme.iconFont
                        font.pixelSize: 15
                    }
                }
                MouseArea {
                    anchors.fill: brand
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (w.shell) w.shell.openHelp()
                }
                // автор: портфолио и канал; правее — название темы
                Row {
                    id: tools
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Repeater {
                        model: [{ k: "edit", i: w.editing ? "󰄬" : "󰏫", on: w.editing }, { k: "view", i: "󰕮", on: w.viewOpen }, { k: "close", i: "✕", on: false }]
                        Rectangle {
                            required property var modelData
                            width: 30; height: 30; radius: 15
                            color: modelData.on ? Theme.accent : (tma.containsMouse ? Theme.fill(0.18) : Theme.fill(0.10))
                            Text { anchors.centerIn: parent; text: modelData.i; color: modelData.on ? "white" : Theme.text; font.family: modelData.k === "close" ? Theme.font : Theme.iconFont; font.pixelSize: modelData.k === "close" ? 12 : 14 }
                            MouseArea {
                                id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (modelData.k === "close") w.close(); else if (modelData.k === "view") w.viewOpen = !w.viewOpen; else w.editing = !w.editing; }
                            }
                        }
                    }
                }
                Row {
                    anchors { right: themeName.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Repeater {
                        model: Theme.links
                        Rectangle {
                            required property var modelData
                            width: 26; height: 26; radius: 13
                            color: lma.containsMouse ? modelData.c : Theme.fill(0.10)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text { anchors.centerIn: parent; text: modelData.i; color: lma.containsMouse ? "white" : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 13 }
                            MouseArea { id: lma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { w.close(); Quickshell.execDetached(["xdg-open", modelData.u]); } }
                        }
                    }
                }
                Text {
                    id: themeName
                    anchors { right: tools.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    visible: !w.editing
                    text: Theme.th.name || ""
                    color: Theme.sub
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }

                    // вид шторки: те же четыре группы и та же логика, что в «Оформлении» (ThemeDrawer): в широком виде — четыре в ряд, в узком — друг под другом
                    Flow {
                        id: viewBox
                        visible: w.viewOpen
                        readonly property int perRow: w.wideL ? 4 : 1
                        readonly property real cellW: (width - spacing * (perRow - 1)) / perRow
                        width: parent.width
                        spacing: 14
                        Column {
                            width: viewBox.cellW; spacing: 6
                            Text { text: Tr.t("Стиль"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                            GSegment {
                                ui: Theme
                                options: [{ v: "desktop", t: Tr.t("Десктопный: окно"), icon: "󰍹" }, { v: "mobile", t: Tr.t("Мобильный: шторка"), icon: "󰏲" }]
                                value: w.mobile ? "mobile" : "desktop"
                                onPicked: (v) => w.setShared("style", v)
                            }
                        }
                        Column {
                            width: viewBox.cellW; spacing: 6
                            Text { text: Tr.t("Где открывается"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                            GSegment {
                                ui: Theme
                                options: [{ v: "left", t: Tr.t("Слева") }, { v: "center", t: Tr.t("По центру") }, { v: "right", t: Tr.t("Справа") }]
                                value: w.align
                                onPicked: (v) => w.setShared("align", v)
                            }
                        }
                        Column {
                            width: viewBox.cellW; spacing: 6
                            Text { text: Tr.t("Ширина"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                            GSegment {
                                ui: Theme
                                options: [{ v: "narrow", t: Tr.t("Узкая") }, { v: "normal", t: Tr.t("Обычная") }, { v: "wide", t: Tr.t("Широкая") }, { v: "full", t: Tr.t("Во всю ширину") }]
                                value: w.wmode
                                onPicked: (v) => w.setShared("wmode", v)
                            }
                        }
                        Column {
                            width: viewBox.cellW; spacing: 6
                            Text { text: Tr.t("Плиток в ряд: крупных / малых"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                            GSegment { ui: Theme; options: [{ v: "1", t: "1" }, { v: "2", t: "2" }, { v: "3", t: "3" }, { v: "4", t: "4" }]; value: String(w.c.cols || 2); onPicked: (v) => Config.set("control.cols", Number(v)) }
                            GSegment { ui: Theme; options: [{ v: "3", t: "3" }, { v: "4", t: "4" }, { v: "5", t: "5" }, { v: "6", t: "6" }, { v: "8", t: "8" }]; value: String(w.c.scols || 5); onPicked: (v) => Config.set("control.scols", Number(v)) }
                        }
                        Column {
                            width: viewBox.cellW; spacing: 6
                            Text { text: Tr.t("Жест от верхнего края: справа — шторка, слева — уведомления"); width: parent.width; wrapMode: Text.WordWrap; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                            GSegment {
                                ui: Theme
                                options: [{ v: "auto", t: Tr.t("Авто: с сенсором") }, { v: "on", t: Tr.t("Всегда") }, { v: "off", t: Tr.t("Выкл") }]
                                value: Config.store.touch.edge || "auto"
                                onPicked: (v) => Config.set("touch.edge", v)
                            }
                        }
                        Column {
                            width: viewBox.cellW; spacing: 6
                            Text { text: Tr.t("Язык"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                            GSegment {
                                ui: Theme
                                options: [{ v: "ru", t: "Русский" }, { v: "en", t: "English" }]
                                value: Tr.lang
                                onPicked: (v) => Config.set("lang", v)
                            }
                        }
                        Text { width: parent.width; wrapMode: Text.WordWrap; text: Tr.t("Высоту меняет ручка внизу шторки: тяните вниз или вверх, двойное нажатие — по содержимому"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                    }

            // во весь экран — две колонки: плитки слева, ползунки, плеер и питание справа
            Grid {
                id: body
                width: parent.width
                columns: w.wideL ? 2 : 1
                columnSpacing: 20
                rowSpacing: 14
                readonly property real leftW: w.wideL ? Math.round((width - 20) * 0.6) : width
                readonly property real rightW: w.wideL ? width - leftW - 20 : width

            Column {
                width: body.leftW
                spacing: 14

                Text {
                    visible: w.editing
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Tr.t("Тяните плитки: на другую плитку — поменяются местами, в другую группу — станут крупной или малой, в корзину — уберутся")
                    color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
                }

                // профили: нажатие применяет набор настроек (подробности — плитка «Профили»)
                Flow {
                    visible: !w.editing && Profiles.list.length > 0
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: Profiles.list
                        Rectangle {
                            id: pc
                            required property var modelData
                            readonly property bool on: Profiles.active === modelData.id
                            width: pcl.implicitWidth + 24; height: 30; radius: 15
                            color: on ? Theme.accent : (pma.containsMouse ? Theme.fill(0.18) : Theme.fill(0.08))
                            border.width: on ? 0 : 1; border.color: Theme.line(0.2)
                            Text { id: pcl; anchors.centerIn: parent; text: pc.modelData.icon + "  " + pc.modelData.name; color: pc.on ? "white" : Theme.text; font.family: Theme.iconFont; font.pixelSize: 12 }
                            MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Profiles.apply(pc.modelData.id) }
                        }
                    }
                }

                // крупные плитки
                Item {
                    id: bigBox
                    width: parent.width
                    height: Math.max(big.height, w.editing ? 72 : 0)
                    Rectangle {
                        visible: w.editing; anchors.fill: parent; radius: Theme.r(18); color: "transparent"
                        border.width: 1; border.color: w.dropAt && w.dropAt.list === "big" ? Theme.accent : Theme.line(0.18)
                        Text { visible: (w.c.big || []).length === 0; anchors.centerIn: parent; text: Tr.t("перетащите сюда крупные плитки"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                    }
                    Grid {
                        id: big
                        width: parent.width
                        columns: w.wideL ? Math.max(2, Math.floor(width / 210)) : (w.c.cols || 2)
                        spacing: 10
                        readonly property real cw: (width - spacing * (columns - 1)) / columns
                        Repeater {
                            model: w.c.big || []
                            CTile { list: "big"; width: big.cw; height: w.wideL ? 92 : 72 }
                        }
                    }
                }

                // малые плитки
                Item {
                    id: smallBox
                    width: parent.width
                    height: Math.max(small.height, w.editing ? 64 : 0)
                    Rectangle {
                        visible: w.editing; anchors.fill: parent; radius: Theme.r(18); color: "transparent"
                        border.width: 1; border.color: w.dropAt && w.dropAt.list === "small" ? Theme.accent : Theme.line(0.18)
                        Text { visible: (w.c.small || []).length === 0; anchors.centerIn: parent; text: Tr.t("перетащите сюда малые плитки"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                    }
                    Grid {
                        id: small
                        width: parent.width
                        columns: w.wideL ? Math.max(5, Math.floor(width / 100)) : (w.c.scols || 5)
                        spacing: 10
                        readonly property real cw: (width - spacing * (columns - 1)) / columns
                        Repeater {
                            model: w.c.small || []
                            CTile { list: "small"; width: small.cw; height: w.wideL ? 84 : 64 }
                        }
                    }
                }

                // корзина: бросить сюда плитку, чтобы убрать её со шторки
                Rectangle {
                    id: trash
                    visible: w.editing && w.dragTile !== null
                    width: parent.width; height: 48; radius: Theme.r(16)
                    color: w.dropAt && w.dropAt.trash ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.35) : Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.12)
                    border.width: 1; border.color: Theme.red
                    Text { anchors.centerIn: parent; text: Tr.t("󰆴  Убрать со шторки"); color: Theme.red; font.family: Theme.iconFont; font.pixelSize: 13 }
                }

                // правка: плитки, которых нет на шторке
                Column {
                    visible: w.editing
                    width: parent.width
                    spacing: 8
                    Row {
                        width: parent.width
                        Text { width: parent.width - resetT.width; text: w.unused.length ? Tr.t("Добавить") : Tr.t("Все плитки на шторке"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Text {
                            id: resetT
                            text: Tr.t("Сбросить"); color: rma.containsMouse ? Theme.accent : Theme.sub; font.family: Theme.font; font.pixelSize: 12
                            MouseArea { id: rma; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.resetTiles() }
                        }
                    }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: w.unused
                            Rectangle {
                                id: addChip
                                required property string modelData
                                readonly property var d: w.info(modelData)
                                width: addRow.implicitWidth + 20; height: 30; radius: 15
                                color: ama.containsMouse ? Theme.fill(0.18) : Theme.fill(0.08)
                                border.width: 1; border.color: Theme.line(0.2)
                                Row {
                                    id: addRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text { text: "+"; color: Theme.accent; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold }
                                    Text { text: addChip.d.i; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 13 }
                                    Text { text: addChip.d.t; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                                }
                                MouseArea { id: ama; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.addTile(addChip.modelData) }
                            }
                        }
                    }
                }
            }

            Column {
                width: body.rightW
                spacing: 14

                PillSlider {
                    ui: Theme; width: parent.width
                    icon: Sound.icon; label: Tr.t("Звук")
                    from: 0; to: 1; value: Sound.volume
                    display: 100; suffix: " %"
                    onCommitted: (v) => Sound.setVolume(v)
                }
                PillSlider {
                    visible: Sys.brightness >= 0
                    ui: Theme; width: parent.width
                    icon: "󰃟"; label: Tr.t("Яркость")
                    from: 1; to: 100; stepSize: 1; decimals: 0; value: Math.max(1, Sys.brightness)
                    suffix: " %"
                    onCommitted: (v) => Sys.setBrightness(v)
                }

                // плеер, пока что-то играет
                PlayerCard {
                    visible: has
                    width: parent.width
                    implicitHeight: 186
                    radius: 22
                }

                // питание
                Row {
                    id: pw
                    width: parent.width
                    spacing: 8
                    readonly property real cw: (width - spacing * 3) / 4
                    Repeater {
                        model: [
                            { k: "lock", i: "󰌾", t: Tr.t("Блок") },
                            { k: "logout", i: "󰍃", t: Tr.t("Выход") },
                            { k: "reboot", i: "󰜉", t: Tr.t("Перезагр.") },
                            { k: "poweroff", i: "󰐥", t: Tr.t("Выкл.") }
                        ]
                        GTile {
                            required property var modelData
                            ui: Theme
                            width: pw.cw; height: 54; radius: 18
                            on: w.armed === modelData.k
                            onColor: Theme.red
                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.i; color: w.armed === modelData.k ? "white" : (modelData.k === "poweroff" ? Theme.red : Theme.text); font.family: Theme.iconFont; font.pixelSize: 17 }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: w.armed === modelData.k ? Tr.t("Ещё раз") : modelData.t; color: w.armed === modelData.k ? "white" : Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                            }
                            onClicked: w.power(modelData.k)
                        }
                    }
                }

                // во весь экран: последние уведомления
                Column {
                    visible: w.wideL
                    width: parent.width
                    spacing: 8
                    Row {
                        width: parent.width
                        Text { width: parent.width - clr.width; text: Tr.t("Уведомления") + (Notifs.count ? " · " + Notifs.count : ""); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Text {
                            id: clr
                            visible: Notifs.count > 0
                            text: Tr.t("Открыть все"); color: oma.containsMouse ? Theme.accent : Theme.sub; font.family: Theme.font; font.pixelSize: 12
                            MouseArea { id: oma; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { w.close(); Notifs.centerOpen = true; } }
                        }
                    }
                    Text { visible: Notifs.count === 0; text: Tr.t("Пусто"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
                    Repeater {
                        model: w.wideL ? Notifs.list.slice(0, 6) : []
                        NotifCard {
                            required property var modelData
                            width: parent.width
                            note: modelData
                            onClosed: Notifs.dismiss(modelData)
                        }
                    }
                }
            }
            }
        }
        }

        // ручка: тянуть вниз — выше, вверх — ниже, до конца вверх — закрыть; двойное нажатие — высота по содержимому
        Item {
            id: grip
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 34
            visible: !w.full
            Rectangle { anchors.centerIn: parent; width: 52; height: 5; radius: 2.5; color: Theme.text; opacity: gma.containsMouse || gdrag.active ? 0.7 : 0.35 }
            MouseArea { id: gma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.SizeVerCursor; acceptedButtons: Qt.NoButton }
            TapHandler { onDoubleTapped: { w.setShared("height", 0); w.dragDy = 0; } }
            DragHandler {
                id: gdrag
                target: null
                yAxis.enabled: true; xAxis.enabled: false
                onTranslationChanged: if (active) w.dragDy = translation.y
                onActiveChanged: if (!active) {
                    var h = w.baseH + w.dragDy;
                    if (h < w.minH - 80) w.close();
                    else w.setShared("height", Math.round(Math.max(w.minH, Math.min(w.maxH, h))));
                    w.dragDy = 0;
                }
            }
        }
    }

    // плитка шторки: крупная: крупная — значок, подпись и состояние; малая — значок и подпись
    component CTile: GTile {
        id: tile
        required property string modelData
        required property int index
        property string list: "small"
        readonly property var d: w.info(modelData)
        readonly property bool isBig: list === "big"
        readonly property bool picked: w.dragTile === tile
        readonly property bool dropHere: w.dropAt !== null && w.dropAt.list === list && w.dropAt.index === index && w.dragTile !== tile
        // смещение при переносе: плитка идёт за курсором, место в сетке остаётся
        property point off: Qt.point(0, 0)
        z: picked ? 100 : 0
        transform: Translate { x: tile.off.x; y: tile.off.y }
        scale: picked ? 1.06 : 1
        readonly property color fg: on ? "white" : Theme.text
        ui: Theme
        radius: isBig ? 22 : 20
        on: d.on === true && !w.editing
        onColor: d.onColor || Theme.accent
        onClicked: if (!w.editing) d.f()
        TapHandler { acceptedButtons: Qt.RightButton; enabled: !w.editing && tile.d.rf !== undefined; onTapped: tile.d.rf() }

        // покачивание в правке, как на iOS
        rotation: w.editing && !picked ? (index % 2 ? 1 : -1) * wob.v : 0
        QtObject { id: wob; property real v: 0 }
        SequentialAnimation {
            running: w.editing && w.visible
            loops: Animation.Infinite
            NumberAnimation { target: wob; property: "v"; from: -1.2; to: 1.2; duration: 140 }
            NumberAnimation { target: wob; property: "v"; from: 1.2; to: -1.2; duration: 140 }
            onStopped: wob.v = 0
        }
        DragHandler {
            id: dh
            enabled: w.editing
            target: null
            onActiveChanged: {
                if (active) { w.dragTile = tile; }
                else { w.dropTile(tile); tile.off = Qt.point(0, 0); w.dragTile = null; w.dropAt = null; }
            }
            onTranslationChanged: if (active) { tile.off = Qt.point(translation.x, translation.y); w.dropAt = w.targetOf(tile); }
            cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        }
        // куда встанет: подсветка плитки-цели
        Rectangle {
            visible: tile.dropHere
            anchors { fill: parent; margins: -3 }
            radius: Theme.r(tile.radius) + 3
            color: "transparent"; border.width: 2; border.color: Theme.accent
        }
        Rectangle {
            visible: tile.picked
            anchors { fill: parent; margins: -3 }
            radius: Theme.r(tile.radius) + 3
            color: "transparent"; border.width: 2; border.color: Theme.accent
        }

        Text {
            visible: tile.isBig
            x: 13; y: 11
            text: tile.d.i; color: tile.fg
            font.family: Theme.iconFont; font.pixelSize: 21
        }
        Column {
            visible: tile.isBig
            x: 13
            anchors { bottom: parent.bottom; bottomMargin: 10 }
            width: parent.width - 20
            Text { width: parent.width; text: tile.d.t; color: tile.fg; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
            Text { width: parent.width; visible: (tile.d.sub || "") !== ""; text: tile.d.sub || ""; color: tile.on ? Qt.rgba(1, 1, 1, 0.78) : Theme.sub; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 11 }
        }
        Column {
            visible: !tile.isBig
            anchors.centerIn: parent
            width: parent.width - 6
            spacing: 4
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.d.i; color: tile.fg; font.family: Theme.iconFont; font.pixelSize: 19 }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                // у записи на малой плитке вместо подписи — время
                text: tile.modelData.indexOf("record") === 0 && Recorder.recording ? Recorder.clock() : tile.d.t
                color: tile.on ? "white" : Theme.sub; font.family: Theme.font; font.pixelSize: 10
            }
        }

        // правка: убрать и сменить размер
        Repeater {
            model: w.editing ? [{ k: "x", t: "×", x: -6 }] : []
            Rectangle {
                required property var modelData
                x: modelData.x; y: -6
                width: 20; height: 20; radius: 10
                color: Theme.red
                Text { anchors.centerIn: parent; text: modelData.t; color: "white"; font.pixelSize: 12; font.weight: Font.Bold }
                MouseArea {
                    anchors { fill: parent; margins: -4 }
                    cursorShape: Qt.PointingHandCursor
                    onClicked: w.removeTile(tile.list, tile.index)
                }
            }
        }
    }
}
