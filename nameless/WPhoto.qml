import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// Фоторамка: картинки из папки (Config.store.photo.dir) по очереди с плавной сменой; клик — следующая,
// правый клик — открыть в просмотрщике. Список папки читается раз в 10 минут
Item {
    id: w
    readonly property var o: Config.store.photo
    readonly property string dir: (o.dir || "~/Pictures").replace(/^~/, Quickshell.env("HOME"))
    property var files: []
    property int idx: 0
    readonly property bool empty: false
    implicitHeight: width * 0.66

    Process {
        id: lister
        command: ["sh", "-c", "find \"$1\" -maxdepth 2 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) 2>/dev/null | shuf | head -n 300", "sh", w.dir]
        stdout: StdioCollector { onStreamFinished: { w.files = text.split("\n").filter(function (x) { return x !== ""; }); w.idx = 0; } }
    }
    onDirChanged: lister.running = true
    Timer { interval: 600000; repeat: true; running: w.visible; triggeredOnStart: true; onTriggered: if (!lister.running) lister.running = true }
    Timer { interval: Math.max(5, w.o.interval || 30) * 1000; repeat: true; running: w.visible && w.files.length > 1 && !Compositor.covered; onTriggered: w.next() }
    function next() { if (files.length > 0) idx = (idx + 1) % files.length; }
    readonly property string cur: files.length > 0 ? "file://" + files[idx % files.length] : ""

    ClippingRectangle {
        anchors.fill: parent
        radius: Theme.ios ? 26 : 20
        color: Theme.fill(0.1)
        // две картинки по очереди: новая проявляется поверх старой
        property bool flip: false
        Image { id: a; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(w.width * 1.5, w.height * 1.5); opacity: parent.flip ? 0 : 1; Behavior on opacity { NumberAnimation { duration: 700 } } }
        Image { id: b; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(w.width * 1.5, w.height * 1.5); opacity: parent.flip ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 700 } } }
        Connections {
            target: w
            function onCurChanged() {
                var c = a.parent;
                if (c.flip) { a.source = w.cur; } else { b.source = w.cur; }
                c.flip = !c.flip;
            }
        }
        Text { anchors.centerIn: parent; visible: w.files.length === 0; text: Tr.t("󰋩  Нет картинок в ") + (w.o.dir || "~/Pictures"); color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 12 }
    }
    Rim { anchors.fill: parent; ui: Theme; radius: Theme.ios ? 26 : 20; strength: 0.6 }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (m) => { if (m.button === Qt.MiddleButton) { if (w.files.length) Quickshell.execDetached(["xdg-open", w.files[w.idx]]); } else w.next(); }
    }
}
