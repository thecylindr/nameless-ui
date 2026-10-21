import QtQuick
import Quickshell
import Quickshell.Widgets

// «Пришло»: значки приложений с непрочитанными уведомлениями и счётчиком; клик — центр уведомлений
WCard {
    id: w
    readonly property var badges: {
        var by = {}, out = [], l = Notifs.list;
        for (var i = 0; i < l.length; i++) {
            var k = l[i].appName || Tr.t("Уведомление");
            if (by[k] === undefined) { by[k] = out.length; out.push({ app: k, icon: l[i].appIcon || "", n: 0 }); }
            out[by[k]].n++;
        }
        return out;
    }
    function iconFor(b) {
        if (b.icon.indexOf("/") === 0) return "file://" + b.icon;
        if (b.icon.indexOf("file://") === 0) return b.icon;
        return Quickshell.iconPath(b.icon || b.app.toLowerCase(), true) || Quickshell.iconPath("dialog-information", true);
    }
    empty: badges.length === 0
    implicitHeight: col.implicitHeight + pad * 2

    Column {
        id: col
        width: parent.width
        spacing: 10
        Text { text: Tr.t("Пришло"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6 }
        Flow {
            width: parent.width
            spacing: 10
            Repeater {
                model: w.badges
                Item {
                    id: bd
                    required property var modelData
                    width: 44; height: 44
                    ClippingRectangle {
                        anchors.fill: parent
                        radius: Theme.r(12)
                        color: Theme.fill(0.12)
                        IconImage { anchors.fill: parent; anchors.margins: 6; source: w.iconFor(bd.modelData) }
                    }
                    Rectangle {
                        anchors { right: parent.right; top: parent.top; rightMargin: -5; topMargin: -5 }
                        width: Math.max(18, cnt.implicitWidth + 8); height: 18; radius: 9
                        color: Theme.red
                        Text { id: cnt; anchors.centerIn: parent; text: bd.modelData.n; color: "white"; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Bold }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.centerOpen = true }
                }
            }
        }
    }
}
