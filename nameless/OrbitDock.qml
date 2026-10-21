import QtQuick
import Quickshell
import Quickshell.Wayland

// Верхний док Orbit: «таблетка» под баром с подключёнными устройствами (значок вида и значок ссылки — подключено; заряд в подсказке). Появляется, пока есть
// подключённые устройства или ждёт запрос на сопряжение; нажатие открывает ленту. Выключается в «Функции» → «Док Orbit»; «Orbit в нижнем доке» переносит её в док приложений.
// Остальная часть окна сквозная (mask), поэтому работе у верхнего края не мешает
PanelWindow {
    id: w
    property var shell: null
    // Таблетка не висит постоянно: появляется аккуратно, когда подключилось новое устройство или пришёл запрос на сопряжение, и сама исчезает
    // через несколько секунд (пока на ней курсор — остаётся). Устройства всегда доступны из бара, нижнего дока и ленты Orbit
    property bool recent: false
    property var known: ({})                                 // устройства, о которых таблетка уже сообщала
    property string hint: ""
    readonly property bool hovered: hint !== ""
    readonly property bool want: OrbitData.enabled && OrbitData.dockOn && Config.store.orbit.indock !== true && OrbitData.running
                                 && (OrbitData.requests > 0 || ((recent || hovered) && OrbitData.connected.length > 0)) && !OrbitData.panelOpen
    Timer { id: hideT; interval: 6500; running: w.recent && !w.hovered; onTriggered: w.recent = false }
    Connections {
        target: OrbitData
        function onConnectedChanged() {
            var now = {}, fresh = false;
            for (var i = 0; i < OrbitData.connected.length; i++) {
                var id = OrbitData.connected[i].deviceId;
                now[id] = true;
                if (!w.known[id]) fresh = true;                  // новое подключение (в том числе повторное после обрыва)
            }
            w.known = now;
            if (fresh) { w.recent = true; hideT.restart(); }
        }
    }

    visible: pill.opacity > 0.01
    anchors { top: true }
    margins { top: 46 }
    implicitWidth: pill.width + 40
    implicitHeight: pill.height + 40
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-orbitdock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: pill }

    Surface {
        id: pill
        x: 20
        y: 8 + (w.want ? 0 : -14)
        width: row.implicitWidth + 20
        height: 50
        radius: 25
        alpha: Theme.overlayAlpha
        opacity: w.want ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.dur(w.want) } }
        Behavior on y { NumberAnimation { duration: Theme.dur(w.want); easing.type: Easing.OutCubic } }

        Row {
            id: row
            x: 10
            height: parent.height
            spacing: 6

            // запрос на сопряжение: мигающая жёлтая точка со счётчиком
            Item {
                visible: OrbitData.requests > 0
                width: 38; height: parent.height
                Rectangle {
                    id: pulse
                    anchors.centerIn: parent
                    width: 36; height: 36; radius: 18
                    color: Qt.rgba(Theme.yellow.r, Theme.yellow.g, Theme.yellow.b, 0.22)
                    border.width: 1.5; border.color: Theme.yellow
                    SequentialAnimation on opacity {
                        running: w.want && OrbitData.requests > 0
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.45; duration: 700 }
                        NumberAnimation { to: 1; duration: 700 }
                    }
                    Text { anchors.centerIn: parent; text: "󰌾"; color: Theme.yellow; font.family: Theme.iconFont; font.pixelSize: 17 }
                }
                MouseArea {
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onEntered: w.hint = Tr.t("Запрос на сопряжение")
                    onExited: w.hint = ""
                    onClicked: OrbitData.panelOpen = true
                }
            }

            Repeater {
                model: OrbitData.connected
                Item {
                    id: it
                    required property var modelData
                    readonly property real bat: modelData.battery
                    width: 38; height: row.height
                    Rectangle {
                        id: circ
                        anchors.centerIn: parent
                        width: ma.containsMouse ? 40 : 36; height: width; radius: width / 2
                        color: ma.containsMouse ? Theme.accent : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.30)
                        Behavior on width { NumberAnimation { duration: 120 } }
                        Text { anchors.centerIn: parent; text: OrbitData.kindIcon(it.modelData.kind); color: "white"; font.family: Theme.iconFont; font.pixelSize: 17 }
                    }
                    // звенья цепочки в углу: устройство подключено (значок сам гаснет через несколько секунд, возвращается при наведении)
                    LinkBadge {
                        x: circ.x + circ.width - 12; y: circ.y + circ.height - 12
                        key: it.modelData.deviceId + ":" + OrbitData.connected.length
                        hover: ma.containsMouse
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onEntered: w.hint = it.modelData.name + (it.bat >= 0 ? " · " + it.bat + "%" + (it.modelData.charging ? " ⚡" : "") : "")
                        onExited: w.hint = ""
                        onClicked: OrbitData.panelOpen = true
                    }
                }
            }
        }
    }

    // подпись при наведении — под таблеткой (вне маски: нажатий не ловит)
    Text {
        visible: w.hint !== "" && w.want
        anchors { horizontalCenter: pill.horizontalCenter; top: pill.bottom; topMargin: 8 }
        text: w.hint
        color: Theme.text; font.family: Theme.font; font.pixelSize: 12
        style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.5)
    }
}
