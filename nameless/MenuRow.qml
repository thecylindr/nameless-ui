import QtQuick

// Строка контекстного меню (док, лаунчер): значок, подпись, подсветка при наведении; danger — красная
Item {
    id: r
    property string icon: ""
    property string label: ""
    property bool danger: false
    signal clicked

    width: parent ? parent.width : 220
    height: 34

    Rectangle {
        anchors.fill: parent
        radius: Theme.r(10)
        color: ma.containsMouse ? (r.danger ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.18) : Theme.fill(0.12)) : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
    }
    Text {
        id: ic
        x: 10
        width: 18
        anchors.verticalCenter: parent.verticalCenter
        text: r.icon
        color: r.danger ? Theme.red : Theme.sub
        font.family: Theme.iconFont
        font.pixelSize: 14
    }
    Text {
        anchors { left: ic.right; leftMargin: 8; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        text: r.label
        elide: Text.ElideRight
        color: r.danger ? Theme.red : Theme.text
        font.family: Theme.font
        font.pixelSize: 13
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: r.clicked()
    }
}
