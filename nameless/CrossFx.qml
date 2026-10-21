import QtQuick

// Эффект перехода курсора на краю экрана: свечение, волна, искры, линия, портал.
// Рисуется в «каноническом» виде — край слева, точка на высоте posC; для остальных краёв холст поворачивается.
// Всё движение — одно свойство t (0 → 1) с одним аниматором; только прямоугольники, без Canvas и шейдеров
Item {
    id: fx
    property string kind: "glow"          // glow | ripple | sparks | line | portal
    property string side: "right"         // край экрана
    property real pos: 0.5                // место вдоль края, 0..1
    property string dir: "out"            // out — курсор ушёл, in — пришёл
    property color tint: "white"
    property int duration: 700
    property real k: 1.0                  // сила (размер и яркость)
    signal finished

    property real t: 0
    NumberAnimation on t { from: 0; to: 1; duration: fx.duration; easing.type: Easing.Linear; onFinished: fx.finished() }
    readonly property real ease: 1 - Math.pow(1 - t, 3)        // быстрое начало, мягкий конец
    readonly property real bell: Math.sin(Math.PI * t)          // вспыхнуть и погаснуть

    // ---- холст: край слева; поворот переносит его на нужную сторону ----
    readonly property bool vertical: side === "left" || side === "right"
    readonly property real posC: (side === "right" || side === "top") ? 1 - pos : pos
    Item {
        id: canon
        width: fx.vertical ? fx.width : fx.height
        height: fx.vertical ? fx.height : fx.width
        anchors.centerIn: parent
        rotation: ({ left: 0, right: 180, top: 90, bottom: -90 })[fx.side] || 0
        readonly property real py: fx.posC * height

        // ---------- свечение: мягкое пятно у края ----------
        Rectangle {
            visible: fx.kind === "glow"
            x: 0; y: canon.py - height / 2
            width: 150 * fx.k; height: Math.min(canon.height, 520 * fx.k)
            opacity: fx.bell
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(fx.tint.r, fx.tint.g, fx.tint.b, 0.75) }
                GradientStop { position: 0.35; color: Qt.rgba(fx.tint.r, fx.tint.g, fx.tint.b, 0.22) }
                GradientStop { position: 1; color: "transparent" }
            }
            // по длине края пятно гаснет к концам: маской служит второй, вертикальный градиент поверх
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
                    GradientStop { position: 0.5; color: Qt.rgba(fx.tint.r, fx.tint.g, fx.tint.b, 0.18) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
                }
            }
        }
        Rectangle {
            visible: fx.kind === "glow"
            x: 0; y: canon.py - height / 2
            width: 3; height: 360 * fx.k * (0.4 + 0.6 * fx.ease)
            radius: 1.5
            color: fx.tint
            opacity: fx.bell
        }

        // ---------- волна: кольца расходятся от точки ----------
        Repeater {
            model: fx.kind === "ripple" ? 3 : 0
            Rectangle {
                required property int index
                readonly property real tt: Math.max(0, Math.min(1, (fx.t - index * 0.16) / 0.68))
                readonly property real d: (40 + 460 * fx.k * (1 - Math.pow(1 - tt, 2)))
                x: -d / 2; y: canon.py - d / 2
                width: d; height: d; radius: d / 2
                color: "transparent"
                border.width: 2.5 * fx.k
                border.color: fx.tint
                opacity: tt > 0 ? (1 - tt) * 0.9 : 0
            }
        }

        // ---------- искры: разлетаются от края (пришёл) или втягиваются в него (ушёл) ----------
        Repeater {
            model: fx.kind === "sparks" ? 22 : 0
            Rectangle {
                required property int index
                // угол и скорость каждой искры постоянны (от номера), картинка не «дрожит» от случайностей
                readonly property real a: (-75 + (index * 37) % 150) * Math.PI / 180
                readonly property real sp: 0.55 + ((index * 53) % 45) / 100
                readonly property real r: 300 * fx.k * sp * (fx.dir === "in" ? fx.ease : 1 - fx.ease)
                readonly property real s: (3 + index % 4) * fx.k
                x: Math.cos(a) * r - s / 2; y: canon.py + Math.sin(a) * r - s / 2
                width: s; height: s; radius: s / 2
                color: index % 3 === 0 ? "white" : fx.tint
                opacity: fx.dir === "in" ? 1 - fx.t : Math.min(1, fx.t * 3) * (1 - fx.t * 0.6)
            }
        }

        // ---------- линия: полоса вдоль всего края растёт от точки ----------
        Rectangle {
            visible: fx.kind === "line"
            readonly property real len: canon.height * Math.min(1, fx.ease * 1.4)
            x: 0; y: Math.max(0, Math.min(canon.height - len, canon.py - len / 2))
            width: 4 * fx.k; height: len
            opacity: 1 - fx.t * fx.t
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.5; color: fx.tint }
                GradientStop { position: 1; color: "transparent" }
            }
        }
        Rectangle {
            visible: fx.kind === "line"
            x: 0; y: canon.py - height / 2
            width: 60 * fx.k; height: 180 * fx.k
            opacity: fx.bell * 0.5
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(fx.tint.r, fx.tint.g, fx.tint.b, 0.6) }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        // ---------- портал: вытянутые кольца у края, вспыхивают и сжимаются ----------
        Repeater {
            model: fx.kind === "portal" ? 4 : 0
            Rectangle {
                required property int index
                readonly property real ph: (fx.t * 1.6 + index * 0.25) % 1
                readonly property real d: 70 * fx.k * (fx.dir === "in" ? 0.3 + ph : 1.3 - ph)
                x: -d / 2; y: canon.py - d / 2
                width: d; height: d; radius: d / 2
                color: "transparent"
                border.width: 2 + (3 - index % 3)
                border.color: index % 2 ? fx.tint : Qt.lighter(fx.tint, 1.5)
                opacity: fx.bell * (1 - Math.abs(ph - 0.5))
                transform: Scale { origin.x: d / 2; origin.y: d / 2; yScale: 3.2 }
            }
        }
        Rectangle {
            visible: fx.kind === "portal"
            x: 0; y: canon.py - height / 2
            width: 46 * fx.k; height: 260 * fx.k
            radius: width / 2
            opacity: fx.bell * 0.55
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: fx.tint }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }
}
