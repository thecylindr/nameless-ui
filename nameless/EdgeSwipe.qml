import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Жест от верхнего края, как на планшете: потянуть вниз у правой половины — шторка NameLess, у левой — уведомления.
// Работает пальцем (сенсорный экран) и мышью. Режим — Config.store.touch.edge: auto (только если есть сенсорный экран), on, off.
// Полоска у края тонкая: на сенсорном экране — 14 px, иначе — 3 px; в режиме off её нет
PanelWindow {
    id: w
    screen: Compositor.panelScreen
    property var shell: null
    property bool hasTouch: false
    Process {
        running: true
        command: ["sh", "-c", "hyprctl -j devices 2>/dev/null | jq '(.touch | length) + (.tablets | length)' 2>/dev/null || echo 0"]
        stdout: StdioCollector { onStreamFinished: w.hasTouch = (parseInt(text) || 0) > 0 }
    }
    readonly property string mode: Config.store.touch.edge || "auto"
    readonly property bool active: mode === "on" || (mode === "auto" && hasTouch)

    visible: active
    anchors { top: true; left: true; right: true }
    implicitHeight: hasTouch ? 14 : 3
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-edge"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    component Zone: Item {
        id: z
        property string target: "control"
        property bool fired: false
        DragHandler {
            target: null
            yAxis.enabled: true; xAxis.enabled: false
            onActiveChanged: if (active) z.fired = false
            onTranslationChanged: if (active && !z.fired && translation.y > 40) {
                z.fired = true;
                if (!w.shell) return;
                if (z.target === "control") w.shell.toggleControl(); else Notifs.centerOpen = true;
            }
        }
    }
    Zone { x: 0; width: parent.width / 2; height: parent.height; target: "notifs" }
    Zone { x: parent.width / 2; width: parent.width / 2; height: parent.height; target: "control" }
}
