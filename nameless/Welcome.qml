import QtQuick
import Quickshell
import Quickshell.Wayland

// Приветствие при запуске: плашка «NameLess UI» с названием темы на 2.5 с
PanelWindow {
    id: w
    property bool shown: false
    property real progress: shown ? 1 : 0
    Behavior on progress { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

    anchors { top: true }
    margins { top: 42 }
    // запас вокруг плашки: тень помещается целиком, без обрезанных граней
    implicitWidth: Math.max(260, Math.min(560, toast.implicitWidth + 64)) + 56
    implicitHeight: 64 + 56
    visible: progress > 0.01
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-welcome"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {}

    // показать после загрузки темы, скрыть через 2.5 с
    Timer { interval: 600; running: true; onTriggered: { w.shown = true; hideT.start(); } }
    Timer { id: hideT; interval: 2500; onTriggered: w.shown = false }

    Surface {
        anchors.fill: parent
        anchors.margins: 28
        radius: 32
        opacity: w.progress
        scale: 0.9 + 0.1 * w.progress
        Row {
            id: toast
            anchors.centerIn: parent
            spacing: 12
            Logo { size: 34; wordmark: false; anchors.verticalCenter: parent.verticalCenter }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text { text: "NameLess UI"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Bold }
                Text { width: Math.min(implicitWidth, 460); elide: Text.ElideRight; text: (Theme.th.name || "") + " · " + Compositor.name; color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
            }
        }
    }
}
