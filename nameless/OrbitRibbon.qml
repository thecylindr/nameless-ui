import QtQuick
import Quickshell
import Quickshell.Wayland

// Лента Orbit: выезжает справа — устройства из NameLess Orbit, запросы на сопряжение с кодом (подтверждение — здесь же),
// подключение по IP, «найти», буфер обмена. Данные и команды — OrbitData (D-Bus); окно Orbit для этого не нужно
PanelWindow {
    id: w
    property var shell: null
    property real progress: 0
    Component.onCompleted: progress = Qt.binding(function () { return OrbitData.panelOpen ? 1 : 0; })
    Behavior on progress { NumberAnimation { duration: Theme.dur(OrbitData.panelOpen); easing.type: Easing.OutCubic } }

    visible: progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-orbit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: OrbitData.panelOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * 0.5 * w.progress }
    MouseArea { anchors.fill: parent; onClicked: OrbitData.panelOpen = false }

    Surface {
        id: panel
        alpha: Theme.overlayAlpha
        width: 380
        height: parent.height - 60
        x: parent.width - width - 10 + (1 - w.progress) * 60
        y: 50
        opacity: w.progress
        radius: Theme.ios ? 28 : 20
        MouseArea { anchors.fill: parent }
        focus: OrbitData.panelOpen
        Keys.onEscapePressed: OrbitData.panelOpen = false

        // ---------- шапка ----------
        Row {
            id: head
            x: 18; y: 16
            width: parent.width - 36
            spacing: 12
            Text { text: "󰟀"; color: OrbitData.running ? Theme.accent : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 30; anchors.verticalCenter: parent.verticalCenter }
            Column {
                width: parent.width - 42 - closeBtn.width
                anchors.verticalCenter: parent.verticalCenter
                Text { text: Tr.t("Устройства"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.ios ? 24 : 20; font.weight: Font.Bold }
                Text {
                    text: !OrbitData.running ? Tr.t("Orbit не запущен") : (OrbitData.connected.length > 0 ? Tr.t("Подключено: ") + OrbitData.connected.length : (OrbitData.discovery ? Tr.t("Поиск включён") : Tr.t("Поиск выключен")))
                    color: Theme.sub; font.family: Theme.font; font.pixelSize: 12
                }
            }
            GButton { id: closeBtn; ui: Theme; width: 36; height: 36; implicitWidth: 36; label: ""; icon: "󰅖"; onClicked: OrbitData.panelOpen = false }
        }

        // не запущен: одна крупная кнопка
        Column {
            visible: !OrbitData.running
            anchors.centerIn: parent
            spacing: 14
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰟀"; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 56 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Tr.t("NameLess Orbit не запущен"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 13 }
            GButton { ui: Theme; anchors.horizontalCenter: parent.horizontalCenter; implicitWidth: 150; label: Tr.t("Запустить"); icon: "󰐊"; on: true; onClicked: { OrbitData.launched = false; OrbitData.autoLaunch(); } }
        }

        Flickable {
            visible: OrbitData.running
            anchors { top: head.bottom; topMargin: 14; bottom: foot.top; bottomMargin: 10; left: parent.left; right: parent.right; leftMargin: 18; rightMargin: 18 }
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: body
                width: parent.width
                spacing: 10

                // запросы на сопряжение: код нужно сверить с экраном второго устройства
                Repeater {
                    model: OrbitData.reqs
                    Rectangle {
                        id: rq
                        required property var modelData
                        width: body.width; height: rcol.implicitHeight + 24
                        radius: 16
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                        border.width: 1; border.color: Theme.accent
                        Column {
                            id: rcol
                            x: 14; y: 12
                            width: parent.width - 28
                            spacing: 8
                            Text { width: parent.width; elide: Text.ElideRight; text: (rq.modelData.outgoing ? Tr.t("Ждём подтверждения: ") : Tr.t("Сопряжение: ")) + rq.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { text: [rq.modelData.model, rq.modelData.address].filter(function (x) { return x; }).join(" · "); visible: text !== ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                            Text { text: rq.modelData.code; color: Theme.accent; font.family: "monospace"; font.pixelSize: 26; font.weight: Font.Bold; font.letterSpacing: 4 }
                            Text { text: Tr.t("Сверьте код с экраном второго устройства"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                            Row {
                                spacing: 8
                                GButton { ui: Theme; height: 32; implicitWidth: 110; label: Tr.t("Сопрячь"); icon: "󰄬"; on: true; onClicked: OrbitData.accept(rq.modelData.deviceId) }
                                GButton { ui: Theme; height: 32; implicitWidth: 110; label: Tr.t("Отклонить"); onClicked: OrbitData.reject(rq.modelData.deviceId) }
                            }
                        }
                    }
                }

                Text {
                    visible: OrbitData.devices.length === 0
                    width: parent.width; wrapMode: Text.WordWrap; topPadding: 20
                    horizontalAlignment: Text.AlignHCenter
                    text: OrbitData.discovery ? Tr.t("Пока никого рядом.\nОткройте Orbit на телефоне в этой же сети.") : Tr.t("Поиск выключен — включите его внизу.")
                    color: Theme.sub; font.family: Theme.font; font.pixelSize: 13
                }

                Repeater {
                    model: OrbitData.devices
                    Rectangle {
                        id: dv
                        required property var modelData
                        width: body.width; height: 72 + (expanded && cmds.length > 0 ? chips.implicitHeight + 14 : 0)
                        property bool expanded: false
                        readonly property var cmds: modelData.commands || []
                        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Item { id: head72; width: parent.width; height: 72 }
                        radius: 16
                        color: Qt.rgba(1, 1, 1, dvMa.containsMouse ? 0.10 : 0.05)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        MouseArea { id: dvMa; anchors.fill: parent; hoverEnabled: true; onClicked: if (dv.cmds.length > 0) dv.expanded = !dv.expanded }
                        Rectangle {
                            id: dvi
                            x: 12; anchors.verticalCenter: head72.verticalCenter
                            width: 38; height: 38; radius: 19
                            color: dv.modelData.online ? Theme.accent : Qt.rgba(1, 1, 1, 0.08)
                            Text { anchors.centerIn: parent; text: OrbitData.kindIcon(dv.modelData.kind); color: dv.modelData.online ? "white" : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 18 }
                            // звенья цепочки: устройство подключено (гаснут сами, возвращаются при наведении)
                            LinkBadge {
                                x: parent.width - 12; y: parent.height - 12
                                linked: dv.modelData.online
                                key: dv.modelData.deviceId + ":" + OrbitData.connected.length
                                hover: dvMa.containsMouse
                            }
                        }
                        Column {
                            anchors { left: dvi.right; leftMargin: 12; right: dacts.left; rightMargin: 6; verticalCenter: head72.verticalCenter }
                            Text { width: parent.width; elide: Text.ElideRight; text: dv.modelData.name || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: [dv.modelData.model, dv.modelData.address, dv.cmds.length > 0 ? dv.cmds.length + Tr.t(" команд ›") : ""].filter(function (x) { return x; }).join(" · ")
                                color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: dv.modelData.online ? Tr.t("󰌷 подключено") + (dv.modelData.battery >= 0 ? " · 󰁹 " + dv.modelData.battery + "%" + (dv.modelData.charging ? " ⚡" : "") : "") : (dv.modelData.connecting ? Tr.t("подключение…") : (dv.modelData.paired ? Tr.t("сопряжено · не подключено") : Tr.t("рядом · не сопряжено")))
                                color: dv.modelData.online && dv.modelData.battery >= 0 && dv.modelData.battery < 20 && !dv.modelData.charging ? Theme.red : Theme.sub
                                font.family: Theme.iconFont; font.pixelSize: 11
                            }
                        }
                        // быстрые команды этого устройства: нажатие запускает, список ведёт само устройство
                        Flow {
                            id: chips
                            visible: dv.expanded && dv.cmds.length > 0
                            x: 12; y: 76
                            width: parent.width - 24
                            spacing: 6
                            Repeater {
                                model: dv.cmds
                                Rectangle {
                                    required property var modelData
                                    width: chipText.implicitWidth + 22; height: 28; radius: 14
                                    color: chipMa.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Qt.rgba(1, 1, 1, 0.09)
                                    Text { id: chipText; anchors.centerIn: parent; text: parent.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 11 }
                                    MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: OrbitData.runCommand(dv.modelData.deviceId, parent.modelData.id) }
                                }
                            }
                        }

                        Row {
                            id: dacts
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: head72.verticalCenter }
                            spacing: 4
                            Repeater {
                                model: dv.modelData.online ? [{ i: "󰍉", a: "ring" }, { i: "󰆏", a: "clip" }, { i: "󰈔", a: "file" }, { i: "󰹑", a: "view" }].concat((dv.modelData.remoteCapabilities || []).indexOf("secondScreen") >= 0 ? [{ i: "󰍺", a: "second" }] : []) : (dv.modelData.connecting ? [] : [{ i: "󰌘", a: "connect" }])
                                Rectangle {
                                    required property var modelData
                                    width: 32; height: 32; radius: 16
                                    color: abMa.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.07)
                                    Text { anchors.centerIn: parent; text: parent.modelData.i; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 15 }
                                    MouseArea {
                                        id: abMa
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var id = dv.modelData.deviceId;
                                            if (parent.modelData.a === "ring") OrbitData.ring(id);
                                            else if (parent.modelData.a === "clip") OrbitData.sendClipboard(id);
                                            else if (parent.modelData.a === "file") OrbitData.sendFile(id);
                                            else if (parent.modelData.a === "view") { OrbitData.panelOpen = false; OrbitData.viewScreen(id); }
                                            else if (parent.modelData.a === "second") { OrbitData.panelOpen = false; OrbitData.secondScreen(id); }
                                            else OrbitData.connectTo(id);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---------- низ: подключение по адресу и действия ----------
        Column {
            id: foot
            visible: OrbitData.running
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 18; rightMargin: 18; bottomMargin: 16 }
            spacing: 10

            Row {
                width: parent.width
                spacing: 8
                Rectangle {
                    width: parent.width - 8 - addrBtn.width; height: 36; radius: 18
                    color: Qt.rgba(1, 1, 1, 0.07); border.width: 1; border.color: addr.activeFocus ? Theme.accent : Theme.line(0.16)
                    TextInput {
                        id: addr
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text; selectByMouse: true; clip: true
                        font.family: Theme.font; font.pixelSize: 13
                        onAccepted: addrBtn.go()
                        Text { visible: addr.text === "" && !addr.activeFocus; anchors.verticalCenter: parent.verticalCenter; text: Tr.t("IP-адрес устройства"); color: Theme.sub; font: addr.font }
                    }
                }
                GButton {
                    id: addrBtn
                    ui: Theme; height: 36; implicitWidth: 96; label: Tr.t("Связать"); icon: "󰌘"; on: addr.text.trim() !== ""
                    function go() { if (addr.text.trim() !== "") { OrbitData.connectAddress(addr.text.trim(), 17894); addr.text = ""; } }
                    onClicked: go()
                }
            }
            Row {
                spacing: 8
                GButton { ui: Theme; height: 34; implicitWidth: 120; label: Tr.t("Открыть Orbit"); icon: "󰏌"; on: true; onClicked: { OrbitData.show(); OrbitData.panelOpen = false; } }
                GButton { ui: Theme; height: 34; implicitWidth: 100; label: OrbitData.discovery ? Tr.t("Стоп") : Tr.t("Искать"); onClicked: OrbitData.setDiscovery(!OrbitData.discovery) }
                GButton { ui: Theme; height: 34; implicitWidth: 44; label: ""; icon: "󰑐"; onClicked: OrbitData.scan() }
            }
        }
    }
}
