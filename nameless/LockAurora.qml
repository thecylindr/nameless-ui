import QtQuick
import QtQuick.Effects

// Блокировка «Аврора»: живое сияние цветов темы — пятна плывут в маленькой текстуре, она размывается и растягивается
// на экран (дёшево для видеокарты); тонкое крупное время по центру, поле-линия с точками
Item {
    id: v
    property var lk
    readonly property bool live: lk ? lk.locked : false

    Rectangle { anchors.fill: parent; color: "#05060d" }

    // сияние: 240×135, размытие и масштаб ×(экран / 240)
    Item {
        id: glow
        width: 240; height: 135
        visible: false
        layer.enabled: true
        Repeater {
            model: [
                { c: Theme.accent, x: 40, y: 30, r: 70, dx: 60, dy: 20, t: 9000 },
                { c: Theme.accent2, x: 140, y: 60, r: 80, dx: -70, dy: -25, t: 11000 },
                { c: "#1fd1a5", x: 90, y: 90, r: 60, dx: 50, dy: -30, t: 13000 },
                { c: "#ff6fb5", x: 180, y: 20, r: 50, dx: -40, dy: 35, t: 15000 }
            ]
            Rectangle {
                id: blob
                required property var modelData
                width: modelData.r * 2; height: width; radius: width / 2
                color: modelData.c
                opacity: 0.75
                x: modelData.x - modelData.r
                y: modelData.y - modelData.r
                SequentialAnimation on x {
                    running: v.live; loops: Animation.Infinite
                    NumberAnimation { to: blob.modelData.x - blob.modelData.r + blob.modelData.dx; duration: blob.modelData.t; easing.type: Easing.InOutSine }
                    NumberAnimation { to: blob.modelData.x - blob.modelData.r; duration: blob.modelData.t; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on y {
                    running: v.live; loops: Animation.Infinite
                    NumberAnimation { to: blob.modelData.y - blob.modelData.r + blob.modelData.dy; duration: blob.modelData.t * 0.8; easing.type: Easing.InOutSine }
                    NumberAnimation { to: blob.modelData.y - blob.modelData.r; duration: blob.modelData.t * 0.8; easing.type: Easing.InOutSine }
                }
            }
        }
    }
    MultiEffect {
        source: glow
        width: glow.width; height: glow.height
        transformOrigin: Item.TopLeft
        scale: Math.max(v.width / glow.width, v.height / glow.height)
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 48
        blur: 1.0
        saturation: 0.3
        opacity: 0.85
    }
    // зерно и затемнение снизу
    Rectangle { anchors.fill: parent; gradient: Gradient { GradientStop { position: 0.5; color: "transparent" } GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.55) } } }

    Column {
        anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: -parent.height * 0.1 }
        spacing: 0
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: v.lk ? v.lk.now.toLocaleString(Qt.locale("ru_RU"), Config.lock.seconds ? "HH:mm:ss" : "HH:mm") : ""
            color: "white"; font.family: Theme.font; font.pixelSize: 170; font.weight: Font.Thin; font.letterSpacing: -4
            font.features: { "tnum": 1 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: v.lk ? v.lk.now.toLocaleString(Qt.locale("ru_RU"), "dddd · d MMMM").toUpperCase() : ""
            color: Qt.rgba(1, 1, 1, 0.8); font.family: Theme.font; font.pixelSize: 15; font.letterSpacing: 6
        }
    }

    // вход: имя и поле-линия
    Column {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: parent.height * 0.16 }
        spacing: 14
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: v.lk ? v.lk.user : ""; color: "white"; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; font.letterSpacing: 2 }
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 300; height: 36
            LockDots { anchors.centerIn: parent; lk: v.lk; dot: 8 }
            Text { visible: v.lk && v.lk.pass === ""; anchors.centerIn: parent; text: v.lk && v.lk.busy ? Tr.t("проверка…") : Tr.t("пароль"); color: Qt.rgba(1, 1, 1, 0.45); font.family: Theme.font; font.pixelSize: 14; font.letterSpacing: 3 }
            Rectangle {
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                width: v.lk && v.lk.pass !== "" ? parent.width : parent.width * 0.5
                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                height: 1.5
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.5; color: v.lk && v.lk.error !== "" ? "#ff8a8a" : Theme.accent }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: !v.lk ? "" : (v.lk.error !== "" ? v.lk.error : (v.lk.caps ? "󰪛  Caps Lock" : ""))
            color: v.lk && v.lk.error !== "" ? "#ffb4ab" : Theme.yellow
            font.family: Theme.iconFont; font.pixelSize: 12
        }
    }
    Row {
        anchors { left: parent.left; leftMargin: 32; bottom: parent.bottom; bottomMargin: 30 }
        spacing: 16
        Text { visible: Sys.hasBattery; text: Sys.batIcon + " " + Sys.batPct + "%"; color: Qt.rgba(1, 1, 1, 0.7); font.family: Theme.iconFont; font.pixelSize: 13 }
        Text {
            visible: v.lk && v.lk.layout !== ""
            text: "󰌌 " + (v.lk ? v.lk.layout.substring(0, 2).toUpperCase() : "")
            color: Qt.rgba(1, 1, 1, 0.7); font.family: Theme.iconFont; font.pixelSize: 13
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: v.lk.nextLayout() }
        }
        Text { visible: Notifs.count > 0 && Config.lock.notifs !== false; text: "󰂚 " + Notifs.count; color: Qt.rgba(1, 1, 1, 0.7); font.family: Theme.iconFont; font.pixelSize: 13 }
    }
    LockPower { lk: v.lk; size: 40; fillA: 0.08; anchors { right: parent.right; rightMargin: 32; bottom: parent.bottom; bottomMargin: 24 } }
}
