import QtQuick
import Quickshell
import Quickshell.Io

// GIF на рабочем столе: любая анимированная картинка (GIF, WebP, APNG); «пиксельно» — без сглаживания, для пиксель-арта.
// Папка — показываются по очереди все GIF из неё (смена раз в interval с); файл — один. Без фона-карточки по умолчанию.
// Настройки — Config.store.gif ({ path, pixel, scale, interval, card }); выбор файла — нажатие на пустой виджет или «Рабочий стол»
Item {
    id: w
    readonly property var o: Config.store.gif || ({})
    readonly property string path: (o.path || "").replace(/^~/, Quickshell.env("HOME"))
    property var files: []
    property int cur: 0
    readonly property string src: files.length > 0 ? "file://" + files[cur % files.length] : ""
    // высота по картинке: её размер × масштаб, ужатый по ширине виджета (не выше 420)
    readonly property real k: Math.max(0.1, o.scale || 1)
    readonly property real fit: Math.min(1, (width - (o.card ? 24 : 0)) / Math.max(1, img.implicitWidth * k))
    implicitHeight: img.status === AnimatedImage.Ready ? Math.min(420, img.implicitHeight * k * fit) + (o.card ? 24 : 0) : 120

    // файл — сам он; папка — все анимированные картинки в ней
    Process {
        id: scan
        running: w.path !== ""
        command: ["sh", "-c", "if [ -d \"$1\" ]; then find \"$1\" -maxdepth 1 -type f \\( -iname '*.gif' -o -iname '*.webp' -o -iname '*.png' \\) | sort; elif [ -f \"$1\" ]; then echo \"$1\"; fi", "sh", w.path]
        stdout: StdioCollector { onStreamFinished: { w.files = text.split("\n").filter(function (x) { return x !== ""; }); w.cur = 0; } }
    }
    onPathChanged: { scan.running = false; if (path !== "") scan.running = true; }
    Timer { interval: Math.max(5, w.o.interval || 30) * 1000; repeat: true; running: w.visible && w.files.length > 1 && !Compositor.covered; onTriggered: w.cur++ }

    Surface { visible: w.o.card === true; anchors.fill: parent; radius: Theme.ios ? 26 : 20 }
    AnimatedImage {
        id: img
        anchors.centerIn: parent
        source: w.src
        // стол закрыт окнами — анимация стоит (кадры GIF не декодируются впустую)
        playing: w.visible && !Compositor.covered
        smooth: w.o.pixel === false
        mipmap: false
        cache: false
        fillMode: Image.PreserveAspectFit
        width: implicitWidth * w.k * w.fit
        height: Math.min(420, implicitHeight * w.k * w.fit)
    }
    Column {
        visible: w.src === "" || img.status === AnimatedImage.Error
        anchors.centerIn: parent
        spacing: 6
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰵸"; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 30 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: img.status === AnimatedImage.Error ? Tr.t("Не удалось открыть файл") : Tr.t("Нажмите, чтобы выбрать GIF"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
    }
    Process {
        id: picker
        command: ["sh", "-c", "kdialog --getopenfilename \"$HOME\" 'image/gif image/webp image/png' 2>/dev/null || zenity --file-selection --file-filter='*.gif *.webp *.png' 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { var p = text.trim(); if (p !== "") Config.set("gif.path", p); } }
    }
    MouseArea {
        anchors.fill: parent
        enabled: w.src === "" || img.status === AnimatedImage.Error
        cursorShape: Qt.PointingHandCursor
        onClicked: picker.running = true
    }
}
