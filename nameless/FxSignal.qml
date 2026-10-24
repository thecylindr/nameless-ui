import QtQuick
import Quickshell
import Quickshell.Wayland

// Сигналы событий: у каждого положительного события есть отрицательная пара, и обе видны одинаково заметно.
//   good — подключилось / появилось: зелёный круг вырастает с кольцами-волнами, галочка
//   bad  — разрыв / пропало: красный круг с крестом, плашка вздрагивает, линия под ней рвётся пополам, осколки разлетаются,
//          по верху экрана — короткая красная вспышка
// События: Orbit (устройство подключилось / связь разорвана), Wi-Fi (подключено / потеряно), Bluetooth (устройство подключено / отключено),
// питание (зарядка подключена / отключена). Первые 5 с после запуска молчат — иначе загрузка состояния выглядела как поток событий.
// Настройки — Config.store.signals: enabled, good (показывать и положительные), sources { orbit, wifi, bt, power }.
// Окно без ввода (mask пустая), существует только пока идёт сигнал
Scope {
    id: fx
    readonly property var cfg: Config.store.signals || ({})
    readonly property var src: cfg.sources || ({})
    property bool armed: false
    Timer { running: true; interval: 5000; onTriggered: fx.armed = true }

    property var queue: []
    property var cur: null                  // { bad, icon, title, sub, n }
    property int seq: 0
    function push(bad, kind, icon, title, sub) {
        if (!armed || cfg.enabled === false || src[kind] === false) return;
        if (!bad && cfg.good === false) return;
        // повтор того же события подряд (дребезг связи) не копится: остаётся последнее
        var q = queue.filter(function (e) { return e.title !== title; });
        if (q.length >= 4) q = q.slice(q.length - 3);
        q.push({ bad: bad, icon: icon, title: title, sub: sub || "" });
        queue = q;
        if (cur === null && !gapT.running) gapT.restart();
    }
    // между сигналами окно закрывается и открывается заново: анимации каждого сигнала идут с начала
    function next() {
        cur = null;
        if (queue.length > 0) gapT.restart();
    }
    Timer {
        id: gapT; interval: 140
        onTriggered: { var q = fx.queue.slice(), e = q.shift(); fx.queue = q; e.n = ++fx.seq; fx.cur = e; }
    }

    // пример из настроек и ipc: без задержки запуска и фильтров источников
    function preview(bad) {
        queue = queue.concat([bad ? { bad: true, icon: "󰅖", title: Tr.t("Связь разорвана: телефон"), sub: Tr.t("Orbit — устройство пропало") }
                                  : { bad: false, icon: "󰄬", title: Tr.t("Подключено: телефон"), sub: Tr.t("Orbit — устройство на связи") }]);
        if (cur === null && !gapT.running) gapT.restart();
    }

    // ---------- источники ----------
    // Orbit: новое устройство в списке — подключилось; пропавшее — разрыв
    property var orbitKnown: ({})
    Connections {
        target: OrbitData
        function onConnectedChanged() {
            var now = {}, i;
            for (i = 0; i < OrbitData.connected.length; i++) now[OrbitData.connected[i].deviceId] = OrbitData.connected[i];
            for (var id in now) if (!fx.orbitKnown[id]) fx.push(false, "orbit", "󰄬", Tr.t("Подключено: ") + now[id].name, Tr.t("Orbit — устройство на связи"));
            for (var old in fx.orbitKnown) if (!now[old]) fx.push(true, "orbit", "󰅖", Tr.t("Связь разорвана: ") + fx.orbitKnown[old].name, Tr.t("Orbit — устройство пропало"));
            fx.orbitKnown = now;
        }
    }
    // Wi-Fi: сеть появилась / пропала (выключение Wi-Fi вручную — тоже разрыв, но с другой подписью)
    property string lastSsid: ""
    Connections {
        target: Sys
        function onSsidChanged() {
            if (Sys.ssid !== "" && Sys.ssid !== fx.lastSsid) fx.push(false, "wifi", "󰤨", Tr.t("Wi-Fi: ") + Sys.ssid, Tr.t("сеть подключена"));
            else if (Sys.ssid === "" && fx.lastSsid !== "") fx.push(true, "wifi", "󰤭", Tr.t("Wi-Fi: ") + fx.lastSsid, Sys.wifiOn ? Tr.t("соединение потеряно") : Tr.t("Wi-Fi выключен"));
            fx.lastSsid = Sys.ssid;
        }
        function onBtDeviceChanged() {
            if (Sys.btDevice !== "" && Sys.btDevice !== fx.lastBt) fx.push(false, "bt", "󰂱", Sys.btDevice, Tr.t("Bluetooth подключён"));
            else if (Sys.btDevice === "" && fx.lastBt !== "") fx.push(true, "bt", "󰂲", fx.lastBt, Tr.t("Bluetooth отключён"));
            fx.lastBt = Sys.btDevice;
        }
        function onChargingChanged() {
            if (!Sys.hasBattery) return;
            if (Sys.charging) fx.push(false, "power", "󰂄", Tr.t("Зарядка подключена"), Sys.batPct + "%");
            else fx.push(true, "power", "󰚦", Tr.t("Зарядка отключена"), Sys.batPct + "%");
        }
    }
    property string lastBt: ""
    Component.onCompleted: { lastSsid = Sys.ssid; lastBt = Sys.btDevice; }

    // ---------- окно сигнала ----------
    LazyLoader {
        active: fx.cur !== null
        PanelWindow {
            id: win
            readonly property var e: fx.cur || ({})
            readonly property bool bad: e.bad === true
            readonly property color tone: bad ? Theme.red : Theme.green
            readonly property bool rich: !Perf.eco && (Config.store.crossing || {}).reducedMotion !== true
            screen: Compositor.mainScreen
            anchors { top: true; left: true; right: true }
            implicitHeight: 190
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.namespace: "nameless-signal"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // красная вспышка по верху экрана: только у разрыва
            Rectangle {
                visible: win.bad && win.rich
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 120
                opacity: 0
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.45) }
                    GradientStop { position: 1; color: "transparent" }
                }
                SequentialAnimation on opacity {
                    running: win.bad && win.rich
                    NumberAnimation { to: 1; duration: 90 }
                    NumberAnimation { to: 0; duration: 650; easing.type: Easing.OutCubic }
                }
            }

            Item {
                id: stage
                anchors.horizontalCenter: parent.horizontalCenter
                y: 54
                width: pill.width; height: pill.height
                opacity: 0
                property real shake: 0
                transform: Translate { x: stage.shake }

                // плашка
                Surface {
                    id: pill
                    width: Math.min(win.width - 40, row.implicitWidth + 36)
                    height: 58; radius: 29
                    shadow: false
                    Rectangle {
                        anchors.fill: parent; radius: Theme.r(29); color: "transparent"
                        border.width: 1.5; border.color: Qt.rgba(win.tone.r, win.tone.g, win.tone.b, 0.7)
                    }
                    Row {
                        id: row
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        // значок: круг цвета события, волны (good) или крест с поворотом (bad)
                        Item {
                            width: 36; height: 36
                            anchors.verticalCenter: parent.verticalCenter
                            Repeater {
                                model: win.rich ? 2 : 0
                                Rectangle {
                                    id: ring
                                    required property int index
                                    anchors.centerIn: parent
                                    width: 36; height: 36; radius: 18
                                    color: "transparent"; border.width: 2; border.color: win.tone
                                    opacity: 0
                                    SequentialAnimation {
                                        running: true
                                        PauseAnimation { duration: 120 + ring.index * 180 }
                                        ParallelAnimation {
                                            NumberAnimation { target: ring; property: "scale"; from: 1; to: win.bad ? 1.9 : 2.3; duration: 700; easing.type: Easing.OutCubic }
                                            NumberAnimation { target: ring; property: "opacity"; from: 0.8; to: 0; duration: 700 }
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                id: disc
                                anchors.centerIn: parent
                                width: 36; height: 36; radius: 18
                                color: win.tone
                                scale: 0.3
                                NumberAnimation on scale { to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                                Text {
                                    anchors.centerIn: parent
                                    text: win.e.icon || (win.bad ? "󰅖" : "󰄬")
                                    color: "white"; font.family: Theme.iconFont; font.pixelSize: 19
                                    rotation: win.bad ? -90 : 0
                                    NumberAnimation on rotation { running: win.bad; to: 0; duration: 420; easing.type: Easing.OutBack }
                                }
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                width: Math.min(implicitWidth, win.width - 140); elide: Text.ElideRight
                                text: win.e.title || ""; color: Theme.text
                                font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                            }
                            Text {
                                visible: text !== ""
                                width: Math.min(implicitWidth, win.width - 140); elide: Text.ElideRight
                                text: win.e.sub || ""; color: win.bad ? Theme.red : Theme.sub
                                font.family: Theme.font; font.pixelSize: 11
                            }
                        }
                    }
                }

                // «разрыв»: линия под плашкой рвётся пополам, половинки разъезжаются и гаснут
                Item {
                    id: rip
                    visible: win.bad
                    anchors { top: pill.bottom; topMargin: 10; horizontalCenter: pill.horizontalCenter }
                    width: pill.width * 0.7; height: 3
                    Rectangle {
                        id: halfL
                        width: parent.width / 2 - 2; height: 3; radius: 1.5; color: Theme.red
                        transformOrigin: Item.Right
                    }
                    Rectangle {
                        id: halfR
                        x: parent.width / 2 + 2
                        width: parent.width / 2 - 2; height: 3; radius: 1.5; color: Theme.red
                        transformOrigin: Item.Left
                    }
                    SequentialAnimation {
                        running: win.bad
                        PauseAnimation { duration: 260 }
                        ParallelAnimation {
                            NumberAnimation { target: halfL; property: "x"; to: -36; duration: 520; easing.type: Easing.OutCubic }
                            NumberAnimation { target: halfL; property: "rotation"; to: -9; duration: 520; easing.type: Easing.OutCubic }
                            NumberAnimation { target: halfR; property: "x"; to: rip.width / 2 + 38; duration: 520; easing.type: Easing.OutCubic }
                            NumberAnimation { target: halfR; property: "rotation"; to: 9; duration: 520; easing.type: Easing.OutCubic }
                            NumberAnimation { target: halfL; property: "opacity"; to: 0; duration: 900 }
                            NumberAnimation { target: halfR; property: "opacity"; to: 0; duration: 900 }
                        }
                    }
                    // осколки из места разрыва
                    Repeater {
                        model: win.bad && win.rich ? 7 : 0
                        Rectangle {
                            id: shard
                            required property int index
                            readonly property real ang: (-150 + index * 20) * Math.PI / 180
                            x: rip.width / 2 - 2; y: -1
                            width: 4 + (index % 3); height: width; color: index % 2 ? Theme.red : Qt.lighter(Theme.red, 1.3)
                            rotation: index * 37
                            opacity: 0
                            SequentialAnimation {
                                running: true
                                PauseAnimation { duration: 260 }
                                ParallelAnimation {
                                    NumberAnimation { target: shard; property: "opacity"; from: 1; to: 0; duration: 700 }
                                    NumberAnimation { target: shard; property: "x"; to: rip.width / 2 + Math.cos(shard.ang) * (40 + shard.index * 7); duration: 700; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: shard; property: "y"; to: Math.sin(shard.ang) * (26 + shard.index * 3) + 30; duration: 700; easing.type: Easing.InQuad }
                                    NumberAnimation { target: shard; property: "rotation"; to: shard.index * 37 + 260; duration: 700 }
                                }
                            }
                        }
                    }
                }

                // появление, вздрагивание (bad), пауза, уход
                SequentialAnimation {
                    running: true
                    ParallelAnimation {
                        NumberAnimation { target: stage; property: "opacity"; to: 1; duration: 200 }
                        NumberAnimation { target: stage; property: "y"; from: 30; to: 54; duration: 320; easing.type: Easing.OutCubic }
                    }
                    // вздрагивание только у разрыва (у положительного — нулевая длительность)
                    SequentialAnimation {
                        NumberAnimation { target: stage; property: "shake"; to: win.bad && win.rich ? 11 : 0; duration: win.bad && win.rich ? 50 : 0 }
                        NumberAnimation { target: stage; property: "shake"; to: win.bad && win.rich ? -9 : 0; duration: win.bad && win.rich ? 70 : 0 }
                        NumberAnimation { target: stage; property: "shake"; to: win.bad && win.rich ? 6 : 0; duration: win.bad && win.rich ? 70 : 0 }
                        NumberAnimation { target: stage; property: "shake"; to: win.bad && win.rich ? -3 : 0; duration: win.bad && win.rich ? 60 : 0 }
                        NumberAnimation { target: stage; property: "shake"; to: 0; duration: win.bad && win.rich ? 60 : 0 }
                    }
                    PauseAnimation { duration: win.bad ? 2400 : 1900 }
                    ParallelAnimation {
                        NumberAnimation { target: stage; property: "opacity"; to: 0; duration: 260 }
                        NumberAnimation { target: stage; property: "y"; to: 36; duration: 260; easing.type: Easing.InCubic }
                    }
                    ScriptAction { script: fx.next() }
                }
            }
        }
    }
}
