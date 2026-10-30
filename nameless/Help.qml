import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Справка NameLess UI: «Добро пожаловать» (при первом запуске сама), «Где что», «Клавиши».
// SUPER+F1, шапка Пункта управления; IPC — help toggle / keys toggle
PanelWindow {
    id: w
    screen: Compositor.panelScreen
    property var shell: null          // shell.qml: панели «Рабочий стол» и Пункт управления
    property bool open: false
    property int tab: 0
    property real progress: open ? 1 : 0
    Behavior on progress { NumberAnimation { duration: Theme.dur(w.open); easing.type: Easing.OutCubic } }

    readonly property string flagFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/nameless/welcomed"

    visible: progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-help"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function show(t) { tab = t; open = true; reader.running = true; }
    function close() {
        open = false;
        // приветствие показано — больше само не открывается
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && touch \"$1\"", "sh", flagFile]);
    }

    // применение оформления из приветствия: те же этапы, что в шторке (theme.sh с THEME_PROGRESS=1 пишет «stage:имя»)
    readonly property var applySteps: [
        { id: "colors", t: Tr.t("Цвета"), icon: "󰏘" },
        { id: "hypr", t: Tr.t("Окна"), icon: "󰖲" },
        { id: "shell", t: Tr.t("Панели"), icon: "󰍜" },
        { id: "wallpaper", t: Tr.t("Обои"), icon: "󰸉" }
    ]
    property string applying: ""
    property string applyingName: ""
    property string applyStage: ""
    readonly property int applyIndex: {
        if (applyStage === "done") return applySteps.length;
        for (var i = 0; i < applySteps.length; i++) if (applySteps[i].id === applyStage) return i;
        return 0;
    }
    Process {
        id: applyProc
        environment: ({ THEME_PROGRESS: "1" })
        stdout: SplitParser { onRead: (line) => { if (line.indexOf("stage:") === 0) w.applyStage = line.substring(6).trim(); } }
        onRunningChanged: if (!running && w.applying !== "") { w.applyStage = "done"; applyDone.restart(); }
    }
    Timer { id: applyDone; interval: 1400; onTriggered: { w.applying = ""; w.applyStage = ""; } }
    function applyTheme(id, name) {
        if (applying !== "") return;
        applying = id; applyingName = name; applyStage = "";
        applyProc.command = [Theme.script, "apply", id];
        applyProc.running = true;
    }

    // клавиши из ~/.config/hypr/keybinds.txt: [{ title, items: [{ key, act }] }]
    property var sections: []
    Process {
        id: reader
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/keybinds.txt"]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [], idx = {}, lines = text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var l = lines[i].trim();
                    if (l === "" || l.charAt(0) === "#") continue;
                    var f = l.split("|");
                    if (f.length < 3) continue;
                    if (idx[f[0]] === undefined) { idx[f[0]] = out.length; out.push({ title: f[0], items: [] }); }
                    out[idx[f[0]]].items.push({ key: f[1], act: f[2] });
                }
                w.sections = out;
            }
        }
    }

    // «Где что»: зона — что там и как пользоваться
    readonly property var guide: [
        { icon: "󰍜", title: Tr.t("Бар"), items: [
            [Tr.t("Знак NameLess"), Tr.t("клик — лаунчер, правый клик — Пункт управления")],
            [Tr.t("Рабочие столы"), Tr.t("клик — перейти, колесо — соседний (в driftwm — «Холст»)")],
            [Tr.t("Часы"), Tr.t("клик — центр уведомлений")],
            ["Wi-Fi", Tr.t("клик — сети и пароль, правый — настройки сети")],
            [Tr.t("Звук"), Tr.t("клик — без звука, колесо — громкость, правый — микшер")],
            [Tr.t("Колокольчик"), Tr.t("клик — уведомления, правый — не беспокоить")],
            [Tr.t("Кнопка оформления"), Tr.t("шторка; правый клик — следующий шаблон")] ] },
        { icon: "󰍜", title: Tr.t("Док и виджеты"), items: [
            [Tr.t("Док"), Tr.t("клик — запуск или следующее окно, средний — новое окно")],
            [Tr.t("Правый клик по значку"), Tr.t("закрепить / убрать, сдвинуть, закрыть окна")],
            [Tr.t("«+» в доке"), Tr.t("выбрать приложение в лаунчере")],
            [Tr.t("Рабочий стол"), Tr.t("Пункт управления → «Рабочий стол»: виджеты, порядок, док")] ] },
        { icon: "󰏖", title: Tr.t("Программы — SUPER+I"), items: [
            [Tr.t("Каталог"), Tr.t("категории сборки: установлено / нет, установить, удалить")],
            [Tr.t("Найти новые"), Tr.t("поиск в репозиториях и AUR")],
            [Tr.t("Остальные в системе"), Tr.t("установленное вне каталога; правый клик — в каталог")],
            [Tr.t("Снять список своих"), Tr.t("packages/apps/mine.txt — перенос на новую систему")] ] },
        { icon: "󰏘", title: Tr.t("Оформление"), items: [
            ["SUPER+X", Tr.t("шторка: шаблоны Классика / Жидкое стекло / iOS")],
            [Tr.t("Темы"), Tr.t("свои темы, светлое / тёмное, акцент, стекло")],
            [Tr.t("Окна"), Tr.t("отступы, скругление, рамки, размытие, анимации")],
            [Tr.t("Система"), Tr.t("панель, лаунчер и его вид, палитры, обои")] ] },
        { icon: "󰸉", title: Tr.t("Обои"), items: [
            ["SUPER+B", Tr.t("выбор из миниатюр, смена плавная")],
            [Tr.t("Пункт управления"), Tr.t("«Обои» — следующие, правый клик — выбор")],
            [Tr.t("Папка и интервал"), Tr.t("шторка → Система → Обои")] ] },
        { icon: "󰂚", title: Tr.t("Уведомления"), items: [
            ["SUPER+N", Tr.t("центр уведомлений: история, плеер")],
            ["SUPER+Z", Tr.t("Пункт управления: плитки, звук, яркость, режимы питания")],
            ["SUPER+SHIFT+N", Tr.t("не беспокоить — только важные")] ] },
        { icon: "󰉋", title: Tr.t("Файлы"), items: [
            ["~/.config/hypr-themes", Tr.t("темы, шаблоны, палитры")],
            ["~/.config/hypr/keybinds.txt", Tr.t("этот список клавиш")],
            ["~/.config/glassrice/autostart.lua", Tr.t("автозапуск приложений")],
            ["~/.cache/nameless.log", Tr.t("лог NameLess UI")] ] },
        { icon: "󰇚", title: Tr.t("Установка"), items: [
            ["install.sh", Tr.t("полная, оформление, только dotfiles, выбор")],
            ["scripts/system/driver.sh", Tr.t("драйвер видеокарты (--check)")],
            ["scripts/apps/apps.sh", Tr.t("приложения по категориям")],
            ["install.sh restore", Tr.t("вернуть свои файлы из бэкапа")] ] }
    ]

    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * w.progress }
    MouseArea { anchors.fill: parent; onClicked: w.close() }

    Surface {
        id: box
        width: Math.min(parent.width - 80, 980)
        // приветствие — по содержимому, справочные вкладки — во всю высоту
        height: Math.min(parent.height - 80, w.tab === 0 ? wcol.implicitHeight + 118 : 680)
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        anchors.centerIn: parent
        anchors.verticalCenterOffset: (1 - w.progress) * 18
        opacity: w.progress
        scale: 0.97 + 0.03 * w.progress
        radius: Theme.ios ? 32 : 24
        alpha: Theme.overlayAlpha
        MouseArea { anchors.fill: parent }
        MoveArea { win: box; anchors { left: parent.left; right: parent.right; top: parent.top } height: 64 }
        focus: w.open
        Keys.onEscapePressed: w.close()
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_F1) w.close();
            else if (e.key === Qt.Key_Tab) { w.tab = (w.tab + 1) % 4; e.accepted = true; }
        }

        // шапка
        Item {
            id: head
            x: 24; y: 20
            width: parent.width - 48
            height: 40
            Logo { size: 30; anchors.verticalCenter: parent.verticalCenter }
            GSegment {
                ui: Theme
                width: Math.min(500, parent.width - 120)
                anchors { right: closeBtn.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                options: [{ v: "0", t: Tr.t("Добро пожаловать"), icon: "󰗠" }, { v: "1", t: Tr.t("Где что"), icon: "󰋗" }, { v: "2", t: Tr.t("Клавиши"), icon: "󰌌" }, { v: "3", t: Tr.t("Вопросы"), icon: "󰘥" }]
                value: String(w.tab)
                onPicked: (v) => w.tab = Number(v)
            }
            GTile {
                id: closeBtn
                ui: Theme
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 34; height: 34; radius: 17
                Text { anchors.centerIn: parent; text: "✕"; color: Theme.text; font.pixelSize: 13 }
                onClicked: w.close()
            }
        }

        Item {
            id: body
            anchors { top: head.bottom; topMargin: 18; left: parent.left; leftMargin: 24; right: parent.right; rightMargin: 24; bottom: parent.bottom; bottomMargin: 20 }

            // ---------- Добро пожаловать ----------
            Flickable {
                id: welcome
                anchors.fill: parent
                visible: w.tab === 0
                contentHeight: wcol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: wcol
                    width: welcome.width
                    spacing: 18

                    // заголовок: знак, приветствие, активная тема
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 18
                        Logo { size: 64; wordmark: false; anchors.verticalCenter: parent.verticalCenter }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Text {
                                text: Tr.t("Добро пожаловать в NameLess UI")
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.ios ? 28 : 25
                                font.weight: Font.Bold
                                font.letterSpacing: Theme.ios ? -0.6 : 0
                            }
                            Text {
                                width: Math.min(560, wcol.width - 100)
                                wrapMode: Text.WordWrap
                                text: Tr.t("Оболочка рабочего стола сборки glassrice для Hyprland и driftwm. Сейчас: тема «") +
                                      (Theme.th.name || "—") + "», " + Compositor.name + "."
                                color: Theme.sub
                                font.family: Theme.font
                                font.pixelSize: 13
                                lineHeight: 1.3
                            }
                        }
                    }

                    // шаблон оформления одним кликом
                    Column {
                        width: parent.width
                        spacing: 8
                        Text { text: Tr.t("Оформление"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7 }
                        Row {
                            id: kits
                            width: parent.width
                            spacing: 10
                            readonly property real cw: (width - spacing * 2) / 3
                            Repeater {
                                model: [
                                    { id: "classic", t: Tr.t("Классика"), d: Tr.t("плотные панели, рамки"), g: ["#24273a", "#8aadf4"] },
                                    { id: "liquid", t: Tr.t("Жидкое стекло"), d: Tr.t("дымка, кант, размытие"), g: ["#3a4a6b", "#b7bdf8"] },
                                    { id: "ios", t: "iOS", d: Tr.t("стекло без рамок и док"), g: ["#0a84ff", "#5e5ce6"] }
                                ]
                                GTile {
                                    id: kitTile
                                    required property var modelData
                                    readonly property bool cur: Theme.st.current === modelData.id
                                    ui: Theme
                                    width: kits.cw; height: 76; radius: 20
                                    on: cur
                                    Rectangle {
                                        id: swatch
                                        x: 12; anchors.verticalCenter: parent.verticalCenter
                                        width: 44; height: 44; radius: Theme.r(14)
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: kitTile.modelData.g[0] }
                                            GradientStop { position: 1.0; color: kitTile.modelData.g[1] }
                                        }
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.25)
                                    }
                                    Column {
                                        anchors { left: swatch.right; leftMargin: 12; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                        spacing: 2
                                        Text { width: parent.width; text: kitTile.modelData.t; elide: Text.ElideRight; color: kitTile.cur ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                                        Text { width: parent.width; text: kitTile.cur ? Tr.t("включено") : kitTile.modelData.d; elide: Text.ElideRight; color: kitTile.cur ? Qt.rgba(1, 1, 1, 0.8) : Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                                    }
                                    onClicked: if (!cur) w.applyTheme(modelData.id, modelData.t)
                                }
                            }
                        }
                    }

                    // ход применения оформления: этапы theme.sh, текущий — с вращающимся значком
                    Item {
                        visible: w.applying !== ""
                        width: parent.width
                        height: visible ? 64 : 0
                        Rectangle { anchors.fill: parent; radius: Theme.r(18); color: Theme.fill(0.08); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.14) }
                        Text {
                            x: 16; y: 10
                            text: w.applyStage === "done" ? "󰄬  «" + w.applyingName + Tr.t("» применено") : Tr.t("󰔟  Применяю «") + w.applyingName + "»…"
                            color: w.applyStage === "done" ? Theme.green : Theme.text
                            font.family: Theme.iconFont; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                        Row {
                            x: 16; anchors { bottom: parent.bottom; bottomMargin: 10 }
                            spacing: 14
                            Repeater {
                                model: w.applySteps
                                Row {
                                    required property var modelData
                                    required property int index
                                    readonly property bool done: index < w.applyIndex
                                    readonly property bool cur: index === w.applyIndex && w.applyStage !== "done"
                                    spacing: 6
                                    Text {
                                        id: spin
                                        text: parent.done ? "󰄬" : (parent.cur ? "󰑓" : modelData.icon)
                                        color: parent.done ? Theme.green : (parent.cur ? Theme.accent : Theme.sub)
                                        font.family: Theme.iconFont; font.pixelSize: 13
                                        RotationAnimation on rotation { running: spin.parent.cur; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                                    }
                                    Text { text: modelData.t; color: parent.done || parent.cur ? Theme.text : Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
                                }
                            }
                        }
                    }

                    // что умеет: карточка открывает своё
                    Column {
                        width: parent.width
                        spacing: 8
                        Text { text: Tr.t("Возможности"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7 }
                        Grid {
                            id: feats
                            width: parent.width
                            columns: 3
                            spacing: 10
                            readonly property real cw: (width - spacing * 2) / 3
                            Repeater {
                                model: [
                                    { i: "󰀻", t: Tr.t("Приложения"), d: Tr.t("поиск, калькулятор; правый клик — в док"), k: "SUPER+R",
                                      f: function () { w.close(); Quickshell.execDetached([Theme.script, "action", "menu"]); } },
                                    { i: "󰍜", t: Tr.t("Док"), d: Tr.t("закрепить, сдвинуть, автоскрытие"), k: Tr.t("Рабочий стол"),
                                      f: function () { w.close(); if (w.shell) w.shell.openDesktop(1); } },
                                    { i: "󰕰", t: Tr.t("Виджеты"), d: Tr.t("часы, плеер, погода, календарь, заметка"), k: Tr.t("Рабочий стол"),
                                      f: function () { w.close(); if (w.shell) w.shell.openDesktop(0); } },
                                    { i: "󰕮", t: Tr.t("Пункт управления"), d: Tr.t("Wi-Fi, звук, яркость, плеер, питание"), k: Tr.t("клик по знаку ПКМ"),
                                      f: function () { w.close(); if (w.shell) w.shell.toggleControl(); } },
                                    { i: "󰏘", t: Tr.t("Шторка тем"), d: Tr.t("свои темы, палитры, стекло, окна"), k: "SUPER+X",
                                      f: function () { w.close(); Quickshell.execDetached([Theme.script, "action", "drawer"]); } },
                                    { i: "󰂚", t: Tr.t("Уведомления"), d: Tr.t("история, не беспокоить"), k: "SUPER+N",
                                      f: function () { w.close(); Notifs.centerOpen = true; } }
                                ]
                                GTile {
                                    id: ft
                                    required property var modelData
                                    ui: Theme
                                    width: feats.cw; height: 84; radius: 20
                                    Text { id: ftIcon; x: 14; y: 14; text: ft.modelData.i; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 22 }
                                    Text {
                                        anchors { right: parent.right; rightMargin: 12; verticalCenter: ftIcon.verticalCenter; left: ftIcon.right; leftMargin: 10 }
                                        horizontalAlignment: Text.AlignRight
                                        text: ft.modelData.k
                                        elide: Text.ElideLeft
                                        color: Theme.sub
                                        font.family: Theme.font
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                    Column {
                                        x: 14; anchors { bottom: parent.bottom; bottomMargin: 11 }
                                        width: parent.width - 28
                                        Text { width: parent.width; text: ft.modelData.t; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                                        Text { width: parent.width; text: ft.modelData.d; elide: Text.ElideRight; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                                    }
                                    onClicked: modelData.f()
                                }
                            }
                        }
                    }

                    // автор: портфолио и канал; и начало
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10
                        Repeater {
                            model: Theme.links
                            GTile {
                                id: lnk
                                required property var modelData
                                ui: Theme
                                width: lrow.implicitWidth + 30
                                height: 48
                                radius: 24
                                on: true
                                onColor: modelData.c
                                Row {
                                    id: lrow
                                    anchors.centerIn: parent
                                    spacing: 9
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: lnk.modelData.i; color: "white"; font.family: Theme.iconFont; font.pixelSize: 19 }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text { text: lnk.modelData.t; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold }
                                        Text { text: lnk.modelData.d; color: Qt.rgba(1, 1, 1, 0.8); font.family: Theme.font; font.pixelSize: 10 }
                                    }
                                }
                                onClicked: Quickshell.execDetached(["xdg-open", modelData.u])
                            }
                        }
                        GButton {
                            ui: Theme
                            height: 48
                            label: Tr.t("Начать")
                            icon: "󰁔"
                            on: true
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: w.close()
                        }
                    }
                }
            }

            // ---------- Где что ----------
            Flickable {
                anchors.fill: parent
                visible: w.tab === 1
                contentHeight: guideFlow.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Flow {
                    id: guideFlow
                    width: parent.width
                    spacing: 12
                    Repeater {
                        model: w.guide
                        Item {
                            id: gsec
                            required property var modelData
                            width: (guideFlow.width - 24) / 3
                            height: gcol.implicitHeight + 26
                            Rectangle { anchors.fill: parent; radius: Theme.r(20); color: Theme.fill(0.06); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.14) }
                            Column {
                                id: gcol
                                x: 14; y: 13
                                width: parent.width - 28
                                spacing: 8
                                Row {
                                    spacing: 8
                                    Text { text: gsec.modelData.icon; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: gsec.modelData.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
                                }
                                Repeater {
                                    model: gsec.modelData.items
                                    Column {
                                        required property var modelData
                                        width: gcol.width
                                        spacing: 1
                                        Text { width: parent.width; text: modelData[0]; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                        Text { width: parent.width; text: modelData[1]; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; wrapMode: Text.WordWrap }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------- Вопросы ----------
            Flickable {
                anchors.fill: parent
                visible: w.tab === 3
                contentHeight: faqCol.implicitHeight + 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: faqCol
                    width: parent.width
                    spacing: 10
                    Repeater {
                        model: Faq.items
                        Rectangle {
                            id: fq
                            required property var modelData
                            property bool open: false
                            width: faqCol.width
                            height: fh.height + (open ? fa.implicitHeight + 14 : 0)
                            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            clip: true
                            radius: Theme.r(16)
                            color: Theme.fill(open ? 0.10 : 0.06); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.14)
                            Item {
                                id: fh
                                width: parent.width; height: 46
                                Text { x: 16; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 52; text: fq.modelData.q; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                Text { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: fq.open ? "󰅃" : "󰅀"; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 14 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: fq.open = !fq.open }
                            }
                            Text {
                                id: fa
                                x: 16; y: fh.height
                                width: parent.width - 32
                                text: fq.modelData.a; wrapMode: Text.WordWrap
                                color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.15
                            }
                        }
                    }
                }
            }

            // ---------- Клавиши ----------
            Flickable {
                anchors.fill: parent
                visible: w.tab === 2
                contentHeight: keysFlow.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // раскладка «кирпичами»: секция встаёт в самую короткую колонку (по числу строк), описания переносятся — без дыр и многоточий
                Row {
                    id: keysFlow
                    width: parent.width
                    spacing: 12
                    readonly property int cols: width >= 900 ? 3 : (width >= 560 ? 2 : 1)
                    readonly property real colW: (width - spacing * (cols - 1)) / cols
                    readonly property var lanes: {
                        var h = [], out = [];
                        for (var c = 0; c < cols; c++) { h.push(0); out.push([]); }
                        w.sections.forEach(function (sec) {
                            var best = 0;
                            for (var k = 1; k < cols; k++) if (h[k] < h[best]) best = k;
                            out[best].push(sec);
                            h[best] += 2 + sec.items.reduce(function (n, it) { return n + 1 + Math.floor(it.act.length / 34); }, 0);
                        });
                        return out;
                    }
                    Repeater {
                        model: keysFlow.lanes
                        Column {
                            required property var modelData
                            width: keysFlow.colW
                            spacing: 12
                            Repeater {
                                model: parent.modelData
                                Item {
                                    id: sec
                                    required property var modelData
                                    width: keysFlow.colW
                                    height: secCol.implicitHeight + 24
                                    Rectangle { anchors.fill: parent; radius: Theme.r(18); color: Theme.fill(0.06); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.14) }
                                    Column {
                                        id: secCol
                                        x: 14; y: 12
                                        width: parent.width - 28
                                        spacing: 7
                                        Text { text: sec.modelData.title; color: Theme.accent; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Bold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6 }
                                        Repeater {
                                            model: sec.modelData.items
                                            Item {
                                                id: kr
                                                required property var modelData
                                                width: secCol.width
                                                height: Math.max(24, actText.implicitHeight)
                                                Rectangle {
                                                    id: keyBox
                                                    width: Math.min(Math.max(keyText.implicitWidth + 14, 40), secCol.width * 0.55); height: 24
                                                    radius: Theme.r(7)
                                                    color: Theme.fill(0.12)
                                                    border.width: Theme.ios ? 0 : 1
                                                    border.color: Theme.line(0.2)
                                                    Text { id: keyText; anchors.centerIn: parent; width: Math.min(implicitWidth, parent.width - 10); elide: Text.ElideRight; text: kr.modelData.key; color: Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
                                                }
                                                Text {
                                                    id: actText
                                                    anchors { left: keyBox.right; leftMargin: 10; right: parent.right }
                                                    topPadding: 4
                                                    text: kr.modelData.act; wrapMode: Text.WordWrap
                                                    color: Theme.sub; font.family: Theme.font; font.pixelSize: 12
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
