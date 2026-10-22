import QtQuick
import Quickshell

// Расход токенов Claude Code: сегодня, за неделю и за последние 5 часов, столбики по дням (цвет — модель), модели в подписи.
// Данные — журналы сессий (claude_stats.py, раз в 2 минуты, разбор инкрементальный). Нажатие — монитор помощников
WCard {
    id: w
    readonly property bool codex: Config.store.tokens.provider === "codex"
    readonly property var st: codex ? AgentsData.codexStats : AgentsData.stats
    readonly property var colors: ({ opus: "#b57bff", sonnet: "#4da3ff", haiku: "#34c759", fable: "#ff7a59" })
    readonly property bool compact: (Config.store.tokens.view || "chart") === "numbers"
    implicitHeight: pad * 2 + 22 + 8 + 46 + (compact ? 0 : 108)

    Row {
        id: head
        spacing: 8
        Text { text: "󰆼"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 14 }
        Text { text: Tr.t("Расход токенов") + (w.codex ? " · Codex" : " · Claude"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6 }
    }
    Text {
        visible: w.st === null
        anchors { top: head.bottom; topMargin: 10 }
        text: !(w.codex ? AgentsData.codexEnabled : AgentsData.enabled) ? Tr.t("Выключено: Функции → «Лимиты Claude»") : Tr.t("Считаю по журналам…")
        color: Theme.sub; font.family: Theme.font; font.pixelSize: 12
    }
    Row {
        id: nums
        visible: w.st !== null
        anchors { top: head.bottom; topMargin: 8 }
        width: parent.width; spacing: 6
        Repeater {
            model: w.st ? [{ l: Tr.t("Сегодня"), v: w.st.today.tokens }, { l: Tr.t("7 дней"), v: w.st.week.tokens }, { l: Tr.t("5 часов"), v: w.st.block5h.tokens }] : []
            Column {
                required property var modelData
                width: (nums.width - 12) / 3
                Text { text: modelData.l; color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                Text { text: AgentsData.tok(modelData.v); color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Light }
            }
        }
    }
    // столбики по дням
    Row {
        visible: w.st !== null && !w.compact
        anchors { top: nums.bottom; topMargin: 8 }
        width: parent.width; height: 96; spacing: 5
        readonly property real peak: w.st ? Math.max(1, Math.max.apply(null, w.st.days.map(function (d) { return d.tokens; }))) : 1
        Repeater {
            model: w.st ? w.st.days : []
            Item {
                id: day
                required property var modelData
                required property int index
                width: (parent.width - 30) / 7; height: parent.height
                Column {
                    anchors { left: parent.left; right: parent.right; bottom: dl.top; bottomMargin: 3 }
                    Repeater {
                        model: Object.keys(day.modelData.models)
                        Rectangle {
                            required property string modelData
                            width: parent.width; radius: 2
                            height: Math.max(0, 62 * (day.modelData.models[modelData] / day.parent.peak))
                            color: w.colors[modelData] || Theme.sub
                        }
                    }
                }
                Text { id: dl; anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom } text: new Date(day.modelData.date).toLocaleString(Qt.locale("ru_RU"), "ddd"); color: day.index === 6 ? Theme.text : Theme.sub; font.family: Theme.font; font.pixelSize: 9 }
            }
        }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["qs", "-c", "nameless", "ipc", "call", "agents", "toggle"]) }
}
