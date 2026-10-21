import QtQuick

// Раздел: заголовок и стеклянная группа элементов
Column {
    id: sec
    property QtObject ui
    property string title
    default property alias content: inner.data

    // в сетке (широкий вид) раздел занимает свою колонку, в обычной колонке — всю ширину
    width: parent && parent.columns !== undefined && parent.columnSpacing !== undefined
           ? (parent.width - parent.columnSpacing * (parent.columns - 1)) / parent.columns : (parent ? parent.width : 400)
    spacing: 8

    Text {
        leftPadding: 4
        text: sec.title
        color: sec.ui.sub
        font.family: sec.ui.font
        font.pixelSize: 12
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.8
    }
    Item {
        width: parent.width
        height: inner.implicitHeight + 28
        Rectangle {
            anchors.fill: parent
            radius: sec.ui.r(22)
            color: sec.ui.fill(0.07)
            border.width: sec.ui.ios ? 0 : 1
            border.color: sec.ui.line(0.18)
        }
        Rim { anchors.fill: parent; ui: sec.ui; radius: sec.ui.r(22); strength: 0.55 }
        Column {
            id: inner
            x: 16; y: 14
            width: parent.width - 32
            spacing: 12
        }
    }
}
