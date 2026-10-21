import QtQuick
import QtQuick.Effects

// Фон экрана блокировки: обои (размытие и затемнение — параметры) или ночное небо в космических темах
Item {
    id: bg
    property var lk
    property real blur: 0.9          // 0 — чёткие обои
    property real dim: 0.2
    property real zoomIn: 1.06       // начальное приближение, плавно уходит к 1
    readonly property bool sky: Theme.cosmos !== "off"

    Image {
        id: wall
        anchors.fill: parent
        source: bg.lk && bg.lk.wallpaper !== "" && !bg.sky ? "file://" + bg.lk.wallpaper : ""
        fillMode: Image.PreserveAspectCrop
        // под размытием полное разрешение не видно: картинка — в половину экрана
        sourceSize: Qt.size(Math.ceil(bg.width / (bg.blur > 0.2 ? 2 : 1)), Math.ceil(bg.height / (bg.blur > 0.2 ? 2 : 1)))
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        visible: wall.status === Image.Ready
        autoPaddingEnabled: false
        blurEnabled: bg.blur > 0.01
        blurMax: 40
        blur: bg.blur
        brightness: -bg.dim
        saturation: 0.1
        scale: bg.lk && bg.lk.locked ? 1.0 : bg.zoomIn
        Behavior on scale { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
    }
    // небо: градиент и звёзды, рисуются один раз
    Rectangle {
        visible: bg.sky || wall.status !== Image.Ready
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#03050c" }
            GradientStop { position: 0.6; color: Qt.tint("#0b1236", Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, 0.15)) }
            GradientStop { position: 1.0; color: Qt.tint("#1f1640", Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)) }
        }
        Canvas {
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d"), n = Math.round(width * height / 5000);
                ctx.reset();
                for (var i = 0; i < n; i++) {
                    var r = function (k) { var x = Math.sin(i * 12.9898 + k * 78.233) * 43758.5453; return x - Math.floor(x); };
                    ctx.fillStyle = Qt.rgba(1, 1, 1, 0.2 + r(3) * 0.6);
                    ctx.beginPath();
                    ctx.arc(r(1) * width, Math.pow(r(2), 1.3) * height, 0.4 + Math.pow(r(4), 3) * 1.4, 0, Math.PI * 2);
                    ctx.fill();
                }
            }
        }
    }
}
