import QtQuick
import QtQuick.Effects

// Переключатель iOS: подпись слева, тумблер справа
Item {
    id: w
    property QtObject ui
    property string label
    property string sub: ""
    property bool checked: false
    property bool active: true
    signal toggled(bool v)

    // состояние на экране: меняется сразу при клике, внешнее checked догоняет (без «прыжков» тумблера)
    property bool on: checked
    onCheckedChanged: on = checked

    width: parent ? parent.width : 300
    // высота по подписи: длинное пояснение переносится, а не уходит под тумблер
    implicitHeight: Math.max(34, texts.implicitHeight + 10)
    opacity: active ? 1 : 0.4

    Column {
        id: texts
        anchors { left: parent.left; right: sw.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        Text { width: parent.width; text: w.label; elide: Text.ElideRight; color: w.ui.text; font.family: w.ui.font; font.pixelSize: 13 }
        Text { width: parent.width; visible: w.sub !== ""; text: w.sub; wrapMode: Text.WordWrap; color: w.ui.sub; font.family: w.ui.font; font.pixelSize: 11 }
    }
    Item {
        id: sw
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: 51; height: 31
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: w.on ? w.ui.accent : w.ui.fill(0.18)
            border.width: w.ui.ios ? 0 : 1
            border.color: w.on ? Qt.darker(w.ui.accent, 1.2) : w.ui.line(0.22)
            Behavior on color { ColorAnimation { duration: 200 } }
        }
        Rim { anchors.fill: parent; ui: w.ui; radius: height / 2; strength: 0.7 }
        RectangularShadow {
            anchors.fill: knob
            radius: knob.radius
            blur: 6
            offset: Qt.vector2d(0, 2)
            color: Qt.rgba(0, 0, 0, 0.28)
        }
        Rectangle {
            id: knob
            y: 2
            x: w.on ? parent.width - width - 2 : 2
            width: ma.pressed ? 33 : 27
            height: 27
            radius: 13.5
            color: "white"
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 140 } }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            enabled: w.active
            cursorShape: Qt.PointingHandCursor
            onClicked: { w.on = !w.on; w.toggled(w.on); }
        }
    }
}
