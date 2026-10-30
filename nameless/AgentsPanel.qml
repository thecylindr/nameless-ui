import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Монитор помощников (плитка «Помощники» на шторке, пункт в баре, виджет): лимиты Claude Code, расход токенов, сессии.
//   Лимиты — те же цифры, что показывает /usage: окно 5 часов и неделя, время сброса, прогноз исчерпания по темпу последних 40 минут.
//   Расход — по журналам сессий (~/.claude/projects): сегодня, неделя, пять часов, по дням, моделям и проектам.
//   Сессии — кто запущен и что делает (agents.py).
PanelWindow {
    id: w
    screen: Compositor.panelScreen
    property var shell: null
    readonly property bool open: shell ? shell.agentsOpen : false
    function close() { if (shell) shell.agentsOpen = false; }
    property real progress: 0
    Component.onCompleted: { progress = Qt.binding(function () { return w.open ? 1 : 0; }); AgentsData.panelOpen = w.open; }
    Component.onDestruction: AgentsData.panelOpen = false
    onOpenChanged: { AgentsData.panelOpen = open; if (open) { AgentsData.refresh(false); poll.running = true; } }
    Behavior on progress { NumberAnimation { duration: Theme.dur(w.open); easing.type: Easing.OutCubic } }

    visible: progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-agents"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // сессии
    property var sessions: []
    readonly property string script: AgentsData.dir + "/agents.py"
    Process {
        id: poll
        command: ["python3", w.script]
        stdout: StdioCollector { onStreamFinished: { try { w.sessions = JSON.parse(text).agents || []; } catch (e) { } } }
    }
    Timer { interval: 3000; repeat: true; running: w.open; onTriggered: if (!poll.running) poll.running = true }
    Timer { interval: 1000; repeat: true; running: w.open; onTriggered: w.tick++ }
    property int tick: 0
    readonly property bool codex: Config.store.agents.statsProvider === "codex"
    readonly property bool dataEnabled: codex ? AgentsData.codexEnabled : AgentsData.enabled
    readonly property var u: codex ? AgentsData.codexUsage : AgentsData.usage
    readonly property var st: codex ? AgentsData.codexStats : AgentsData.stats
    readonly property var modelColors: ({ opus: "#b57bff", sonnet: "#4da3ff", haiku: "#34c759", fable: "#ff7a59" })

    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * w.progress }
    MouseArea { anchors.fill: parent; onClicked: w.close() }

    Surface {
        id: box
        alpha: Theme.overlayAlpha
        width: Math.min(parent.width - 40, 660)
        height: Math.min(parent.height - 60, 780)
        anchors.horizontalCenter: parent.horizontalCenter
        y: (parent.height - height) / 2 - 30 * (1 - w.progress)
        opacity: Math.min(1, w.progress * 2)
        radius: Theme.ios ? 30 : 22
        MouseArea { anchors.fill: parent }
        MoveArea { win: box; anchors { left: parent.left; right: parent.right; top: parent.top } height: 56 }
        focus: w.open
        Keys.onEscapePressed: w.close()

        Item {
            id: head
            x: 18; y: 14
            width: parent.width - 36; height: 40
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text { anchors.verticalCenter: parent.verticalCenter; text: "󰚩"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 22 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: Tr.t("Помощники"); color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
                    Text { text: (w.codex ? "Codex" : "Claude Code") + (w.u && w.u.plan ? Tr.t(" · план ") + w.u.plan : "") + (w.u && w.u.ok ? Tr.t(" · данные ") + w.u.age + Tr.t(" с назад") : ""); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 8
                GButton { ui: Theme; height: 34; icon: "󰑓"; label: AgentsData.loading ? Tr.t("Обновляю…") : Tr.t("Обновить"); active: !AgentsData.loading; onClicked: AgentsData.refresh(true) }
                GTile { ui: Theme; width: 36; height: 36; radius: 18; Text { anchors.centerIn: parent; text: "✕"; color: Theme.text; font.pixelSize: 13 } onClicked: w.close() }
            }
        }

        Flickable {
            anchors { top: head.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 18; rightMargin: 18; bottomMargin: 18 }
            contentHeight: col.implicitHeight + 8
            clip: true; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: col
                width: parent.width
                spacing: 12

                GSegment {
                    ui: Theme
                    options: [{ v: "claude", t: "Claude Code" }, { v: "codex", t: "Codex" }]
                    value: w.codex ? "codex" : "claude"
                    onPicked: v => { Config.set("agents.statsProvider", v); AgentsData.refresh(false); }
                }

                // ---------- лимиты ----------
                Card {
                    title: Tr.t("Лимиты")
                    Text {
                        visible: !w.dataEnabled
                        width: parent.width; wrapMode: Text.WordWrap
                        text: w.codex ? Tr.t("Статистика Codex выключена в разделе «Функции».") : Tr.t("Запросы лимитов выключены (Функции → «Лимиты Claude»).")
                        color: Theme.sub; font.family: Theme.font; font.pixelSize: 12
                    }
                    Text {
                        visible: w.dataEnabled && (!w.u || !w.u.ok)
                        width: parent.width; wrapMode: Text.WordWrap
                        text: w.codex ? Tr.t("Лимиты появятся после запроса в Codex. Данные читаются из локального журнала.") : (AgentsData.loading ? Tr.t("Получаю данные…") : (AgentsData.err !== "" ? AgentsData.errText(AgentsData.err) : Tr.t("Нет данных")))
                        color: Theme.yellow; font.family: Theme.font; font.pixelSize: 12
                    }
                    Meter {
                        visible: !w.codex && w.u && w.u.ok
                        label: Tr.t("Окно 5 часов"); value: w.u && w.u.ok ? w.u.five.util : 0
                        note: w.u && w.u.ok ? Tr.t("сброс через ") + AgentsData.left(w.u.five.resets) + " · " + AgentsData.clock(w.u.five.resets) + (w.tick >= 0 ? "" : "") : ""
                    }
                    Text {
                        visible: !w.codex && w.u && w.u.ok
                        width: parent.width; wrapMode: Text.WordWrap
                        text: !w.u || !w.u.ok ? "" : (w.u.eta ? Tr.t("При текущем темпе окно исчерпается через ") + AgentsData.etaText(w.u.eta) + Tr.t(" — раньше сброса.") : Tr.t("Темп безопасный: до сброса лимит не исчерпается."))
                        color: w.u && w.u.eta ? Theme.red : Theme.sub; font.family: Theme.font; font.pixelSize: 11
                    }
                    Meter {
                        visible: !w.codex && w.u && w.u.ok
                        label: Tr.t("Неделя"); value: w.u && w.u.ok && w.u.seven ? w.u.seven.util : 0
                        note: w.u && w.u.ok && w.u.seven ? Tr.t("сброс через ") + AgentsData.left(w.u.seven.resets) + " · " + AgentsData.clock(w.u.seven.resets) : ""
                    }
                    Meter { visible: !w.codex && w.u && w.u.ok && w.u.sonnet !== null; label: Tr.t("Неделя · Sonnet"); value: w.u && w.u.sonnet ? w.u.sonnet.util || 0 : 0; note: "" }
                    Meter { visible: !w.codex && w.u && w.u.ok && w.u.opus !== null; label: Tr.t("Неделя · Opus"); value: w.u && w.u.opus ? w.u.opus.util || 0 : 0; note: "" }
                    Repeater {
                        model: w.codex && w.dataEnabled ? AgentsData.quotaWindows(w.u, true) : []
                        Meter {
                            required property var modelData
                            label: modelData.t; value: modelData.u.util
                            note: modelData.u.resets > 0 ? Tr.t("сброс через ") + AgentsData.left(modelData.u.resets) : ""
                        }
                    }
                    // ход окна за последние замеры
                    Graph {
                        visible: !w.codex && w.u && w.u.ok && w.u.hist && w.u.hist.length > 2
                        width: parent.width; height: 60
                        maxValue: 100
                        series: [{ values: w.u && w.u.hist ? w.u.hist.map(function (h) { return h[1]; }) : [], color: Theme.accent }]
                    }
                    Text {
                        visible: !w.codex && AgentsData.err !== "" && w.u && w.u.ok
                        width: parent.width; wrapMode: Text.WordWrap
                        text: AgentsData.errText(AgentsData.err); color: Theme.yellow; font.family: Theme.font; font.pixelSize: 11
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: w.codex ? Tr.t("Снимок лимитов из журнала Codex, без сетевых запросов. Обновляется при работе Codex; время снимка указано сверху.") : Tr.t("Лимиты общие для Claude.ai, Claude Code и приложения. Запрос идёт с токеном Claude Code, сам токен нигде не сохраняется; отключается в «Функции».")
                        color: Theme.sub; font.family: Theme.font; font.pixelSize: 10; opacity: 0.8
                    }
                }

                // ---------- расход ----------
                Card {
                    title: Tr.t("Расход токенов")
                    Row {
                        width: parent.width
                        spacing: 8
                        Stat { width: (parent.width - 16) / 3; label: Tr.t("Сегодня"); value: w.st ? AgentsData.tok(w.st.today.tokens) : "…"; sub: w.st ? w.st.today.msgs + (w.codex ? Tr.t(" запросов модели") : Tr.t(" ответов")) : "" }
                        Stat { width: (parent.width - 16) / 3; label: Tr.t("7 дней"); value: w.st ? AgentsData.tok(w.st.week.tokens) : "…"; sub: w.st ? w.st.week.msgs + (w.codex ? Tr.t(" запросов модели") : Tr.t(" ответов")) : "" }
                        Stat { width: (parent.width - 16) / 3; label: Tr.t("Последние 5 часов"); value: w.st ? AgentsData.tok(w.st.block5h.tokens) : "…"; sub: !w.codex && w.st && w.u && w.u.ok && w.u.five.util > 1 ? "≈ " + AgentsData.tok(w.st.block5h.tokens / w.u.five.util) + Tr.t(" на 1 %") : "" }
                    }
                    Row {
                        visible: w.codex && w.st !== null
                        width: parent.width; spacing: 8
                        Stat { width: (parent.width - 8) / 2; label: Tr.t("Из кеша · 5 часов"); value: w.st ? AgentsData.tok(w.st.block5h.cacheRead) : "…"; sub: Tr.t("уже учтено во входе") }
                        Stat { width: (parent.width - 8) / 2; label: Tr.t("Reasoning · 5 часов"); value: w.st ? AgentsData.tok(w.st.block5h.reasoning) : "…"; sub: Tr.t("уже учтено в выходе") }
                    }
                    // по дням: столбики, цвета — модели
                    Row {
                        visible: w.st !== null
                        width: parent.width; height: 96; spacing: 6
                        readonly property real peak: w.st ? Math.max(1, Math.max.apply(null, w.st.days.map(function (d) { return d.tokens; }))) : 1
                        Repeater {
                            model: w.st ? w.st.days : []
                            Item {
                                required property var modelData
                                width: (parent.width - 36) / 7; height: parent.height
                                Column {
                                    anchors { left: parent.left; right: parent.right; bottom: dl.top; bottomMargin: 3 }
                                    spacing: 0
                                    Repeater {
                                        model: Object.keys(modelData.models)
                                        Rectangle {
                                            required property string modelData
                                            width: parent.width
                                            height: Math.max(0, 66 * (parent.parent.modelData.models[modelData] / parent.parent.parent.peak))
                                            color: w.modelColors[modelData] || Theme.sub
                                        }
                                    }
                                }
                                Text { id: dl; anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom } text: new Date(modelData.date).toLocaleString(Qt.locale("ru_RU"), "ddd"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                            }
                        }
                    }
                    Flow {
                        visible: w.st !== null
                        width: parent.width; spacing: 14
                        Repeater {
                            model: w.st ? w.st.models.filter(function (m) { return m[1] > 0; }) : []
                            Row {
                                required property var modelData
                                spacing: 5
                                Rectangle { width: 10; height: 10; radius: 2; color: w.modelColors[modelData[0]] || Theme.sub; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: modelData[0] + " " + AgentsData.tok(modelData[1]); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                            }
                        }
                    }
                    Repeater {
                        model: w.st ? w.st.projects : []
                        Row {
                            required property var modelData
                            width: parent.width
                            Text { width: parent.width - 90; elide: Text.ElideRight; text: "󰉋 " + modelData[0]; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 12 }
                            Text { width: 90; horizontalAlignment: Text.AlignRight; text: AgentsData.tok(modelData[1]); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
                        }
                    }
                    Text { width: parent.width; wrapMode: Text.WordWrap; text: w.codex ? Tr.t("Вход и выход по журналам Codex. Кеш и reasoning уже входят в итог; это расход токенов, а не процент квоты.") : Tr.t("Считаются вход, выход и запись кеша; чтение кеша дёшево и квоту почти не тратит."); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10; opacity: 0.8 }
                }

                // ---------- сессии ----------
                Card {
                    title: Tr.t("Сессии")
                    Text { visible: w.sessions.length === 0; text: Tr.t("Сейчас никто не запущен"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
                    Repeater {
                        model: w.sessions
                        Row {
                            required property var modelData
                            width: parent.width; spacing: 8
                            readonly property var inf: ({ busy: { t: Tr.t("работает"), c: Theme.accent }, idle: { t: Tr.t("ждёт задачу"), c: Theme.green } })[modelData.status] || { t: modelData.status, c: Theme.yellow }
                            Rectangle { width: 8; height: 8; radius: 4; color: parent.inf.c; anchors.verticalCenter: parent.verticalCenter }
                            Text { width: parent.width - 30 - 150; elide: Text.ElideRight; text: (modelData.kind === "codex" ? "X " : "✳ ") + modelData.project; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                            Text { width: 150; horizontalAlignment: Text.AlignRight; text: parent.inf.t + " · " + Math.max(0, Math.round(Date.now() / 1000 - modelData.since) + (w.tick * 0)) + Tr.t(" с"); color: parent.inf.c; font.family: Theme.font; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }
            }
        }
    }

    // ---------- части ----------
    component Card: Rectangle {
        id: cd
        property string title
        default property alias content: inner.data
        width: parent ? parent.width : 300
        height: inner.implicitHeight + 24 + (title !== "" ? 26 : 0)
        radius: Theme.r(18)
        color: Theme.fill(0.06); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.14)
        Text { x: 16; y: 12; visible: cd.title !== ""; text: cd.title; color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7 }
        Column { id: inner; x: 16; y: 12 + (cd.title !== "" ? 26 : 0); width: parent.width - 32; spacing: 8 }
    }
    // полоса лимита: подпись, процент, цвет по запасу
    component Meter: Item {
        id: mt
        property string label
        property real value: 0
        property string note
        width: parent ? parent.width : 300
        height: 44
        Text { text: mt.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
        Text { anchors.right: parent.right; text: Math.round(mt.value) + " %"; color: AgentsData.level(mt.value); font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold; font.features: { "tnum": 1 } }
        Rectangle {
            y: 22; width: parent.width; height: 8; radius: 4; color: Theme.fill(0.14)
            Rectangle { width: parent.width * Math.min(1, mt.value / 100); height: parent.height; radius: 4; color: AgentsData.level(mt.value); Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } } }
        }
        Text { y: 32; visible: mt.note !== ""; text: mt.note; color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
    }
    component Stat: Column {
        property string label
        property string value
        property string sub
        spacing: 2
        Text { text: label; color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
        Text { text: value; color: Theme.text; font.family: Theme.font; font.pixelSize: 20; font.weight: Font.Light }
        Text { text: sub; visible: sub !== ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
    }
}
