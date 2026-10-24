import QtQuick
import Quickshell
import Quickshell.Io

// Клод — пиксельный персонаж Claude Code, который показывает, что делают помощники:
//   кто-то работает — печатает; ждёт вашего ответа — машет и зовёт; все свободны — бездельничает; тихо больше 10 минут — спит.
// Облачко — проект и последнее сообщение. Нажатие — монитор помощников. Данные — agents.py раз в 3 с, только пока виджет виден
Item {
    id: w
    property var list: []
    property double quietSince: Date.now()
    readonly property string script: (Quickshell.shellDir || (Quickshell.env("HOME") + "/.config/quickshell/nameless")) + "/agents.py"
    readonly property var busy: list.filter(function (a) { return a.status === "busy"; })
    readonly property var waiting: list.filter(function (a) { return /wait|input|permission|approval/i.test(a.status || ""); })
    readonly property string mood: waiting.length > 0 ? "wait" : (busy.length > 0 ? "work" : (Date.now() - quietSince > 600000 ? "sleep" : "idle"))
    readonly property var focusAgent: waiting.length > 0 ? waiting[0] : (busy.length > 0 ? busy[0] : (list.length > 0 ? list[0] : null))
    implicitHeight: 150

    Process {
        id: poll
        command: ["python3", w.script]
        stdout: StdioCollector {
            onStreamFinished: {
                try { w.list = JSON.parse(text).agents || []; } catch (e) { }
                if (w.busy.length > 0 || w.waiting.length > 0) w.quietSince = Date.now();
            }
        }
    }
    Timer { interval: 3000; repeat: true; running: w.visible && !Compositor.covered; triggeredOnStart: true; onTriggered: if (!poll.running) poll.running = true }

    property int tick: 0
    Timer { interval: Perf.eco ? 300 : 180; repeat: true; running: w.visible && !Compositor.covered; onTriggered: w.tick++ }

    // облачко
    Rectangle {
        id: bubble
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: bcol.implicitHeight + 16
        radius: 14
        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, Theme.panelAlpha)
        border.width: 1; border.color: w.mood === "wait" ? Theme.yellow : Theme.line(0.16)
        Column {
            id: bcol
            x: 12; y: 8; width: parent.width - 24
            spacing: 2
            Text {
                width: parent.width; elide: Text.ElideRight
                text: w.mood === "wait" ? Tr.t("Эй! Нужен ваш ответ") : (w.mood === "work" ? Tr.t("Работаю…") + (w.busy.length > 1 ? " ×" + w.busy.length : "")
                      : (w.mood === "sleep" ? Tr.t("Сплю. Разбудите задачей") : (w.list.length ? Tr.t("Свободен, жду задачу") : Tr.t("Помощники не запущены"))))
                color: w.mood === "wait" ? Theme.yellow : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
            }
            Text {
                visible: w.focusAgent !== null
                width: parent.width; elide: Text.ElideRight
                text: w.focusAgent ? (w.focusAgent.project + (w.focusAgent.last ? " · " + w.focusAgent.last : "")) : ""
                color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
            }
        }
        // хвостик облачка
        Rectangle { width: 10; height: 10; rotation: 45; color: bubble.color; x: clawd.x + clawd.width / 2 - 5; y: parent.height - 5 }
    }

    PixelPet {
        id: clawd
        species: "clawd"; look: "clawd"
        unit: 4
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 6 }
        pose: w.mood
        tick: w.tick
    }
    // ноутбук перед Клодом, пока он работает
    Rectangle {
        visible: w.mood === "work"
        anchors { left: clawd.right; leftMargin: -6; bottom: clawd.bottom; bottomMargin: 6 }
        width: 26; height: 16; radius: 2
        color: "#2b2d36"; border.width: 2; border.color: "#14151a"
        Rectangle { anchors.centerIn: parent; width: 16; height: 2; color: Theme.accent; opacity: w.tick % 2 ? 1 : 0.4 }
    }
    Text {
        visible: w.mood === "sleep"
        anchors { left: clawd.right; bottom: clawd.top; bottomMargin: -10 }
        text: "z"; color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 + (w.tick % 6)
        opacity: 1 - (w.tick % 6) / 8
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["qs", "-c", "nameless", "ipc", "call", "agents", "toggle"]) }
}
