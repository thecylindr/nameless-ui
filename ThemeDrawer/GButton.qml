import QtQuick

// Стеклянная кнопка-таблетка
GTile {
    id: b
    property string label
    property string icon: ""
    property bool danger: false

    implicitWidth: Math.max(88, row.implicitWidth + 30)
    implicitHeight: 38
    radius: height / 2

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Text {
            visible: b.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: b.icon
            color: b.danger ? b.ui.red : b.ui.text
            font.family: b.ui.iconFont
            font.pixelSize: 15
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: b.label
            color: b.danger ? b.ui.red : b.ui.text
            font.family: b.ui.font
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }
}
