import QtQuick

// Блокировка «Циферблат»: большие стрелочные часы на размытых обоях, дата в окошке, поле пароля под ними
Item {
    id: v
    property var lk
    readonly property date t: v.lk ? v.lk.now : new Date()

    LockBg { anchors.fill: parent; lk: v.lk; blur: 0.8; dim: 0.45 }

    Item {
        id: face
        width: 380; height: 380
        anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: -80 }
        Rectangle {
            anchors.fill: parent; radius: width / 2
            color: Qt.rgba(1, 1, 1, 0.07)
            border.width: 1.5; border.color: Qt.rgba(1, 1, 1, 0.25)
        }
        // деления: 60 штрихов, часовые — длиннее
        Repeater {
            model: 60
            Rectangle {
                id: tick
                required property int index
                readonly property bool hour: index % 5 === 0
                x: face.width / 2 - width / 2; y: 12
                width: hour ? 4 : 1.5; height: hour ? 20 : 9; radius: width / 2
                color: Qt.rgba(1, 1, 1, hour ? 0.85 : 0.35)
                transform: Rotation { origin.x: tick.width / 2; origin.y: face.height / 2 - 12; angle: tick.index * 6 }
            }
        }
        // окошко даты
        Rectangle {
            x: face.width * 0.66; anchors.verticalCenter: parent.verticalCenter
            width: dateT.implicitWidth + 14; height: 26; radius: 6
            color: Qt.rgba(0, 0, 0, 0.35); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.2)
            Text { id: dateT; anchors.centerIn: parent; text: v.t.toLocaleString(Qt.locale("ru_RU"), "ddd d").toUpperCase(); color: "white"; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: face.height * 0.26 }
            text: v.lk ? v.lk.host : ""
            color: Qt.rgba(1, 1, 1, 0.45); font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: 2
        }
        Hand { len: 0.27; w: 7; c: "white"; angle: (v.t.getHours() % 12 + v.t.getMinutes() / 60) * 30 }
        Hand { len: 0.39; w: 4.5; c: "white"; angle: (v.t.getMinutes() + v.t.getSeconds() / 60) * 6 }
        Hand { visible: Config.lock.seconds !== false; len: 0.43; w: 2; c: Theme.accent; angle: v.t.getSeconds() * 6; tail: 26 }
        Rectangle { anchors.centerIn: parent; width: 14; height: 14; radius: 7; color: Theme.accent; border.width: 3; border.color: "white" }
    }

    Column {
        anchors { horizontalCenter: parent.horizontalCenter; top: face.bottom; topMargin: 34 }
        spacing: 12
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: v.t.toLocaleString(Qt.locale("ru_RU"), "d MMMM yyyy, dddd")
            color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.font; font.pixelSize: 15
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 300; height: 44; radius: 22
            color: Qt.rgba(1, 1, 1, 0.12)
            border.width: 1; border.color: v.lk && v.lk.error !== "" ? "#ff8a8a" : Qt.rgba(1, 1, 1, 0.3)
            LockDots { anchors.centerIn: parent; lk: v.lk; dot: 8; tone: v.lk && v.lk.error !== "" ? "#ff8a8a" : "white" }
            Text {
                visible: v.lk && v.lk.pass === ""
                anchors.centerIn: parent
                text: v.lk && v.lk.busy ? Tr.t("Проверка…") : (v.lk && v.lk.error !== "" ? v.lk.error : Tr.t("Пароль для ") + (v.lk ? v.lk.user : ""))
                color: v.lk && v.lk.error !== "" ? "#ffb4ab" : Qt.rgba(1, 1, 1, 0.6); font.family: Theme.font; font.pixelSize: 13
            }
        }
        LockStatus { anchors.horizontalCenter: parent.horizontalCenter; lk: v.lk }
    }

    LockPower { lk: v.lk; size: 40; anchors { right: parent.right; rightMargin: 32; bottom: parent.bottom; bottomMargin: 28 } }

    // стрелка от центра; tail — хвост за центром
    component Hand: Rectangle {
        id: hand
        property real len: 0.3
        property real w: 4
        property color c: "white"
        property real angle: 0
        property real tail: 14
        x: face.width / 2 - width / 2; y: face.height / 2 - height + tail
        width: w; height: face.width * len + tail; radius: w / 2
        color: c
        antialiasing: true
        transform: Rotation { origin.x: hand.width / 2; origin.y: hand.height - hand.tail; angle: hand.angle }
    }
}
