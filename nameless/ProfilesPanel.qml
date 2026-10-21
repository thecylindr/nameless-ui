import QtQuick
import Quickshell
import Quickshell.Wayland

// Профили (плитка «Профили» на шторке): карточки «Обычный», «Работа», «Игры», «Ночь» и свои.
//   «Применить» ставит набор настроек; «Настроить» раскрывает значения: что менять и на что.
//   «Не менять» — настройка остаётся как есть. Список и активный профиль запоминаются
PanelWindow {
    id: w
    property var shell: null
    readonly property bool open: shell ? shell.profilesOpen : false
    function close() { if (shell) shell.profilesOpen = false; }
    property real progress: 0
    Component.onCompleted: progress = Qt.binding(function () { return w.open ? 1 : 0; })
    Behavior on progress { NumberAnimation { duration: Theme.dur(w.open); easing.type: Easing.OutCubic } }

    visible: progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-profiles"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property string expanded: ""
    readonly property var opts3: [{ v: "keep", t: Tr.t("Не менять") }, { v: "on", t: Tr.t("Вкл") }, { v: "off", t: Tr.t("Выкл") }]
    readonly property var rows: [["dnd", Tr.t("Не беспокоить")], ["caffeine", Tr.t("Кофеин: экран не гаснет")], ["night", Tr.t("Ночной свет")], ["animations", Tr.t("Анимации окон")], ["blur", Tr.t("Размытие")], ["rgb", Tr.t("Подсветка клавиатуры")]]

    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * w.progress }
    MouseArea { anchors.fill: parent; onClicked: w.close() }

    Surface {
        id: box
        alpha: Theme.overlayAlpha
        width: Math.min(parent.width - 40, 620)
        height: Math.min(parent.height - 60, 720)
        anchors.horizontalCenter: parent.horizontalCenter
        y: (parent.height - height) / 2 - 30 * (1 - w.progress)
        opacity: Math.min(1, w.progress * 2)
        radius: Theme.ios ? 30 : 22
        MouseArea { anchors.fill: parent }
        MoveArea { win: box; anchors { left: parent.left; right: parent.right; top: parent.top } height: 56 }
        focus: w.open
        Keys.onEscapePressed: w.close()

        Item {
            id: head
            x: 18; y: 14
            width: parent.width - 36; height: 40
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text { anchors.verticalCenter: parent.verticalCenter; text: "󰣆"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 22 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: Tr.t("Профили"); color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
                    Text { text: Tr.t("сейчас: ") + (Profiles.current ? Profiles.current.name : "—"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 8
                GButton { ui: Theme; height: 34; icon: "󰐕"; label: Tr.t("Новый"); onClicked: w.expanded = Profiles.add() }
                GTile { ui: Theme; width: 36; height: 36; radius: 18; Text { anchors.centerIn: parent; text: "✕"; color: Theme.text; font.pixelSize: 13 } onClicked: w.close() }
            }
        }

        ListView {
            anchors { top: head.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 18; rightMargin: 18; bottomMargin: 18 }
            clip: true
            spacing: 10
            boundsBehavior: Flickable.StopAtBounds
            model: Profiles.list
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property bool isActive: Profiles.active === modelData.id
                readonly property bool isOpen: w.expanded === modelData.id
                width: ListView.view.width
                height: head2.height + (isOpen ? body.implicitHeight + 16 : 0) + 20
                Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                clip: true
                radius: Theme.r(18)
                color: isActive ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : Theme.fill(0.06)
                border.width: isActive ? 1.5 : 1; border.color: isActive ? Theme.accent : Theme.line(0.14)

                Item {
                    id: head2
                    x: 14; y: 10
                    width: parent.width - 28; height: 44
                    Rectangle { id: ic; width: 40; height: 40; radius: 12; anchors.verticalCenter: parent.verticalCenter; color: card.isActive ? Theme.accent : Theme.fill(0.12)
                        Text { anchors.centerIn: parent; text: card.modelData.icon; color: card.isActive ? "white" : Theme.text; font.family: Theme.iconFont; font.pixelSize: 19 } }
                    Column {
                        anchors { left: ic.right; leftMargin: 12; right: btns.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        Text { width: parent.width; elide: Text.ElideRight; text: card.modelData.name + (card.isActive ? Tr.t("  · активен") : ""); color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { width: parent.width; elide: Text.ElideRight; text: Profiles.summary(card.modelData) || Tr.t("ничего не меняет"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                    }
                    Row {
                        id: btns
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        GButton { ui: Theme; height: 32; icon: "󰐊"; label: Tr.t("Применить"); on: !card.isActive; onClicked: Profiles.apply(card.modelData.id) }
                        GButton { ui: Theme; height: 32; icon: card.isOpen ? "󰅃" : "󰒓"; label: ""; onClicked: w.expanded = card.isOpen ? "" : card.modelData.id }
                    }
                }

                // настройки профиля
                Column {
                    id: body
                    x: 14; y: head2.y + head2.height + 12
                    width: parent.width - 28
                    spacing: 8
                    visible: card.isOpen
                    Rectangle {
                        width: parent.width; height: 36; radius: 18
                        color: Theme.fill(0.08); border.width: 1; border.color: Theme.line(0.2)
                        TextInput {
                            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                            verticalAlignment: TextInput.AlignVCenter; clip: true
                            text: card.modelData.name
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                            onEditingFinished: if (text.trim() !== "") Profiles.update(card.modelData.id, "name", text.trim())
                        }
                    }
                    Repeater {
                        model: w.rows
                        Item {
                            required property var modelData
                            width: body.width; height: 34
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                            GSegment {
                                ui: Theme
                                width: 250; implicitHeight: 32
                                anchors.right: parent.right
                                options: w.opts3
                                value: card.modelData[modelData[0]] || "keep"
                                onPicked: (v) => Profiles.update(card.modelData.id, modelData[0], v)
                            }
                        }
                    }
                    PillSlider {
                        visible: card.modelData.night === "on"
                        ui: Theme; width: parent.width; icon: "󰖔"; label: Tr.t("Температура ночного света")
                        from: 2500; to: 6000; stepSize: 100; decimals: 0; value: card.modelData.nightTemp || 4000; suffix: " K"
                        onCommitted: (v) => Profiles.update(card.modelData.id, "nightTemp", v)
                    }
                    PillSlider {
                        ui: Theme; width: parent.width; icon: "󰃟"; label: Tr.t("Яркость, 0 — не менять")
                        from: 0; to: 100; stepSize: 5; decimals: 0; value: card.modelData.brightness || 0; suffix: " %"
                        onCommitted: (v) => Profiles.update(card.modelData.id, "brightness", v)
                    }
                    GButton { visible: Profiles.list.length > 1; ui: Theme; height: 32; icon: "󰆴"; label: Tr.t("Удалить профиль"); danger: true; onClicked: { w.expanded = ""; Profiles.remove(card.modelData.id); } }
                }
            }
        }
    }
}
