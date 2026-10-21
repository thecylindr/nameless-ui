import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// Меню значка трея в стиле оболочки: пункты, флажки и переключатели, значки, подменю (вход внутрь и «Назад»).
// Нативное меню (SystemTrayItem.display) и всплывающее окно с захватом фокуса на панелях Wayland открываются
// ненадёжно (захвату нужен ввод в родительском окне) — меню рисуется на своём прозрачном слое поверх экрана:
// пункты DBusMenu отдаёт QsMenuOpener, клик — triggered(); клик мимо или Esc — закрыть
PanelWindow {
    id: m
    property var item: null                // SystemTrayItem
    property var stack: []                 // открытые подменю
    readonly property var current: stack.length > 0 ? stack[stack.length - 1] : (item ? item.menu : null)
    property real ax: 0                    // точка под значком, координаты экрана
    property real ay: 0

    visible: false
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "nameless-traymenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // anchorItem — значок в окне бара: бар прижат к верху экрана, его координаты совпадают с экранными
    function show(trayItem, anchorItem) {
        item = trayItem;
        stack = [];
        var p = anchorItem.mapToItem(null, anchorItem.width / 2, anchorItem.height);
        ax = p.x; ay = p.y + 10;
        visible = true;
    }
    function run(entry) {
        if (entry.hasChildren) { stack = stack.concat([entry]); return; }
        entry.triggered();
        visible = false;
    }
    onVisibleChanged: if (!visible) stack = []

    QsMenuOpener { id: op; menu: m.current }
    // подписи DBusMenu: «_» перед буквой — мнемоника, «__» — само подчёркивание
    function clean(t) { return (t || "").replace(/__/g, "\u0001").replace(/_/g, "").replace(/\u0001/g, "_"); }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: m.visible = false }
    Item { focus: m.visible; Keys.onEscapePressed: { if (m.stack.length > 0) m.stack = m.stack.slice(0, -1); else m.visible = false; } }

    Item {
        id: box
        width: 270
        height: Math.min(m.height - m.ay - 12, col.implicitHeight + 16)
        x: Math.max(8, Math.min(m.width - width - 8, m.ax - width / 2))
        y: m.ay
        MouseArea { anchors.fill: parent }
        Rectangle {
            anchors.fill: parent
            radius: Theme.r(16)
            color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, Theme.glass ? 0.96 : 0.98)
            border.width: 1
            border.color: Theme.glass ? Qt.rgba(1, 1, 1, 0.16) : Theme.line(0.22)
        }
        Flickable {
            anchors { fill: parent; margins: 8 }
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: col
                width: parent.width
                spacing: 1

                // заголовок: название приложения или «Назад» в подменю
                Item {
                    width: parent.width
                    height: 30
                    Text {
                        visible: m.stack.length === 0
                        anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: m.item ? (m.item.tooltipTitle || m.item.title || m.item.id || "") : ""
                        elide: Text.ElideRight
                        color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                    MenuRow {
                        visible: m.stack.length > 0
                        anchors.fill: parent
                        icon: "󰅁"
                        label: Tr.t("Назад · ") + (m.stack.length > 0 ? m.clean(m.stack[m.stack.length - 1].text) : "")
                        onClicked: m.stack = m.stack.slice(0, -1)
                    }
                }

                Repeater {
                    model: op.children
                    Item {
                        id: row
                        required property var modelData
                        readonly property var e: modelData
                        width: col.width
                        height: e.isSeparator ? 9 : 34
                        opacity: e.enabled ? 1 : 0.4

                        Rectangle {
                            visible: row.e.isSeparator
                            anchors.centerIn: parent
                            width: parent.width - 16; height: 1
                            color: Theme.fill(0.14)
                        }
                        Rectangle {
                            visible: !row.e.isSeparator
                            anchors.fill: parent
                            radius: Theme.r(10)
                            color: rma.containsMouse && row.e.enabled ? Theme.fill(0.12) : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                        // флажок / переключатель или значок
                        Item {
                            id: lead
                            visible: !row.e.isSeparator
                            x: 8; width: 20; height: 20
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                visible: row.e.buttonType !== QsMenuButtonType.None
                                anchors.centerIn: parent
                                width: 16; height: 16
                                radius: row.e.buttonType === QsMenuButtonType.RadioButton ? 8 : Theme.r(4)
                                color: row.e.checkState === Qt.Checked ? Theme.accent : "transparent"
                                border.width: row.e.checkState === Qt.Checked ? 0 : 1.5
                                border.color: Theme.line(0.5)
                                Text { anchors.centerIn: parent; visible: row.e.checkState === Qt.Checked; text: row.e.buttonType === QsMenuButtonType.RadioButton ? "●" : "󰄬"; color: "white"; font.family: Theme.iconFont; font.pixelSize: 10 }
                            }
                            IconImage {
                                visible: row.e.buttonType === QsMenuButtonType.None && (row.e.icon || "") !== ""
                                anchors.fill: parent
                                source: row.e.icon || ""
                            }
                        }
                        Text {
                            visible: !row.e.isSeparator
                            anchors { left: lead.right; leftMargin: 10; right: arrow.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            text: m.clean(row.e.text)
                            elide: Text.ElideRight
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                        }
                        Text {
                            id: arrow
                            visible: row.e.hasChildren
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: "󰅂"; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 13
                            width: visible ? implicitWidth : 0
                        }
                        MouseArea {
                            id: rma
                            anchors.fill: parent
                            visible: !row.e.isSeparator
                            enabled: row.e.enabled
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: m.run(row.e)
                        }
                    }
                }
                Text {
                    visible: op.children.values !== undefined && op.children.values.length === 0
                    width: parent.width; padding: 10
                    text: Tr.t("Меню пустое"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12
                }
            }
        }
    }
}
