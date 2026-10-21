import QtQuick
import QtQuick.Effects

// Панель из жидкого стекла: снимок экрана под ней преломляется в изогнутом крае, расходится по цветам и размывается
// (shaders/liquidglass.frag — шейдер GlassCard из приложения). Без снимка или при ошибке шейдера — плотная заливка
Item {
    id: g
    property QtObject ui
    property Item backdrop: null       // ShaderEffectSource снимка экрана с уровнями mip
    property size winSize: Qt.size(1, 1)
    property real radius: 30
    property real tint: 0.28           // матовость: доля подкраски
    property real strength: 1.0        // сила преломления
    property real blurPx: 10

    RectangularShadow {
        anchors.fill: parent
        radius: g.ui.r(g.radius)
        blur: 56
        offset: Qt.vector2d(0, 18)
        color: Qt.rgba(0, 0, 0, g.ui.dark ? 0.50 : 0.24)
    }

    ShaderEffect {
        id: fx
        anchors.fill: parent
        visible: g.backdrop !== null
        vertexShader: Qt.resolvedUrl("shaders/liquidglass.vert.qsb")
        fragmentShader: Qt.resolvedUrl("shaders/liquidglass.frag.qsb")
        property variant src: g.backdrop
        property size glassSize: Qt.size(width, height)
        property size winSize: g.winSize
        property real radius: g.ui.r(g.radius)
        property real bezel: Math.min(Math.min(width, height) * 0.36, 26)
        property real thickness: 35 * g.strength
        property real dispersion: 0.08 * g.strength
        property real blurPx: g.blurPx
        property real tintMix: g.tint
        property real saturation: 1.3
        property real dark: g.ui.dark ? 1 : 0
        property real rim: 0.55
        property real grain: 0.006
        property real magnify: 0.08 * g.strength * Math.min(1, 160 / Math.max(1, height))
        // выборок размытия на пиксель: 10 вместо 14 — слабой встроенной GPU легче, mip-уровни скрывают разницу
        property real taps: 10
        property real dpr: Screen.devicePixelRatio
        property real fbHeight: g.winSize.height * Screen.devicePixelRatio
        property real yUp: GraphicsInfo.api === GraphicsInfo.OpenGL ? 1 : 0
        property point lightDir: Qt.point(-0.55, -0.83)
        property real texScale: 1
        property real edgeColor: 1.0
    }

    // стекло клиента: белый кант по краю панели
    Rectangle {
        anchors.fill: parent
        visible: fx.visible && g.ui.kit === "liquid"
        radius: g.ui.r(g.radius)
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.30)
    }

    // сплошной стиль (как rofi и waybar) и запасной вариант стекла
    Rectangle {
        anchors.fill: parent
        visible: !fx.visible || fx.status === ShaderEffect.Error
        radius: g.ui.r(g.radius)
        color: g.ui.glass ? Qt.rgba(g.ui.base.r, g.ui.base.g, g.ui.base.b, g.ui.dark ? 0.82 : 0.88) : g.ui.base
        border.width: 1
        border.color: g.ui.glass ? Qt.rgba(1, 1, 1, g.ui.dark ? 0.16 : 0.6) : g.ui.line(0.22)
    }
}
