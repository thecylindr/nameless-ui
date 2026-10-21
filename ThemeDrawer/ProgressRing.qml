import QtQuick
import QtQuick.Shapes

// Кольцо прогресса: дорожка и дуга со скруглёнными концами (векторно, без растровых краёв).
// progress 0..1 заполняет дугу плавно; spinning — дуга медленно вращается, пока идёт шаг
Item {
    id: r
    property real progress: 0
    property bool spinning: true
    property color color: "white"
    property color track: Qt.rgba(1, 1, 1, 0.14)
    property real thickness: 6

    implicitWidth: 96
    implicitHeight: 96
    readonly property real rad: Math.min(width, height) / 2 - thickness / 2 - 1
    property real shown: progress
    Behavior on shown { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: r.track
            strokeWidth: r.thickness
            fillColor: "transparent"
            PathAngleArc { centerX: r.width / 2; centerY: r.height / 2; radiusX: r.rad; radiusY: r.rad; startAngle: 0; sweepAngle: 360 }
        }
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: r.color
            strokeWidth: r.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: r.width / 2; centerY: r.height / 2
                radiusX: r.rad; radiusY: r.rad
                startAngle: -90
                sweepAngle: Math.max(10, 359.9 * Math.min(1, r.shown))
            }
        }
        RotationAnimator on rotation {
            running: r.spinning && r.visible
            from: 0; to: 360
            duration: 1400
            loops: Animation.Infinite
        }
    }
}
