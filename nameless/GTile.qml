import QtQuick

// Стеклянная плитка: полупрозрачная заливка, объём края, проседание при нажатии; on — заливка акцентом
Item {
    id: t
    property QtObject ui
    property real radius: 18
    property bool on: false
    property bool active: true
    property color onColor: ui.accent
    property real fillAlpha: 0.10
    readonly property bool pressed: ma.pressed
    readonly property bool hovered: ma.containsMouse
    default property alias content: inner.data
    signal clicked

    opacity: active ? 1 : 0.38
    scale: pressed ? 0.95 : 1
    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: t.ui.r(t.radius)
        color: t.on ? t.onColor : t.ui.fill(t.hovered ? t.fillAlpha + 0.06 : t.fillAlpha)
        border.width: t.ui.ios ? 0 : 1
        border.color: t.on ? Qt.darker(t.onColor, 1.3) : t.ui.line(t.hovered ? 0.42 : 0.26)
        Behavior on color { ColorAnimation { duration: 200 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }

        // стекло клиента (GlassCard): мягкий верхний свет
        Rectangle {
            visible: t.ui.kit === "liquid" && !t.on
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.00; color: Qt.rgba(1, 1, 1, 0.13) }
                GradientStop { position: 0.18; color: Qt.rgba(1, 1, 1, 0.045) }
                GradientStop { position: 0.52; color: Qt.rgba(1, 1, 1, 0.0) }
                GradientStop { position: 1.00; color: Qt.rgba(0, 0, 0, 0.08) }
            }
        }
        // сплошной материал: лёгкий глянец на верхней половине
        Rectangle {
            visible: !t.ui.glass && !t.pressed
            width: parent.width
            height: parent.height / 2
            radius: parent.radius
            color: "white"
            opacity: 0.06
        }
    }
    Rim {
        anchors.fill: parent
        ui: t.ui
        radius: t.ui.r(t.radius)
        pressedAmount: t.pressed ? 1 : 0
        strength: t.on ? 0.8 : 1.0
    }
    Item { id: inner; anchors.fill: parent }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        enabled: t.active
        cursorShape: Qt.PointingHandCursor
        onClicked: t.clicked()
    }
}
