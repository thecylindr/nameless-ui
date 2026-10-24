import QtQuick
import QtQuick.Effects

// Поверхность панели в материале комплекта:
//   classic — плотная, рамка цвета текста (как исходный waybar);
//   liquid  — дымка с белым кантом и верхним светом (как карточки клиента);
//   iOS     — дымка без рамок, объёмный край.
// Размытие под стеклом даёт Hyprland (правило слоя ^nameless в стеклянных темах)
Item {
    id: s
    property real radius: 16
    property bool shadow: true
    property real alpha: Theme.panelAlpha
    default property alias content: inner.data
    // смещение окна при переносе за шапку (MoveArea); у неподвижных поверхностей — 0
    property real dx: 0
    property real dy: 0
    transform: Translate { x: s.dx; y: s.dy }

    RectangularShadow {
        visible: s.shadow && Theme.glass && !Perf.eco        // тень — в экономном режиме нет (размытая тень перерисовывается вместе с панелью)
        anchors.fill: parent
        radius: Theme.r(s.radius)
        blur: 28
        offset: Qt.vector2d(0, 8)
        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.35 : 0.18)
    }
    Rectangle {
        anchors.fill: parent
        radius: Theme.r(s.radius)
        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, s.alpha)
        border.width: Theme.ios ? 0 : 1
        border.color: Theme.glass ? Qt.rgba(1, 1, 1, 0.22) : Theme.line(0.16)
    }
    // верхний свет стекла
    Rectangle {
        visible: Theme.glass
        anchors.fill: parent
        radius: Theme.r(s.radius)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, Theme.ios ? 0.08 : 0.12) }
            GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.0) }
        }
    }
    Rim {
        visible: Theme.glass && s.height >= 44
        anchors.fill: parent
        ui: Theme
        radius: Theme.r(s.radius)
        strength: Theme.ios ? 0.9 : 0.6
    }
    Item { id: inner; anchors.fill: parent }
}
