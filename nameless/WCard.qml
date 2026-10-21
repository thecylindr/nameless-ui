import QtQuick

// Карточка виджета: фон по выбору (Config.widgets.look) — стекло темы, плотный, без фона (только текст с тенью).
// empty — виджету нечего показать (нет плеера, нет уведомлений): место он не занимает
Item {
    id: c
    property real radius: Theme.ios ? 26 : 20
    property bool empty: false
    property real pad: 16
    default property alias content: inner.data
    readonly property string look: Config.widgets.look || "glass"
    readonly property bool clear: look === "clear"

    Surface {
        visible: !c.clear
        anchors.fill: parent
        radius: c.radius
        alpha: c.look === "solid" ? Math.min(0.96, Theme.panelAlpha + 0.3) : Theme.panelAlpha
    }
    Item {
        id: inner
        anchors.fill: parent
        anchors.margins: c.pad
    }
}
