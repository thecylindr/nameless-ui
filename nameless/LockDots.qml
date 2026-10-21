import QtQuick

// Точки пароля: появляются по одной; при ошибке ряд трясётся. dark — точки тёмные (светлые виды)
Item {
    id: d
    property var lk
    property real dot: 10
    property color tone: "white"
    property bool hollowWhenEmpty: false     // iOS: пустые кружки до ввода
    property int slots: 6
    implicitWidth: row.implicitWidth
    implicitHeight: dot
    readonly property int n: lk ? lk.pass.length : 0

    Row {
        id: row
        anchors.centerIn: parent
        spacing: d.dot * 0.9
        Repeater {
            model: d.hollowWhenEmpty ? Math.max(d.slots, Math.min(d.n, 24)) : Math.min(d.n, 24)
            Rectangle {
                required property int index
                width: d.dot; height: d.dot; radius: d.dot / 2
                color: index < d.n ? d.tone : "transparent"
                border.width: d.hollowWhenEmpty && index >= d.n ? 1.5 : 0
                border.color: d.tone
                scale: 0
                Component.onCompleted: scale = 1
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                Behavior on color { ColorAnimation { duration: 100 } }
            }
        }
    }
    SequentialAnimation {
        id: shake
        NumberAnimation { target: row; property: "anchors.horizontalCenterOffset"; to: -16; duration: 50 }
        NumberAnimation { target: row; property: "anchors.horizontalCenterOffset"; to: 13; duration: 70 }
        NumberAnimation { target: row; property: "anchors.horizontalCenterOffset"; to: -7; duration: 60 }
        NumberAnimation { target: row; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
    }
    Connections { target: d.lk; function onFailsChanged() { if (d.lk.fails > 0) shake.restart(); } }
}
