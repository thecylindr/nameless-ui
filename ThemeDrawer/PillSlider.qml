import QtQuick

// Широкий ползунок как в Пункте управления iOS: заливка акцентом, значок и подпись внутри; значение уходит при отпускании
Item {
    id: s
    property QtObject ui
    property string icon
    property string label
    property real from: 0
    property real to: 1
    property real stepSize: 0.01
    property int decimals: 2
    property real value: 0
    property string suffix: ""
    property real display: 1          // множитель для показа (0.22 -> 22 %)
    property bool active: true
    signal committed(real v)

    property real shown: value
    onValueChanged: if (!ma.pressed) shown = value
    readonly property real ratio: Math.max(0, Math.min(1, (shown - from) / (to - from)))
    readonly property real fillW: Math.max(height, width * ratio)

    implicitHeight: 54
    opacity: active ? 1 : 0.4
    scale: ma.pressed ? 1.015 : 1
    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    function snap(px) {
        var r = Math.max(0, Math.min(1, px / width));
        var v = Math.round((from + r * (to - from)) / stepSize) * stepSize;
        return Number(Math.max(from, Math.min(to, v)).toFixed(decimals));
    }

    Rectangle {
        anchors.fill: parent
        radius: s.ui.r(height / 2)
        color: s.ui.fill(0.10)
        border.width: s.ui.ios ? 0 : 1
        border.color: s.ui.line(0.22)
    }
    Rectangle {
        width: s.fillW
        height: parent.height
        radius: s.ui.r(height / 2)
        color: s.ui.accent
        Behavior on width { enabled: !ma.pressed; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }
    Rim { anchors.fill: parent; ui: s.ui; radius: s.ui.r(height / 2); pressedAmount: ma.pressed ? 0.6 : 0 }

    Text {
        id: ic
        x: 18
        anchors.verticalCenter: parent.verticalCenter
        text: s.icon
        color: s.fillW > x + width ? "white" : s.ui.text
        font.family: s.ui.iconFont
        font.pixelSize: 20
    }
    Text {
        x: ic.x + ic.width + 10
        anchors.verticalCenter: parent.verticalCenter
        text: s.label
        color: s.fillW > x + width * 0.6 ? "white" : s.ui.text
        font.family: s.ui.font
        font.pixelSize: 14
        font.weight: Font.DemiBold
    }
    Text {
        anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
        text: (s.shown * s.display).toFixed(s.display === 1 ? s.decimals : 0) + s.suffix
        color: s.ratio > 0.92 ? "white" : s.ui.sub
        font.family: s.ui.font
        font.pixelSize: 13
        font.features: { "tnum": 1 }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: s.active
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: (m) => s.shown = s.snap(m.x)
        onPositionChanged: (m) => { if (pressed) s.shown = s.snap(m.x); }
        onReleased: s.committed(s.shown)
    }
}
