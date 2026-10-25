import QtQuick
import Quickshell
import Quickshell.Wayland

// Сигналы событий: у каждого положительного события есть отрицательная пара, и обе видны одинаково заметно.
//   Плашка — «связь»: слева устройство, справа этот компьютер (или сеть, наушники, розетка), между ними линия.
//   good   — линия срастается от краёв к середине, в месте встречи — зелёная галочка с волнами
//   bad    — линия краснеет, трескается посередине, половинки надламываются, осколки разлетаются, плашка вздрагивает, по верху экрана — вспышка
//   manual — отключили сами (кнопкой, выключили Wi-Fi): то же без тряски и вспышки, жёлтым — это не авария
// Под плашкой — полоса оставшегося времени; под курсором время стоит. Кнопка справа: «Переподключить» (разрыв устройства Orbit)
// или «Открыть» (лента Orbit). Сигналы идут по очереди, повтор того же события заменяет прежний.
// События: Orbit (на связи / разрыв / отключено вами / Orbit остановлен), Wi-Fi, Bluetooth, зарядка.
// Первые 5 с после запуска молчат — иначе загрузка состояния выглядела как поток событий.
// Настройки — Config.store.signals: enabled, good, sources { orbit, wifi, bt, power }; пример — ipc signal test good|bad|manual
Scope {
    id: fx
    readonly property var cfg: Config.store.signals || ({})
    readonly property var src: cfg.sources || ({})
    property bool armed: false
    Timer { running: true; interval: 5000; onTriggered: fx.armed = true }

    property var queue: []
    property var cur: null
    property int seq: 0
    // e: { mood: good|bad|manual, kind, left, right, title, sub, action: "" | reconnect | orbit, device }
    function push(e) {
        if (!armed || cfg.enabled === false || src[e.kind] === false) return;
        if (e.mood === "good" && cfg.good === false) return;
        var q = queue.filter(function (x) { return x.title !== e.title; });
        if (q.length >= 4) q = q.slice(q.length - 3);
        q.push(e);
        queue = q;
        if (cur === null && !gapT.running) gapT.restart();
    }
    // между сигналами окно закрывается и открывается заново: анимации каждого идут с начала
    function next() { cur = null; if (queue.length > 0) gapT.restart(); }
    Timer {
        id: gapT; interval: 140
        onTriggered: { if (fx.queue.length === 0) return; var q = fx.queue.slice(), e = q.shift(); fx.queue = q; e.n = ++fx.seq; fx.cur = e; }
    }
    function preview(mood) {
        var m = mood === "bad" || mood === "manual" ? mood : "good";
        queue = queue.concat([{ mood: m, kind: "orbit", left: "󰏲", right: "󰍹",
            title: m === "good" ? Tr.t("Телефон на связи") : (m === "bad" ? Tr.t("Связь с телефоном разорвана") : Tr.t("Телефон отключён")),
            sub: m === "good" ? Tr.t("Orbit · заряд 82%") : (m === "bad" ? Tr.t("устройство пропало из сети") : Tr.t("вы отключили его сами")),
            action: m === "good" ? "orbit" : (m === "bad" ? "reconnect" : ""), device: "" }]);
        if (cur === null && !gapT.running) gapT.restart();
    }

    // ---------- источники ----------
    // Orbit: новое устройство в списке — на связи; пропавшее — разрыв, или «отключён», если его только что отключили кнопкой
    property var orbitKnown: ({})
    Connections {
        target: OrbitData
        function onConnectedChanged() {
            var now = {}, i;
            for (i = 0; i < OrbitData.connected.length; i++) now[OrbitData.connected[i].deviceId] = OrbitData.connected[i];
            // Orbit остановился: один сигнал вместо разрыва с каждым устройством
            if (!OrbitData.running && Object.keys(fx.orbitKnown).length > 0) {
                fx.push({ mood: OrbitData.enabled ? "bad" : "manual", kind: "orbit", left: "󰟀", right: "󰍹", title: Tr.t("Orbit остановлен"),
                          sub: Object.keys(fx.orbitKnown).map(function (k) { return fx.orbitKnown[k].name; }).join(", ") + Tr.t(" — без связи"),
                          action: OrbitData.enabled ? "reconnect" : "", device: "" });
                fx.orbitKnown = now;
                return;
            }
            for (var id in now) if (!fx.orbitKnown[id]) {
                var c = now[id], bat = ["phone", "tablet", "laptop"].indexOf(c.kind) >= 0 && c.battery >= 0 ? Tr.t(" · заряд ") + c.battery + "%" : "";
                fx.push({ mood: "good", kind: "orbit", left: OrbitData.kindIcon(c.kind), right: "󰍹", title: c.name + Tr.t(" на связи"),
                          sub: "Orbit" + bat, action: "orbit", device: id });
            }
            for (var old in fx.orbitKnown) if (!now[old]) {
                var o = fx.orbitKnown[old], manual = Date.now() - (OrbitData.manualOff[old] || 0) < 8000;
                fx.push({ mood: manual ? "manual" : "bad", kind: "orbit", left: OrbitData.kindIcon(o.kind), right: "󰍹",
                          title: manual ? o.name + Tr.t(" отключён") : Tr.t("Связь с ") + o.name + Tr.t(" разорвана"),
                          sub: manual ? Tr.t("вы отключили его сами") : Tr.t("устройство пропало из сети"),
                          action: manual ? "" : "reconnect", device: old });
            }
            fx.orbitKnown = now;
        }
    }
    property string lastSsid: ""
    property string lastBt: ""
    Connections {
        target: Sys
        function onSsidChanged() {
            if (Sys.ssid !== "" && Sys.ssid !== fx.lastSsid)
                fx.push({ mood: "good", kind: "wifi", left: "󰍹", right: "󰤨", title: Tr.t("Wi-Fi: ") + Sys.ssid,
                          sub: Tr.t("сеть подключена") + (Sys.signal > 0 ? Tr.t(" · сигнал ") + Sys.signal + "%" : ""), action: "", device: "" });
            else if (Sys.ssid === "" && fx.lastSsid !== "")
                fx.push({ mood: Sys.wifiOn ? "bad" : "manual", kind: "wifi", left: "󰍹", right: "󰤭", title: Tr.t("Wi-Fi: ") + fx.lastSsid,
                          sub: Sys.wifiOn ? Tr.t("соединение потеряно") : Tr.t("Wi-Fi выключен"), action: "", device: "" });
            fx.lastSsid = Sys.ssid;
        }
        function onBtDeviceChanged() {
            if (Sys.btDevice !== "" && Sys.btDevice !== fx.lastBt)
                fx.push({ mood: "good", kind: "bt", left: "󰍹", right: "󰋋", title: Sys.btDevice, sub: Tr.t("Bluetooth подключён"), action: "", device: "" });
            else if (Sys.btDevice === "" && fx.lastBt !== "")
                fx.push({ mood: Sys.btOn ? "bad" : "manual", kind: "bt", left: "󰍹", right: "󰂲", title: fx.lastBt,
                          sub: Sys.btOn ? Tr.t("Bluetooth отключён") : Tr.t("Bluetooth выключен"), action: "", device: "" });
            fx.lastBt = Sys.btDevice;
        }
        function onChargingChanged() {
            if (!Sys.hasBattery) return;
            // отключение зарядки — не авария: жёлтым, без тряски
            if (Sys.charging) fx.push({ mood: "good", kind: "power", left: "󰌢", right: "󰚥", title: Tr.t("Зарядка подключена"), sub: Sys.batPct + "%", action: "", device: "" });
            else fx.push({ mood: "manual", kind: "power", left: "󰌢", right: "󰚦", title: Tr.t("Зарядка отключена"), sub: Sys.batPct + Tr.t("% · работа от батареи"), action: "", device: "" });
        }
    }
    Component.onCompleted: { lastSsid = Sys.ssid; lastBt = Sys.btDevice; }

    // ---------- окно сигнала ----------
    LazyLoader {
        active: fx.cur !== null
        PanelWindow {
            id: win
            readonly property var e: fx.cur || ({})
            readonly property bool good: e.mood === "good"
            readonly property bool bad: e.mood === "bad"
            readonly property color tone: good ? Theme.green : (bad ? Theme.red : Theme.yellow)
            readonly property bool rich: !Perf.eco && (Config.store.crossing || {}).reducedMotion !== true
            screen: Compositor.mainScreen
            anchors { top: true; left: true; right: true }
            implicitHeight: 200
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region { item: pill }
            WlrLayershell.namespace: "nameless-signal"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // вспышка по верху экрана — только у аварийного разрыва, в момент трещины
            Rectangle {
                visible: win.bad && win.rich
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 110
                opacity: 0
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.42) }
                    GradientStop { position: 1; color: "transparent" }
                }
                SequentialAnimation on opacity {
                    running: win.bad && win.rich
                    PauseAnimation { duration: 380 }
                    NumberAnimation { to: 1; duration: 80 }
                    NumberAnimation { to: 0; duration: 700; easing.type: Easing.OutCubic }
                }
            }

            Item {
                id: stage
                anchors.horizontalCenter: parent.horizontalCenter
                y: 54
                width: pill.width; height: pill.height
                opacity: 0
                property real shake: 0
                property real life: 1                    // доля оставшегося времени показа
                transform: Translate { x: stage.shake }

                Surface {
                    id: pill
                    width: Math.min(win.width - 32, body.implicitWidth + 28)
                    height: 68; radius: 34
                    alpha: Theme.overlayAlpha            // плотнее панелей: текст читается на любых обоях
                    // кант цвета события и полоса оставшегося времени по низу
                    Rectangle {
                        anchors.fill: parent; radius: Theme.r(34); color: "transparent"
                        border.width: 1.5; border.color: Qt.rgba(win.tone.r, win.tone.g, win.tone.b, 0.75)
                    }
                    Rectangle {
                        anchors { bottom: parent.bottom; bottomMargin: 5; horizontalCenter: parent.horizontalCenter }
                        width: (parent.width - 64) * stage.life; height: 2; radius: 1
                        color: Qt.rgba(win.tone.r, win.tone.g, win.tone.b, 0.7)
                    }
                    HoverHandler { id: hov }
                    // нажатие по плашке — убрать (у «на связи» — ещё и открыть ленту Orbit)
                    TapHandler { onTapped: { if (win.e.action === "orbit") OrbitData.panelOpen = true; leave.start(); } }

                    Row {
                        id: body
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        spacing: 14

                        // «связь»: левый значок — линия — правый значок; в середине линии — знак события
                        Item {
                            id: link
                            width: 112; height: 44
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property real mid: width / 2
                            Repeater {
                                model: [{ i: win.e.left || "󰟀", r: false }, { i: win.e.right || "󰍹", r: true }]
                                Rectangle {
                                    required property var modelData
                                    x: modelData.r ? link.width - width : 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 30; height: 30; radius: 15
                                    color: Theme.fill(0.10); border.width: 1; border.color: Theme.line(0.18)
                                    Text { anchors.centerIn: parent; text: parent.modelData.i; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 15 }
                                }
                            }
                            // половинки линии: срастаются (good) или надламываются (bad, manual)
                            Rectangle {
                                id: halfL
                                x: 32; y: link.height / 2 - 1.5
                                width: link.mid - 36; height: 3; radius: 1.5
                                color: win.tone
                                transformOrigin: Item.Left
                                scale: win.good ? 0 : 1
                            }
                            Rectangle {
                                id: halfR
                                x: link.mid + 4; y: link.height / 2 - 1.5
                                width: link.mid - 36; height: 3; radius: 1.5
                                color: win.tone
                                transformOrigin: Item.Right
                                scale: win.good ? 0 : 1
                            }
                            // осколки из трещины
                            Repeater {
                                model: win.bad && win.rich ? 8 : 0
                                Rectangle {
                                    id: shard
                                    required property int index
                                    readonly property real ang: (-160 + index * 20) * Math.PI / 180
                                    x: link.mid - 2; y: link.height / 2 - 2
                                    width: 3 + index % 3; height: width
                                    color: index % 2 ? Theme.red : Qt.lighter(Theme.red, 1.35)
                                    opacity: 0
                                    SequentialAnimation {
                                        running: true
                                        PauseAnimation { duration: 380 }
                                        ParallelAnimation {
                                            NumberAnimation { target: shard; property: "opacity"; from: 1; to: 0; duration: 750 }
                                            NumberAnimation { target: shard; property: "x"; to: link.mid + Math.cos(shard.ang) * (22 + shard.index * 4); duration: 750; easing.type: Easing.OutQuad }
                                            NumberAnimation { target: shard; property: "y"; to: link.height / 2 + Math.sin(shard.ang) * (14 + shard.index * 2) + 26; duration: 750; easing.type: Easing.InQuad }
                                            NumberAnimation { target: shard; property: "rotation"; to: 200 + shard.index * 40; duration: 750 }
                                        }
                                    }
                                }
                            }
                            // волны от места встречи (good) или от трещины (bad)
                            Repeater {
                                model: win.rich && win.e.mood !== "manual" ? 2 : 0
                                Rectangle {
                                    id: ring
                                    required property int index
                                    x: link.mid - 13; y: link.height / 2 - 13
                                    width: 26; height: 26; radius: 13
                                    color: "transparent"; border.width: 2; border.color: win.tone
                                    opacity: 0
                                    SequentialAnimation {
                                        running: true
                                        PauseAnimation { duration: (win.good ? 520 : 400) + ring.index * 170 }
                                        ParallelAnimation {
                                            NumberAnimation { target: ring; property: "scale"; from: 1; to: 2.4; duration: 700; easing.type: Easing.OutCubic }
                                            NumberAnimation { target: ring; property: "opacity"; from: 0.85; to: 0; duration: 700 }
                                        }
                                    }
                                }
                            }
                            // знак события в середине линии
                            Rectangle {
                                id: sign
                                x: link.mid - 13; y: link.height / 2 - 13
                                width: 26; height: 26; radius: 13
                                color: win.tone
                                scale: 0
                                Text {
                                    id: signT
                                    anchors.centerIn: parent
                                    text: win.good ? "󰄬" : (win.bad ? "󰅖" : "󰤮")
                                    color: win.e.mood === "manual" && !Theme.dark ? "#1e1e2e" : "white"
                                    font.family: Theme.iconFont; font.pixelSize: 15
                                }
                            }

                            SequentialAnimation {
                                running: true
                                PauseAnimation { duration: 200 }
                                // good: половинки вырастают от значков к середине
                                ParallelAnimation {
                                    NumberAnimation { target: halfL; property: "scale"; to: 1; duration: win.good ? 320 : 0; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: halfR; property: "scale"; to: 1; duration: win.good ? 320 : 0; easing.type: Easing.OutCubic }
                                }
                                // bad / manual: трещина — половинки надламываются вниз и отъезжают от середины
                                ParallelAnimation {
                                    NumberAnimation { target: halfL; property: "rotation"; to: win.good ? 0 : (win.bad ? 24 : 10); duration: win.good ? 0 : 380; easing.type: Easing.OutBack }
                                    NumberAnimation { target: halfR; property: "rotation"; to: win.good ? 0 : (win.bad ? -24 : -10); duration: win.good ? 0 : 380; easing.type: Easing.OutBack }
                                    NumberAnimation { target: halfL; property: "x"; to: win.good ? 32 : 26; duration: win.good ? 0 : 380 }
                                    NumberAnimation { target: halfR; property: "x"; to: win.good ? link.mid + 4 : link.mid + 10; duration: win.good ? 0 : 380 }
                                    NumberAnimation { target: halfL; property: "opacity"; to: win.good ? 1 : 0.55; duration: win.good ? 0 : 600 }
                                    NumberAnimation { target: halfR; property: "opacity"; to: win.good ? 1 : 0.55; duration: win.good ? 0 : 600 }
                                }
                                // знак появляется с перелётом
                                ParallelAnimation {
                                    NumberAnimation { target: sign; property: "scale"; from: 0; to: 1; duration: 360; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                                    NumberAnimation { target: signT; property: "rotation"; from: win.good ? -30 : -120; to: 0; duration: 420; easing.type: Easing.OutBack }
                                }
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                width: Math.min(implicitWidth, win.width - 330); elide: Text.ElideRight
                                text: win.e.title || ""; color: Theme.text
                                font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                            }
                            Text {
                                visible: text !== ""
                                width: Math.min(implicitWidth, win.width - 330); elide: Text.ElideRight
                                text: win.e.sub || ""; color: win.good ? Theme.sub : win.tone
                                font.family: Theme.font; font.pixelSize: 11
                            }
                        }

                        // действие: переподключить (разрыв Orbit) или открыть ленту Orbit
                        Rectangle {
                            visible: win.e.action === "reconnect" || win.e.action === "orbit"
                            anchors.verticalCenter: parent.verticalCenter
                            width: actT.implicitWidth + 26; height: 32; radius: 16
                            color: actMa.containsMouse ? Qt.rgba(win.tone.r, win.tone.g, win.tone.b, 0.9) : Qt.rgba(win.tone.r, win.tone.g, win.tone.b, 0.22)
                            border.width: 1; border.color: win.tone
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                id: actT
                                anchors.centerIn: parent
                                text: win.e.action === "reconnect" ? "󰑓  " + Tr.t("Переподключить") : "󰟀  " + Tr.t("Открыть")
                                color: actMa.containsMouse ? "white" : Theme.text
                                font.family: Theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: actMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (win.e.action === "reconnect") { if (win.e.device) OrbitData.connectTo(win.e.device); else OrbitData.start(false); }
                                    else OrbitData.panelOpen = true;
                                    leave.start();
                                }
                            }
                        }
                    }
                }
            }

            // появление → вздрагивание (только авария) → время показа (под курсором стоит) → уход
            SequentialAnimation {
                running: true
                ParallelAnimation {
                    NumberAnimation { target: stage; property: "opacity"; to: 1; duration: 200 }
                    NumberAnimation { target: stage; property: "y"; from: 30; to: 54; duration: 340; easing.type: Easing.OutCubic }
                }
                PauseAnimation { duration: 180 }
                SequentialAnimation {
                    NumberAnimation { target: stage; property: "shake"; to: win.bad && win.rich ? 12 : 0; duration: win.bad && win.rich ? 45 : 0 }
                    NumberAnimation { target: stage; property: "shake"; to: win.bad && win.rich ? -10 : 0; duration: win.bad && win.rich ? 65 : 0 }
                    NumberAnimation { target: stage; property: "shake"; to: win.bad && win.rich ? 7 : 0; duration: win.bad && win.rich ? 65 : 0 }
                    NumberAnimation { target: stage; property: "shake"; to: win.bad && win.rich ? -4 : 0; duration: win.bad && win.rich ? 55 : 0 }
                    NumberAnimation { target: stage; property: "shake"; to: 0; duration: win.bad && win.rich ? 55 : 0 }
                }
                ScriptAction { script: lifeA.start() }
            }
            NumberAnimation {
                id: lifeA
                target: stage; property: "life"; from: 1; to: 0
                duration: win.good ? 3600 : (win.bad ? 6500 : 4200)
                paused: running && hov.hovered
                onFinished: leave.start()
            }
            SequentialAnimation {
                id: leave
                ScriptAction { script: lifeA.stop() }
                ParallelAnimation {
                    NumberAnimation { target: stage; property: "opacity"; to: 0; duration: 240 }
                    NumberAnimation { target: stage; property: "y"; to: 36; duration: 240; easing.type: Easing.InCubic }
                }
                ScriptAction { script: fx.next() }
            }
        }
    }
}
