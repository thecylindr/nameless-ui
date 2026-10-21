import QtQuick
import QtQuick.Effects

// Тонкий ползунок с подписью для подробной настройки; значение уходит при отпускании
Item {
    id: s
    property QtObject ui
    property string label
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property int decimals: 0
    property real value: 0
    property string suffix: ""
    property bool active: true
    signal committed(real v)

    property real shown: value
    onValueChanged: if (!drag.pressed) shown = value

    width: parent ? parent.width : 300
    implicitHeight: 44
    opacity: active ? 1 : 0.4

    function snap(px) {
        var r = Math.max(0, Math.min(1, (px - knob.width / 2) / (track.width - knob.width)));
        var v = Math.round((from + r * (to - from)) / stepSize) * stepSize;
        return Number(Math.max(from, Math.min(to, v)).toFixed(decimals));
    }

    Text {
        anchors { left: parent.left; top: parent.top }
        text: s.label
        color: s.ui.text
        font.family: s.ui.font
        font.pixelSize: 13
    }
    Text {
        anchors { right: parent.right; top: parent.top }
        text: s.shown.toFixed(s.decimals) + s.suffix
        color: s.ui.sub
        font.family: s.ui.font
        font.pixelSize: 13
        font.features: { "tnum": 1 }
    }
    Rectangle {
        id: track
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 7 }
        height: 6
        radius: 3
        color: s.ui.fill(0.14)
        Rectangle {
            width: knob.x + knob.width / 2
            height: parent.height
            radius: 3
            color: s.ui.accent
        }
        RectangularShadow {
            anchors.fill: knob
            radius: knob.radius
            blur: 8
            offset: Qt.vector2d(0, 2)
            color: Qt.rgba(0, 0, 0, 0.3)
        }
        Rectangle {
            id: knob
            width: 22; height: 22; radius: 11
            anchors.verticalCenter: parent.verticalCenter
            x: (s.shown - s.from) / (s.to - s.from) * (track.width - width)
            color: "white"
            scale: drag.pressed ? 1.15 : 1
            Behavior on scale { NumberAnimation { duration: 140 } }
        }
        MouseArea {
            id: drag
            anchors.fill: parent
            anchors.margins: -12
            enabled: s.active
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onPressed: (m) => s.shown = s.snap(m.x - 12)
            onPositionChanged: (m) => { if (pressed) s.shown = s.snap(m.x - 12); }
            onReleased: s.committed(s.shown)
        }
    }
}
