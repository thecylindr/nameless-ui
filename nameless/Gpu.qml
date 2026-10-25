pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Графика ноутбука с двумя видеокартами (gpu.sh сборки): режим «Гибрид» / «Экономия» / «Производительность», состояние дискретной
// и кто её держит. Общий режим питания (процессор + видеокарта) и вопрос при отключении зарядки — Power.qml
Singleton {
    id: g
    property string rice: ""
    readonly property string script: rice !== "" ? rice + "/scripts/system/gpu.sh" : ""
    property var st: ({ mode: "", hybrid: false, holders: [], state: "", relogin: false, dgpu: "" })
    readonly property bool hybrid: st.hybrid === true
    readonly property var o: Config.store.gpu || ({})

    Process {
        running: true
        // папка, где скрипт действительно есть: сборка (~/.config/glassrice/rice) могла быть старой, без него — тогда копия установщика
        command: ["sh", "-c", "r=$(cat \"$HOME/.config/glassrice/rice\" 2>/dev/null); for d in \"$r\" \"$HOME/.local/share/nameless\" \"$HOME/newdesign/glassrice\" \"$HOME/glassrice\"; do [ -n \"$d\" ] && [ -f \"$d/scripts/system/gpu.sh\" ] && { echo \"$d\"; exit; }; done"]
        stdout: StdioCollector { onStreamFinished: { g.rice = text.trim(); g.refresh(); } }
    }
    property var after: null              // что сделать, когда придёт свежее состояние
    Process {
        id: stProc
        command: [g.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { g.st = JSON.parse(text); } catch (e) { }
                if (g.after) { var f = g.after; g.after = null; f(); }
            }
        }
    }
    function refresh(then) { if (then) after = then; if (script !== "" && !stProc.running) stProc.running = true; }

    Process { id: setProc; onExited: g.refresh() }
    function setMode(m) { if (script === "") return; setProc.command = [script, "mode", m]; setProc.running = true; }
    function free() { if (script === "") return; setProc.command = [script, "free"]; setProc.running = true; }

    // вопрос при отключении зарядки задаёт Power.qml (режим питания целиком: процессор и видеокарта)
    function tell(title, body) { Quickshell.execDetached(["notify-send", "-a", "NameLess", "-i", "video-display", title, body]); }
}
