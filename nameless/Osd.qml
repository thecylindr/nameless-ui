import QtQuick
import Quickshell
import Quickshell.Wayland

// OSD громкости и яркости: таблетка внизу по центру на 1.5 с после изменения
PanelWindow {
    id: w
    screen: Compositor.panelScreen
    property string kind: "volume"
    property bool shown: false
    property real progress: shown ? 1 : 0
    Behavior on progress { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    anchors { bottom: true }
    margins { bottom: 32 }
    // запас под тень
    implicitWidth: 280 + 56
    implicitHeight: 56 + 56
    visible: progress > 0.01
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {}

    function show(k) { kind = k; shown = true; hideT.restart(); }
    Timer { id: hideT; interval: 1500; onTriggered: w.shown = false }

    // первые значения при запуске не показываются
    property bool ready: false
    Timer { interval: 2000; running: true; onTriggered: w.ready = true }
    Connections {
        target: Sound
        function onVolumeChanged() { if (w.ready) w.show("volume"); }
        function onMutedChanged() { if (w.ready) w.show("volume"); }
    }
    Connections {
        target: Sys
        function onBrightnessChanged() { if (w.ready && Sys.brightness >= 0) w.show("brightness"); }
    }

    readonly property real value: kind === "volume" ? (Sound.muted ? 0 : Math.min(1, Sound.volume)) : Sys.brightness / 100

    Surface {
        anchors.fill: parent
        anchors.margins: 28
        radius: 28
        opacity: w.progress
        scale: 0.94 + 0.06 * w.progress
        Row {
            anchors.centerIn: parent
            spacing: 14
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: w.kind === "volume" ? Sound.icon : "󰃟"
                color: Theme.text
                font.family: Theme.iconFont
                font.pixelSize: 22
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 170; height: 8; radius: 4
                color: Theme.fill(0.16)
                Rectangle {
                    width: parent.width * w.value
                    height: parent.height; radius: 4
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 120 } }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                text: Math.round(w.value * 100)
                color: Theme.sub
                font.family: Theme.font
                font.pixelSize: 13
                font.features: { "tnum": 1 }
            }
        }
    }
}
