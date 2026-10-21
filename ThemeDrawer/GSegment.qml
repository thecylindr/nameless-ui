import QtQuick

// Сегментированный выбор с плывущим стеклянным выделением: options = [{ v, t, icon, on }]
Item {
    id: g
    property QtObject ui
    property var options: []
    property string value
    signal picked(string v)

    width: parent ? parent.width : 300
    implicitHeight: 38
    readonly property int idx: {
        for (var i = 0; i < options.length; i++) if (options[i].v === value) return i;
        return -1;
    }
    readonly property real cell: (width - 6) / Math.max(1, options.length)

    Rectangle {
        anchors.fill: parent
        radius: g.ui.r(height / 2)
        color: g.ui.fill(0.08)
        border.width: g.ui.ios ? 0 : 1
        border.color: g.ui.line(0.22)
    }
    Item {
        id: knob
        visible: g.idx >= 0
        x: 3 + Math.max(0, g.idx) * g.cell
        y: 3
        width: g.cell
        height: parent.height - 6
        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            radius: g.ui.r(height / 2)
            color: !g.ui.glass ? Qt.rgba(g.ui.accent.r, g.ui.accent.g, g.ui.accent.b, 0.24)
                               : (g.ui.dark ? Qt.rgba(1, 1, 1, 0.20) : "white")
        }
        Rim { anchors.fill: parent; ui: g.ui; radius: g.ui.r(height / 2) }
    }
    Row {
        x: 3; y: 3
        Repeater {
            model: g.options
            Item {
                id: seg
                required property var modelData
                required property int index
                readonly property bool on: modelData.on !== false
                width: g.cell
                height: g.height - 6
                opacity: on ? 1 : 0.35
                // подпись не выходит за сегмент: при нехватке места значок прячется, текст сжимается до 10 px и обрезается
                readonly property real room: width - 16
                readonly property bool withIcon: !!modelData.icon && label.implicitWidth + 21 <= room
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        visible: seg.withIcon
                        anchors.verticalCenter: parent.verticalCenter
                        text: seg.modelData.icon || ""
                        color: g.ui.text
                        font.family: g.ui.iconFont
                        font.pixelSize: 15
                    }
                    Text {
                        id: label
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, seg.room - (seg.withIcon ? 21 : 0))
                        height: seg.height
                        verticalAlignment: Text.AlignVCenter
                        text: seg.modelData.t
                        color: g.ui.text
                        elide: Text.ElideRight
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 10
                        font.family: g.ui.font
                        font.pixelSize: 13
                        font.weight: seg.index === g.idx ? Font.DemiBold : Font.Normal
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: seg.on && seg.index !== g.idx
                    cursorShape: Qt.PointingHandCursor
                    onClicked: g.picked(seg.modelData.v)
                }
            }
        }
    }
}
