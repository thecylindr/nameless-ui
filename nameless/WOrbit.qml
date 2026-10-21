import QtQuick
import Quickshell

// Устройства: NameLess Orbit — кто подключён (заряд батареи) и кто рядом. Кнопки у строки: «найти», «буфер обмена»,
// «подключить». Запрос на сопряжение с кодом подтверждается здесь же; «Лента» — выезжающая панель, «Orbit» — окно программы.
// Разрешения для устройств — в окне Orbit. Данные — OrbitData (D-Bus)
WCard {
    id: w
    readonly property var list: OrbitData.devices.slice(0, 4)
    readonly property bool off: !OrbitData.enabled
    readonly property bool up: OrbitData.enabled && OrbitData.running
    readonly property var req: OrbitData.reqs.length > 0 ? OrbitData.reqs[0] : null
    implicitHeight: pad * 2 + 30 + (off ? 44 : up ? (list.length > 0 ? list.length * 40 + 8 : 22) + 40 + (req ? 78 : 0) : 44)

    Row {
        id: head
        width: parent.width
        spacing: 10
        Text { text: "󰟀"; color: w.up ? Theme.accent : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 24; anchors.verticalCenter: parent.verticalCenter }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
                text: w.off ? Tr.t("Orbit выключен") : (!OrbitData.loaded ? Tr.t("Устройства…") : (!w.up ? Tr.t("Orbit не запущен") : (OrbitData.connected.length > 0 ? Tr.t("Подключено: ") + OrbitData.connected.length : Tr.t("Устройства"))))
                color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold
            }
            Text {
                text: w.off ? Tr.t("нажмите, чтобы включить") : !w.up ? Tr.t("нажмите, чтобы запустить") : (OrbitData.requests > 0 ? Tr.t("Запрос на сопряжение: ") + OrbitData.requests : (OrbitData.discovery ? Tr.t("поиск включён") : Tr.t("поиск выключен")))
                color: OrbitData.requests > 0 ? Theme.yellow : Theme.sub; font.family: Theme.font; font.pixelSize: 11
            }
        }
    }

    Column {
        visible: w.up
        anchors { top: head.bottom; topMargin: 8 }
        width: parent.width
        spacing: 0
        // запрос на сопряжение: код сверяется с экраном второго устройства
        Rectangle {
            visible: w.req !== null
            width: parent.width; height: 70; radius: 14
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
            border.width: 1; border.color: Theme.accent
            Column {
                x: 12; y: 8
                // после «Сопрячь» карточка сразу говорит, что ждём второе устройство, и сколько осталось
                Text { text: !w.req ? "" : (w.req.localAccepted ? Tr.t("Ждём ") + w.req.name + " · " + OrbitData.secondsLeft(w.req) + Tr.t(" с") : (w.req.remoteAccepted ? w.req.name + Tr.t(" уже подтвердил") : w.req.name)); color: w.req && w.req.remoteAccepted && !w.req.localAccepted ? Theme.green : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                Text { text: w.req ? w.req.code : ""; color: Theme.accent; font.family: "monospace"; font.pixelSize: 20; font.weight: Font.Bold; font.letterSpacing: 3 }
            }
            Row {
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                spacing: 6
                GButton { visible: w.req !== null && !w.req.localAccepted; ui: Theme; height: 30; implicitWidth: 40; label: ""; icon: "󰄬"; on: true; onClicked: OrbitData.accept(w.req.deviceId) }
                GButton { ui: Theme; height: 30; implicitWidth: 40; label: ""; icon: "󰅖"; onClicked: OrbitData.reject(w.req.deviceId) }
            }
        }
        Text {
            visible: w.list.length === 0
            width: parent.width; height: 22
            text: OrbitData.discovery ? Tr.t("Пока никого рядом") : Tr.t("Включите поиск")
            color: Theme.sub; font.family: Theme.font; font.pixelSize: 12
        }
        Repeater {
            model: w.list
            Item {
                id: row
                required property var modelData
                width: parent.width; height: 40
                Text { id: ic; anchors.verticalCenter: parent.verticalCenter; text: OrbitData.kindIcon(row.modelData.kind); color: row.modelData.online ? Theme.green : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 18 }
                Column {
                    anchors { left: ic.right; leftMargin: 10; right: acts.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    Text { width: parent.width; elide: Text.ElideRight; text: row.modelData.name || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: (row.modelData.address ? row.modelData.address + " · " : "") + (row.modelData.online ? Tr.t("󰌷 подключено") + (row.modelData.battery >= 0 ? " · " + row.modelData.battery + "%" + (row.modelData.charging ? Tr.t(" · заряжается") : "") : "")) : (row.modelData.pairing ? Tr.t("ждёт сопряжения") : row.modelData.paired ? Tr.t("сопряжено · не подключено") : Tr.t("рядом · не сопряжено")))
                        color: row.modelData.online && row.modelData.battery >= 0 && row.modelData.battery < 20 && !row.modelData.charging ? Theme.red : Theme.sub
                        font.family: Theme.font; font.pixelSize: 11
                    }
                }
                Row {
                    id: acts
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Repeater {
                        model: row.modelData.online ? [{ i: "󰍉", a: "ring" }, { i: "󰆏", a: "clip" }] : (row.modelData.connecting || row.modelData.pairing ? [] : [{ i: "󰌘", a: "connect" }])
                        Rectangle {
                            required property var modelData
                            width: 30; height: 30; radius: 15
                            color: ma.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                            Text { anchors.centerIn: parent; text: parent.modelData.i; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 14 }
                            MouseArea {
                                id: ma
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var id = row.modelData.deviceId;
                                    if (parent.modelData.a === "ring") OrbitData.ring(id);
                                    else if (parent.modelData.a === "clip") OrbitData.sendClipboard(id);
                                    else OrbitData.connectTo(id);
                                }
                            }
                        }
                    }
                }
            }
        }
        Row {
            topPadding: 8
            spacing: 6
            GButton { ui: Theme; height: 30; implicitWidth: 92; label: Tr.t("Лента"); icon: "󰏌"; on: true; onClicked: OrbitData.panelOpen = true }
            GButton { ui: Theme; height: 30; implicitWidth: 84; label: "Orbit"; onClicked: OrbitData.show() }
            GButton { ui: Theme; height: 30; implicitWidth: 84; label: OrbitData.discovery ? Tr.t("Стоп") : Tr.t("Искать"); onClicked: OrbitData.discovery ? OrbitData.setDiscovery(false) : OrbitData.setDiscovery(true) }
            GButton { ui: Theme; height: 30; implicitWidth: 40; label: ""; icon: "󰑐"; onClicked: OrbitData.scan() }
        }
    }
    MouseArea { visible: !w.up; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (w.off) OrbitData.setEnabled(true); else OrbitData.launch(); } }
}
