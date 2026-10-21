import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// Центр уведомлений: выезжает справа; «Не беспокоить», «Очистить всё», плеер, история
PanelWindow {
    id: w
    property real progress: 0
    Component.onCompleted: progress = Qt.binding(function () { return Notifs.centerOpen ? 1 : 0; })
    Behavior on progress { NumberAnimation { duration: Theme.dur(Notifs.centerOpen); easing.type: Easing.OutCubic } }

    visible: progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    // во весь экран, как шторка оформления: затемнение накрывает и бар
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Notifs.centerOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * 0.6 * w.progress }
    MouseArea { anchors.fill: parent; onClicked: Notifs.centerOpen = false }

    Surface {
        id: panel
        alpha: Theme.overlayAlpha
        width: 400
        height: parent.height - 60
        x: parent.width - width - 10 + (1 - w.progress) * 40
        y: 50
        opacity: w.progress
        radius: Theme.ios ? 28 : 20
        MouseArea { anchors.fill: parent }
        focus: Notifs.centerOpen
        Keys.onEscapePressed: Notifs.centerOpen = false

        Column {
            id: head
            x: 16; y: 16
            width: parent.width - 32
            spacing: 12

            Row {
                width: parent.width
                Column {
                    width: parent.width - clearBtn.width
                    Text {
                        text: Tr.t("Уведомления")
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.ios ? 24 : 20
                        font.weight: Font.Bold
                        font.letterSpacing: Theme.ios ? -0.5 : 0
                    }
                    Text {
                        text: Notifs.count === 0 ? Tr.t("Нет новых") : Notifs.count + " " + (Notifs.count % 10 === 1 && Notifs.count % 100 !== 11 ? Tr.t("уведомление")
                              : (Notifs.count % 10 >= 2 && Notifs.count % 10 <= 4 && (Notifs.count % 100 < 10 || Notifs.count % 100 >= 20) ? Tr.t("уведомления") : Tr.t("уведомлений")))
                        color: Theme.sub
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                }
                GButton {
                    id: clearBtn
                    ui: Theme
                    visible: Notifs.count > 0
                    icon: "󰎟"
                    label: Tr.t("Очистить")
                    onClicked: Notifs.clear()
                }
            }
            GSwitch {
                ui: Theme
                width: parent.width
                label: Tr.t("Не беспокоить")
                sub: Notifs.dnd ? Tr.t("Показываются только важные") : Tr.t("Все уведомления всплывают")
                checked: Notifs.dnd
                onToggled: (v) => Notifs.dnd = v
            }
            // плеер
            Item {
                visible: Sys.player !== null
                width: parent.width
                height: 72
                Surface { anchors.fill: parent; radius: Theme.ios ? 20 : 14; shadow: false; alpha: Math.max(0.0, Theme.panelAlpha - 0.25) }
                Row {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    ClippingRectangle {
                        width: 48; height: 48; radius: Theme.r(10)
                        color: Theme.fill(0.12)
                        Image { anchors.fill: parent; source: Sys.player ? (Sys.player.trackArtUrl || "") : ""; fillMode: Image.PreserveAspectCrop }
                        Text { anchors.centerIn: parent; visible: !Sys.player || !Sys.player.trackArtUrl; text: "󰝚"; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 20 }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 180
                        Text { width: parent.width; text: Sys.player ? (Sys.player.trackTitle || "—") : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Text { width: parent.width; text: Sys.player ? (Sys.player.trackArtist || "") : ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; elide: Text.ElideRight }
                    }
                }
                Row {
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Repeater {
                        model: [{ i: "󰒮", f: "previous" }, { i: Sys.player && Sys.player.isPlaying ? "󰏤" : "󰐊", f: "togglePlaying" }, { i: "󰒭", f: "next" }]
                        GTile {
                            required property var modelData
                            ui: Theme
                            width: 32; height: 32; radius: 16
                            fillAlpha: 0.0
                            Text { anchors.centerIn: parent; text: modelData.i; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 17 }
                            onClicked: if (Sys.player) Sys.player[modelData.f]()
                        }
                    }
                }
            }
        }

        // история
        ListView {
            anchors { top: head.bottom; topMargin: 14; left: parent.left; leftMargin: 16; right: parent.right; rightMargin: 16; bottom: parent.bottom; bottomMargin: 16 }
            clip: true
            spacing: 8
            model: Notifs.list
            boundsBehavior: Flickable.StopAtBounds
            delegate: NotifCard {
                required property var modelData
                width: ListView.view.width
                note: modelData
                onClosed: Notifs.dismiss(modelData)
            }
            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 } }
            removeDisplaced: Transition { NumberAnimation { property: "y"; duration: 200; easing.type: Easing.OutCubic } }

            Column {
                anchors.centerIn: parent
                visible: Notifs.count === 0
                spacing: 8
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰂚"; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 40 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: Tr.t("Всё прочитано"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 13 }
            }
        }
    }
}
