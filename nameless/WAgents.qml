import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Помощники: Claude Code и Codex на одном виджете.
//   Строки — запущенные помощники: проект, что делает (работает / ждёт задачу / ждёт ответа), сколько времени, последнее сообщение.
//   Нажатие на строку — перейти в окно терминала помощника.
//   «Быстрый вопрос»: короткий вопрос без открытия терминала — ответ появляется здесь же (Claude Code: режим «план», без правок;
//   Codex: только чтение). Папка вопроса — проект одного из запущенных помощников или домашняя.
// Данные — agents.py (читает ~/.claude/sessions и процессы, настройки помощников не трогает); опрос раз в 3 с, только пока виджет виден
WCard {
    id: w
    readonly property var o: Config.store.agents
    property var list: []
    property real nowT: Date.now() / 1000
    readonly property string script: (Quickshell.shellDir || (Quickshell.env("HOME") + "/.config/quickshell/nameless")) + "/agents.py"
    readonly property int rowsMax: width > 340 ? 5 : 3
    readonly property var shown: list.slice(0, rowsMax)
    readonly property int busyN: list.filter(function (a) { return a.status === "busy"; }).length

    // ---------- состояние помощников ----------
    Process {
        id: poll
        command: ["python3", w.script]
        stdout: StdioCollector {
            onStreamFinished: {
                try { var d = JSON.parse(text); w.list = d.agents || []; w.nowT = d.t || Date.now() / 1000; } catch (e) { }
            }
        }
    }
    Timer { interval: 3000; repeat: true; running: w.visible && !Compositor.covered; triggeredOnStart: true; onTriggered: if (!poll.running) poll.running = true }

    function info(s) {
        if (s === "busy") return { t: Tr.t("работает"), c: Theme.accent };
        if (s === "idle") return { t: Tr.t("ждёт задачу"), c: Theme.green };
        if (/wait|input|permission|approval/i.test(s)) return { t: Tr.t("ждёт ответа"), c: Theme.yellow };
        return { t: s, c: Theme.sub };
    }
    function ago(since) {
        var s = Math.max(0, Math.round(nowT - since));
        return s < 60 ? s + Tr.t(" с") : (s < 3600 ? Math.floor(s / 60) + Tr.t(" мин") : Math.floor(s / 3600) + Tr.t(" ч ") + Math.floor(s / 60) % 60 + Tr.t(" мин"));
    }
    function focus(a) { if (a.addr && Compositor.hyprland) Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + a.addr + "\" })"); }
    function launch(kind) { Quickshell.execDetached(["kitty", "-e", kind === "codex" ? "codex" : "claude"]); }

    // ---------- быстрый вопрос ----------
    property string askKind: o.ask || "claude"
    property string askDir: Quickshell.env("HOME")
    property string answer: ""
    property bool asking: false
    property real askStart: 0
    property string askErr: ""
    readonly property var dirs: {
        var out = [Quickshell.env("HOME")];
        for (var i = 0; i < list.length; i++) if (out.indexOf(list[i].cwd) < 0) out.push(list[i].cwd);
        return out;
    }
    function dirName(d) { return d === Quickshell.env("HOME") ? "~" : d.substring(d.lastIndexOf("/") + 1); }
    function nextDir() { var i = dirs.indexOf(askDir); askDir = dirs[(i + 1) % dirs.length]; }
    function send(q) {
        q = q.trim();
        if (q === "" || asking) return;
        answer = ""; askErr = ""; asking = true; askStart = Date.now();
        var cmd = askKind === "codex"
            ? ["codex", "exec", "--sandbox", "read-only", "--skip-git-repo-check", q]
            : ["claude", "-p", q, "--permission-mode", "plan", "--output-format", "text", "--no-session-persistence"];
        ask.command = ["sh", "-c", "cd \"$1\" 2>/dev/null || cd; shift; exec timeout 150 \"$@\"", "sh", askDir].concat(cmd);
        ask.running = true;
    }
    Process {
        id: ask
        stdout: StdioCollector { onStreamFinished: w.answer = text.trim() }
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "" && w.answer === "") w.askErr = text.trim().split("\n").slice(-2).join(" ") }
        onExited: (code) => { w.asking = false; if (code !== 0 && w.answer === "" && w.askErr === "") w.askErr = code === 124 ? Tr.t("нет ответа за 150 с") : Tr.t("помощник завершился с кодом ") + code; }
    }
    Timer { interval: 1000; repeat: true; running: w.asking; onTriggered: w.nowT = Date.now() / 1000 }
    function cancel() { if (ask.running) ask.signal(15); }
    function copy() { Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", answer]); }

    readonly property real quotaH: !AgentsData.enabled ? 0 : (AgentsData.usage && AgentsData.usage.ok ? 40 : (AgentsData.err !== "" ? 16 : 0))
    implicitHeight: pad * 2 + 30 + quotaH + (quotaH > 0 ? 8 : 0) + (shown.length ? shown.length * 54 : 56) + 12 + 38 + (asking || answer !== "" || askErr !== "" ? ansBox.height + 8 : 0)

    // ---------- шапка ----------
    Row {
        id: head
        width: parent.width
        spacing: 8
        Text { text: "󰚩"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
        Text { text: Tr.t("Помощники"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6; anchors.verticalCenter: parent.verticalCenter }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: w.busyN > 0 ? Tr.t("· работают: ") + w.busyN : (w.list.length ? Tr.t("· свободны") : "")
            color: w.busyN > 0 ? Theme.accent : Theme.sub; font.family: Theme.font; font.pixelSize: 11
        }
    }

    // ---------- лимиты Claude Code: окно 5 часов и неделя ----------
    Item {
        id: quota
        anchors { top: head.bottom; topMargin: 8 }
        width: parent.width; height: w.quotaH
        visible: height > 0
        Row {
            visible: AgentsData.usage !== null && AgentsData.usage.ok
            width: parent.width; spacing: 12
            Repeater {
                model: AgentsData.usage && AgentsData.usage.ok ? [{ t: Tr.t("5 ч"), u: AgentsData.usage.five }, { t: Tr.t("Неделя"), u: AgentsData.usage.seven }] : []
                Item {
                    required property var modelData
                    width: (quota.width - 12) / 2; height: 38
                    Text { text: modelData.t; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                    Text { anchors.right: parent.right; text: Math.round(modelData.u.util) + " %"; color: AgentsData.level(modelData.u.util); font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Bold }
                    Rectangle { y: 16; width: parent.width; height: 5; radius: 2.5; color: Theme.fill(0.14)
                        Rectangle { width: parent.width * Math.min(1, modelData.u.util / 100); height: parent.height; radius: 2.5; color: AgentsData.level(modelData.u.util) } }
                    Text { y: 24; text: Tr.t("сброс через ") + AgentsData.left(modelData.u.resets); color: Theme.sub; font.family: Theme.font; font.pixelSize: 9 }
                }
            }
        }
        Text { visible: !(AgentsData.usage && AgentsData.usage.ok) && AgentsData.err !== ""; text: Tr.t("󰖪 лимиты: ") + AgentsData.errText(AgentsData.err); color: Theme.yellow; font.family: Theme.iconFont; font.pixelSize: 10; elide: Text.ElideRight; width: parent.width }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["qs", "-c", "nameless", "ipc", "call", "agents", "toggle"]) }
    }

    // ---------- строки помощников ----------
    Column {
        id: rows
        anchors { top: quota.visible ? quota.bottom : head.bottom; topMargin: 8 }
        width: parent.width
        spacing: 4
        Repeater {
            model: w.shown
            Rectangle {
                id: row
                required property var modelData
                readonly property var st: w.info(modelData.status)
                width: rows.width; height: 50; radius: Theme.r(12)
                color: rma.containsMouse ? Theme.fill(0.12) : Theme.fill(0.05)
                Behavior on color { ColorAnimation { duration: 120 } }
                // знак помощника
                Rectangle {
                    id: badge
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30; radius: 9
                    color: row.modelData.kind === "codex" ? "#10a37f" : "#d97757"
                    Text { anchors.centerIn: parent; text: row.modelData.kind === "codex" ? "X" : "✳"; color: "white"; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Bold }
                    // точка состояния; «работает» мягко мигает
                    Rectangle {
                        x: parent.width - 8; y: parent.height - 8
                        width: 11; height: 11; radius: 5.5; color: row.st.c
                        border.width: 2; border.color: Theme.base
                        SequentialAnimation on opacity {
                            running: row.modelData.status === "busy" && w.visible
                            loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.35; to: 1; duration: 700; easing.type: Easing.InOutSine }
                        }
                    }
                }
                Column {
                    anchors { left: badge.right; leftMargin: 12; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 1
                    Row {
                        spacing: 6
                        Text { text: row.modelData.project; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text { text: row.st.t + " · " + w.ago(row.modelData.since); color: row.st.c; font.family: Theme.font; font.pixelSize: 11; anchors.baseline: parent.children[0].baseline }
                    }
                    Text {
                        visible: w.o.last !== false && text !== ""
                        width: parent.width; elide: Text.ElideRight
                        text: row.modelData.last !== "" ? row.modelData.last : row.modelData.prompt
                        color: Theme.sub; font.family: Theme.font; font.pixelSize: 10
                    }
                }
                MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: row.modelData.addr ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: w.focus(row.modelData) }
            }
        }
        // никто не запущен
        Item {
            visible: w.shown.length === 0
            width: parent.width; height: 56
            Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter } text: Tr.t("Не запущены"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 6
                Chip { text: "✳ Claude"; onClicked: w.launch("claude") }
                Chip { text: "X Codex"; onClicked: w.launch("codex") }
            }
        }
    }

    // ---------- быстрый вопрос ----------
    Row {
        id: askRow
        anchors { top: rows.bottom; topMargin: 12 }
        width: parent.width
        spacing: 6
        Rectangle {
            width: parent.width - kindChip.width - dirChip.width - 12; height: 34; radius: 17
            color: Theme.fill(0.08); border.width: 1; border.color: qin.activeFocus ? Theme.accent : Theme.line(0.2)
            TextInput {
                id: qin
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                verticalAlignment: TextInput.AlignVCenter; clip: true
                color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                enabled: !w.asking
                onAccepted: { w.send(text); text = ""; }
                Text { visible: qin.text === ""; anchors.verticalCenter: parent.verticalCenter; text: w.asking ? Tr.t("думаю…") : Tr.t("Вопрос, Enter"); color: Theme.sub; font: qin.font }
            }
        }
        Chip { id: kindChip; height: 34; text: w.askKind === "codex" ? "X Codex" : "✳ Claude"; on: true; onClicked: { w.askKind = w.askKind === "codex" ? "claude" : "codex"; Config.set("agents.ask", w.askKind); } }
        Chip { id: dirChip; height: 34; text: "󰉋 " + w.dirName(w.askDir); onClicked: w.nextDir() }
    }

    // ответ
    Rectangle {
        id: ansBox
        visible: w.asking || w.answer !== "" || w.askErr !== ""
        anchors { top: askRow.bottom; topMargin: 8 }
        width: parent.width; height: Math.min(150, atext.implicitHeight + 34)
        radius: Theme.r(12); color: Theme.fill(0.06); border.width: 1; border.color: w.askErr !== "" ? Theme.red : Theme.line(0.14)
        Flickable {
            anchors { fill: parent; margins: 10; bottomMargin: 24 }
            contentHeight: atext.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds
            Text {
                id: atext
                width: parent.width
                wrapMode: Text.Wrap
                text: w.asking ? Tr.t("Спрашиваю ") + (w.askKind === "codex" ? "Codex" : "Claude") + "… " + Math.max(0, Math.round(w.nowT - w.askStart / 1000)) + Tr.t(" с") : (w.askErr !== "" ? w.askErr : w.answer)
                color: w.askErr !== "" ? Theme.red : Theme.text; font.family: Theme.font; font.pixelSize: 11
            }
        }
        Row {
            anchors { right: parent.right; rightMargin: 8; bottom: parent.bottom; bottomMargin: 4 }
            spacing: 4
            Text { visible: w.asking; text: Tr.t("Отмена"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10; MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: w.cancel() } }
            Text { visible: !w.asking && w.answer !== ""; text: Tr.t("Копировать"); color: Theme.accent; font.family: Theme.font; font.pixelSize: 10; MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: w.copy() } }
            Text { visible: !w.asking; text: Tr.t("Скрыть"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10; MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: { w.answer = ""; w.askErr = ""; } } }
        }
    }

    component Chip: Rectangle {
        id: ch
        property alias text: ct.text
        property bool on: false
        signal clicked
        width: ct.implicitWidth + 18; height: 26
        radius: height / 2
        color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : (cma.containsMouse ? Theme.fill(0.18) : Theme.fill(0.08))
        Text { id: ct; anchors.centerIn: parent; color: Theme.text; font.family: Theme.font; font.pixelSize: 11 }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
    }
}
