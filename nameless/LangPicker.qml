import QtQuick
import Quickshell
import Quickshell.Wayland

// Первый запуск NameLess UI: выбор языка интерфейса (дальше меняется в «Пункт управления» → значок вида → «Язык»)
PanelWindow {
    id: w
    screen: Compositor.panelScreen
    property real progress: 0
    Component.onCompleted: progress = 1
    Behavior on progress { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-lang"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * w.progress }

    Surface {
        id: box
        alpha: Theme.overlayAlpha
        width: Math.min(parent.width - 40, 380)
        height: col.implicitHeight + 44
        anchors.centerIn: parent
        opacity: w.progress
        scale: 0.94 + 0.06 * w.progress
        radius: Theme.ios ? 30 : 22
        MouseArea { anchors.fill: parent }
        Column {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
            spacing: 14
            Logo { size: 40; wordmark: false; anchors.horizontalCenter: parent.horizontalCenter }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: "Выберите язык · Choose language"
                color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold
            }
            GButton { ui: Theme; width: parent.width; height: 44; label: "Русский"; on: true; onClicked: Config.set("lang", "ru") }
            GButton { ui: Theme; width: parent.width; height: 44; label: "English"; on: true; onClicked: Config.set("lang", "en") }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: "Можно изменить позже · You can change this later"
                color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
            }
        }
    }
}
