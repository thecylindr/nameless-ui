import QtQuick
import Quickshell

// Лимиты Claude Code: два кольца — окно 5 часов и неделя; под ними время до сброса и прогноз «хватит до сброса / исчерпается через…».
// Цвет кольца — по запасу: зелёный, жёлтый от 70 %, красный от 90 %. Вид «полосы» — компактнее. Нажатие — монитор помощников.
// Данные — AgentsData (usage.py, раз в 2 минуты; выключается в «Функции» → «Лимиты Claude»)
WCard {
    id: w
    readonly property bool codex: Config.store.claude.provider === "codex"
    readonly property bool enabledData: codex ? AgentsData.codexEnabled : AgentsData.enabled
    readonly property var u: codex ? AgentsData.codexUsage : AgentsData.usage
    readonly property bool ok: enabledData && u !== null && u.ok === true
    readonly property bool bars: (Config.store.claude.view || "rings") === "bars"
    implicitHeight: pad * 2 + 22 + (!w.enabledData || !ok ? 56 : (bars ? 96 : 128)) + (ok ? 22 : 0)

    Row {
        id: head
        spacing: 8
        Text { text: "󰚩"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 14 }
        Text { text: (w.codex ? Tr.t("Лимиты Codex") : Tr.t("Лимиты Claude")); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6 }
        Text { visible: w.ok && w.u.plan !== ""; text: w.ok ? "· " + w.u.plan : ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
    }

    // нет данных: причина
    Text {
        visible: !w.ok
        anchors { top: head.bottom; topMargin: 10 }
        width: parent.width; wrapMode: Text.WordWrap
        text: !w.enabledData ? Tr.t("Лимиты выключены: Функции → «Лимиты Claude»") : (w.codex ? Tr.t("Лимиты появятся после запроса в Codex") : (AgentsData.loading ? Tr.t("Получаю данные…") : (AgentsData.err !== "" ? "󰖪 " + AgentsData.errText(AgentsData.err) : Tr.t("Нет данных"))))
        color: AgentsData.err !== "" ? Theme.yellow : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 12
    }

    // кольца
    Row {
        visible: w.ok && !w.bars
        anchors { top: head.bottom; topMargin: 10 }
        width: parent.width; spacing: 10
        Repeater {
            model: w.ok ? AgentsData.quotaWindows(w.u, w.codex) : []
            Column {
                required property var modelData
                width: (parent.width - 10) / 2; spacing: 4
                GaugeRing {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(88, parent.width); height: width
                    value: modelData.u.util; tone: AgentsData.level(modelData.u.util)
                    text: Math.round(modelData.u.util) + "%"; caption: modelData.t
                }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: Tr.t("сброс через ") + AgentsData.left(modelData.u.resets); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
            }
        }
    }
    // полосы
    Column {
        visible: w.ok && w.bars
        anchors { top: head.bottom; topMargin: 10 }
        width: parent.width; spacing: 8
        Repeater {
            model: w.ok ? AgentsData.quotaWindows(w.u, w.codex) : []
            Item {
                required property var modelData
                width: parent.width; height: 38
                Text { text: modelData.t; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                Text { anchors.right: parent.right; text: Math.round(modelData.u.util) + " %"; color: AgentsData.level(modelData.u.util); font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold }
                Rectangle { y: 18; width: parent.width; height: 6; radius: 3; color: Theme.fill(0.14); Rectangle { width: parent.width * Math.min(1, modelData.u.util / 100); height: parent.height; radius: 3; color: AgentsData.level(modelData.u.util) } }
                Text { y: 27; text: Tr.t("сброс через ") + AgentsData.left(modelData.u.resets); color: Theme.sub; font.family: Theme.font; font.pixelSize: 9 }
            }
        }
    }
    // прогноз
    Text {
        visible: w.ok
        anchors { bottom: parent.bottom }
        width: parent.width; elide: Text.ElideRight
        text: !w.ok ? "" : (w.codex ? Tr.t("Снимок Codex · ") + w.u.age + Tr.t(" с назад") : (w.u.eta ? Tr.t("󰀦 исчерпается через ") + AgentsData.etaText(w.u.eta) : Tr.t("󰄬 хватит до сброса")))
        color: w.ok && w.u.eta ? Theme.red : Theme.green; font.family: Theme.iconFont; font.pixelSize: 11
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["qs", "-c", "nameless", "ipc", "call", "agents", "toggle"]) }
}
