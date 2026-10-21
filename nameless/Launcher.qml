import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// Лаунчер приложений: поиск по названию, описанию и ключевым словам; вид — из темы (список / сетка / Spotlight).
// Стрелки — выбор, Enter — запуск, Esc — закрыть; правый клик — закрепить в доке / убрать.
// Выражение («2+2*3», «15%*840», «2^10») — калькулятор: Enter копирует ответ.
// pick — режим выбора из дока («+»): клик закрепляет приложение, а не запускает
PanelWindow {
    id: w
    property bool open: false
    property bool pick: false
    property real progress: open ? 1 : 0
    Behavior on progress { NumberAnimation { duration: Theme.dur(w.open); easing.type: Easing.OutCubic } }

    readonly property string style: Theme.th.launcher_style || "list"
    readonly property bool grid: style === "grid"
    readonly property bool spot: style === "spot"
    readonly property int cols: grid ? 6 : 1

    visible: progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: { if (open) { query.text = ""; current = 0; query.forceActiveFocus(); } else pick = false; }

    // ---------- калькулятор: только цифры и операторы, поэтому вычисление безопасно ----------
    readonly property string calc: {
        var q = query.text.trim().replace(/,/g, ".").replace(/×/g, "*").replace(/÷/g, "/").replace(/\s+/g, "");
        if (q === "" || !/^[-+*\/%^().0-9]+$/.test(q) || !/[-+*\/%^]/.test(q) || !/[0-9]/.test(q)) return "";
        // «15%» — процент: 15% * 840 = 126
        q = q.replace(/([0-9.]+)%/g, "($1/100)").replace(/\^/g, "**");
        try {
            var v = Function("return (" + q + ")")();
            if (typeof v !== "number" || !isFinite(v)) return "";
            return String(Math.round(v * 1e10) / 1e10);
        } catch (e) { return ""; }
    }
    function copyCalc() { Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", calc]); open = false; }

    // ---------- поиск ----------
    property int current: 0
    readonly property var results: {
        var q = query.text.trim().toLowerCase(), all = DesktopEntries.applications.values, out = [];
        for (var i = 0; i < all.length; i++) {
            var e = all[i];
            if (e.noDisplay) continue;
            var name = (e.name || "").toLowerCase();
            var score = 0;
            if (q === "") score = 1;
            else if (name.indexOf(q) === 0) score = 100;
            else if (name.indexOf(q) > 0) score = 60;
            else if ((e.genericName || "").toLowerCase().indexOf(q) >= 0) score = 40;
            else if ((e.keywords || []).join(" ").toLowerCase().indexOf(q) >= 0) score = 30;
            else if ((e.comment || "").toLowerCase().indexOf(q) >= 0) score = 10;
            if (score > 0) out.push({ e: e, s: score, n: name });
        }
        out.sort(function (a, b) { return b.s - a.s || (a.n < b.n ? -1 : a.n > b.n ? 1 : 0); });
        return out.slice(0, grid ? 36 : 40).map(function (x) { return x.e; });
    }
    // значок приложения или запасной (iconPath(…, true) возвращает пусто, если значка нет в теме)
    function iconFor(name) { return Quickshell.iconPath(name || "", true) || Quickshell.iconPath("application-x-executable"); }
    function launch(e) {
        if (!e) return;
        if (pick) { Config.pin(e.id); open = false; return; }
        AppRun.run(e); open = false;
    }
    function move(d) { if (results.length > 0) current = Math.max(0, Math.min(results.length - 1, current + d)); }

    // затемнение и закрытие по клику мимо
    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * w.progress }
    MouseArea { anchors.fill: parent; onClicked: w.open = false }

    Surface {
        id: box
        alpha: Theme.overlayAlpha
        width: w.grid ? 860 : (w.spot ? 660 : 640)
        height: w.spot ? Math.min(64 + calcRow.height + (calcRow.visible ? 10 : 0) + list.contentHeight + (w.results.length > 0 ? 16 : 0), 470)
                       : (w.grid ? 560 : 520)
        x: (parent.width - width) / 2
        y: (w.spot ? parent.height * 0.22 : (parent.height - height) / 2) + (1 - w.progress) * 16
        opacity: w.progress
        radius: Theme.ios ? 26 : 20
        MouseArea { anchors.fill: parent }

        // строка поиска
        Item {
            id: searchRow
            x: 14; y: 14
            width: parent.width - 28
            height: w.spot ? 44 : 46
            Rectangle {
                anchors.fill: parent
                radius: Theme.r(w.spot ? 14 : 14)
                color: Theme.fill(0.08)
                border.width: Theme.ios ? 0 : 1
                border.color: Theme.line(0.18)
            }
            Text {
                id: lens
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "󰍉"
                color: Theme.accent
                font.family: Theme.iconFont
                font.pixelSize: 18
            }
            TextInput {
                id: query
                anchors { left: lens.right; leftMargin: 12; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                color: Theme.text
                selectionColor: Theme.accent
                font.family: Theme.font
                font.pixelSize: w.spot ? 18 : 16
                clip: true
                onTextChanged: w.current = 0
                Keys.onEscapePressed: w.open = false
                Keys.onReturnPressed: { if (w.calc !== "") w.copyCalc(); else w.launch(w.results[w.current]); }
                Keys.onEnterPressed: { if (w.calc !== "") w.copyCalc(); else w.launch(w.results[w.current]); }
                Keys.onDownPressed: w.move(w.cols)
                Keys.onUpPressed: w.move(-w.cols)
                Keys.onRightPressed: (e) => { if (w.grid) w.move(1); else e.accepted = false; }
                Keys.onLeftPressed: (e) => { if (w.grid) w.move(-1); else e.accepted = false; }
                Keys.onTabPressed: w.move(1)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: query.text === ""
                    text: w.pick ? Tr.t("Выберите приложение для дока") : (w.spot ? Tr.t("Поиск Spotlight") : Tr.t("Поиск приложений"))
                    color: Theme.sub
                    font: query.font
                }
            }
        }

        // плитки, как в «Пуске»: пока строка поиска пуста. Нажатие — действие, правый клик — включить / выключить
        Item {
            id: tilesRow
            visible: query.text === "" && !w.pick && !w.spot
            anchors { top: searchRow.bottom; topMargin: visible ? 10 : 0; left: parent.left; leftMargin: 14; right: parent.right; rightMargin: 14 }
            height: visible ? 74 : 0
            Row {
                anchors.fill: parent
                spacing: 10
                StartTile {
                    icon: "󰟀"; title: "Orbit"; on: OrbitData.enabled
                    sub: !OrbitData.enabled ? Tr.t("выключен — нажмите, чтобы включить") : (!OrbitData.running ? Tr.t("запускается…") : (OrbitData.requests > 0 ? Tr.t("ждёт сопряжение") : (OrbitData.connected.length > 0 ? Tr.t("Подключено: ") + OrbitData.connected.length : Tr.t("ищет устройства"))))
                    onActivated: { if (!OrbitData.enabled) OrbitData.setEnabled(true); else { w.open = false; OrbitData.panelOpen = true; } }
                    onToggled: OrbitData.toggleEnabled()
                }
                StartTile {
                    icon: Sys.wifiIcon; title: "Wi-Fi"; on: Sys.wifiOn
                    sub: !Sys.wifiOn ? Tr.t("выкл.") : (Sys.ssid || Tr.t("не подключено"))
                    onActivated: Sys.toggleWifi()
                    onToggled: Sys.toggleWifi()
                }
                StartTile {
                    icon: Notifs.dnd ? "󰂛" : "󰂚"; title: Tr.t("Не беспокоить"); on: Notifs.dnd
                    sub: Notifs.dnd ? Tr.t("включено") : Tr.t("выключено")
                    onActivated: Notifs.dnd = !Notifs.dnd
                    onToggled: Notifs.dnd = !Notifs.dnd
                }
            }
        }

        // ответ калькулятора
        Item {
            id: calcRow
            visible: w.calc !== ""
            anchors { top: tilesRow.bottom; topMargin: visible ? 10 : 0; left: parent.left; leftMargin: 14; right: parent.right; rightMargin: 14 }
            height: visible ? 52 : 0
            Rectangle { anchors.fill: parent; radius: Theme.r(14); color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) }
            Text { id: calcIcon; x: 16; anchors.verticalCenter: parent.verticalCenter; text: "󰃬"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 20 }
            Text {
                anchors { left: calcIcon.right; leftMargin: 14; right: calcHint.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                text: "= " + w.calc
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 20
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
            }
            Text { id: calcHint; anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: Tr.t("Enter — копировать"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.copyCalc() }
        }

        // результаты
        GridView {
            id: list
            anchors { top: calcRow.bottom; topMargin: 12; left: parent.left; leftMargin: 14; right: parent.right; rightMargin: 14; bottom: parent.bottom; bottomMargin: w.spot ? 14 : 34 }
            clip: true
            model: w.results
            currentIndex: w.current
            cellWidth: w.grid ? width / w.cols : width
            cellHeight: w.grid ? 120 : (w.spot ? 44 : 52)
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 120
            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                width: list.cellWidth
                height: list.cellHeight
                readonly property bool sel: index === w.current
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: w.grid ? 4 : 2
                    radius: Theme.r(w.grid ? 18 : 10)
                    color: cell.sel ? (Theme.glass ? Theme.fill(0.16) : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.9))
                                    : (cellMa.containsMouse ? Theme.fill(0.08) : "transparent")
                    border.width: cell.sel && Theme.kit === "liquid" ? 1 : 0
                    border.color: Qt.rgba(1, 1, 1, 0.22)
                    // классика: полоса акцента слева у выбранной строки (как в исходном rofi)
                    Rectangle {
                        visible: cell.sel && !Theme.glass && !w.grid
                        width: 3; height: parent.height - 14
                        anchors { left: parent.left; leftMargin: 3; verticalCenter: parent.verticalCenter }
                        radius: 1.5
                        color: Theme.accent
                    }
                }
                // строка
                Row {
                    visible: !w.grid
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                    spacing: 14
                    IconImage {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: w.spot ? 24 : 32
                        source: w.iconFor(cell.modelData.icon)
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: cell.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: w.spot ? 14 : 15 }
                        Text {
                            visible: !w.spot && (cell.modelData.genericName || cell.modelData.comment)
                            text: cell.modelData.genericName || cell.modelData.comment || ""
                            color: Theme.sub
                            font.family: Theme.font
                            font.pixelSize: 11
                            width: list.width - 90
                            elide: Text.ElideRight
                        }
                    }
                }
                // сетка
                Column {
                    visible: w.grid
                    anchors.centerIn: parent
                    spacing: 8
                    IconImage {
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitSize: 56
                        source: w.iconFor(cell.modelData.icon)
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: list.cellWidth - 16
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: cell.modelData.name
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                }
                // закреплено в доке
                Text {
                    visible: Config.isPinned(cell.modelData.id)
                    anchors { right: parent.right; rightMargin: w.grid ? 12 : 16; top: w.grid ? parent.top : undefined; topMargin: 10; verticalCenter: w.grid ? undefined : parent.verticalCenter }
                    text: "󰐃"
                    color: Theme.accent
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                }
                MouseArea {
                    id: cellMa
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onEntered: w.current = cell.index
                    onClicked: (m) => { if (m.button === Qt.RightButton) Config.togglePin(cell.modelData.id); else w.launch(cell.modelData); }
                }
            }
        }
        // подвал: знак и число приложений
        Row {
            visible: !w.spot
            anchors { right: parent.right; rightMargin: 18; bottom: parent.bottom; bottomMargin: 10 }
            spacing: 8
            opacity: 0.7
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: w.results.length + (w.pick ? Tr.t(" · клик — в док · Esc — закрыть") : Tr.t(" · Enter — запуск · ПКМ — в док · Esc — закрыть"))
                color: Theme.sub
                font.family: Theme.font
                font.pixelSize: 11
            }
            Logo { size: 14; anchors.verticalCenter: parent.verticalCenter }
        }
        Text {
            anchors.centerIn: list
            visible: w.results.length === 0
            text: Tr.t("Ничего не найдено")
            color: Theme.sub
            font.family: Theme.font
            font.pixelSize: 14
        }
    }

    component StartTile: Rectangle {
        id: st
        property string icon: ""
        property string title: ""
        property string sub: ""
        property bool on: false
        signal activated
        signal toggled
        width: (parent.width - 20) / 3; height: parent.height
        radius: Theme.r(16)
        color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, ma.containsMouse ? 0.42 : 0.30) : Theme.fill(ma.containsMouse ? 0.14 : 0.08)
        border.width: Theme.ios ? 0 : 1
        border.color: on ? Theme.accent : Theme.line(0.18)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text { id: sti; x: 14; y: 12; text: st.icon; color: st.on ? Theme.accent : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 24 }
        Text { x: 14; y: 42; width: parent.width - 28; elide: Text.ElideRight; text: st.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
        Text { x: 14; y: 58; width: parent.width - 28; elide: Text.ElideRight; text: st.sub; color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
        MouseArea {
            id: ma
            anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton; cursorShape: Qt.PointingHandCursor
            onClicked: m => { if (m.button === Qt.RightButton) st.toggled(); else st.activated(); }
        }
    }
}
