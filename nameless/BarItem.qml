import QtQuick

// Элемент бара: значок и текст; в классике и стекле — отдельная таблетка, в iOS — плоский на общей полосе.
// Колесо мыши, левый, правый и средний клик — сигналами
Item {
    id: b
    property string icon: ""
    property string label: ""
    property color iconColor: Theme.text
    property bool pill: false
    property bool highlight: false
    signal clicked
    signal rightClicked
    signal middleClicked
    signal wheel(int dir)

    implicitWidth: row.implicitWidth + (pill ? 24 : 18)
    implicitHeight: parent ? parent.height : 30

    Surface {
        visible: b.pill
        anchors.fill: parent
        anchors.topMargin: 5
        anchors.bottomMargin: 5
        radius: 8
        shadow: false
    }
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 8; anchors.bottomMargin: 8
        anchors.leftMargin: 2; anchors.rightMargin: 2
        radius: Theme.r(b.pill ? 8 : 10)
        color: b.highlight ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                           : (ma.containsMouse ? Theme.fill(0.12) : "transparent")
        Behavior on color { ColorAnimation { duration: 150 } }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Text {
            visible: b.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: b.icon
            color: b.iconColor
            font.family: Theme.iconFont
            font.pixelSize: 15
        }
        Text {
            visible: b.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: b.label
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            font.weight: Theme.ios ? Font.Medium : Font.DemiBold
            font.features: { "tnum": 1 }
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (m) => {
            if (m.button === Qt.RightButton) b.rightClicked();
            else if (m.button === Qt.MiddleButton) b.middleClicked();
            else b.clicked();
        }
        onWheel: (w) => b.wheel(w.angleDelta.y > 0 ? 1 : -1)
    }
}
