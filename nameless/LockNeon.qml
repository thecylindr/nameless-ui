import QtQuick
import QtQuick.Effects

// Блокировка «Неон»: тёмный фон, светящееся кольцо секунд вокруг времени, неоновое поле пароля.
// Цвет свечения — акцент темы; при ошибке — красный
Item {
    id: v
    property var lk
    readonly property color glow: v.lk && v.lk.error !== "" ? "#ff4d6d" : Theme.accent
    readonly property color glow2: Theme.accent2

    Rectangle { anchors.fill: parent; color: "#06060c" }
    LockBg { anchors.fill: parent; lk: v.lk; blur: 1.0; dim: 0.82 }

    // кольцо: дуга секунд
    Item {
        id: ring
        width: 360; height: 360
        anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: -70 }
        Canvas {
            id: arc
            anchors.fill: parent
            visible: false
            readonly property real frac: v.lk ? (v.lk.now.getSeconds() + 1) / 60 : 0
            onFracChanged: requestPaint()
            onPaint: {
                var g = getContext("2d"), c = width / 2, r = c - 14;
                g.reset();
                g.lineWidth = 3; g.strokeStyle = Qt.rgba(1, 1, 1, 0.08);
                g.beginPath(); g.arc(c, c, r, 0, Math.PI * 2); g.stroke();
                g.lineWidth = 5; g.lineCap = "round"; g.strokeStyle = v.glow;
                g.beginPath(); g.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac); g.stroke();
            }
            Connections { target: v; function onGlowChanged() { arc.requestPaint(); } }
        }
        MultiEffect { anchors.fill: arc; source: arc; shadowEnabled: true; shadowColor: v.glow; shadowBlur: 1.0; shadowHorizontalOffset: 0; shadowVerticalOffset: 0 }

        Column {
            anchors.centerIn: parent
            spacing: 6
            Text {
                id: time
                anchors.horizontalCenter: parent.horizontalCenter
                text: v.lk ? v.lk.now.toLocaleString(Qt.locale("ru_RU"), "HH:mm") : ""
                color: "white"; font.family: Theme.font; font.pixelSize: 86; font.weight: Font.Light
                font.features: { "tnum": 1 }
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: v.glow2; shadowBlur: 0.8; shadowHorizontalOffset: 0; shadowVerticalOffset: 0 }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: v.lk ? v.lk.now.toLocaleString(Qt.locale("ru_RU"), "dddd, d MMMM").toUpperCase() : ""
                color: v.glow; font.family: Theme.font; font.pixelSize: 12; font.letterSpacing: 3
            }
        }
    }

    Column {
        anchors { horizontalCenter: parent.horizontalCenter; top: ring.bottom; topMargin: 30 }
        spacing: 14
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 320; height: 48; radius: 10
            color: Qt.rgba(v.glow.r, v.glow.g, v.glow.b, 0.06)
            border.width: 2; border.color: v.glow
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: v.glow; shadowBlur: 0.7; shadowHorizontalOffset: 0; shadowVerticalOffset: 0 }
            LockDots { anchors.centerIn: parent; lk: v.lk; dot: 9; tone: v.glow }
            Text {
                visible: v.lk && v.lk.pass === ""
                anchors.centerIn: parent
                text: v.lk && v.lk.busy ? Tr.t("ПРОВЕРКА…") : (v.lk && v.lk.error !== "" ? v.lk.error.toUpperCase() : Tr.t("ПАРОЛЬ · ") + (v.lk ? v.lk.user.toUpperCase() : ""))
                color: Qt.rgba(1, 1, 1, 0.6); font.family: Theme.font; font.pixelSize: 13; font.letterSpacing: 2
            }
        }
        LockStatus { anchors.horizontalCenter: parent.horizontalCenter; lk: v.lk; tone: v.glow; fillA: 0.1 }
    }

    LockNotifs { maxCards: 2; cardW: 360; alpha: 0.3; anchors { left: parent.left; leftMargin: 32; bottom: parent.bottom; bottomMargin: 30 } }
    LockPower { lk: v.lk; size: 40; tone: v.glow; fillA: 0.1; anchors { right: parent.right; rightMargin: 32; bottom: parent.bottom; bottomMargin: 28 } }
}
