import QtQuick

// Плитка быстрого действия: значок сверху, подпись и состояние снизу
GTile {
    id: q
    property string icon
    property string label
    property string sub: ""

    radius: 22
    readonly property color fg: q.on ? "white" : q.ui.text

    Text {
        x: 13; y: 11
        text: q.icon
        color: q.fg
        font.family: q.ui.iconFont
        font.pixelSize: 21
    }
    Column {
        x: 13
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        width: parent.width - 20
        Text {
            width: parent.width
            text: q.label
            color: q.fg
            elide: Text.ElideRight
            font.family: q.ui.font
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            visible: q.sub !== ""
            text: q.sub
            color: q.on ? Qt.rgba(1, 1, 1, 0.78) : q.ui.sub
            elide: Text.ElideRight
            font.family: q.ui.font
            font.pixelSize: 11
        }
    }
}
