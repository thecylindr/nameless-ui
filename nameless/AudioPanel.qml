import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire

// Звук (правый клик по громкости в баре): выход, вход, приложения — без pavucontrol.
//   Выход        — громкость и без звука, выбор устройства, живой уровень, проверка: левый / правый / оба канала
//   Вход         — громкость микрофона, выбор устройства, живой уровень, проверка: записать 3 с и прослушать
//   Приложения   — громкость и без звука у каждого играющего и записывающего приложения
// Устройство по умолчанию меняется сразу (Pipewire.preferredDefaultAudio*); уровень — PwNodePeakMonitor,
// включается только на открытой вкладке
PanelWindow {
    id: w
    property var shell: null
    readonly property bool open: shell ? shell.audioOpen : false
    function close() { if (shell) shell.audioOpen = false; }
    property int tab: 0
    property real progress: 0
    Component.onCompleted: {
        progress = Qt.binding(function () { return w.open ? 1 : 0; });
    }
    Behavior on progress { NumberAnimation { duration: Theme.dur(w.open); easing.type: Easing.OutCubic } }

    visible: progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-audio"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // ---------- устройства и потоки ----------
    // Списки строятся прямо по модели Pipewire.nodes: Repeater получает от неё сигналы вставки и удаления и сам
    // убирает исчезнувший узел. Раньше узлы копировались в JS-массив, и когда поток (проверка звука, закрытое
    // приложение) пропадал во время пересборки списка, Quickshell падал. Каждая строка сама решает, показываться ли ей.
    function isSinkDev(n) { return n && n.audio && n.isSink && !n.isStream; }
    function isSourceDev(n) { return n && n.audio && !n.isSink && !n.isStream && (n.name || "").indexOf(".monitor") < 0; }
    function isPlay(n) { return n && n.audio && n.isStream && !n.isSink; }
    function isRec(n) { return n && n.audio && n.isStream && n.isSink; }
    // только числа — объекты узлов в свойствах не хранятся
    readonly property int playingCount: Pipewire.nodes.values.filter(function (n) { return w.isPlay(n); }).length
    readonly property int appsCount: playingCount + Pipewire.nodes.values.filter(function (n) { return w.isRec(n); }).length
    PwObjectTracker { objects: Pipewire.nodes.values }

    function title(n) { return n ? (n.nickname || n.description || n.name || "") : ""; }
    function appName(n) { var p = n.properties || {}; return p["application.name"] || n.description || n.name || Tr.t("Приложение"); }
    function appIcon(n) {
        var p = n.properties || {}, i = p["application.icon-name"] || (p["application.process.binary"] || "").toLowerCase();
        return Quickshell.iconPath(i || "", true) || Quickshell.iconPath("audio-volume-high", true);
    }
    function pct(v) { return Math.round((v || 0) * 100); }

    // ---------- проверка звука ----------
    readonly property string sounds: "/usr/share/sounds/freedesktop/stereo/"
    property string testing: ""
    Process {
        id: player
        onExited: w.testing = ""
    }
    function play(kind) {
        if (player.running) return;
        testing = kind;
        var f = { left: ["audio-channel-front-left.oga"], right: ["audio-channel-front-right.oga"], both: ["audio-channel-front-left.oga", "audio-channel-front-right.oga"] }[kind];
        player.command = ["sh", "-c", f.map(function (x) { return "pw-play '" + sounds + x + "'"; }).join(" && ")];
        player.running = true;
    }
    property string micState: ""         // "" | rec | play
    Process {
        id: micTest
        stdout: SplitParser { onRead: (l) => { if (l === "play") w.micState = "play"; } }
        onExited: w.micState = ""
    }
    function testMic() {
        if (micTest.running) return;
        micState = "rec";
        micTest.command = ["sh", "-c", "f=\"${XDG_RUNTIME_DIR:-/tmp}/glassrice-mic.wav\"; timeout 3 pw-record \"$f\"; echo play; pw-play \"$f\"; rm -f \"$f\""];
        micTest.running = true;
    }

    // живой уровень: только на открытой вкладке
    PwNodePeakMonitor { id: outPeak; node: Sound.sink; enabled: w.open && w.tab === 0 }
    PwNodePeakMonitor { id: inPeak; node: Sound.source; enabled: w.open && w.tab === 1 }

    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * 0.6 * w.progress }
    MouseArea { anchors.fill: parent; onClicked: w.close() }

    Surface {
        id: box
        alpha: Theme.overlayAlpha
        width: Math.min(460, parent.width - 20)
        height: Math.min(parent.height - 70, col.implicitHeight + 32)
        x: parent.width - width - 10
        y: 48 + (1 - w.progress) * -20
        opacity: w.progress
        radius: Theme.ios ? 30 : 22
        MouseArea { anchors.fill: parent }
        MoveArea { win: box; anchors { left: parent.left; right: parent.right; top: parent.top } height: 56 }
        focus: w.open
        Keys.onEscapePressed: w.close()

        Flickable {
            anchors { fill: parent; margins: 16 }
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: col
                width: parent.width
                spacing: 12

                Item {
                    width: parent.width; height: 32
                    Text { anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Звук"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.ios ? 22 : 19; font.weight: Font.Bold }
                    GTile {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        ui: Theme; width: 30; height: 30; radius: 15
                        Text { anchors.centerIn: parent; text: "✕"; color: Theme.text; font.pixelSize: 12 }
                        onClicked: w.close()
                    }
                }
                GSegment {
                    ui: Theme
                    options: [{ v: "0", t: Tr.t("Выход"), icon: "󰓃" }, { v: "1", t: Tr.t("Вход"), icon: "󰍬" }, { v: "2", t: Tr.t("Приложения") + (w.playingCount ? " " + w.playingCount : ""), icon: "󰀻" }]
                    value: String(w.tab)
                    onPicked: (v) => w.tab = Number(v)
                }

                // ================= выход =================
                Column {
                    visible: w.tab === 0
                    width: parent.width
                    spacing: 10
                    PillSlider {
                        ui: Theme; width: parent.width
                        icon: Sound.icon; label: w.title(Sound.sink) || Tr.t("Выход")
                        from: 0; to: 1.5; value: Sound.volume; display: 100; suffix: " %"
                        onCommitted: (v) => Sound.setVolume(v)
                    }
                    Meter { level: outPeak.peak; on: !Sound.muted }
                    Row {
                        spacing: 6
                        GButton { ui: Theme; height: 34; icon: Sound.muted ? "󰝟" : "󰕾"; label: Sound.muted ? Tr.t("Включить звук") : Tr.t("Без звука"); on: Sound.muted; onClicked: Sound.toggleMute() }
                        GButton { ui: Theme; height: 34; icon: "󰓃"; label: w.testing === "left" ? Tr.t("Играет…") : Tr.t("Левый"); onClicked: w.play("left") }
                        GButton { ui: Theme; height: 34; icon: "󰓃"; label: w.testing === "right" ? Tr.t("Играет…") : Tr.t("Правый"); onClicked: w.play("right") }
                        GButton { ui: Theme; height: 34; icon: "󰓃"; label: w.testing === "both" ? Tr.t("Играет…") : Tr.t("Оба"); onClicked: w.play("both") }
                    }
                    Text { text: Tr.t("Устройство вывода"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6 }
                    Repeater {
                        model: Pipewire.nodes
                        DeviceRow {
                            required property var modelData
                            shown: w.isSinkDev(modelData)
                            node: modelData
                            current: Sound.sink === modelData
                            icon: (modelData.name || "").indexOf("bluez") >= 0 ? "󰋋" : ((modelData.name || "").indexOf("hdmi") >= 0 ? "󰡁" : "󰓃")
                            onPick: Pipewire.preferredDefaultAudioSink = modelData
                        }
                    }
                }

                // ================= вход =================
                Column {
                    visible: w.tab === 1
                    width: parent.width
                    spacing: 10
                    PillSlider {
                        ui: Theme; width: parent.width
                        icon: Sound.micMuted ? "󰍭" : "󰍬"; label: w.title(Sound.source) || Tr.t("Микрофон")
                        from: 0; to: 1.5
                        value: Sound.source && Sound.source.audio ? Sound.source.audio.volume : 0
                        display: 100; suffix: " %"
                        onCommitted: (v) => { if (Sound.source && Sound.source.audio) { Sound.source.audio.muted = false; Sound.source.audio.volume = v; } }
                    }
                    Meter { level: inPeak.peak; on: !Sound.micMuted }
                    Text { text: Sound.micMuted ? Tr.t("Микрофон выключен") : Tr.t("Скажите что-нибудь: полоса показывает уровень"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                    Row {
                        spacing: 6
                        GButton { ui: Theme; height: 34; icon: Sound.micMuted ? "󰍭" : "󰍬"; label: Sound.micMuted ? Tr.t("Включить микрофон") : Tr.t("Выключить"); on: Sound.micMuted; onClicked: Sound.toggleMic() }
                        GButton {
                            ui: Theme; height: 34; icon: "󰑊"; on: w.micState !== ""
                            label: w.micState === "rec" ? Tr.t("Запись 3 с…") : (w.micState === "play" ? Tr.t("Воспроизведение…") : Tr.t("Записать и прослушать"))
                            onClicked: w.testMic()
                        }
                    }
                    Text { text: Tr.t("Устройство ввода"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6 }
                    Repeater {
                        model: Pipewire.nodes
                        DeviceRow {
                            required property var modelData
                            shown: w.isSourceDev(modelData)
                            node: modelData
                            current: Sound.source === modelData
                            icon: (modelData.name || "").indexOf("bluez") >= 0 ? "󰋎" : "󰍬"
                            onPick: Pipewire.preferredDefaultAudioSource = modelData
                        }
                    }
                }

                // ================= приложения =================
                Column {
                    visible: w.tab === 2
                    width: parent.width
                    spacing: 8
                    Text { visible: w.appsCount === 0; text: Tr.t("Сейчас ни одно приложение не играет и не записывает"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
                    Repeater {
                        model: Pipewire.nodes
                        Item {
                            required property var modelData
                            readonly property bool shown: w.isPlay(modelData) || w.isRec(modelData)
                            readonly property bool rec: modelData.isSink
                            visible: shown
                            width: col.width; height: shown ? 76 : 0
                            Rectangle { anchors.fill: parent; radius: Theme.r(16); color: Theme.fill(0.07) }
                            IconImage { id: ai; x: 12; y: 12; implicitSize: 28; source: w.appIcon(modelData) }
                            Column {
                                anchors { left: ai.right; leftMargin: 10; right: muteB.left; rightMargin: 8; top: parent.top; topMargin: 10 }
                                Text { width: parent.width; elide: Text.ElideRight; text: (parent.parent.rec ? "󰍬 " : "") + w.appName(modelData); color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 13; font.weight: Font.DemiBold }
                                Text { width: parent.width; elide: Text.ElideRight; text: (modelData.properties || {})["media.name"] || ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                            }
                            GTile {
                                id: muteB
                                anchors { right: parent.right; rightMargin: 10; top: parent.top; topMargin: 10 }
                                ui: Theme; width: 30; height: 30; radius: 15
                                on: modelData.audio && modelData.audio.muted
                                onColor: Theme.red
                                Text { anchors.centerIn: parent; text: parent.on ? "󰝟" : "󰕾"; color: parent.on ? "white" : Theme.text; font.family: Theme.iconFont; font.pixelSize: 14 }
                                onClicked: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
                            }
                            // громкость приложения: тянуть — сразу
                            Item {
                                anchors { left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12; bottom: parent.bottom; bottomMargin: 10 }
                                height: 18
                                readonly property real v: modelData.audio ? modelData.audio.volume : 0
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: Theme.fill(0.16) }
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * Math.min(1, parent.v); height: 6; radius: 3; color: Theme.accent }
                                Text { anchors { right: parent.right; bottom: parent.top } text: w.pct(parent.v) + " %"; color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -6; preventStealing: true; cursorShape: Qt.PointingHandCursor
                                    function setAt(x) { if (modelData.audio) { modelData.audio.muted = false; modelData.audio.volume = Math.max(0, Math.min(1, (x - 6) / (width - 12))); } }
                                    onPressed: (m) => setAt(m.x)
                                    onPositionChanged: (m) => { if (pressed) setAt(m.x); }
                                }
                            }
                        }
                    }
                }

                GButton { ui: Theme; height: 34; icon: "󰒓"; label: Tr.t("Расширенные настройки (pavucontrol)"); onClicked: { w.close(); Quickshell.execDetached(["pavucontrol"]); } }
            }
        }
    }

    // ---------- части ----------
    // уровень сигнала: зелёный → жёлтый → красный, с пиком
    component Meter: Item {
        id: mt
        property real level: 0
        property bool on: true
        width: parent ? parent.width : 300
        height: 10
        Rectangle { anchors.fill: parent; radius: 5; color: Theme.fill(0.12) }
        Rectangle {
            width: parent.width * Math.min(1, mt.on ? mt.level : 0)
            height: parent.height; radius: 5
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.green }
                GradientStop { position: 0.7; color: Theme.yellow }
                GradientStop { position: 1.0; color: Theme.red }
            }
            Behavior on width { NumberAnimation { duration: 80 } }
        }
    }

    // устройство: значок, название, отметка выбранного
    component DeviceRow: Item {
        id: dr
        property var node
        property bool current: false
        property string icon: "󰓃"
        property bool shown: true
        signal pick
        visible: shown
        width: parent ? parent.width : 300
        height: shown ? 46 : 0
        Rectangle {
            anchors.fill: parent; radius: Theme.r(14)
            color: dr.current ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : (dma.containsMouse ? Theme.fill(0.12) : Theme.fill(0.06))
            border.width: dr.current ? 1.5 : 0; border.color: Theme.accent
        }
        Text { id: di; x: 14; anchors.verticalCenter: parent.verticalCenter; text: dr.icon; color: dr.current ? Theme.accent : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 18 }
        Column {
            anchors { left: di.right; leftMargin: 12; right: parent.right; rightMargin: 40; verticalCenter: parent.verticalCenter }
            Text { width: parent.width; elide: Text.ElideRight; text: w.title(dr.node); color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: dr.current ? Font.DemiBold : Font.Normal }
            Text { width: parent.width; elide: Text.ElideRight; text: dr.node && dr.node.audio ? Tr.t("громкость ") + w.pct(dr.node.audio.volume) + " %" + (dr.node.audio.muted ? Tr.t(" · без звука") : "") : ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
        }
        Text { visible: dr.current; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } text: "󰄬"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 16 }
        MouseArea { id: dma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dr.pick() }
    }
}
