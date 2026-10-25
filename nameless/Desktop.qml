import QtQuick
import Quickshell
import Quickshell.Wayland

// Панель «Рабочий стол» (SUPER+W): виджеты, док и экран блокировки — все параметры сохраняются сразу (Config).
//   Виджеты      — набор, порядок, размер, фон, полная настройка каждого (клик по строке), расстановка на столе
//   Док          — стиль (macOS / iOS), размер, увеличение, плитки, автоскрытие, Загрузки и корзина, закреплённые
//   Космос       — вместо обоев: звёздное небо или солнечная система (для темы), их подробная настройка
//   Блокировка   — оформление экрана блокировки, уведомления и плеер на нём, проверка
// Списки строятся по числу пунктов: изменение настройки не пересоздаёт строки (раньше от этого панель подлагивала)
PanelWindow {
    id: w
    property var shell: null
    readonly property bool open: shell ? shell.desktopOpen : false
    function close() { if (shell) shell.desktopOpen = false; }
    // вкладка и раскрытая строка хранятся в оболочке: окно выгружается после закрытия
    property int tab: shell ? shell.desktopTab : 0
    property string expanded: shell ? shell.desktopExpanded : ""
    onTabChanged: if (shell) shell.desktopTab = tab
    property real progress: 0
    Component.onCompleted: {
        progress = Qt.binding(function () { return w.open ? 1 : 0; });
    }
    Behavior on progress { NumberAnimation { duration: Theme.dur(w.open); easing.type: Easing.OutCubic } }

    visible: progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-desktop"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    function themeSet(key, v) { Quickshell.execDetached([Theme.script, "set", key, v ? "true" : "false"]); }
    // значение темы как JSON: строка, число, false
    function themeSetJson(key, json) { Quickshell.execDetached([Theme.script, "set", key, json]); }
    function editOnDesk() { close(); if (shell) shell.widgetsEdit = true; }

    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * w.progress }
    MouseArea { anchors.fill: parent; onClicked: w.close() }

    Surface {
        id: box
        alpha: Theme.overlayAlpha
        width: Math.min(parent.width - 40, 660)
        height: Math.min(parent.height - 60, head.height + body.contentHeight + 56)
        anchors.centerIn: parent
        anchors.verticalCenterOffset: (1 - w.progress) * 14
        opacity: w.progress
        radius: Theme.ios ? 30 : 22
        MouseArea { anchors.fill: parent }
        MoveArea { win: box; anchors { left: parent.left; right: parent.right; top: parent.top } height: 64 }
        focus: w.open
        Keys.onEscapePressed: w.close()
        Keys.onPressed: (e) => { if (e.key === Qt.Key_Tab) { w.tab = (w.tab + 1) % 4; e.accepted = true; } }

        Item {
            id: head
            x: 20; y: 18
            width: parent.width - 40
            height: 38
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Tr.t("Рабочий стол")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.ios ? 22 : 19
                font.weight: Font.Bold
            }
            GSegment {
                ui: Theme
                width: 440
                anchors { right: closeBtn.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                options: [{ v: "0", t: Tr.t("Виджеты"), icon: "󰕰" }, { v: "1", t: Tr.t("Док"), icon: "󰍜" }, { v: "2", t: Tr.t("Космос"), icon: "󰖔" }, { v: "3", t: Tr.t("Блокировка"), icon: "󰌾" }]
                value: String(w.tab)
                onPicked: (v) => { w.tab = Number(v); body.contentY = 0; }
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

        Flickable {
            id: body
            anchors { top: head.bottom; topMargin: 16; left: parent.left; leftMargin: 20; right: parent.right; rightMargin: 20; bottom: parent.bottom; bottomMargin: 20 }
            contentHeight: [widgetsPage, dockPage, cosmosPage, lockPage][w.tab].implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // ================= виджеты =================
            Column {
                id: widgetsPage
                visible: w.tab === 0
                width: body.width
                spacing: 12

                Group {
                    GSwitch {
                        ui: Theme
                        label: Tr.t("Виджеты на рабочем столе")
                        sub: Tr.t("для темы «") + (Theme.th.name || "") + "»"
                        checked: Theme.th.widgets === true
                        onToggled: (v) => w.themeSet(".widgets", v)
                    }
                    Labeled {
                        label: Tr.t("Фон карточек")
                        GSegment {
                            ui: Theme
                            options: [{ v: "glass", t: Tr.t("Стекло") }, { v: "solid", t: Tr.t("Плотный") }, { v: "tint", t: Tr.t("Акцент") }, { v: "outline", t: Tr.t("Контур") }, { v: "clear", t: Tr.t("Без фона") }]
                            value: Config.widgets.look || "glass"
                            onPicked: (v) => Config.set("widgets.look", v)
                        }
                    }
                    // оформление карточек — общее для всех виджетов (WCard)
                    Labeled {
                        visible: (Config.widgets.look || "glass") !== "clear"
                        label: Tr.t("Углы")
                        GSegment {
                            ui: Theme
                            options: [{ v: "0", t: Tr.t("По теме") }, { v: "8", t: Tr.t("Острые") }, { v: "16", t: Tr.t("Мягкие") }, { v: "28", t: Tr.t("Круглые") }]
                            value: String(Config.widgets.corners || 0)
                            onPicked: (v) => Config.set("widgets.corners", Number(v))
                        }
                    }
                    Labeled {
                        visible: (Config.widgets.look || "glass") !== "clear"
                        label: Tr.t("Обводка")
                        GSegment {
                            ui: Theme
                            options: [{ v: "none", t: Tr.t("Нет") }, { v: "thin", t: Tr.t("Тонкая") }, { v: "accent", t: Tr.t("Акцент") }, { v: "gradient", t: Tr.t("Градиент") }]
                            value: Config.widgets.border || "none"
                            onPicked: (v) => Config.set("widgets.border", v)
                        }
                    }
                    Labeled {
                        label: Tr.t("Отступы")
                        GSegment {
                            ui: Theme
                            options: [{ v: "compact", t: Tr.t("Плотно") }, { v: "normal", t: Tr.t("Обычно") }, { v: "roomy", t: Tr.t("Просторно") }]
                            value: Config.widgets.density || "normal"
                            onPicked: (v) => Config.set("widgets.density", v)
                        }
                    }
                    GSwitch {
                        visible: (Config.widgets.look || "glass") !== "clear"
                        ui: Theme; label: Tr.t("Свет сверху"); sub: Tr.t("мягкое свечение акцентом по верху карточки")
                        checked: Config.widgets.glow === true; onToggled: (v) => Config.set("widgets.glow", v)
                    }
                    PillSlider {
                        visible: ["glass", "solid", "tint"].indexOf(Config.widgets.look || "glass") >= 0
                        ui: Theme; width: parent.width; icon: "󰃞"; label: Tr.t("Плотность фона")
                        from: 30; to: 100; stepSize: 5; decimals: 0; suffix: "%"
                        value: Math.round((Config.widgets.opacity === undefined ? 1 : Config.widgets.opacity) * 100)
                        onCommitted: (v) => Config.set("widgets.opacity", v / 100)
                    }
                    Labeled {
                        label: Tr.t("Расстановка")
                        GSegment {
                            ui: Theme
                            options: [{ v: "auto", t: Tr.t("По рядам"), icon: "󰕮" }, { v: "grid", t: Tr.t("Сетка"), icon: "󰕰" }, { v: "columns", t: Tr.t("Колонки"), icon: "󰕭" }, { v: "free", t: Tr.t("Свободно"), icon: "󰆾" }]
                            value: Config.widgets.layout || "auto"
                            onPicked: (v) => Config.set("widgets.layout", v)
                        }
                    }
                    Labeled {
                        visible: (Config.widgets.layout || "auto") === "auto"
                        label: Tr.t("Ряды")
                        GSegment {
                            ui: Theme
                            options: [{ v: "left", t: Tr.t("Слева"), icon: "󰁍" }, { v: "center", t: Tr.t("По центру"), icon: "󰘞" }, { v: "right", t: Tr.t("Справа"), icon: "󰁔" }, { v: "fill", t: Tr.t("На всю ширину"), icon: "󰡎" }]
                            value: Config.widgets.align || "center"
                            onPicked: (v) => Config.set("widgets.align", v)
                        }
                    }
                    Labeled {
                        visible: ["auto", "columns"].indexOf(Config.widgets.layout || "auto") >= 0
                        label: Tr.t("Колонок")
                        GSegment {
                            ui: Theme
                            options: [{ v: "0", t: Tr.t("Авто") }, { v: "2", t: "2" }, { v: "3", t: "3" }, { v: "4", t: "4" }, { v: "5", t: "5" }, { v: "6", t: "6" }, { v: "8", t: "8" }]
                            value: String(Config.widgets.cols || 0)
                            onPicked: (v) => { Config.set("widgets.cols", Number(v)); if (Number(v) > 0) Config.set("widgets.rows", 0); }
                        }
                    }
                    Labeled {
                        visible: (Config.widgets.layout || "auto") === "auto"
                        label: Tr.t("Рядов")
                        GSegment {
                            ui: Theme
                            options: [{ v: "0", t: Tr.t("Авто") }, { v: "1", t: "1" }, { v: "2", t: "2" }, { v: "3", t: "3" }, { v: "4", t: "4" }]
                            value: String(Config.widgets.rows || 0)
                            onPicked: (v) => { Config.set("widgets.rows", Number(v)); if (Number(v) > 0) Config.set("widgets.cols", 0); }
                        }
                    }
                    Text {
                        visible: (Config.widgets.cols || 0) > 0 || (Config.widgets.rows || 0) > 0
                        width: parent.width; wrapMode: Text.WordWrap
                        text: Tr.t("Колонки делят ширину экрана поровну, размер виджетов подбирается сам — масштаб ниже не действует")
                        color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
                    }
                    Labeled {
                        label: Tr.t("Масштаб")
                        GSegment {
                            ui: Theme
                            options: [{ v: "auto", t: Tr.t("Авто") }, { v: "0.5", t: "50%" }, { v: "0.7", t: "70%" }, { v: "0.85", t: "85%" }, { v: "1", t: "100%" }, { v: "1.15", t: "115%" }, { v: "1.3", t: "130%" }, { v: "1.5", t: "150%" }]
                            value: String(Config.widgets.scale === undefined ? "auto" : Config.widgets.scale)
                            onPicked: (v) => Config.set("widgets.scale", v === "auto" ? "auto" : Number(v))
                        }
                    }
                    Labeled {
                        visible: (Config.widgets.layout || "auto") !== "auto"
                        label: Tr.t("Колонки с края")
                        GSegment {
                            ui: Theme
                            options: [{ v: "left", t: Tr.t("Слева"), icon: "󰁍" }, { v: "right", t: Tr.t("Справа"), icon: "󰁔" }]
                            value: Config.widgets.side === "right" ? "right" : "left"
                            onPicked: (v) => Config.set("widgets.side", v)
                        }
                    }
                    Row {
                        spacing: 8
                        GButton { ui: Theme; icon: "󰙵"; label: Tr.t("Расставить на столе"); on: true; onClicked: w.editOnDesk() }
                        GButton { ui: Theme; icon: "󰕰"; label: Tr.t("Всё в колонку"); onClicked: Config.unplaceWidgets() }
                    }
                }

                Text { text: Tr.t("Виджеты — клик по строке открывает настройки"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7 }

                Repeater {
                    model: Config.widgets.items.length
                    Item {
                        id: wrow
                        required property int index
                        readonly property var it: Config.widgets.items[index] || ({})
                        readonly property var kind: Config.kinds[it.type] || ({ name: it.type, icon: "", about: "" })
                        readonly property bool open: w.expanded === it.type
                        width: widgetsPage.width
                        height: 60 + (open ? opts.implicitHeight + 14 : 0)
                        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        clip: true
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.r(18)
                            color: Theme.fill(wrow.it.on ? 0.10 : 0.05)
                            border.width: Theme.ios ? 0 : 1
                            border.color: wrow.open ? Theme.accent : Theme.line(0.14)
                        }
                        MouseArea { width: parent.width; height: 60; cursorShape: Qt.PointingHandCursor; onClicked: w.expanded = wrow.open ? "" : wrow.it.type }
                        Rectangle {
                            id: wIcon
                            x: 12; y: 12
                            width: 36; height: 36; radius: Theme.r(11)
                            color: wrow.it.on ? Theme.accent : Theme.fill(0.12)
                            Text { anchors.centerIn: parent; text: wrow.kind.icon; color: wrow.it.on ? "white" : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 17 }
                        }
                        Column {
                            anchors { left: wIcon.right; leftMargin: 12; right: ctl.left; rightMargin: 8 }
                            y: 13
                            Text { width: parent.width; text: wrow.kind.name + (wrow.it.x !== undefined ? Tr.t("  ·  на своём месте") : ""); elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { width: parent.width; text: wrow.kind.about; elide: Text.ElideRight; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                        }
                        Row {
                            id: ctl
                            anchors { right: parent.right; rightMargin: 10 }
                            y: 13
                            spacing: 4
                            SmallBtn { icon: "󰁝"; enabled: wrow.index > 0; onClicked: Config.moveWidget(wrow.it.type, -1) }
                            SmallBtn { icon: "󰁅"; enabled: wrow.index < Config.widgets.items.length - 1; onClicked: Config.moveWidget(wrow.it.type, 1) }
                            GSwitch { ui: Theme; width: 56; checked: wrow.it.on === true; onToggled: Config.toggleWidget(wrow.it.type) }
                        }

                        // ---------- параметры виджета ----------
                        Column {
                            id: opts
                            visible: wrow.open
                            x: 16; y: 66
                            width: parent.width - 32
                            spacing: 10
                            readonly property string t: wrow.it.type

                            Labeled {
                                label: Tr.t("Размер")
                                GSegment { ui: Theme; options: [{ v: "S", t: "S · 240" }, { v: "M", t: "M · 300" }, { v: "L", t: "L · 380" }]; value: wrow.it.size || "M"; onPicked: (v) => Config.setItem(wrow.it.type, "size", v) }
                            }
                            // часы
                            Column {
                                visible: opts.t === "clock"
                                width: parent.width; spacing: 10
                                readonly property var o: Config.store.clock
                                Labeled { label: Tr.t("Вид"); GSegment { ui: Theme; options: [{ v: "digital", t: Tr.t("Цифры") }, { v: "analog", t: Tr.t("Стрелки") }, { v: "words", t: Tr.t("Словами") }, { v: "stack", t: Tr.t("Столбик") }, { v: "flip", t: Tr.t("Карточки") }, { v: "pixel", t: Tr.t("Пиксели") }]; value: Config.store.clock.style || "digital"; onPicked: (v) => Config.set("clock.style", v) } }
                                Labeled { label: Tr.t("Дата"); GSegment { ui: Theme; options: [{ v: "long", t: Tr.t("Полная") }, { v: "short", t: Tr.t("Кратко") }, { v: "none", t: Tr.t("Нет") }]; value: Config.store.clock.date || "long"; onPicked: (v) => Config.set("clock.date", v) } }
                                GSwitch { ui: Theme; label: Tr.t("24-часовой формат"); checked: Config.store.clock.h24 !== false; onToggled: (v) => Config.set("clock.h24", v) }
                                GSwitch { ui: Theme; label: Tr.t("Секунды"); checked: Config.store.clock.seconds === true; onToggled: (v) => Config.set("clock.seconds", v) }
                                Field { icon: "󰥔"; hint: Tr.t("Второй пояс: подпись (пусто — нет), например «Токио»"); value: Config.store.clock.zone || ""; onCommitted: (v) => Config.set("clock.zone", v) }
                                PillSlider {
                                    visible: !!Config.store.clock.zone
                                    ui: Theme; width: parent.width; icon: "󰗶"; label: Tr.t("Смещение от UTC")
                                    from: -12; to: 14; stepSize: 0.5; decimals: 1; value: Config.store.clock.offset || 0; suffix: Tr.t(" ч")
                                    onCommitted: (v) => Config.set("clock.offset", v)
                                }
                            }
                            // нагрузка
                            Column {
                                visible: opts.t === "system"
                                width: parent.width; spacing: 10
                                readonly property var o: Config.store.system
                                Labeled { label: Tr.t("Вид"); GSegment { ui: Theme; options: [{ v: "bars", t: Tr.t("Полосы") }, { v: "rings", t: Tr.t("Кольца") }, { v: "graph", t: Tr.t("Графики") }]; value: Config.store.system.view || "bars"; onPicked: (v) => Config.set("system.view", v) } }
                                PillSlider { ui: Theme; width: parent.width; icon: "󰔟"; label: Tr.t("Обновлять раз в"); from: 1; to: 10; stepSize: 1; decimals: 0; value: Config.store.system.interval || 2; suffix: Tr.t(" с"); onCommitted: (v) => Config.set("system.interval", v) }
                                Text { text: Tr.t("Показывать"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                                Chips {
                                    keys: [["cpu", Tr.t("󰻠 Процессор")], ["ram", Tr.t("󰍛 Память")], ["swap", Tr.t("󰾴 Подкачка")], ["temp", Tr.t("󰔏 Температура")], ["gpu", Tr.t("󰢮 Видеокарта NVIDIA")], ["igpu", Tr.t("󰢮 Встроенная графика")], ["freq", Tr.t("󰓅 Частота")],
                                           ["disk", Tr.t("󰋊 Диск")], ["net", Tr.t("󰛳 Сеть")], ["battery", Tr.t("󰁹 Батарея")], ["uptime", Tr.t("󰅐 Время работы")]]
                                    isOn: function (k) { return k === "freq" ? Config.store.system.freq !== false : Config.store.system[k] === true; }
                                    onToggle: (k) => Config.set("system." + k, !(k === "freq" ? Config.store.system.freq !== false : Config.store.system[k] === true))
                                }
                                Text { visible: Config.store.system.gpu === true; width: parent.width; wrapMode: Text.WordWrap; text: Tr.t("NVIDIA опрашивается через nvidia-smi, пока карта не спит (спящую не будим), но сам опрос не даёт ей уснуть — на батарее лучше выключить."); color: Theme.yellow; font.family: Theme.font; font.pixelSize: 11 }
                            }
                            // погода
                            Column {
                                visible: opts.t === "weather"
                                width: parent.width; spacing: 10
                                Field { icon: "󰍎"; hint: Tr.t("Город (пусто — по IP)"); value: Config.store.weather.city || ""; onCommitted: (v) => Config.set("weather.city", v) }
                                Labeled { label: Tr.t("Источник"); GSegment { ui: Theme; options: [{ v: "open-meteo", t: "Open-Meteo" }, { v: "metno", t: "MET Norway" }, { v: "wttr", t: "wttr.in" }]; value: Config.store.weather.provider || "open-meteo"; onPicked: (v) => Config.set("weather.provider", v) } }
                                Labeled { label: Tr.t("Единицы"); GSegment { ui: Theme; options: [{ v: "C", t: "°C" }, { v: "F", t: "°F" }]; value: Config.store.weather.units || "C"; onPicked: (v) => Config.set("weather.units", v) } }
                                Labeled { label: Tr.t("Прогноз"); GSegment { ui: Theme; options: [{ v: "1", t: Tr.t("Сегодня") }, { v: "2", t: Tr.t("2 дня") }, { v: "3", t: Tr.t("3 дня") }]; value: String(Config.store.weather.days || 3); onPicked: (v) => Config.set("weather.days", Number(v)) } }
                            }
                            GSwitch { visible: opts.t === "calendar"; ui: Theme; label: Tr.t("Номера недель"); checked: Config.store.calendar.weeks === true; onToggled: (v) => Config.set("calendar.weeks", v) }
                            GSwitch { visible: opts.t === "player"; ui: Theme; label: Tr.t("Компактный"); sub: Tr.t("без полосы перемотки"); checked: Config.store.player.compact === true; onToggled: (v) => Config.set("player.compact", v) }
                            PillSlider { visible: opts.t === "notes"; ui: Theme; width: parent.width; icon: "󰛖"; label: Tr.t("Размер текста"); from: 11; to: 22; stepSize: 1; decimals: 0; value: Config.store.notes.size || 13; suffix: " px"; onCommitted: (v) => Config.set("notes.size", v) }
                            Column {
                                visible: opts.t === "timer"
                                width: parent.width; spacing: 10
                                PillSlider { ui: Theme; width: parent.width; icon: "󰔛"; label: Tr.t("Работа"); from: 5; to: 90; stepSize: 5; decimals: 0; value: Config.store.timer.work || 25; suffix: Tr.t(" мин"); onCommitted: (v) => Config.set("timer.work", v) }
                                PillSlider { ui: Theme; width: parent.width; icon: "󰅶"; label: Tr.t("Перерыв"); from: 1; to: 30; stepSize: 1; decimals: 0; value: Config.store.timer.rest || 5; suffix: Tr.t(" мин"); onCommitted: (v) => Config.set("timer.rest", v) }
                            }
                            Chips {
                                visible: opts.t === "actions"
                                keys: [["terminal", Tr.t("󰆍 Терминал")], ["files", Tr.t("󰉋 Файлы")], ["browser", Tr.t("󰖟 Браузер")], ["screenshot", Tr.t("󰹑 Скриншот")], ["lock", Tr.t("󰌾 Блок")],
                                       ["drawer", Tr.t("󰏘 Темы")], ["programs", Tr.t("󰏖 Программы")], ["wallpaper", Tr.t("󰸉 Обои")], ["dnd", Tr.t("󰂛 Тишина")], ["monitor", Tr.t("󰍛 Диспетчер")],
                                       ["settings", Tr.t("󰒓 Стол")], ["power", Tr.t("󰐥 Питание")]]
                                isOn: function (k) { return (Config.store.actions.list || []).indexOf(k) >= 0; }
                                onToggle: (k) => {
                                    var l = (Config.store.actions.list || []).slice(), i = l.indexOf(k);
                                    if (i >= 0) l.splice(i, 1); else l.push(k);
                                    Config.set("actions.list", l);
                                }
                            }
                            Column {
                                visible: opts.t === "photo"
                                width: parent.width; spacing: 10
                                Field { icon: "󰉋"; hint: Tr.t("Папка с картинками"); value: Config.store.photo.dir || "~/Pictures"; onCommitted: (v) => Config.set("photo.dir", v || "~/Pictures") }
                                PillSlider { ui: Theme; width: parent.width; icon: "󰔟"; label: Tr.t("Смена раз в"); from: 5; to: 300; stepSize: 5; decimals: 0; value: Config.store.photo.interval || 30; suffix: Tr.t(" с"); onCommitted: (v) => Config.set("photo.interval", v) }
                            }
                            PillSlider { visible: opts.t === "updates"; ui: Theme; width: parent.width; icon: "󰚰"; label: Tr.t("Проверять раз в"); from: 15; to: 360; stepSize: 15; decimals: 0; value: Config.store.updates.interval || 60; suffix: Tr.t(" мин"); onCommitted: (v) => Config.set("updates.interval", v) }
                            Column {
                                visible: opts.t === "countdown"
                                width: parent.width; spacing: 10
                                Field { icon: "󰔟"; hint: Tr.t("Подпись"); value: Config.store.countdown.title || ""; onCommitted: (v) => Config.set("countdown.title", v) }
                                Field { icon: "󰃭"; hint: Tr.t("Дата ГГГГ-ММ-ДД"); value: Config.store.countdown.date || ""; onCommitted: (v) => { if (/^\d{4}-\d{2}-\d{2}$/.test(v)) Config.set("countdown.date", v); } }
                            }
                            Column {
                                visible: opts.t === "claude" || opts.t === "tokens"
                                width: parent.width; spacing: 10
                                Labeled { label: Tr.t("Помощник"); GSegment { ui: Theme; options: [{ v: "claude", t: "Claude" }, { v: "codex", t: "Codex" }]; value: (opts.t === "tokens" ? Config.store.tokens.provider : Config.store.claude.provider) || "claude"; onPicked: v => Config.set(opts.t + ".provider", v) } }
                                Labeled { visible: opts.t === "claude"; label: Tr.t("Вид"); GSegment { ui: Theme; options: [{ v: "rings", t: Tr.t("Кольца") }, { v: "bars", t: Tr.t("Полосы") }]; value: Config.store.claude.view || "rings"; onPicked: (v) => Config.set("claude.view", v) } }
                                Labeled { visible: opts.t === "tokens"; label: Tr.t("Вид"); GSegment { ui: Theme; options: [{ v: "chart", t: Tr.t("График") }, { v: "numbers", t: Tr.t("Только числа") }]; value: Config.store.tokens.view || "chart"; onPicked: (v) => Config.set("tokens.view", v) } }
                                GSwitch { ui: Theme; label: Tr.t("Запрашивать лимиты"); sub: Tr.t("раз в 2 минуты, с токеном Claude Code (он не сохраняется)"); checked: Config.store.agents.quota !== false; onToggled: (v) => Config.set("agents.quota", v) }
                            }
                            Column {
                                visible: opts.t === "agents"
                                width: parent.width; spacing: 10
                                Labeled { label: Tr.t("Кого спрашивать"); GSegment { ui: Theme; options: [{ v: "claude", t: "✳ Claude Code" }, { v: "codex", t: "X Codex" }]; value: Config.store.agents.ask || "claude"; onPicked: (v) => Config.set("agents.ask", v) } }
                                GSwitch { ui: Theme; label: Tr.t("Последнее сообщение"); sub: Tr.t("под названием проекта"); checked: Config.store.agents.last !== false; onToggled: (v) => Config.set("agents.last", v) }
                                GSwitch { ui: Theme; label: Tr.t("Лимиты Claude"); sub: Tr.t("окно 5 часов и неделя; запрос с токеном Claude Code раз в 2 минуты"); checked: Config.store.agents.quota !== false; onToggled: (v) => Config.set("agents.quota", v) }
                                GSwitch { ui: Theme; label: Tr.t("Лимит в баре"); sub: Tr.t("процент окна 5 часов рядом со временем"); checked: Config.store.agents.bar === true; onToggled: (v) => Config.set("agents.bar", v) }
                            }
                            Column {
                                visible: opts.t === "pets"
                                width: parent.width; spacing: 10
                                Chips {
                                    keys: [["ginger", Tr.t("󰄛 Рыжий кот")], ["white", Tr.t("󰄛 Белая кошка")], ["black", Tr.t("󰄛 Чёрный кот")], ["corgi", Tr.t("󰩃 Корги")], ["fox", Tr.t("󰩃 Лиса")], ["clawd", Tr.t("󰚩 Клод")]]
                                    isOn: function (k) { return (Config.store.pets.list || []).indexOf(k) >= 0; }
                                    onToggle: (k) => {
                                        var l = (Config.store.pets.list || []).slice(), i = l.indexOf(k);
                                        if (i >= 0) l.splice(i, 1); else l.push(k);
                                        Config.set("pets.list", l);
                                    }
                                }
                                Text { text: Tr.t("Сцена"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                                Chips {
                                    keys: [["auto", Tr.t("󰃭 Авто по дате")], ["none", Tr.t("Без фона")], ["home", Tr.t("󰋜 Дом")], ["park", Tr.t("󰐅 Парк")], ["night", Tr.t("󰖔 Ночь")],
                                           ["winter", Tr.t("󰜗 Зима")], ["beach", Tr.t("󰖨 Пляж")], ["spring", Tr.t("󰉊 Весна")], ["autumn", Tr.t("󰌪 Осень")],
                                           ["newyear", Tr.t("󰜈 Новый год")], ["halloween", Tr.t("󰮣 Хэллоуин")], ["valentine", Tr.t("󰣐 День влюблённых")]]
                                    isOn: function (k) { return (Config.store.pets.scene || "auto") === k; }
                                    onToggle: (k) => Config.set("pets.scene", k)
                                }
                                Text { width: parent.width; wrapMode: Text.WordWrap; text: Tr.t("Наведите и подержите — мурлычет; нажатие — прыжок; перетащите — переставить; клик по пустому месту — мячик; «Покормить» — миска. Дома котики спят в лукошке у печки."); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                                PillSlider { ui: Theme; width: parent.width; icon: "󰩨"; label: Tr.t("Размер"); from: 2; to: 7; stepSize: 1; decimals: 0; value: Config.store.pets.unit || 4; onCommitted: (v) => Config.set("pets.unit", v) }
                                GSwitch { visible: (Config.store.pets.scene || "auto") === "none"; ui: Theme; label: Tr.t("Земля"); sub: Tr.t("тонкая линия, по которой ходят питомцы"); checked: Config.store.pets.ground !== false; onToggled: (v) => Config.set("pets.ground", v) }
                            }
                            Column {
                                visible: opts.t === "gif"
                                width: parent.width; spacing: 10
                                Field { icon: "󰵸"; hint: Tr.t("Файл или папка с GIF"); value: Config.store.gif.path || ""; onCommitted: (v) => Config.set("gif.path", v) }
                                GSwitch { ui: Theme; label: Tr.t("Пиксельно"); sub: Tr.t("без сглаживания — для пиксель-арта"); checked: Config.store.gif.pixel !== false; onToggled: (v) => Config.set("gif.pixel", v) }
                                GSwitch { ui: Theme; label: Tr.t("Карточка"); sub: Tr.t("стеклянная подложка под картинкой"); checked: Config.store.gif.card === true; onToggled: (v) => Config.set("gif.card", v) }
                                PillSlider { ui: Theme; width: parent.width; icon: "󰩨"; label: Tr.t("Масштаб"); from: 1; to: 6; stepSize: 1; decimals: 0; value: Config.store.gif.scale || 1; suffix: "×"; onCommitted: (v) => Config.set("gif.scale", v) }
                                PillSlider { ui: Theme; width: parent.width; icon: "󰔟"; label: Tr.t("Смена (папка) раз в"); from: 5; to: 300; stepSize: 5; decimals: 0; value: Config.store.gif.interval || 30; suffix: Tr.t(" с"); onCommitted: (v) => Config.set("gif.interval", v) }
                            }
                            // ёлочка: гирлянда, цвета, скорость, снег и подарки
                            Column {
                                id: treeOpts
                                visible: opts.t === "tree"
                                width: parent.width; spacing: 10
                                readonly property var o: Config.store.tree || ({})
                                Labeled { label: Tr.t("Гирлянда"); GSegment { ui: Theme; options: [{ v: "chase", t: Tr.t("Бегущие огни") }, { v: "twinkle", t: Tr.t("Мерцание") }, { v: "wave", t: Tr.t("Волна") }]; value: treeOpts.o.garland || "chase"; onPicked: (v) => Config.set("tree.garland", v) } }
                                Labeled { label: Tr.t("Цвета"); GSegment { ui: Theme; options: [{ v: "multi", t: Tr.t("Разноцветная") }, { v: "warm", t: Tr.t("Тёплая") }, { v: "accent", t: Tr.t("Цвета темы") }]; value: treeOpts.o.colors || "multi"; onPicked: (v) => Config.set("tree.colors", v) } }
                                PillSlider { ui: Theme; width: parent.width; icon: "󰓅"; label: Tr.t("Скорость гирлянды"); from: 1; to: 10; stepSize: 1; decimals: 0; value: treeOpts.o.speed || 5; onCommitted: (v) => Config.set("tree.speed", v) }
                                GSwitch { ui: Theme; label: Tr.t("Снег"); checked: treeOpts.o.snow !== false; onToggled: (v) => Config.set("tree.snow", v) }
                                GSwitch { ui: Theme; label: Tr.t("Подарки под ёлкой"); checked: treeOpts.o.gifts !== false; onToggled: (v) => Config.set("tree.gifts", v) }
                            }
                            PillSlider { visible: opts.t === "fish"; ui: Theme; width: parent.width; icon: "󰈺"; label: Tr.t("Рыбок"); from: 1; to: 8; stepSize: 1; decimals: 0; value: Config.store.fish.count || 4; onCommitted: (v) => Config.set("fish.count", v) }
                            Text { visible: ["notifs", "clawd", "moon", "quote"].indexOf(opts.t) >= 0; text: Tr.t("Других параметров нет"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                        }
                    }
                }

                GButton { ui: Theme; label: Tr.t("Вернуть набор по умолчанию"); icon: "󰑓"; onClicked: Config.resetWidgets() }
            }

            // ================= док =================
            Column {
                id: dockPage
                visible: w.tab === 1
                width: body.width
                spacing: 12

                Group {
                    GSwitch {
                        ui: Theme
                        label: Tr.t("Док внизу экрана")
                        sub: Tr.t("для темы «") + (Theme.th.name || "") + "»"
                        checked: Theme.th.dock === true
                        onToggled: (v) => w.themeSet(".dock", v)
                    }
                    Labeled {
                        label: Tr.t("Стиль")
                        GSegment {
                            ui: Theme
                            options: [{ v: "mac", t: Tr.t("macOS — полка") }, { v: "ios", t: Tr.t("iOS — плашка") }]
                            value: Config.dock.style === "ios" ? "ios" : "mac"
                            onPicked: (v) => Config.set("dock.style", v)
                        }
                    }
                    PillSlider { ui: Theme; width: parent.width; icon: "󰍹"; label: Tr.t("Размер значков"); from: 36; to: 80; stepSize: 2; decimals: 0; value: Config.dock.size || 54; suffix: " px"; onCommitted: (v) => Config.set("dock.size", v) }
                    GSwitch { ui: Theme; label: Tr.t("Увеличение под курсором"); checked: Config.dock.magnify !== false; onToggled: (v) => Config.set("dock.magnify", v) }
                    PillSlider { visible: Config.dock.magnify !== false; ui: Theme; width: parent.width; icon: "󰐕"; label: Tr.t("Сила увеличения"); from: 1.2; to: 2.2; stepSize: 0.1; decimals: 1; value: Config.dock.zoom || 1.7; suffix: "×"; onCommitted: (v) => Config.set("dock.zoom", v) }
                    GSwitch { ui: Theme; label: Tr.t("Значки на плитках"); sub: Tr.t("одинаковые «сквирклы», как в iOS"); checked: Config.dock.tiles === true; onToggled: (v) => Config.set("dock.tiles", v) }
                }
                Group {
                    GSwitch { ui: Theme; label: Tr.t("Скрывать автоматически"); sub: Tr.t("появляется у нижнего края экрана"); checked: Config.dock.autohide === true; onToggled: (v) => Config.set("dock.autohide", v) }
                    GSwitch { ui: Theme; label: Tr.t("Запущенные приложения"); sub: Tr.t("значки открытых, но не закреплённых"); checked: Config.dock.running !== false; onToggled: (v) => Config.set("dock.running", v) }
                    GSwitch { ui: Theme; label: Tr.t("Подписи при наведении"); checked: Config.dock.labels !== false; onToggled: (v) => Config.set("dock.labels", v) }
                    GSwitch { ui: Theme; label: Tr.t("Папка «Загрузки»"); sub: Tr.t("справа, клик — последние файлы"); checked: Config.dock.downloads !== false; onToggled: (v) => Config.set("dock.downloads", v) }
                    GSwitch { ui: Theme; label: Tr.t("Корзина"); sub: Tr.t("справа, показывает, есть ли что-то внутри"); checked: Config.dock.trash !== false; onToggled: (v) => Config.set("dock.trash", v) }
                }

                Text { text: Tr.t("Закреплённые · ") + (Config.dock.pinned || []).length + Tr.t("  —  в самом доке их можно перетаскивать, а вытянуть вверх — убрать"); width: parent.width; wrapMode: Text.WordWrap; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }

                Repeater {
                    model: (Config.dock.pinned || []).length
                    Item {
                        id: prow
                        required property int index
                        readonly property string id0: (Config.dock.pinned || [])[index] || ""
                        readonly property var apps: DesktopEntries.applications.values
                        readonly property var entry: apps.length >= 0 && id0 !== "" ? (DesktopEntries.byId(id0) || DesktopEntries.heuristicLookup(id0)) : null
                        width: dockPage.width
                        height: 52
                        Rectangle { anchors.fill: parent; radius: Theme.r(16); color: Theme.fill(0.07); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.12) }
                        Image {
                            id: pIcon
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32
                            sourceSize: Qt.size(32, 32)
                            asynchronous: true
                            source: {
                                return Icons.app(prow.entry ? prow.entry.icon : prow.id0);
                            }
                        }
                        Column {
                            anchors { left: pIcon.right; leftMargin: 12; right: pctl.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            Text { width: parent.width; text: prow.entry ? prow.entry.name : prow.id0; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { width: parent.width; text: prow.entry ? prow.id0 : Tr.t("ярлык не найден"); elide: Text.ElideRight; color: prow.entry ? Theme.sub : Theme.red; font.family: Theme.font; font.pixelSize: 10 }
                        }
                        Row {
                            id: pctl
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 4
                            SmallBtn { icon: "󰁝"; enabled: prow.index > 0; onClicked: Config.movePin(prow.id0, -1) }
                            SmallBtn { icon: "󰁅"; enabled: prow.index < Config.dock.pinned.length - 1; onClicked: Config.movePin(prow.id0, 1) }
                            SmallBtn { icon: "󰅖"; danger: true; onClicked: Config.unpin(prow.id0) }
                        }
                    }
                }

                GButton { ui: Theme; label: Tr.t("Добавить приложение"); icon: "󰐕"; on: true; onClicked: { w.close(); if (w.shell) w.shell.pickForDock(); } }
            }

            // ================= космос =================
            Column {
                id: cosmosPage
                visible: w.tab === 2
                width: body.width
                spacing: 12
                readonly property var sk: Config.store.sky
                readonly property var so: Config.store.space

                Group {
                    Text { width: parent.width; wrapMode: Text.WordWrap; text: Tr.t("Вместо обоев — для темы «") + (Theme.th.name || "") + Tr.t("». Обои при этом выключаются целиком."); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                    GSegment {
                        ui: Theme
                        options: [{ v: "off", t: Tr.t("Обои"), icon: "󰸉" }, { v: "stars", t: Tr.t("Звёздное небо"), icon: "󰖔" }, { v: "solar", t: Tr.t("Астрономия"), icon: "󰖨" }, { v: "apps", t: Tr.t("Орбиты окон"), icon: "󰍹" }]
                        value: Theme.cosmos
                        onPicked: (v) => w.themeSetJson(".sky", v === "off" ? "false" : JSON.stringify(v))
                    }
                }

                Text { text: Tr.t("Звёздное небо — вид с Земли"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7 }
                Group {
                    opacity: Theme.cosmos === "stars" ? 1 : 0.5
                    Labeled {
                        label: Tr.t("Цвета неба")
                        GSegment {
                            ui: Theme
                            options: [{ v: "theme", t: Tr.t("Тема") }, { v: "deep", t: Tr.t("Синее") }, { v: "violet", t: Tr.t("Фиолет") }, { v: "teal", t: Tr.t("Бирюза") }, { v: "ember", t: Tr.t("Закат") }]
                            value: cosmosPage.sk.palette || "theme"
                            onPicked: (v) => Config.set("sky.palette", v)
                        }
                    }
                    PillSlider { ui: Theme; width: parent.width; icon: "󰖔"; label: Tr.t("Звёзд"); from: 0.3; to: 2; stepSize: 0.1; decimals: 1; value: cosmosPage.sk.stars || 1; suffix: "×"; onCommitted: (v) => Config.set("sky.stars", v) }
                    PillSlider { ui: Theme; width: parent.width; icon: "󰼯"; label: Tr.t("Туманности"); from: 0; to: 2; stepSize: 0.1; decimals: 1; value: cosmosPage.sk.nebula === undefined ? 1 : cosmosPage.sk.nebula; suffix: "×"; onCommitted: (v) => Config.set("sky.nebula", v) }
                    Chips {
                        keys: [["twinkle", Tr.t("󰖨 Мерцание")], ["meteors", Tr.t("󰄵 Падающие звёзды")], ["milkyway", Tr.t("󰯉 Млечный Путь")], ["constellations", Tr.t("󱁉 Созвездия")],
                               ["moon", Tr.t("󰽥 Луна")], ["daytime", Tr.t("󰖜 Сумерки по времени")]]
                        isOn: function (k) { return Config.store.sky[k] !== false; }
                        onToggle: (k) => Config.set("sky." + k, Config.store.sky[k] === false)
                    }
                    PillSlider {
                        visible: cosmosPage.sk.meteors !== false
                        ui: Theme; width: parent.width; icon: "󰄵"; label: Tr.t("Частота падающих звёзд"); from: 0.3; to: 3; stepSize: 0.1; decimals: 1
                        value: cosmosPage.sk.meteorRate || 1; suffix: "×"; onCommitted: (v) => Config.set("sky.meteorRate", v)
                    }
                }

                Text { text: Tr.t("Космос — вид из космоса: солнечная система, спутники, ближайшие звёзды"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7 }
                Group {
                    opacity: Theme.cosmos === "solar" ? 1 : 0.5
                    Labeled {
                        label: Tr.t("Скорость")
                        GSegment {
                            ui: Theme
                            options: [{ v: "0", t: Tr.t("Пауза") }, { v: "0.5", t: "×0,5" }, { v: "1", t: "×1" }, { v: "5", t: "×5" }, { v: "10", t: "×10" }, { v: "100", t: "×100" }]
                            value: String(cosmosPage.so.speed === undefined ? 1 : cosmosPage.so.speed)
                            onPicked: (v) => Config.set("space.speed", Number(v))
                        }
                    }
                    PillSlider { ui: Theme; width: parent.width; icon: "󰖔"; label: Tr.t("Звёзды фона"); from: 0.3; to: 2; stepSize: 0.1; decimals: 1; value: cosmosPage.so.bgStars || 1; suffix: "×"; onCommitted: (v) => Config.set("space.bgStars", v) }
                    PillSlider { ui: Theme; width: parent.width; icon: "󰼯"; label: Tr.t("Туманности"); from: 0; to: 2; stepSize: 0.1; decimals: 1; value: cosmosPage.so.bgNebula === undefined ? 1 : cosmosPage.so.bgNebula; suffix: "×"; onCommitted: (v) => Config.set("space.bgNebula", v) }
                    PillSlider { ui: Theme; width: parent.width; icon: "󰧞"; label: Tr.t("Размер планет"); from: 0.6; to: 2; stepSize: 0.1; decimals: 1; value: cosmosPage.so.planetScale || 1; suffix: "×"; onCommitted: (v) => Config.set("space.planetScale", v) }
                    PillSlider { ui: Theme; width: parent.width; icon: "󰩨"; label: Tr.t("Расстояния"); from: 0.7; to: 1.6; stepSize: 0.1; decimals: 1; value: cosmosPage.so.spread || 1; suffix: "×"; onCommitted: (v) => Config.set("space.spread", v) }
                    Chips {
                        keys: [["details", Tr.t("󰋩 Детали поверхностей")], ["moons", Tr.t("󰽥 Спутники")], ["orbits", Tr.t("󰑐 Орбиты")], ["labels", Tr.t("󰗊 Подписи")],
                               ["belt", Tr.t("󰪥 Пояс астероидов")], ["kuiper", Tr.t("󰪥 Пояс Койпера")], ["comet", Tr.t("☄ Комета Галлея")], ["follow", Tr.t("󰄀 Камера за планетой")],
                               ["satellites", Tr.t("󰒋 Спутники Земли: МКС, Хаббл")], ["systems", Tr.t("󰓎 Ближайшие звёзды")], ["galaxies", Tr.t("󰟀 Далёкие галактики")]]
                        isOn: function (k) { return Config.store.space[k] !== false; }
                        onToggle: (k) => Config.set("space." + k, Config.store.space[k] === false)
                    }
                    Text { width: parent.width; wrapMode: Text.WordWrap; text: Tr.t("Кнопки планет (терминал, файлы, оформление…) меняются в карточке планеты: клик по планете → «Сменить»."); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                    GButton { ui: Theme; icon: "󰑓"; label: Tr.t("Кнопки планет по умолчанию"); onClicked: Config.set("space.planets", Config.defaults.space.planets) }
                }
            }

            // ================= блокировка =================
            Column {
                id: lockPage
                visible: w.tab === 3
                width: body.width
                spacing: 12

                Text { text: Tr.t("Оформление"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7 }
                Grid {
                    id: lockGrid
                    width: parent.width
                    columns: 3
                    spacing: 10
                    readonly property real cw: (width - spacing * 2) / 3
                    Repeater {
                        model: [
                            { v: "theme", t: Tr.t("По теме"), d: Tr.t("свой у каждого комплекта"), g: [Theme.accent, Theme.accent2] },
                            { v: "ios", t: "iOS", d: Tr.t("крупное время, уведомления, ввод по нажатию"), g: ["#0a84ff", "#5e5ce6"] },
                            { v: "glass", t: Tr.t("Стекло"), d: Tr.t("часы и вход на одной стеклянной карточке"), g: ["#3a4a6b", "#b7bdf8"] },
                            { v: "aurora", t: Tr.t("Аврора"), d: Tr.t("живое сияние, время по центру"), g: ["#1fd1a5", "#7b5cff"] },
                            { v: "terminal", t: Tr.t("Терминал"), d: Tr.t("сведения о системе и вход строкой"), g: ["#0b0f0b", "#3ddc84"] },
                            { v: "minimal", t: Tr.t("Минимал"), d: Tr.t("только время и поле, ничего лишнего"), g: ["#111111", "#555555"] },
                            { v: "neon", t: Tr.t("Неон"), d: Tr.t("светящееся кольцо секунд, неоновое поле"), g: ["#ff2d95", "#00e5ff"] },
                            { v: "analog", t: Tr.t("Циферблат"), d: Tr.t("стрелочные часы с окошком даты"), g: ["#c9a96e", "#3b3024"] },
                            { v: "split", t: Tr.t("Половины"), d: Tr.t("обои и время слева, панель входа справа"), g: ["#2b5876", "#4e4376"] }
                        ]
                        GTile {
                            id: lt
                            required property var modelData
                            readonly property bool cur: (Config.lock.style || "theme") === modelData.v
                            ui: Theme
                            width: lockGrid.cw; height: 96; radius: 18
                            on: cur
                            Rectangle {
                                x: 10; y: 10
                                width: 30; height: 30; radius: Theme.r(9)
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: lt.modelData.g[0] }
                                    GradientStop { position: 1.0; color: lt.modelData.g[1] }
                                }
                                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.25)
                            }
                            Column {
                                x: 10; anchors { bottom: parent.bottom; bottomMargin: 9 }
                                width: parent.width - 20
                                Text { width: parent.width; text: lt.modelData.t; elide: Text.ElideRight; color: lt.cur ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                                Text { width: parent.width; text: lt.modelData.d; elide: Text.ElideRight; color: lt.cur ? Qt.rgba(1, 1, 1, 0.8) : Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                            }
                            onClicked: Config.set("lock.style", modelData.v)
                        }
                    }
                }
                Group {
                    GSwitch { ui: Theme; label: Tr.t("Уведомления на экране блокировки"); checked: Config.lock.notifs !== false; onToggled: (v) => Config.set("lock.notifs", v) }
                    GSwitch { ui: Theme; label: Tr.t("Плеер"); checked: Config.lock.player !== false; onToggled: (v) => Config.set("lock.player", v) }
                    GSwitch { ui: Theme; label: Tr.t("Секунды в часах"); checked: Config.lock.seconds === true; onToggled: (v) => Config.set("lock.seconds", v) }
                }
                GButton {
                    ui: Theme; icon: "󰌾"; label: Tr.t("Заблокировать и посмотреть"); on: true
                    onClicked: { w.close(); Quickshell.execDetached(["sh", "-c", "sleep 0.4; qs -c nameless ipc call lock lock"]); }
                }
            }
        }
    }

    // ---------- части ----------
    component Group: Item {
        default property alias content: gcol.data
        width: parent ? parent.width : 400
        implicitHeight: gcol.implicitHeight + 28
        Rectangle { anchors.fill: parent; radius: Theme.r(20); color: Theme.fill(0.06); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.14) }
        Column { id: gcol; x: 14; y: 14; width: parent.width - 28; spacing: 10 }
    }

    // подпись слева, элемент справа
    component Labeled: Item {
        property string label
        default property alias content: lslot.data
        width: parent ? parent.width : 400
        height: 38
        Text { anchors.verticalCenter: parent.verticalCenter; width: 130; text: parent.label; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
        Item { id: lslot; anchors { left: parent.left; leftMargin: 140; right: parent.right; top: parent.top; bottom: parent.bottom } }
    }

    // переключатели-ярлыки: keys = [[ключ, подпись]], isOn(ключ), toggle(ключ)
    component Chips: Flow {
        id: chips
        property var keys: []
        property var isOn: function (k) { return false; }
        signal toggle(string k)
        width: parent ? parent.width : 400
        spacing: 6
        Repeater {
            model: chips.keys
            Rectangle {
                required property var modelData
                readonly property bool on: chips.isOn(modelData[0])
                width: chipText.implicitWidth + 22; height: 30; radius: 15
                color: on ? Theme.accent : Theme.fill(0.10)
                border.width: on || Theme.ios ? 0 : 1
                border.color: Theme.line(0.2)
                Behavior on color { ColorAnimation { duration: 120 } }
                Text { id: chipText; anchors.centerIn: parent; text: modelData[1]; color: parent.on ? "white" : Theme.text; font.family: Theme.iconFont; font.pixelSize: 12 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: chips.toggle(parent.modelData[0]) }
            }
        }
    }

    component SmallBtn: Item {
        id: sb
        property string icon
        property bool danger: false
        signal clicked
        width: 30; height: 30
        opacity: enabled ? 1 : 0.3
        Rectangle { anchors.fill: parent; radius: 15; color: sbMa.containsMouse ? (sb.danger ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.2) : Theme.fill(0.16)) : "transparent" }
        Text { anchors.centerIn: parent; text: sb.icon; color: sb.danger ? Theme.red : Theme.text; font.family: Theme.iconFont; font.pixelSize: 15 }
        MouseArea { id: sbMa; anchors.fill: parent; hoverEnabled: true; enabled: sb.enabled; cursorShape: Qt.PointingHandCursor; onClicked: sb.clicked() }
    }

    component Field: Item {
        id: fd
        property string icon
        property string hint
        property string value
        signal committed(string v)
        width: parent ? parent.width : 300
        height: 38
        Rectangle { anchors.fill: parent; radius: Theme.r(12); color: Theme.fill(0.08); border.width: Theme.ios ? 0 : 1; border.color: input.activeFocus ? Theme.accent : Theme.line(0.18) }
        Text { id: fdIcon; x: 12; anchors.verticalCenter: parent.verticalCenter; text: fd.icon; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 14 }
        TextInput {
            id: input
            anchors { left: fdIcon.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: fd.value
            color: Theme.text
            selectionColor: Theme.accent
            clip: true
            font.family: Theme.font
            font.pixelSize: 13
            onAccepted: { fd.committed(text.trim()); focus = false; }
            onActiveFocusChanged: if (!activeFocus && text.trim() !== fd.value) fd.committed(text.trim())
            Text { visible: input.text === ""; text: fd.hint; color: Theme.sub; font: input.font; anchors.verticalCenter: parent.verticalCenter }
        }
    }
}
