import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// Эффект перехода курсора на краю экрана: свечение, волна, искры, линия, портал, комета, северное сияние, лучи, эхо; отдельно — «отказ» (красный крест) для неудавшегося перехода.
// Рисуется в «каноническом» виде — край слева, точка на высоте posC; для остальных краёв холст поворачивается.
// Картинка — дважды: размытая копия даёт мягкий ореол (bloom), чёткая — яркое ядро. Всё движение — одно свойство t (0 → 1);
// слой эффекта — квадрат вокруг точки, а не весь экран: размытие считается только там
Item {
    id: fx
    property string kind: "glow"          // glow | ripple | sparks | line | portal | comet | aurora | burst | echo | deny
    property string side: "right"         // край экрана
    property real pos: 0.5                // место вдоль края, 0..1
    property string dir: "out"            // out — курсор ушёл, in — пришёл
    property color tint: "white"
    property int duration: 700
    property real k: 1.0                  // сила (размер и яркость)
    signal finished

    property real t: 0
    NumberAnimation on t { from: 0; to: 1; duration: fx.duration; easing.type: Easing.Linear; onFinished: fx.finished() }
    readonly property real ease: 1 - Math.pow(1 - t, 3)              // быстрое начало, мягкий конец
    readonly property real easeQ: 1 - Math.pow(1 - t, 5)             // ещё резче: волны и искры
    readonly property real bell: Math.sin(Math.PI * Math.min(1, t * 1.15))   // вспыхнуть и погаснуть (чуть раньше конца)
    readonly property real fade: 1 - t * t                            // плавное угасание
    readonly property color hot: Qt.lighter(tint, 1.6)                // ядро — светлее основного цвета
    readonly property real span: 520 * k                              // половина стороны слоя эффекта

    // ---- холст: край слева; поворот переносит его на нужную сторону ----
    readonly property bool vertical: side === "left" || side === "right"
    readonly property real posC: (side === "right" || side === "top") ? 1 - pos : pos
    Item {
        id: canon
        width: fx.vertical ? fx.width : fx.height
        height: fx.vertical ? fx.height : fx.width
        anchors.centerIn: parent
        rotation: ({ left: 0, right: 180, top: 90, bottom: -90 })[fx.side] || 0

        // слой вокруг точки: её место внутри слоя — (span, span), край экрана — вертикаль x = span
        Item {
            id: stage
            x: -fx.span; y: fx.posC * canon.height - fx.span
            width: fx.span * 2; height: fx.span * 2
            // ореол: та же картинка, размытая и подсвеченная
            Loader {
                anchors.fill: parent
                sourceComponent: art
                onLoaded: item.halo = true
                opacity: 0.95
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 56; blurMultiplier: 0.6; brightness: 0.2; saturation: 0.25 }
            }
            // ядро: чёткая картинка поверх ореола
            Loader { anchors.fill: parent; sourceComponent: art; opacity: 0.85 }
        }
    }

    Component {
        id: art
        Item {
            id: artRoot
            property bool halo: false             // размытая копия: широкие мягкие пятна рисуются только в ней (в чёткой — резкие края)
            readonly property real cx: fx.span + 2 * fx.k     // на пару пикселей внутрь экрана: у самой кромки линию срезает рамка монитора
            readonly property real cy: fx.span

            // ---------- свечение: вытянутый мягкий сгусток света на краю и яркая полоса ----------
            Item {
                visible: fx.kind === "glow"
                anchors.fill: parent
                readonly property real len: 380 * fx.k * (fx.dir === "in" ? 0.45 + 0.55 * fx.ease : 1 - 0.4 * fx.ease)
                Rectangle {
                    visible: artRoot.halo
                    x: parent.parent.cx - width / 2; y: parent.parent.cy - height / 2
                    width: 90 * fx.k; height: parent.len
                    radius: width / 2
                    opacity: fx.bell * 0.8
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: fx.tint }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
                Rectangle {
                    x: parent.parent.cx; y: parent.parent.cy - height / 2
                    width: 4 * fx.k; height: parent.len * 0.9
                    radius: width / 2
                    opacity: fx.bell
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: fx.hot }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
                // искра в самой точке перехода
                Rectangle {
                    readonly property real d: 22 * fx.k * (0.6 + 0.6 * fx.bell)
                    x: parent.parent.cx - d / 2; y: parent.parent.cy - d / 2
                    width: d; height: d; radius: d / 2
                    color: "white"
                    opacity: fx.bell * 0.9
                }
            }

            // ---------- волна: тонкие кольца расходятся от точки, вспышка в начале ----------
            Repeater {
                model: fx.kind === "ripple" ? 3 : 0
                Rectangle {
                    required property int index
                    readonly property real tt: Math.max(0, Math.min(1, (fx.t - index * 0.13) / 0.75))
                    readonly property real e: 1 - Math.pow(1 - tt, 4)
                    readonly property real d: 30 + 640 * fx.k * e
                    x: parent.cx - d / 2; y: parent.cy - d / 2
                    width: d; height: d; radius: d / 2
                    color: "transparent"
                    border.width: Math.max(1, (5 - index * 1.2) * fx.k * (1 - tt))
                    border.color: index === 0 ? fx.hot : fx.tint
                    opacity: tt > 0 ? Math.pow(1 - tt, 1.4) : 0
                }
            }
            Rectangle {
                visible: fx.kind === "ripple" && artRoot.halo
                readonly property real d: 120 * fx.k * (0.4 + fx.easeQ)
                x: parent.cx - d / 2; y: parent.cy - d / 2
                width: d; height: d; radius: d / 2
                color: fx.tint
                opacity: Math.max(0, 1 - fx.t * 3.5) * 0.85
            }

            // ---------- искры: короткие светящиеся штрихи со шлейфом, разлетаются (пришёл) или втягиваются (ушёл) ----------
            Repeater {
                model: fx.kind === "sparks" ? 30 : 0
                Item {
                    required property int index
                    // угол, скорость и размер постоянны для каждой искры: картинка не «дрожит»
                    readonly property real a: (-78 + (index * 47) % 156) * Math.PI / 180
                    readonly property real sp: 0.45 + ((index * 61) % 55) / 100
                    readonly property real prog: fx.dir === "in" ? fx.easeQ : 1 - fx.easeQ
                    readonly property real r: 360 * fx.k * sp * prog
                    readonly property real trail: (8 + 46 * sp) * fx.k * (fx.dir === "in" ? 1 - fx.easeQ * 0.85 : 0.3 + fx.easeQ * 0.7)
                    readonly property real w: (2.5 + (index % 3)) * fx.k
                    x: parent.cx + Math.cos(a) * r
                    y: parent.cy + Math.sin(a) * r
                    rotation: a * 180 / Math.PI
                    opacity: (fx.dir === "in" ? 1 - fx.t : Math.min(1, fx.t * 4) * (1 - fx.t)) * (0.6 + 0.4 * ((index * 7) % 5) / 4)
                    // шлейф — за искрой, по направлению движения
                    Rectangle {
                        x: fx.dir === "in" ? -width : 0; y: -height / 2
                        width: parent.trail; height: parent.w
                        radius: height / 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: fx.dir === "in" ? "transparent" : (index % 4 === 0 ? "white" : fx.hot) }
                            GradientStop { position: 1; color: fx.dir === "in" ? (index % 4 === 0 ? "white" : fx.hot) : "transparent" }
                        }
                    }
                }
            }

            // ---------- линия: свет бежит вдоль всего края от точки в обе стороны ----------
            Item {
                visible: fx.kind === "line"
                anchors.fill: parent
                readonly property real reach: fx.span * 0.98 * fx.ease
                Rectangle {
                    x: parent.parent.cx; y: parent.parent.cy - parent.reach
                    width: 4 * fx.k; height: parent.reach * 2
                    opacity: fx.fade
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.12; color: fx.tint }
                        GradientStop { position: 0.5; color: fx.hot }
                        GradientStop { position: 0.88; color: fx.tint }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
                // «кометы» на концах бегущего света
                Repeater {
                    model: 2
                    Rectangle {
                        required property int index
                        readonly property real d: 14 * fx.k
                        x: parent.parent.cx - d / 2 + 1
                        y: parent.parent.cy + (index === 0 ? -1 : 1) * parent.reach - d / 2
                        width: d; height: d; radius: d / 2
                        color: "white"
                        opacity: fx.fade * (fx.t < 0.9 ? 1 : (1 - fx.t) * 10)
                    }
                }
                Rectangle {
                    visible: artRoot.halo
                    x: parent.parent.cx - width / 2; y: parent.parent.cy - height / 2
                    width: 60 * fx.k; height: 220 * fx.k; radius: width / 2
                    color: fx.tint
                    opacity: fx.bell * 0.55
                }
            }

            // ---------- портал: вращающиеся пунктирные овалы и светящаяся сердцевина ----------
            Shape {
                id: portal
                visible: fx.kind === "portal"
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                readonly property real open: fx.dir === "in" ? fx.easeQ : 1 - fx.easeQ * 0.7
                readonly property real a0: fx.bell
                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillGradient: RadialGradient {
                        centerX: fx.span; centerY: fx.span; centerRadius: 140 * fx.k
                        focalX: fx.span; focalY: fx.span
                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.9 * fx.bell) }
                        GradientStop { position: 0.35; color: Qt.rgba(fx.tint.r, fx.tint.g, fx.tint.b, 0.6 * fx.bell) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                    PathAngleArc { centerX: fx.span; centerY: fx.span; radiusX: 70 * fx.k; radiusY: 190 * fx.k * (0.4 + 0.6 * portal.open); startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    strokeWidth: 3 * fx.k
                    strokeColor: Qt.rgba(fx.hot.r, fx.hot.g, fx.hot.b, fx.bell)
                    fillColor: "transparent"
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [3, 2.5]
                    dashOffset: fx.t * 22
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: fx.span; centerY: fx.span; radiusX: 46 * fx.k; radiusY: 150 * fx.k * (0.4 + 0.6 * portal.open); startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    strokeWidth: 2 * fx.k
                    strokeColor: Qt.rgba(fx.tint.r, fx.tint.g, fx.tint.b, fx.bell * 0.85)
                    fillColor: "transparent"
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [6, 4]
                    dashOffset: -fx.t * 30
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: fx.span; centerY: fx.span; radiusX: 78 * fx.k; radiusY: 230 * fx.k * (0.4 + 0.6 * portal.open); startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    strokeWidth: 1.5 * fx.k
                    strokeColor: Qt.rgba(fx.tint.r, fx.tint.g, fx.tint.b, fx.bell * 0.5)
                    fillColor: "transparent"
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [2, 6]
                    dashOffset: fx.t * 40
                    PathAngleArc { centerX: fx.span; centerY: fx.span; radiusX: 110 * fx.k; radiusY: 300 * fx.k * (0.4 + 0.6 * portal.open); startAngle: 0; sweepAngle: 360 }
                }
            }

            // ---------- комета: яркая точка с хвостом летит от края вглубь экрана (пришёл) или к краю (ушёл) ----------
            Item {
                visible: fx.kind === "comet"
                anchors.fill: parent
                readonly property real travel: 440 * fx.k * (fx.dir === "in" ? fx.ease : 1 - fx.ease)
                readonly property real tail: (90 + 160 * fx.bell) * fx.k
                Rectangle {
                    x: parent.parent.cx + parent.travel - (fx.dir === "in" ? width : 0)      // хвост — позади головы; при «ушёл» картинка перевёрнута
                    rotation: fx.dir === "in" ? 0 : 180
                    y: parent.parent.cy - height / 2
                    width: parent.tail; height: 5 * fx.k; radius: height / 2
                    opacity: fx.bell
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.75; color: fx.tint }
                        GradientStop { position: 1; color: fx.hot }
                    }
                }
                Rectangle {
                    visible: artRoot.halo
                    readonly property real d: 70 * fx.k
                    x: parent.parent.cx + parent.travel - d / 2; y: parent.parent.cy - d / 2
                    width: d; height: d; radius: d / 2
                    color: fx.tint; opacity: fx.bell * 0.6
                }
                Rectangle {
                    readonly property real d: 16 * fx.k
                    x: parent.parent.cx + parent.travel - d / 2; y: parent.parent.cy - d / 2
                    width: d; height: d; radius: d / 2
                    color: "white"; opacity: fx.bell
                }
            }

            // ---------- сияние: мягкие вертикальные завесы колышутся у края ----------
            Repeater {
                model: fx.kind === "aurora" ? 4 : 0
                Rectangle {
                    required property int index
                    readonly property real sway: Math.sin(fx.t * 5 + index * 1.7)
                    x: parent.cx + index * 16 * fx.k * (0.4 + fx.ease)
                    y: parent.cy - height / 2 + sway * 22 * fx.k
                    width: (170 - index * 28) * fx.k
                    height: (300 + 120 * Math.sin(fx.t * 3 + index)) * fx.k * (fx.dir === "in" ? 0.5 + 0.5 * fx.ease : 1)
                    opacity: fx.bell * (0.55 - index * 0.1)
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: index % 2 === 0 ? fx.tint : fx.hot }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
            }

            // ---------- лучи: веер тонких лучей из точки перехода ----------
            Repeater {
                model: fx.kind === "burst" ? 15 : 0
                Item {
                    required property int index
                    readonly property real a: (-80 + index * (160 / 14)) * Math.PI / 180
                    readonly property real len: (60 + 300 * fx.k * (0.4 + 0.6 * ((index * 37) % 10) / 9)) * (fx.dir === "in" ? fx.easeQ : 1 - fx.easeQ * 0.6)
                    x: parent.cx; y: parent.cy
                    rotation: a * 180 / Math.PI
                    opacity: fx.fade * Math.min(1, fx.t * 8)
                    Rectangle {
                        y: -height / 2
                        width: parent.len; height: (index % 3 === 0 ? 3.5 : 2) * fx.k; radius: height / 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: index % 3 === 0 ? "white" : fx.hot }
                            GradientStop { position: 1; color: "transparent" }
                        }
                    }
                }
            }

            // ---------- эхо: копии светящейся линии края уходят вглубь экрана (пришёл) или втягиваются (ушёл) ----------
            Repeater {
                model: fx.kind === "echo" ? 5 : 0
                Rectangle {
                    required property int index
                    readonly property real tt: Math.max(0, Math.min(1, (fx.t - index * 0.07) / 0.8))
                    readonly property real e: 1 - Math.pow(1 - tt, 3)
                    x: parent.cx + (fx.dir === "in" ? e : 1 - e) * (30 + index * 46) * fx.k
                    y: parent.cy - height / 2
                    width: (4 - index * 0.5) * fx.k; height: (360 - index * 40) * fx.k; radius: width / 2
                    opacity: tt > 0 ? Math.sin(Math.PI * tt) * (1 - index * 0.16) : 0
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: index === 0 ? fx.hot : fx.tint }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
            }

            // ---------- отказ: красный крест на краю и дрожащая полоса ----------
            Item {
                visible: fx.kind === "deny"
                anchors.fill: parent
                Rectangle {
                    x: parent.parent.cx + Math.sin(fx.t * 46) * 6 * (1 - fx.t) * fx.k; y: parent.parent.cy - height / 2
                    width: 5 * fx.k; height: 260 * fx.k; radius: width / 2
                    opacity: fx.bell
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: fx.tint }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
                Repeater {
                    model: 2
                    Rectangle {
                        required property int index
                        x: parent.parent.cx + 34 * fx.k - width / 2; y: parent.parent.cy - height / 2
                        width: 56 * fx.k; height: 7 * fx.k; radius: height / 2
                        rotation: index === 0 ? 45 : -45
                        color: fx.hot
                        opacity: fx.bell * Math.min(1, fx.t * 10)
                        scale: 0.7 + 0.3 * fx.easeQ
                    }
                }
            }
        }
    }
}
