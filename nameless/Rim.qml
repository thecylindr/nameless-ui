import QtQuick

// Объём края жидкого стекла для элементов: блик, «мениск», глубина (shaders/liquidrim.frag — LiquidRim приложения)
ShaderEffect {
    id: r
    property QtObject ui
    property real radius: 12
    property real pressedAmount: 0
    property real strength: 1.0

    // экономный режим (и «авто» от батареи): объёмный кант не рисуется — шейдер на каждой плитке и панели заметно грузит
    // встроенную видеокарту; стекло остаётся стеклом (размытие, дымка, верхний свет)
    visible: width > 2 && height > 2 && (!ui || ui.glass !== false) && !Perf.eco
    vertexShader: Qt.resolvedUrl("shaders/liquidrim.vert.qsb")
    fragmentShader: Qt.resolvedUrl("shaders/liquidrim.frag.qsb")
    property size size: Qt.size(width, height)
    property real bezel: Math.min(10, Math.min(width, height) * 0.35)
    property real rim: r.strength
    property real dark: r.ui && r.ui.dark ? 1 : 0
    property real pressed: r.pressedAmount
    property point lightDir: Qt.point(-0.55, -0.83)
    Behavior on pressed { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
}
