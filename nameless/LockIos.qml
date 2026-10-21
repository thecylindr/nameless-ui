import QtQuick
import Quickshell
import Quickshell.Widgets

// Блокировка «iOS»: сверху дата и крупное время с глубиной, под ним — плашки состояния; уведомления и плеер;
// внизу — подсказка и полоска «домой». Любая клавиша или клик — ввод: фон сильнее размывается, аватар и кружки
Item {
    id: v
    property var lk
    readonly property bool auth: lk && (lk.awake || lk.pass !== "" || lk.error !== "")

    LockBg { anchors.fill: parent; lk: v.lk; blur: v.auth ? 0.95 : 0.25; dim: v.auth ? 0.3 : 0.1
        Behavior on blur { NumberAnimation { duration: 300 } } }
    Rectangle { anchors.fill: parent; gradient: Gradient { GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.25) } GradientStop { position: 0.45; color: "transparent" } GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.35) } } }

    // строка состояния
    Row {
        anchors { right: parent.right; rightMargin: 30; top: parent.top; topMargin: 18 }
        spacing: 14
        Text { visible: v.lk && v.lk.layout !== ""; text: v.lk ? v.lk.layout.substring(0, 2).toUpperCase() : ""; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold
               MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: v.lk.nextLayout() } }
        Text { text: Sys.wifiIcon; color: "white"; font.family: Theme.iconFont; font.pixelSize: 15 }
        Text { visible: Sys.hasBattery; text: Sys.batPct + "% " + Sys.batIcon; color: "white"; font.family: Theme.iconFont; font.pixelSize: 14 }
    }
    Text { anchors { left: parent.left; leftMargin: 30; top: parent.top; topMargin: 18 } text: "󰌾"; color: "white"; font.family: Theme.iconFont; font.pixelSize: 16 }

    // время
    Column {
        id: clock
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * (v.auth ? 0.08 : 0.1) }
        Behavior on anchors.topMargin { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        scale: v.auth ? 0.82 : 1
        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: v.lk ? v.lk.now.toLocaleString(Qt.locale("ru_RU"), "dddd, d MMMM") : ""
            color: Qt.rgba(1, 1, 1, 0.9); font.family: Theme.font; font.pixelSize: 22; font.weight: Font.DemiBold; font.capitalization: Font.Capitalize
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: v.lk ? v.lk.now.toLocaleString(Qt.locale("ru_RU"), Config.lock.seconds ? "HH:mm:ss" : "HH:mm") : ""
            color: "white"; font.family: Theme.font; font.pixelSize: 150; font.weight: Font.Bold; font.letterSpacing: -5
            font.features: { "tnum": 1 }
            style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.18)
        }
    }

    // ----- «сон»: уведомления и плеер -----
    Column {
        visible: !v.auth
        anchors { horizontalCenter: parent.horizontalCenter; top: clock.bottom; topMargin: 24 }
        spacing: 12
        opacity: v.auth ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 200 } }
        PlayerCard {
            visible: Config.lock.player !== false && has
            width: 420; implicitHeight: 186; radius: 26
        }
        LockNotifs { cardW: 420; radius: 22 }
    }
    Column {
        visible: !v.auth
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
        spacing: 14
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Tr.t("Начните вводить пароль или нажмите для разблокировки"); color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.font; font.pixelSize: 13 }
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 140; height: 5; radius: 2.5; color: "white"; opacity: 0.85 }
    }
    // кнопки по углам, как фонарик и камера
    LockPower { visible: !v.auth; lk: v.lk; size: 50; fillA: 0.18; anchors { left: parent.left; leftMargin: 40; bottom: parent.bottom; bottomMargin: 40 } }

    // ----- ввод -----
    Column {
        visible: v.auth
        opacity: v.auth ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
        anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: parent.height * 0.08 }
        spacing: 18
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96; height: 96
            Rectangle {
                anchors.fill: parent; radius: width / 2
                gradient: Gradient { GradientStop { position: 0; color: Theme.accent } GradientStop { position: 1; color: Theme.accent2 } }
                Text { anchors.centerIn: parent; visible: !v.lk || v.lk.avatar === ""; text: v.lk ? v.lk.user.charAt(0).toUpperCase() : ""; color: "white"; font.family: Theme.font; font.pixelSize: 40; font.weight: Font.Bold }
            }
            ClippingRectangle {
                visible: v.lk && v.lk.avatar !== ""
                anchors.fill: parent; radius: width / 2
                Image { anchors.fill: parent; source: v.lk && v.lk.avatar !== "" ? "file://" + v.lk.avatar : ""; fillMode: Image.PreserveAspectCrop }
            }
        }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: v.lk ? (v.lk.busy ? Tr.t("Проверка…") : Tr.t("Введите пароль")) : ""; color: "white"; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold }
        LockDots { anchors.horizontalCenter: parent.horizontalCenter; lk: v.lk; dot: 14; hollowWhenEmpty: true; slots: 6 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: !v.lk ? "" : (v.lk.error !== "" ? v.lk.error + (v.lk.fails > 1 ? Tr.t(" · попыток: ") + v.lk.fails : "") : (v.lk.caps ? "󰪛  Caps Lock" : Tr.t("Enter — войти · Esc — отмена")))
            color: v.lk && v.lk.error !== "" ? "#ffb4ab" : Qt.rgba(1, 1, 1, 0.6)
            font.family: Theme.iconFont; font.pixelSize: 13
        }
    }
    Text {
        visible: v.auth
        anchors { right: parent.right; rightMargin: 40; bottom: parent.bottom; bottomMargin: 34 }
        text: Tr.t("Отмена"); color: "white"; font.family: Theme.font; font.pixelSize: 16
        MouseArea { anchors.fill: parent; anchors.margins: -10; cursorShape: Qt.PointingHandCursor; onClicked: { v.lk.pass = ""; v.lk.awake = false; } }
    }
}
