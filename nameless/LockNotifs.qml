import QtQuick
import Quickshell
import Quickshell.Widgets

// Уведомления на экране блокировки (Config.lock.notifs): последние карточки стопкой, остальные — «ещё N»
Column {
    id: n
    property int maxCards: 3
    property real cardW: 400
    property real radius: 20
    property real alpha: 0.42
    readonly property var list: Config.lock.notifs !== false ? Notifs.list.slice().reverse() : []
    spacing: 8
    function iconFor(x) {
        var i = x.appIcon || x.image || "";
        if (i.indexOf("/") === 0) return "file://" + i;
        if (i.indexOf("file://") === 0 || i.indexOf("image://") === 0) return i;
        return Quickshell.iconPath(i || (x.appName || "").toLowerCase(), true) || Quickshell.iconPath("dialog-information", true);
    }
    Repeater {
        model: n.list.slice(0, n.maxCards)
        Item {
            required property var modelData
            width: n.cardW
            height: 66
            Surface { anchors.fill: parent; radius: n.radius; alpha: n.alpha; shadow: false }
            IconImage { id: ni; x: 14; anchors.verticalCenter: parent.verticalCenter; implicitSize: 34; source: n.iconFor(modelData) }
            Column {
                anchors { left: ni.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                Text { width: parent.width; text: (modelData.appName || "").toUpperCase(); elide: Text.ElideRight; color: Qt.rgba(1, 1, 1, 0.6); font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.5 }
                Text { width: parent.width; text: modelData.summary || ""; elide: Text.ElideRight; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                Text { width: parent.width; text: modelData.body || ""; elide: Text.ElideRight; color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.font; font.pixelSize: 12 }
            }
        }
    }
    Text {
        visible: n.list.length > n.maxCards
        anchors.horizontalCenter: parent.horizontalCenter
        text: Tr.t("ещё ") + (n.list.length - n.maxCards)
        color: Qt.rgba(1, 1, 1, 0.6); font.family: Theme.font; font.pixelSize: 12
    }
}
