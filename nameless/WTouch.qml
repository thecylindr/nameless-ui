import QtQuick
import Quickshell
import Quickshell.Io

// Сенсорная панель (как touchview): панель-тачпад с точками на месте пальцев и подсветкой кликов своим цветом:
//   левая кнопка / касание одним пальцем — цвет акцента, правая / касание двумя — красный, средняя / тремя — зелёный
// (цвета меняются в Config.store.touchpad: left, right, middle, dot — имя цвета темы или #RRGGBB). Нажатие кнопки даёт круг на месте
// пальца, касание без нажатия — более тонкий; под панелью три «кнопки» загораются, пока их держат.
// Данные — touchpad.py (читает события тачпада без внешних библиотек; нужна группа input); работает, пока виджет виден
WCard {
    id: w
    readonly property var o: Config.store.touchpad || ({})
    property var fingers: []
    property bool bl: false
    property bool br: false
    property bool bm: false
    property string dev: ""
    property string err: ""
    property string lastClick: ""
    readonly property string script: (Quickshell.shellDir || (Quickshell.env("HOME") + "/.config/quickshell/nameless")) + "/touchpad.py"

    function col(name, fallback) {
        if (!name) return fallback;
        if (name.charAt(0) === "#") return name;
        var m = { accent: Theme.accent, accent2: Theme.accent2, red: Theme.red, green: Theme.green, yellow: Theme.yellow, peach: Theme.peach, teal: Theme.teal, text: Theme.text };
        return m[name] || fallback;
    }
    readonly property color cLeft: col(o.left, Theme.accent)
    readonly property color cRight: col(o.right, Theme.red)
    readonly property color cMid: col(o.middle, Theme.green)
    readonly property color cDot: col(o.dot, Theme.accent)
    readonly property real dotR: o.dotSize || 9
    readonly property real panelW: width - pad * 2
    readonly property real panelH: Math.round(panelW * 0.6)
    function colorOf(b) { return b === "l" ? cLeft : (b === "r" ? cRight : cMid); }
    // цвет точки: пока кнопка зажата — цвет кнопки
    readonly property color dotNow: bl ? cLeft : (br ? cRight : (bm ? cMid : cDot))

    implicitHeight: pad * 2 + 30 + panelH + 12 + 28

    function handle(line) {
        var d;
        try { d = JSON.parse(line); } catch (e) { return; }
        if (d.hello !== undefined) { dev = d.hello; err = ""; return; }
        if (d.err !== undefined) { err = d.err; return; }
        if (d.e === "click") { ripple(d.b, d.x, d.y, false); lastClick = ({ l: Tr.t("левая"), r: Tr.t("правая"), m: Tr.t("средняя") })[d.b] || ""; return; }
        if (d.e === "tap") { var b = d.n >= 3 ? "m" : (d.n === 2 ? "r" : "l"); ripple(b, d.x, d.y, true); lastClick = Tr.t("касание ×") + d.n; return; }
        fingers = d.f || [];
        bl = d.l === 1; br = d.r === 1; bm = d.m === 1;
    }
    function ripple(b, x, y, tap) { rip.append({ b: b, cx: x, cy: y, tap: tap, born: Date.now() }); }

    ListModel { id: rip }
    // старые круги убираются: анимация длится 600 мс
    Timer { interval: 700; repeat: true; running: rip.count > 0; onTriggered: { var now = Date.now(); while (rip.count > 0 && now - rip.get(0).born > 650) rip.remove(0); } }

    Process {
        id: proc
        running: w.visible && w.err !== "perm" && w.err !== "no-touchpad"
        command: ["python3", w.script]
        stdout: SplitParser { onRead: data => w.handle(data) }
        onExited: { w.fingers = []; w.bl = false; w.br = false; w.bm = false; }
    }
    // ошибка устройства: раз в 10 секунд пробуем снова (тачпад могли включить, группу — добавить)
    Timer { interval: 10000; repeat: true; running: w.visible && (w.err === "perm" || w.err === "no-touchpad"); onTriggered: w.err = "" }

    Row {
        id: head
        width: parent.width
        spacing: 10
        Text { text: "󰟸"; color: w.err === "" ? Theme.accent : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 20; anchors.verticalCenter: parent.verticalCenter }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 40
            Text { text: Tr.t("Сенсорная панель"); color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Bold }
            Text { width: parent.width; elide: Text.ElideRight; text: w.err === "perm" ? Tr.t("нет доступа к /dev/input — нужна группа input") : (w.err === "no-touchpad" ? Tr.t("тачпад не найден") : (w.dev !== "" ? w.dev : Tr.t("ждём касаний…"))); color: w.err === "" ? Theme.sub : Theme.yellow; font.family: Theme.font; font.pixelSize: 10 }
        }
    }

    // панель
    Rectangle {
        id: panel
        anchors { top: head.bottom; topMargin: 8 }
        width: w.panelW; height: w.panelH
        radius: 14
        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.55)
        border.width: 1; border.color: Theme.line(0.22)
        clip: true

        // лёгкая сетка, чтобы панель читалась как тачпад
        Repeater { model: 3; Rectangle { x: (index + 1) * panel.width / 4; width: 1; height: panel.height; color: Theme.line(0.07) } }
        Repeater { model: 2; Rectangle { y: (index + 1) * panel.height / 3; height: 1; width: panel.width; color: Theme.line(0.07) } }

        // круги кликов
        Repeater {
            model: rip
            Rectangle {
                id: rc
                required property string b
                required property real cx
                required property real cy
                required property bool tap
                property real k: 0
                width: (tap ? 70 : 100) * (0.35 + k); height: width; radius: width / 2
                x: cx * panel.width - width / 2; y: cy * panel.height - height / 2
                color: tap ? "transparent" : Qt.rgba(w.colorOf(b).r, w.colorOf(b).g, w.colorOf(b).b, 0.35)
                border.width: tap ? 3 : 2; border.color: w.colorOf(b)
                opacity: 1 - k
                NumberAnimation on k { from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic }
            }
        }

        // пальцы: точка со свечением
        Repeater {
            model: w.fingers
            Item {
                required property var modelData
                x: modelData[0] * panel.width; y: modelData[1] * panel.height
                Rectangle { x: -w.dotR * 2.4; y: -w.dotR * 2.4; width: w.dotR * 4.8; height: width; radius: width / 2; color: Qt.rgba(w.dotNow.r, w.dotNow.g, w.dotNow.b, 0.22) }
                Rectangle { x: -w.dotR; y: -w.dotR; width: w.dotR * 2; height: width; radius: width / 2; color: w.dotNow; border.width: 2; border.color: Qt.rgba(1, 1, 1, 0.55) }
            }
        }
    }

    // кнопки
    Row {
        id: btns
        anchors { top: panel.bottom; topMargin: 12 }
        width: parent.width
        spacing: 8
        Repeater {
            model: [{ k: "l", t: Tr.t("Левая"), c: w.cLeft, on: w.bl }, { k: "m", t: Tr.t("Средняя"), c: w.cMid, on: w.bm }, { k: "r", t: Tr.t("Правая"), c: w.cRight, on: w.br }]
            Rectangle {
                required property var modelData
                width: (btns.width - 16) / 3; height: 28; radius: 14
                color: modelData.on ? modelData.c : Qt.rgba(modelData.c.r, modelData.c.g, modelData.c.b, 0.14)
                border.width: 1; border.color: modelData.c
                Behavior on color { ColorAnimation { duration: 80 } }
                Text { anchors.centerIn: parent; text: modelData.t; color: modelData.on ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
            }
        }
    }
}
