import QtQuick

// Карточка устройства в ленте Orbit (OrbitRibbon).
// шапка: значок, имя, модель и адрес, состояние «пилюлей» (цвет — на связи / подключается / нет), заряд;
// на связи — плитки действий с подписями и подсказка, что делает наведённая; иначе — одна понятная кнопка
Rectangle {
    id: dv
    required property var modelData
    readonly property bool online: modelData.online === true
    readonly property bool busy: modelData.connecting === true || modelData.pairing === true
    // батарея — только у тех, у кого она бывает (телефон, планшет, ноутбук); у ПК старые версии Orbit присылали 0 %
    readonly property bool hasBattery: modelData.battery >= 0 && ["phone", "tablet", "laptop"].indexOf(modelData.kind) >= 0
    readonly property var media: online ? (modelData.media || null) : null
    readonly property var cmds: modelData.commands || []
    property bool showCmds: false
    property string hint: ""
    readonly property var acts: {
        var caps = modelData.remoteCapabilities || [];
        var a = [
            { i: "󰍉", t: Tr.t("Найти"), a: "ring", h: Tr.t("Устройство зазвонит, даже если звук выключен") },
            { i: "󰆏", t: Tr.t("Буфер"), a: "clip", h: Tr.t("Отправить скопированный текст или картинку") },
            { i: "󰈔", t: Tr.t("Файл"), a: "file", h: Tr.t("Выбрать файл и отправить на устройство") },
            { i: "󰹑", t: Tr.t("Его экран"), a: "view", h: Tr.t("Посмотреть экран устройства и управлять им") },
            { i: "󰍹", t: Tr.t("Мой экран"), a: "share", h: Tr.t("Показать этот экран на устройстве") }
        ];
        if (caps.indexOf("secondScreen") >= 0) a.push({ i: "󰍺", t: Tr.t("2-й экран"), a: "second", h: Tr.t("Этот компьютер станет вторым монитором устройства") });
        if (cmds.length > 0) a.push({ i: "󰘳", t: Tr.t("Команды"), a: "cmds", h: Tr.t("Быстрые команды, которые ведёт само устройство") });
        return a;
    }
    function run(a) {
        var id = modelData.deviceId;
        if (a === "ring") OrbitData.ring(id);
        else if (a === "clip") OrbitData.sendClipboard(id);
        else if (a === "file") OrbitData.sendFile(id);
        else if (a === "view") { OrbitData.panelOpen = false; OrbitData.viewScreen(id); }
        else if (a === "share") { OrbitData.panelOpen = false; OrbitData.shareScreen(id); }
        else if (a === "second") { OrbitData.panelOpen = false; OrbitData.secondScreen(id); }
        else if (a === "cmds") showCmds = !showCmds;
    }

    height: col.implicitHeight + 24
    radius: 18
    color: Qt.rgba(1, 1, 1, dvMa.containsMouse ? 0.09 : 0.05)
    border.width: 1
    border.color: online ? Qt.rgba(Theme.green.r, Theme.green.g, Theme.green.b, 0.35) : Theme.line(0.10)
    Behavior on color { ColorAnimation { duration: 120 } }
    MouseArea { id: dvMa; anchors.fill: parent; hoverEnabled: true }

    Column {
        id: col
        x: 12; y: 12
        width: parent.width - 24
        spacing: 10

        // шапка
        Item {
            width: parent.width; height: 44
            Rectangle {
                id: dvi
                width: 44; height: 44; radius: 14
                color: dv.online ? Theme.accent : Qt.rgba(1, 1, 1, 0.08)
                Text { anchors.centerIn: parent; text: OrbitData.kindIcon(dv.modelData.kind); color: dv.online ? "white" : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 20 }
                LinkBadge {
                    x: parent.width - 12; y: parent.height - 12
                    linked: dv.online
                    key: dv.modelData.deviceId + ":" + OrbitData.connected.length
                    hover: dvMa.containsMouse
                }
            }
            Column {
                anchors { left: dvi.right; leftMargin: 12; right: pill.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                spacing: 2
                Text { width: parent.width; elide: Text.ElideRight; text: dv.modelData.name || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: [dv.modelData.model, dv.modelData.address].filter(function (x) { return x; }).join(" · ")
                    color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
                }
            }
            // состояние
            Rectangle {
                id: pill
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                height: 24; radius: 12
                width: pillRow.implicitWidth + 18
                readonly property color c: dv.online ? Theme.green : (dv.busy ? Theme.accent : Theme.sub)
                color: Qt.rgba(c.r, c.g, c.b, 0.14)
                Row {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle { width: 7; height: 7; radius: 4; color: pill.c; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: dv.online ? ((dv.hasBattery ? "󰁹 " + dv.modelData.battery + "%" + (dv.modelData.charging ? " ⚡" : "") : Tr.t("на связи")) + (dv.modelData.brightness >= 0 ? "  󰃠 " + dv.modelData.brightness + "%" : ""))
                              : (dv.modelData.pairing ? Tr.t("сопряжение") : (dv.modelData.connecting ? Tr.t("подключение…") : (dv.modelData.paired ? Tr.t("не на связи") : Tr.t("рядом"))))
                        color: dv.online && dv.hasBattery && dv.modelData.battery < 20 && !dv.modelData.charging ? Theme.red : Theme.text
                        font.family: Theme.iconFont; font.pixelSize: 11
                    }
                }
            }
        }

        // что играет на устройстве: обложка, трек, приложение, прогресс (досчитывается от момента получения), кнопки

        Rectangle {

            id: mp

            visible: dv.media !== null

            width: parent.width; height: 74; radius: 14

            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10)

            readonly property var m: dv.media || ({})

            property real now: Date.now()

            Timer { interval: 1000; repeat: true; running: mp.visible && mp.m.playing === true && OrbitData.panelOpen; onTriggered: mp.now = Date.now() }

            readonly property real pos: (mp.m.pos || 0) + (mp.m.playing ? Math.max(0, mp.now - (mp.m.at || mp.now)) : 0)

            function fmt(ms) { var t = Math.floor(ms / 1000); return Math.floor(t / 60) + ":" + ("0" + t % 60).slice(-2); }

            Rectangle {

                id: art

                x: 10; anchors.verticalCenter: parent.verticalCenter

                width: 54; height: 54; radius: 10

                color: Theme.fill(0.10); clip: true

                Image { anchors.fill: parent; source: mp.m.art || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; visible: status === Image.Ready }

                Text { anchors.centerIn: parent; visible: !mp.m.art; text: "󰎆"; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 22 }

            }

            Column {

                anchors { left: art.right; leftMargin: 10; right: ctl.left; rightMargin: 6; verticalCenter: parent.verticalCenter }

                spacing: 2

                Text { width: parent.width; elide: Text.ElideRight; text: mp.m.title || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }

                Text { width: parent.width; elide: Text.ElideRight; text: [mp.m.artist, mp.m.app].filter(function (x) { return x; }).join(" · "); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }

                Item {

                    visible: (mp.m.len || 0) > 0

                    width: parent.width; height: 12

                    Rectangle {

                        anchors.verticalCenter: parent.verticalCenter; width: parent.width - 66; height: 3; radius: 2; color: Theme.fill(0.15)

                        Rectangle { width: parent.width * Math.min(1, mp.pos / Math.max(1, mp.m.len)); height: parent.height; radius: 2; color: Theme.accent }

                    }

                    Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: mp.fmt(Math.min(mp.pos, mp.m.len)) + " / " + mp.fmt(mp.m.len); color: Theme.sub; font.family: Theme.font; font.pixelSize: 9; font.features: { "tnum": 1 } }

                }

            }

            Row {

                id: ctl

                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }

                spacing: 2

                Repeater {

                    model: [["󰒮", "previous"], [mp.m.playing ? "󰏤" : "󰐊", "playpause"], ["󰒭", "next"]]

                    Rectangle {

                        required property var modelData

                        width: 30; height: 30; radius: 15

                        color: mcMa.containsMouse ? Theme.fill(0.16) : "transparent"

                        Text { anchors.centerIn: parent; text: parent.modelData[0]; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: parent.modelData[1] === "playpause" ? 18 : 15 }

                        MouseArea { id: mcMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: OrbitData.mediaCommand(dv.modelData.deviceId, parent.modelData[1]) }

                    }

                }

            }

        }


        // на связи: плитки действий с подписями
        Grid {
            visible: dv.online
            width: parent.width
            columns: 4
            spacing: 6
            readonly property real cw: (width - spacing * (columns - 1)) / columns
            Repeater {
                model: dv.online ? dv.acts : []
                Rectangle {
                    id: tile
                    required property var modelData
                    width: parent.cw; height: 54; radius: 12
                    readonly property bool active: tile.modelData.a === "cmds" && dv.showCmds
                    color: tMa.pressed ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                         : (tMa.containsMouse || tile.active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : Qt.rgba(1, 1, 1, 0.06))
                    Column {
                        anchors.centerIn: parent
                        spacing: 3
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.i; color: tMa.containsMouse || tile.active ? Theme.accent : Theme.text; font.family: Theme.iconFont; font.pixelSize: 18 }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.t; color: Theme.text; font.family: Theme.font; font.pixelSize: 10 }
                    }
                    MouseArea {
                        id: tMa
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: dv.hint = containsMouse ? tile.modelData.h : (dv.hint === tile.modelData.h ? "" : dv.hint)
                        onClicked: dv.run(tile.modelData.a)
                    }
                }
            }
        }
        // что делает наведённая плитка
        Text {
            visible: dv.online
            width: parent.width; elide: Text.ElideRight
            text: dv.hint !== "" ? dv.hint : Tr.t("Наведите на действие — здесь появится подсказка")
            color: dv.hint !== "" ? Theme.text : Theme.sub; opacity: dv.hint !== "" ? 1 : 0.6
            font.family: Theme.font; font.pixelSize: 11
        }
        // быстрые команды устройства
        Flow {
            visible: dv.online && dv.showCmds && dv.cmds.length > 0
            width: parent.width
            spacing: 6
            Repeater {
                model: dv.showCmds ? dv.cmds : []
                Rectangle {
                    required property var modelData
                    width: chipText.implicitWidth + 22; height: 28; radius: 14
                    color: chipMa.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Qt.rgba(1, 1, 1, 0.09)
                    Text { id: chipText; anchors.centerIn: parent; text: parent.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 11 }
                    MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: OrbitData.runCommand(dv.modelData.deviceId, parent.modelData.id) }
                }
            }
        }
        // на связи — отключить; не на связи — одна понятная кнопка
        Row {
            width: parent.width
            spacing: 8
            GButton {
                visible: !dv.online && !dv.busy
                ui: Theme; height: 34; width: parent.width
                label: dv.modelData.paired ? Tr.t("Подключить") : Tr.t("Подключить и сопрячь"); icon: "󰌘"; on: true
                onClicked: OrbitData.connectTo(dv.modelData.deviceId)
            }
            Text {
                visible: dv.busy
                width: parent.width; height: 34; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                text: dv.modelData.pairing ? Tr.t("Ждёт подтверждения сопряжения — см. запрос выше") : Tr.t("Подключаемся…")
                color: Theme.sub; font.family: Theme.font; font.pixelSize: 12
            }
            GButton {
                visible: dv.online
                ui: Theme; height: 30; width: parent.width
                label: Tr.t("Отключить"); icon: "󰌙"
                onClicked: OrbitData.disconnectFrom(dv.modelData.deviceId)
            }
        }
    }
}
