import QtQuick
import Quickshell
import Quickshell.Wayland

// Лента Orbit: выезжает справа — устройства из NameLess Orbit, запросы на сопряжение с кодом (подтверждение — здесь же),
// подключение по IP, «найти», буфер обмена. Данные и команды — OrbitData (D-Bus); окно Orbit для этого не нужно
PanelWindow {
    id: w
    screen: Compositor.panelScreen
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
        width: 400
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
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: OrbitData.launchState === "starting" ? Tr.t("Запускаем Orbit…") : Tr.t("NameLess Orbit не запущен"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 13 }
            Text {
                visible: OrbitData.launchState === "failed"
                width: 300; anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: OrbitData.launchError; color: Theme.red; font.family: Theme.font; font.pixelSize: 12
            }
            GButton {
                ui: Theme; anchors.horizontalCenter: parent.horizontalCenter; implicitWidth: 170
                enabled: OrbitData.launchState !== "starting"
                label: OrbitData.launchState === "starting" ? Tr.t("Запуск…") : (OrbitData.launchFix === "restart" ? Tr.t("Перезапустить") : (OrbitData.launchFix === "window" ? Tr.t("Открыть окно") : Tr.t("Запустить")))
                icon: OrbitData.launchFix === "restart" ? "󰑓" : "󰐊"; on: true
                onClicked: {
                    if (OrbitData.launchFix === "window") OrbitData.launch();
                    else OrbitData.start(OrbitData.launchFix === "restart");
                }
            }
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

                // запросы на сопряжение: код сверяется с экраном второго устройства, «Сопрячь» нажимают на обоих.
                // Состояния карточки: ждём вас → второе устройство уже согласилось → вы согласились, ждём его (с отсчётом до отмены)
                Repeater {
                    model: OrbitData.reqs
                    Rectangle {
                        id: rq
                        required property var modelData
                        readonly property bool mine: rq.modelData.localAccepted === true
                        readonly property bool theirs: rq.modelData.remoteAccepted === true
                        readonly property int secs: OrbitData.secondsLeft(rq.modelData)
                        width: body.width; height: rcol.implicitHeight + 24
                        radius: 16
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, rq.mine ? 0.08 : 0.14)
                        border.width: 1; border.color: rq.theirs && !rq.mine ? Theme.green : Theme.accent
                        Column {
                            id: rcol
                            x: 14; y: 12
                            width: parent.width - 28
                            spacing: 8
                            Row {
                                width: parent.width
                                spacing: 8
                                Text { id: rqIc; anchors.verticalCenter: parent.verticalCenter; text: OrbitData.kindIcon(rq.modelData.kind); color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 18 }
                                Text {
                                    width: parent.width - rqIc.width - rqLeft.width - 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    text: (rq.modelData.outgoing ? Tr.t("Сопряжение с ") : Tr.t("Запрос на сопряжение: ")) + rq.modelData.name
                                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                                }
                                Text { id: rqLeft; anchors.verticalCenter: parent.verticalCenter; text: rq.secs + Tr.t(" с"); color: rq.secs < 20 ? Theme.red : Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                            }
                            Text { text: [rq.modelData.model, rq.modelData.address].filter(function (x) { return x; }).join(" · "); visible: text !== ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                            Text { text: rq.modelData.code; color: Theme.accent; font.family: "monospace"; font.pixelSize: 26; font.weight: Font.Bold; font.letterSpacing: 4; opacity: rq.mine ? 0.6 : 1 }
                            // отсчёт до автоматической отмены (Orbit держит запрос 90 секунд)
                            Rectangle {
                                width: parent.width; height: 3; radius: 2
                                color: Qt.rgba(1, 1, 1, 0.08)
                                Rectangle { width: parent.width * Math.min(1, rq.secs / 90); height: parent.height; radius: 2; color: rq.secs < 20 ? Theme.red : Theme.accent; Behavior on width { NumberAnimation { duration: 900 } } }
                            }
                            Row {
                                spacing: 8
                                width: parent.width
                                Text {
                                    id: rqSpin
                                    visible: rq.mine
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰑓"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 14
                                    RotationAnimation on rotation { running: rqSpin.visible && OrbitData.panelOpen; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                                }
                                Text {
                                    width: parent.width - (rq.mine ? rqSpin.width + 8 : 0)
                                    wrapMode: Text.WordWrap
                                    text: rq.mine ? Tr.t("Вы подтвердили. Нажмите «Сопрячь» на ") + rq.modelData.name + Tr.t(" — код должен совпасть")
                                          : (rq.theirs ? rq.modelData.name + Tr.t(" уже подтвердил — сверьте код и нажмите «Сопрячь»")
                                                       : Tr.t("Сверьте код с экраном второго устройства и подтвердите на обоих"))
                                    color: rq.theirs && !rq.mine ? Theme.green : Theme.sub; font.family: Theme.font; font.pixelSize: 11
                                }
                            }
                            Row {
                                spacing: 8
                                width: parent.width
                                GButton {
                                    visible: !rq.mine
                                    ui: Theme; height: 34; width: (parent.width - 8) / 2
                                    label: Tr.t("Сопрячь"); icon: "󰄬"; on: true
                                    onClicked: OrbitData.accept(rq.modelData.deviceId)
                                }
                                GButton {
                                    ui: Theme; height: 34; width: rq.mine ? parent.width : (parent.width - 8) / 2
                                    label: rq.mine ? Tr.t("Отменить") : Tr.t("Отклонить"); icon: "󰅖"
                                    onClicked: OrbitData.reject(rq.modelData.deviceId)
                                }
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

                // устройства по группам: на связи — сверху, с подписанными действиями; сопряжённые — с кнопкой «Подключить»; рядом — «Сопрячь»
                Repeater {
                    model: [
                        { t: Tr.t("На связи"), list: OrbitData.devices.filter(function (d) { return d.online; }) },
                        { t: Tr.t("Сопряжённые"), list: OrbitData.devices.filter(function (d) { return !d.online && d.paired; }) },
                        { t: Tr.t("Рядом"), list: OrbitData.devices.filter(function (d) { return !d.online && !d.paired; }) }
                    ]
                    Column {
                        id: grp
                        required property var modelData
                        visible: grp.modelData.list.length > 0
                        width: body.width
                        spacing: 8
                        Text { text: grp.modelData.t + " · " + grp.modelData.list.length; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6; leftPadding: 4 }
                        Repeater {
                            model: grp.modelData.list
                            DeviceCard { width: grp.width }
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
                        Text { visible: addr.text === "" && !addr.activeFocus; anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Подключить по IP, например 192.168.1.5"); color: Theme.sub; font: addr.font }
                    }
                }
                GButton {
                    id: addrBtn
                    ui: Theme; height: 36; implicitWidth: 112; label: Tr.t("Подключить"); icon: "󰌘"; on: addr.text.trim() !== ""
                    function go() { if (addr.text.trim() !== "") { OrbitData.connectAddress(addr.text.trim(), 17894); addr.text = ""; } }
                    onClicked: go()
                }
            }
            // три подписанные кнопки поровну: поиск — переключатель (подсвечен, пока включён), обновить список, окно Orbit
            Row {
                id: acts
                width: parent.width
                spacing: 8
                readonly property real third: (width - spacing * 2) / 3
                GButton { ui: Theme; height: 36; width: acts.third; implicitWidth: acts.third; label: Tr.t("Поиск"); icon: OrbitData.discovery ? "󰍉" : "󰍊"; on: OrbitData.discovery; onClicked: OrbitData.setDiscovery(!OrbitData.discovery) }
                GButton { ui: Theme; height: 36; width: acts.third; implicitWidth: acts.third; label: Tr.t("Обновить"); icon: "󰑐"; onClicked: OrbitData.scan() }
                GButton { ui: Theme; height: 36; width: acts.third; implicitWidth: acts.third; label: "Orbit"; icon: "󰏌"; onClicked: { OrbitData.show(); OrbitData.panelOpen = false; } }
            }
        }
    }
}
