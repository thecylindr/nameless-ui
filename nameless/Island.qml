import QtQuick

// Остров бара: группа элементов на одной поверхности в материале комплекта
Item {
    id: isl
    default property alias content: row.data
    property real pad: 6
    implicitWidth: row.implicitWidth + pad * 2
    implicitHeight: parent ? parent.height : 40
    visible: row.visibleChildren.length > 0

    Surface {
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: Theme.ios ? 16 : 12
        // без отбрасываемой тени: окно бара всего 42 px, тень обрезалась бы его краем в полосу с гранью
        shadow: false
        // острова плотнее тонкой полосы: читаются и без размытия Hyprland
        alpha: Theme.glass ? Math.max(0.5, Theme.panelAlpha + 0.08) : Theme.panelAlpha
    }
    Row {
        id: row
        x: isl.pad
        height: parent.height
        spacing: 0
    }
}
