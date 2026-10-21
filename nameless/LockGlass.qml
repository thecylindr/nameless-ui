import QtQuick
import Quickshell
import Quickshell.Widgets

// Блокировка «Стекло»: по центру одна стеклянная карточка — слева время, дата и состояние, справа аватар и поле
// пароля со стрелкой; ниже — плеер и уведомления. В EchoStar фон — звёздное небо
Item {
    id: v
    property var lk

    LockBg { anchors.fill: parent; lk: v.lk; blur: 0.85; dim: 0.18 }

    Item {
        id: card
        width: Math.min(parent.width - 80, 820)
        height: 300
        anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: -parent.height * 0.06 }
        Surface { anchors.fill: parent; radius: 36; alpha: 0.32 }

        // слева: время
        Column {
            anchors { left: parent.left; leftMargin: 44; verticalCenter: parent.verticalCenter }
            width: parent.width / 2 - 60
            spacing: 2
            Text {
                text: v.lk ? v.lk.now.toLocaleString(Qt.locale("ru_RU"), "HH:mm") : ""
                color: "white"; font.family: Theme.font; font.pixelSize: 112; font.weight: Font.Light; font.letterSpacing: -2
                font.features: { "tnum": 1 }
                Text {
                    visible: Config.lock.seconds === true
                    anchors { left: parent.right; leftMargin: 6; baseline: parent.baseline }
                    text: v.lk ? v.lk.now.toLocaleString(Qt.locale("ru_RU"), "ss") : ""
                    color: Theme.accent; font.family: Theme.font; font.pixelSize: 30; font.features: { "tnum": 1 }
                }
            }
            Text { text: v.lk ? v.lk.now.toLocaleString(Qt.locale("ru_RU"), "dddd, d MMMM") : ""; color: Qt.rgba(1, 1, 1, 0.85); font.family: Theme.font; font.pixelSize: 20; font.capitalization: Font.Capitalize }
            Row {
                topPadding: 14
                spacing: 16
                Text { text: Sys.wifiIcon + "  " + (Sys.ssid || Tr.t("нет сети")); color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.iconFont; font.pixelSize: 13 }
                Text { visible: Sys.hasBattery; text: Sys.batIcon + "  " + Sys.batPct + "%"; color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.iconFont; font.pixelSize: 13 }
                Text {
                    visible: v.lk && v.lk.layout !== ""
                    text: "󰌌  " + (v.lk ? v.lk.layout.substring(0, 2).toUpperCase() : "")
                    color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.iconFont; font.pixelSize: 13
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: v.lk.nextLayout() }
                }
            }
        }
        // разделитель
        Rectangle { anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter } width: 1; height: parent.height - 80; color: Qt.rgba(1, 1, 1, 0.18) }

        // справа: вход
        Column {
            anchors { right: parent.right; rightMargin: 44; verticalCenter: parent.verticalCenter }
            width: parent.width / 2 - 88
            spacing: 14
            Row {
                spacing: 14
                Item {
                    width: 64; height: 64
                    Rectangle {
                        anchors.fill: parent; radius: width / 2
                        gradient: Gradient { GradientStop { position: 0; color: Theme.accent } GradientStop { position: 1; color: Theme.accent2 } }
                        Text { anchors.centerIn: parent; visible: !v.lk || v.lk.avatar === ""; text: v.lk ? v.lk.user.charAt(0).toUpperCase() : ""; color: "white"; font.family: Theme.font; font.pixelSize: 28; font.weight: Font.Bold }
                    }
                    ClippingRectangle {
                        visible: v.lk && v.lk.avatar !== ""
                        anchors.fill: parent; radius: width / 2
                        Image { anchors.fill: parent; source: v.lk && v.lk.avatar !== "" ? "file://" + v.lk.avatar : ""; fillMode: Image.PreserveAspectCrop }
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: v.lk ? v.lk.user : ""; color: "white"; font.family: Theme.font; font.pixelSize: 20; font.weight: Font.DemiBold }
                    Text { text: v.lk ? (v.lk.host || "") : ""; color: Qt.rgba(1, 1, 1, 0.6); font.family: Theme.font; font.pixelSize: 12 }
                }
            }
            // поле со стрелкой
            Item {
                width: parent.width; height: 52
                Rectangle {
                    anchors.fill: parent; radius: 26
                    color: Qt.rgba(1, 1, 1, 0.12)
                    border.width: 1.5
                    border.color: v.lk && v.lk.error !== "" ? "#ff8a8a" : Qt.rgba(1, 1, 1, 0.3)
                }
                Rim { anchors.fill: parent; ui: Theme; radius: 26; strength: 0.8 }
                LockDots { anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter } lk: v.lk; dot: 9 }
                Text {
                    visible: v.lk && v.lk.pass === ""
                    anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                    text: v.lk && v.lk.busy ? Tr.t("Проверка…") : Tr.t("Пароль")
                    color: Qt.rgba(1, 1, 1, 0.55); font.family: Theme.font; font.pixelSize: 15
                }
                Rectangle {
                    anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    width: 40; height: 40; radius: 20
                    color: v.lk && v.lk.pass !== "" ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text { anchors.centerIn: parent; text: "󰁔"; color: "white"; font.family: Theme.iconFont; font.pixelSize: 18 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: v.lk.submit() }
                }
            }
            Text {
                text: !v.lk ? "" : (v.lk.error !== "" ? v.lk.error + (v.lk.fails > 1 ? Tr.t(" · попыток: ") + v.lk.fails : "") : (v.lk.caps ? Tr.t("󰪛  Включён Caps Lock") : Tr.t("Enter — войти")))
                color: v.lk && v.lk.error !== "" ? "#ffb4ab" : (v.lk && v.lk.caps ? Theme.yellow : Qt.rgba(1, 1, 1, 0.5))
                font.family: Theme.iconFont; font.pixelSize: 12
            }
        }
    }

    // ниже карточки: плеер и уведомления
    Row {
        anchors { horizontalCenter: parent.horizontalCenter; top: card.bottom; topMargin: 24 }
        spacing: 16
        PlayerCard { visible: Config.lock.player !== false && has; width: 380; implicitHeight: 150; compact: true; radius: 26 }
        LockNotifs { maxCards: 2; cardW: 380; radius: 22; alpha: 0.32 }
    }
    LockPower { lk: v.lk; anchors { right: parent.right; rightMargin: 32; bottom: parent.bottom; bottomMargin: 28 } }
}
