import QtQuick
import Quickshell
import Quickshell.Io

// Обновления: сколько пакетов ждёт (checkupdates из pacman-contrib и yay -Qua для AUR), первые из списка;
// «Обновить» — мастер программ, обновление в терминале. Проверка — раз в Config.store.updates.interval минут
WCard {
    id: w
    property var repo: []
    property var aur: []
    property bool checking: false
    property string err: ""
    readonly property int n: repo.length + aur.length
    implicitHeight: pad * 2 + Math.max(30, head.height) + (n > 0 ? Math.min(4, n) * 18 + 44 : 22)

    Process {
        id: proc
        command: ["sh", "-c", "command -v checkupdates >/dev/null || { echo NOTOOL; exit; }; checkupdates 2>/dev/null; echo ---; command -v yay >/dev/null && yay -Qua 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                w.checking = false;
                if (text.indexOf("NOTOOL") === 0) { w.err = "нужен pacman-contrib (checkupdates)"; return; }
                var parts = text.split("---"), split = function (s) { return (s || "").split("\n").filter(function (x) { return x.trim() !== ""; }); };
                w.repo = split(parts[0]); w.aur = split(parts[1]); w.err = "";
            }
        }
    }
    function check() { if (!proc.running) { checking = true; proc.running = true; } }
    Timer { interval: Math.max(15, Config.store.updates.interval || 60) * 60000; repeat: true; running: w.visible; triggeredOnStart: true; onTriggered: w.check() }

    Row {
        id: head
        width: parent.width
        spacing: 10
        Text { text: "󰚰"; color: w.n > 0 ? Theme.accent : Theme.green; font.family: Theme.iconFont; font.pixelSize: 24; anchors.verticalCenter: parent.verticalCenter }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 34
            Text { width: parent.width; elide: Text.ElideRight; text: w.checking ? Tr.t("Проверка…") : (w.err !== "" ? Tr.t("Не проверить") : (w.n > 0 ? Tr.t("Обновлений: ") + w.n : Tr.t("Система свежая"))); color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold }
            Text { width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; text: w.err !== "" ? w.err : (w.n > 0 ? Tr.t("репозитории ") + w.repo.length + " · AUR " + w.aur.length : Tr.t("проверка раз в ") + (Config.store.updates.interval || 60) + Tr.t(" мин")); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
        }
    }
    Column {
        visible: w.n > 0
        anchors { top: head.bottom; topMargin: 8 }
        width: parent.width
        spacing: 2
        Repeater {
            model: w.repo.concat(w.aur).slice(0, 4)
            Text {
                required property string modelData
                width: parent.width; elide: Text.ElideRight
                // «пакет старая -> новая»
                text: modelData.split(" ")[0] + "  " + (modelData.split(" ")[3] || "")
                color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
            }
        }
        Row {
            topPadding: 6
            spacing: 6
            GButton { ui: Theme; height: 30; implicitWidth: 100; label: Tr.t("Обновить"); icon: "󰚰"; on: true; onClicked: Quickshell.execDetached(["qs", "-c", "nameless", "ipc", "call", "programs", "toggle"]) }
            GButton { ui: Theme; height: 30; implicitWidth: 92; label: Tr.t("Проверить"); onClicked: w.check() }
        }
    }
    MouseArea { visible: w.n === 0; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.check() }
}
