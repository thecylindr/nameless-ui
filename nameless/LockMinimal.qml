import QtQuick

// Блокировка «Минимал»: затемнённые обои, подпись «Экран заблокирован», время и дата, поле пароля с подсказкой;
// кнопки питания появляются при наведении в правый нижний угол
Item {
    id: v
    property var lk

    LockBg { anchors.fill: parent; lk: v.lk; blur: 0.6; dim: 0.55 }

    Column {
        anchors.centerIn: parent
        spacing: 10
        // что это за экран: без этого минимальный вид было непонятно, чего он ждёт
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Tr.t("󰌾  Экран заблокирован")
            color: Qt.rgba(1, 1, 1, 0.7); font.family: Theme.iconFont; font.pixelSize: 14; font.letterSpacing: 1
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: v.lk ? v.lk.now.toLocaleString(Qt.locale("ru_RU"), Config.lock.seconds ? "HH:mm:ss" : "HH:mm") : ""
            color: "white"; font.family: Theme.font; font.pixelSize: 72; font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: v.lk ? v.lk.now.toLocaleString(Qt.locale("ru_RU"), "d MMMM, dddd") : ""
            color: Qt.rgba(1, 1, 1, 0.6); font.family: Theme.font; font.pixelSize: 14
        }
        Item { width: 1; height: 22 }
        // поле пароля: рамка, точки или подсказка
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 300; height: 44; radius: 22
            color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1.5
            border.color: v.lk && v.lk.error !== "" ? "#ff8a8a" : Qt.rgba(1, 1, 1, v.lk && v.lk.pass !== "" ? 0.6 : 0.3)
            LockDots { anchors.centerIn: parent; lk: v.lk; dot: 8; tone: v.lk && v.lk.error !== "" ? "#ff8a8a" : "white" }
            Text {
                visible: v.lk && v.lk.pass === ""
                anchors.centerIn: parent
                text: v.lk && v.lk.busy ? Tr.t("Проверка…") : Tr.t("Введите пароль")
                color: Qt.rgba(1, 1, 1, 0.55); font.family: Theme.font; font.pixelSize: 14
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: !v.lk ? "" : (v.lk.error !== "" ? v.lk.error + (v.lk.fails > 1 ? Tr.t(" · попыток: ") + v.lk.fails : "")
                                                  : Tr.t("Enter — войти · Esc — очистить"))
            color: v.lk && v.lk.error !== "" ? "#ffb4ab" : (v.lk && v.lk.caps ? Theme.yellow : Qt.rgba(1, 1, 1, 0.45))
            font.family: Theme.iconFont; font.pixelSize: 12
        }
        LockStatus { anchors.horizontalCenter: parent.horizontalCenter; lk: v.lk; fillA: 0.08 }
    }
    Item {
        anchors { right: parent.right; bottom: parent.bottom }
        width: 220; height: 110
        HoverHandler { id: corner }
        LockPower { lk: v.lk; size: 36; fillA: 0.1; opacity: corner.hovered ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 200 } }
                    anchors { right: parent.right; rightMargin: 28; bottom: parent.bottom; bottomMargin: 26 } }
    }
}
