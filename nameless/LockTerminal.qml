import QtQuick

// Блокировка «Терминал»: экран-консоль — сведения о системе как у fastfetch, крупное время,
// вход строкой «sudo unlock» с мигающим курсором; ошибки — как у sudo
Item {
    id: v
    property var lk
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property color green: "#3ddc84"
    readonly property color dim: Qt.rgba(0.75, 0.85, 0.78, 0.55)

    Rectangle { anchors.fill: parent; color: "#070a08" }
    // едва заметные строки развёртки
    Canvas {
        anchors.fill: parent
        opacity: 0.05
        onPaint: { var ctx = getContext("2d"); ctx.reset(); ctx.fillStyle = "#ffffff"; for (var y = 0; y < height; y += 4) ctx.fillRect(0, y, width, 1); }
    }

    Column {
        anchors { left: parent.left; leftMargin: parent.width * 0.12; verticalCenter: parent.verticalCenter }
        spacing: 6

        Text {
            text: v.lk ? v.lk.now.toLocaleString(Qt.locale("ru_RU"), Config.lock.seconds ? "HH:mm:ss" : "HH:mm") : ""
            color: v.green; font.family: v.mono; font.pixelSize: 120; font.weight: Font.Bold
        }
        Text { text: v.lk ? "# " + v.lk.now.toLocaleString(Qt.locale("ru_RU"), "dddd, d MMMM yyyy") : ""; color: v.dim; font.family: v.mono; font.pixelSize: 16 }
        Item { width: 1; height: 18 }

        // сведения о системе
        Text { text: v.lk ? v.lk.user + "@" + v.lk.host : ""; color: v.green; font.family: v.mono; font.pixelSize: 17; font.weight: Font.Bold }
        Text { text: "─".repeat(32); color: v.dim; font.family: v.mono; font.pixelSize: 14 }
        Repeater {
            model: [
                [Tr.t("ядро"), v.lk ? v.lk.kernel : ""],
                [Tr.t("оболочка"), Compositor.name + " · NameLess UI"],
                [Tr.t("тема"), Theme.th.name || ""],
                [Tr.t("сеть"), Sys.ssid !== "" ? Sys.ssid + " (" + Sys.signal + "%)" : (Sys.wifiOn ? Tr.t("не подключено") : Tr.t("выкл."))],
                [Tr.t("батарея"), Sys.hasBattery ? Sys.batPct + "%" + (Sys.charging ? Tr.t(", заряжается") : "") : Tr.t("нет")],
                [Tr.t("раскладка"), v.lk ? v.lk.layout : ""],
                [Tr.t("уведомления"), Config.lock.notifs !== false ? String(Notifs.count) : Tr.t("скрыты")]
            ]
            Row {
                required property var modelData
                Text { width: 150; text: modelData[0]; color: v.green; font.family: v.mono; font.pixelSize: 15 }
                Text { text: modelData[1]; color: "#d8e6dc"; font.family: v.mono; font.pixelSize: 15 }
            }
        }
        Item { width: 1; height: 22 }

        // вход
        Row {
            Text { text: v.lk ? v.lk.user + "@" + v.lk.host + " " : ""; color: v.green; font.family: v.mono; font.pixelSize: 17; font.weight: Font.Bold }
            Text { text: "~ ❯ "; color: "#7aa2f7"; font.family: v.mono; font.pixelSize: 17; font.weight: Font.Bold }
            Text { text: "sudo unlock"; color: "#d8e6dc"; font.family: v.mono; font.pixelSize: 17 }
        }
        Row {
            Text { text: v.lk ? Tr.t("[sudo] пароль для ") + v.lk.user + ": " : ""; color: "#d8e6dc"; font.family: v.mono; font.pixelSize: 17 }
            Text { text: v.lk ? "•".repeat(Math.min(32, v.lk.pass.length)) : ""; color: v.green; font.family: v.mono; font.pixelSize: 17 }
            Rectangle {
                width: 10; height: 20
                anchors.verticalCenter: parent.verticalCenter
                color: v.green
                SequentialAnimation on opacity { running: v.lk ? v.lk.locked : false; loops: Animation.Infinite; NumberAnimation { to: 0; duration: 500 } NumberAnimation { to: 1; duration: 500 } }
            }
        }
        Text {
            visible: text !== ""
            text: !v.lk ? "" : (v.lk.busy ? Tr.t("проверка…") : (v.lk.error !== "" ? Tr.t("Извините, попробуйте ещё раз.") + (v.lk.fails > 1 ? " (" + v.lk.fails + Tr.t(" неверных)") : "")
                                                           : (v.lk.caps ? Tr.t("внимание: включён Caps Lock") : "")))
            color: v.lk && v.lk.error !== "" ? "#ff6b6b" : "#e0c060"
            font.family: v.mono; font.pixelSize: 15
        }
    }
    // питание — команды
    Row {
        anchors { right: parent.right; rightMargin: 40; bottom: parent.bottom; bottomMargin: 30 }
        spacing: 24
        Repeater {
            model: [["suspend", "systemctl suspend"], ["reboot", "reboot"], ["poweroff", "poweroff"]]
            Text {
                required property var modelData
                text: "[ " + modelData[1] + " ]"
                color: tma.containsMouse ? v.green : v.dim
                font.family: v.mono; font.pixelSize: 13
                MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: v.lk.power(parent.modelData[0]) }
            }
        }
    }
}
