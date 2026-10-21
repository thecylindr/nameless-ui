import QtQuick

// Кнопки питания экрана блокировки: сон, перезагрузка, выключение; подпись при наведении
Row {
    id: p
    property var lk
    property real size: 44
    property color tone: "white"
    property real fillA: 0.12
    spacing: 10
    Repeater {
        model: [
            { i: "󰤄", t: Tr.t("Сон"), k: "suspend" },
            { i: "󰜉", t: Tr.t("Перезагрузка"), k: "reboot" },
            { i: "󰐥", t: Tr.t("Выключение"), k: "poweroff" }
        ]
        Item {
            required property var modelData
            width: p.size; height: p.size
            Rectangle { anchors.fill: parent; radius: width / 2; color: Qt.rgba(p.tone.r, p.tone.g, p.tone.b, pma.containsMouse ? p.fillA + 0.12 : p.fillA) }
            Text { anchors.centerIn: parent; text: modelData.i; color: p.tone; font.family: Theme.iconFont; font.pixelSize: p.size * 0.4 }
            Text {
                visible: pma.containsMouse
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 6 }
                text: modelData.t; color: p.tone; font.family: Theme.font; font.pixelSize: 11
            }
            MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: p.lk.power(modelData.k) }
        }
    }
}
