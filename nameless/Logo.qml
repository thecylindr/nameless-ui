import QtQuick

// Знак NameLess UI: скруглённый квадрат с градиентом из двух акцентов темы и буквой «N»; рядом — надпись
Row {
    id: l
    property int size: 22
    property bool wordmark: true
    spacing: 8

    Rectangle {
        width: l.size; height: l.size
        radius: Theme.ios ? l.size * 0.28 : Theme.r(l.size * 0.3)
        anchors.verticalCenter: parent.verticalCenter
        // блик — часть градиента: отдельный слой меньшего размера давал видимый контур
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.lighter(Theme.accent, 1.25) }
            GradientStop { position: 0.45; color: Theme.accent }
            GradientStop { position: 1.0; color: Theme.accent2 }
        }
        Text {
            anchors.centerIn: parent
            text: "N"
            color: "white"
            font.family: Theme.font
            font.pixelSize: l.size * 0.62
            font.weight: Font.Black
        }
    }
    Text {
        visible: l.wordmark
        anchors.verticalCenter: parent.verticalCenter
        text: "NameLess"
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: l.size * 0.62
        font.weight: Font.Bold
        font.letterSpacing: Theme.ios ? -0.3 : 0.2
    }
}
