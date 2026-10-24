import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Quickshell.Io

// Бар NameLess UI на каждом экране: острова в материале комплекта.
//   слева   — знак, рабочие столы, окно
//   центр   — часы и плеер
//   справа  — трей · сеть, звук, яркость, батарея · уведомления, оформление, Пункт управления
Variants {
    id: bars
    model: Compositor.screens
    property var shell: null          // shell.qml: открытие панелей

    PanelWindow {
        id: bar
        required property var modelData
        screen: modelData
        anchors { top: true; left: true; right: true }
        implicitHeight: 42
        // ширина экрана в логических пикселях: 2 — обычный монитор, 1 — средний (планшет, окно), 0 — узкий (телефон как второй монитор): бар теряет второстепенное, а не налезает сам на себя
        readonly property int tier: width >= 1280 ? 2 : (width >= 900 ? 1 : 0)
        exclusiveZone: implicitHeight - 2
        color: "transparent"
        WlrLayershell.namespace: "nameless-bar"
        WlrLayershell.layer: WlrLayer.Top

        // меню значков трея: своё, с пунктами DBusMenu (нативное на панелях Wayland не принимает клики)
        TrayMenu { id: trayMenu }

        // ---------- слева ----------
        Row {
            anchors { left: parent.left; leftMargin: 8; top: parent.top; bottom: parent.bottom }
            spacing: 8

            Island {
                // знак NameLess: клик — лаунчер, правый клик — Пункт управления
                Item {
                    implicitWidth: logo.implicitWidth + 18
                    height: parent.height
                    Logo { id: logo; anchors.centerIn: parent; size: 20; wordmark: !Theme.ios && bar.tier > 0 }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (m) => m.button === Qt.RightButton ? bars.shell.toggleControl() : bars.shell.toggleLauncher()
                    }
                }

                // рабочие столы Hyprland
                Item {
                    visible: Compositor.hyprland
                    implicitWidth: wsRow.implicitWidth + 12
                    height: parent.height
                    Row {
                        id: wsRow
                        anchors.centerIn: parent
                        spacing: 4
                        Repeater {
                            model: Compositor.workspaces
                            Rectangle {
                                id: ws
                                required property var modelData
                                readonly property bool active: modelData.id === Compositor.activeWorkspace
                                width: active ? 30 : 22
                                height: 22
                                radius: Theme.r(Theme.ios ? 11 : 7)
                                color: active ? Theme.accent : (wsMa.containsMouse ? Theme.fill(0.14) : "transparent")
                                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 160 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: ws.modelData.id
                                    color: ws.active ? (Theme.glass ? "white" : Theme.crust) : Theme.sub
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                                MouseArea { id: wsMa; anchors.fill: parent; hoverEnabled: true; onClicked: Compositor.focusWorkspace(ws.modelData.id) }
                            }
                        }
                    }
                    WheelHandler { onWheel: (e) => Compositor.stepWorkspace(e.angleDelta.y > 0 ? -1 : 1) }
                }
                // driftwm и другие: бесконечный холст без рабочих столов
                BarItem { visible: !Compositor.hyprland; icon: "󰹞"; label: Tr.t("Холст") }
            }

            Island {
                visible: Compositor.activeTitle !== "" && bar.tier === 2
                BarItem {
                    icon: "󰖯"
                    iconColor: Theme.sub
                    label: Compositor.activeTitle.length > 42 ? Compositor.activeTitle.substring(0, 40) + "…" : Compositor.activeTitle
                }
            }
        }

        // ---------- центр: часы и плеер ----------
        Island {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; bottom: parent.bottom }

            BarItem {
                id: clock
                property date now: new Date()
                icon: "󰥔"
                iconColor: Theme.accent
                label: now.toLocaleString(Qt.locale("ru_RU"), Theme.ios ? "ddd d MMM  HH:mm" : "HH:mm")
                onClicked: Notifs.centerOpen = !Notifs.centerOpen
                // часы показывают минуты: просыпаться раз в секунду незачем — следующий тик точно на смене минуты
                Timer { id: clockT; interval: 1000; running: true; repeat: true; onTriggered: { clock.now = new Date(); interval = Math.max(500, 60500 - clock.now.getSeconds() * 1000 - clock.now.getMilliseconds()); } }
            }
            // мини-плеер: свёрнутый — название и пауза, по нажатию раскрывается: управление, время, перемотка
            MiniPlayer { compactHide: bar.tier < 2 }
            // лимит Claude Code (окно 5 часов): цвет по запасу; нажатие — монитор помощников. Включается в «Функции»
            BarItem {
                visible: AgentsData.barOn && AgentsData.util5 >= 0 && bar.tier > 0
                icon: "󰚩"
                iconColor: AgentsData.level(AgentsData.util5)
                label: Math.round(AgentsData.util5) + "%"
                onClicked: bars.shell.openAgents()
            }
        }

        // ---------- справа ----------
        Row {
            anchors { right: parent.right; rightMargin: 8; top: parent.top; bottom: parent.bottom }
            spacing: 8
            layoutDirection: Qt.RightToLeft

            // идёт запись экрана: время, клик — остановить
            Island {
                visible: Recorder.recording
                BarItem {
                    icon: "󰑋"
                    iconColor: Theme.red
                    label: Recorder.clock()
                    onClicked: Recorder.stop()
                    onRightClicked: Recorder.openFolder()
                }
            }

            // Orbit: значок связи с устройствами (скрывается в «Функции» → «Orbit в баре»)
            Island {
                visible: Config.store.orbit.bar !== false
                BarItem {
                    icon: "󰟀"
                    label: OrbitData.enabled && OrbitData.connected.length > 0 ? String(OrbitData.connected.length) : ""
                    iconColor: !OrbitData.enabled ? Theme.sub : (OrbitData.connected.length > 0 ? Theme.green : (OrbitData.requests > 0 ? Theme.yellow : Theme.text))
                    highlight: OrbitData.panelOpen
                    // клик — лента Orbit (выключен — сначала включается), правый клик — включить / выключить Orbit целиком
                    onClicked: { if (!OrbitData.enabled) OrbitData.setEnabled(true); else if (OrbitData.panelOpen) OrbitData.panelOpen = false; else bars.shell.openOrbit(); }
                    onRightClicked: OrbitData.toggleEnabled()
                }
            }

            Island {
                BarItem {
                    icon: "󰕮"
                    highlight: bars.shell.controlOpen
                    onClicked: bars.shell.toggleControl()
                }
                BarItem {
                    icon: "󰏘"
                    iconColor: Theme.accent2
                    onClicked: Quickshell.execDetached([Theme.script, "action", "drawer"])
                    onRightClicked: Quickshell.execDetached([Theme.script, "toggle"])
                }
                BarItem {
                    icon: Notifs.dnd ? "󰂛" : (Notifs.count > 0 ? "󱅫" : "󰂚")
                    label: Notifs.count > 0 ? String(Notifs.count) : ""
                    iconColor: Notifs.dnd ? Theme.sub : (Notifs.count > 0 ? Theme.accent : Theme.text)
                    highlight: Notifs.centerOpen
                    onClicked: Notifs.centerOpen = !Notifs.centerOpen
                    onRightClicked: Notifs.dnd = !Notifs.dnd
                }
            }

            Island {
                BarItem {
                    icon: Sys.wifiIcon
                    label: bar.tier < 2 || Sys.ssid === "" ? "" : (Sys.ssid.length > 14 ? Sys.ssid.substring(0, 13) + "…" : Sys.ssid)
                    iconColor: Theme.teal
                    onClicked: Sys.wifiMenu()
                    onRightClicked: Quickshell.execDetached(["nm-connection-editor"])
                }
                BarItem {
                    icon: Sound.icon
                    label: Sound.muted || bar.tier < 2 ? "" : Math.round(Sound.volume * 100) + "%"
                    iconColor: Sound.muted ? Theme.sub : Theme.text
                    onClicked: Sound.toggleMute()
                    // правый клик — своё окно звука, средний — pavucontrol
                    onRightClicked: bars.shell.toggleAudio()
                    onMiddleClicked: Quickshell.execDetached(["pavucontrol"])
                    onWheel: (d) => Sound.step(d * 0.05)
                }
                BarItem {
                    visible: Sys.brightness >= 0 && bar.tier === 2
                    icon: "󰃟"
                    label: Sys.brightness + "%"
                    iconColor: Theme.yellow
                    onWheel: (d) => Sys.setBrightness(Sys.brightness + d * 5)
                }
                BarItem {
                    visible: Sys.hasBattery
                    icon: Sys.batIcon
                    label: bar.tier === 0 ? "" : Sys.batPct + "%"
                    iconColor: Sys.batPct <= 15 && !Sys.charging ? Theme.red : (Sys.charging ? Theme.green : Theme.text)
                }
            }

            // счётчик кадров (по желанию: бар перерисовывается каждый кадр, пока он виден)
            Island {
                visible: Theme.th.fps_counter === true && bar.tier === 2
                BarItem {
                    id: fps
                    property int frames: 0
                    property int value: 0
                    property real hz: 0
                    icon: "󰓅"
                    iconColor: value >= hz * 0.9 ? Theme.green : (value >= hz * 0.5 ? Theme.yellow : Theme.red)
                    label: value + " FPS · " + Math.round(hz) + Tr.t(" Гц")
                    // замер — одна секунда из пяти: FrameAnimation заставляет бар перерисовываться каждый кадр монитора (165 раз в секунду),
                    // а с ним и размытие под баром; постоянный замер сам съедал заметную часть видеокарты
                    property bool measuring: false
                    FrameAnimation { running: fps.visible && fps.measuring; onTriggered: fps.frames++ }
                    Timer {
                        interval: fps.measuring ? 1000 : 4000; repeat: true; running: fps.visible; triggeredOnStart: true
                        onTriggered: {
                            if (fps.measuring) { fps.value = fps.frames; fps.measuring = false; }
                            else { fps.frames = 0; fps.measuring = true; }
                        }
                    }
                    Process {
                        running: fps.visible && Compositor.hyprland
                        command: ["hyprctl", "-j", "monitors"]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                try {
                                    var ms = JSON.parse(text);
                                    for (var i = 0; i < ms.length; i++) if (ms[i].name === bar.modelData.name) fps.hz = ms[i].refreshRate;
                                } catch (e) { }
                            }
                        }
                    }
                    onClicked: bars.shell.openDisplay()
                }
            }

            // трей
            Island {
                visible: SystemTray.items.values.length > 0 && bar.tier > 0
                pad: 10
                Row {
                    height: parent.height
                    spacing: 10
                    Repeater {
                        model: SystemTray.items
                        Item {
                            id: trayCell
                            required property var modelData
                            width: 18
                            height: parent.height
                            IconImage {
                                id: trayIcon
                                anchors.centerIn: parent
                                implicitSize: 17
                                source: trayCell.modelData.icon
                                scale: trayMa.pressed ? 0.85 : 1
                                Behavior on scale { NumberAnimation { duration: 120 } }
                            }
                            // левый клик — окно приложения (у значков без окна — меню), правый — меню,
                            // средний — второе действие, колесо — прокрутка значка (громкость и т. п.)
                            MouseArea {
                                id: trayMa
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (m) => {
                                    var it = trayCell.modelData;
                                    if (m.button === Qt.RightButton || (m.button === Qt.LeftButton && it.onlyMenu)) {
                                        if (it.hasMenu) trayMenu.show(it, trayIcon);
                                    } else if (m.button === Qt.MiddleButton) it.secondaryActivate();
                                    else it.activate();
                                }
                                onWheel: (wh) => trayCell.modelData.scroll(wh.angleDelta.y / 120, false)
                            }
                        }
                    }
                }
            }
        }
    }
}
