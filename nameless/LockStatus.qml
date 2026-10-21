import QtQuick

// Состояние ввода на экране блокировки: раскладка (клик — следующая) и Caps Lock, когда включён
Row {
    id: st
    property var lk
    property color tone: "white"
    property real fillA: 0.12
    spacing: 8
    readonly property string short: {
        var l = lk ? lk.layout.toLowerCase() : "";
        if (l === "") return "";
        if (l.indexOf("russian") === 0 || l.indexOf("рус") === 0) return "RU";
        if (l.indexOf("english") === 0) return "EN";
        return lk.layout.substring(0, 2).toUpperCase();
    }
    Rectangle {
        visible: st.short !== ""
        width: lay.implicitWidth + 20; height: 28; radius: 14
        color: Qt.rgba(st.tone.r, st.tone.g, st.tone.b, lma.containsMouse ? st.fillA + 0.1 : st.fillA)
        Text { id: lay; anchors.centerIn: parent; text: "󰌌  " + st.short; color: st.tone; font.family: Theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold }
        MouseArea { id: lma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (st.lk) st.lk.nextLayout() }
    }
    Rectangle {
        visible: st.lk !== null && st.lk !== undefined && st.lk.caps
        width: caps.implicitWidth + 20; height: 28; radius: 14
        color: Qt.rgba(1, 0.8, 0.2, 0.22)
        border.width: 1; border.color: Theme.yellow
        Text { id: caps; anchors.centerIn: parent; text: "󰪛  Caps Lock"; color: Theme.yellow; font.family: Theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold }
    }
}
