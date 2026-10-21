import QtQuick
import Quickshell
import Quickshell.Wayland

// Всплывающие уведомления справа сверху: исчезают через 6 с (важные — по закрытию), наведение ставит таймер на паузу
PanelWindow {
    id: w
    anchors { top: true; right: true }
    margins { top: 0; right: 0 }
    // запас 24 px вокруг карточек под тень
    implicitWidth: 380 + 48
    implicitHeight: Math.max(1, stack.implicitHeight + 48)
    visible: Notifs.popups.length > 0 && !Notifs.centerOpen
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.namespace: "nameless-popups"
    WlrLayershell.layer: WlrLayer.Overlay

    Column {
        id: stack
        x: 24; y: 16
        width: parent.width - 48
        spacing: 10
        Repeater {
            model: Notifs.popups
            NotifCard {
                id: pc
                required property var modelData
                note: modelData
                popup: true
                onClosed: Notifs.dismiss(modelData)
                // появление: сдвиг справа
                x: shown ? 0 : 40
                opacity: shown ? 1 : 0
                property bool shown: false
                Component.onCompleted: shown = true
                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Timer {
                    interval: 6000
                    running: !pc.critical && !pc.hovered
                    onTriggered: Notifs.hidePopup(pc.modelData)
                }
                TapHandler { onTapped: { Notifs.hidePopup(pc.modelData); Notifs.centerOpen = true; } }
            }
        }
    }
}
