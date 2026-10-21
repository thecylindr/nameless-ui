import QtQuick
import QtQuick.Effects

// Блокировка «Половины»: слева — чёткие обои с временем и плеером, справа — панель входа:
// аватар, имя, поле пароля, раскладка, уведомления и питание
Item {
    id: v
    property var lk
    readonly property bool err: v.lk && v.lk.error !== ""

    LockBg { anchors.fill: parent; lk: v.lk; blur: 0; dim: 0.15 }

    // левая половина: время и дата снизу слева
    Column {
        anchors { left: parent.left; leftMargin: 64; bottom: parent.bottom; bottomMargin: 60 }
        spacing: 4
        Text {
            text: v.lk ? v.lk.now.toLocaleString(Qt.locale("ru_RU"), "HH:mm") : ""
            color: "white"; font.family: Theme.font; font.pixelSize: 120; font.weight: Font.Bold
            font.features: { "tnum": 1 }
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.6); shadowBlur: 0.6 }
        }
        Text {
            text: v.lk ? v.lk.now.toLocaleString(Qt.locale("ru_RU"), "dddd, d MMMM") : ""
            color: "white"; font.family: Theme.font; font.pixelSize: 22; font.capitalization: Font.Capitalize
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.6); shadowBlur: 0.5 }
        }
        Item { width: 1; height: 16 }
        PlayerCard { visible: Config.lock.player !== false && has; width: 380; implicitHeight: 150; compact: true; radius: 24 }
    }

    // правая панель входа
    Rectangle {
        id: side
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        width: Math.min(480, parent.width * 0.34)
        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.82)
        Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 1; color: Qt.rgba(1, 1, 1, 0.12) }

        Column {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: -40; margins: 48 }
            spacing: 16
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 104; height: 104; radius: 52
                color: Theme.accent
                clip: true
                Text { visible: ava.status !== Image.Ready; anchors.centerIn: parent; text: v.lk ? v.lk.user.substring(0, 1).toUpperCase() : ""; color: "white"; font.family: Theme.font; font.pixelSize: 44; font.weight: Font.Bold }
                Image {
                    id: ava; anchors.fill: parent; visible: false
                    source: v.lk && v.lk.avatar !== "" ? "file://" + v.lk.avatar : ""
                    fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(208, 208)
                }
                MultiEffect {
                    anchors.fill: parent; source: ava; visible: ava.status === Image.Ready
                    maskEnabled: true; maskSource: avaMask
                }
                Rectangle { id: avaMask; anchors.fill: parent; radius: 52; visible: false; layer.enabled: true }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: v.lk ? v.lk.user : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 22; font.weight: Font.DemiBold }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: v.lk ? v.lk.host + " · " + v.lk.kernel : ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
            Item { width: 1; height: 6 }
            Rectangle {
                width: parent.width; height: 48; radius: Theme.r(14)
                color: Theme.fill(0.08)
                border.width: 1.5; border.color: v.err ? Theme.red : (v.lk && v.lk.pass !== "" ? Theme.accent : Theme.line(0.25))
                LockDots { anchors.centerIn: parent; lk: v.lk; dot: 8; tone: v.err ? Theme.red : Theme.text }
                Text {
                    visible: v.lk && v.lk.pass === ""
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                    text: v.lk && v.lk.busy ? Tr.t("Проверка…") : Tr.t("Пароль")
                    color: Theme.sub; font.family: Theme.font; font.pixelSize: 14
                }
                Text { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: "󰌑"; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 16 }
            }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: !v.lk ? "" : (v.err ? v.lk.error + (v.lk.fails > 1 ? Tr.t(" · попыток: ") + v.lk.fails : "") : Tr.t("Enter — войти · Esc — очистить"))
                color: v.err ? Theme.red : Theme.sub; font.family: Theme.font; font.pixelSize: 12
            }
            LockStatus { anchors.horizontalCenter: parent.horizontalCenter; lk: v.lk; tone: Theme.text; fillA: 0.1 }
        }
        LockNotifs { maxCards: 2; cardW: side.width - 64; alpha: 0.3; anchors { horizontalCenter: parent.horizontalCenter; bottom: pwr.top; bottomMargin: 20 } }
        LockPower { id: pwr; lk: v.lk; size: 40; tone: Theme.text; fillA: 0.1; anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 30 } }
    }
}
