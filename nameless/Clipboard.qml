import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Буфер обмена (SUPER+SHIFT+V, плитка на шторке): история копирования с поиском, закреплённое, изображения.
//   клик — вернуть в буфер (и закрыть); Enter — первое найденное; ↑ ↓ — выбор; значок булавки — закрепить (закреплённое хранится
//   в настройках и не стирается); корзина — удалить запись; «Очистить» — стереть всю историю (двойное нажатие).
// История — cliphist; её наполняют наблюдатели wl-paste, их запускает shell.qml. Пароли тоже попадают в историю —
// для них есть отключение истории в настройках (Config.store.clipboard.on)
PanelWindow {
    id: w
    property var shell: null
    readonly property bool open: shell ? shell.clipboardOpen : false
    function close() { if (shell) shell.clipboardOpen = false; }
    property real progress: 0
    Component.onCompleted: { progress = Qt.binding(function () { return w.open ? 1 : 0; }); refresh(); query.forceActiveFocus(); }
    Behavior on progress { NumberAnimation { duration: Theme.dur(w.open); easing.type: Easing.OutCubic } }

    visible: progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    onOpenChanged: if (open) { refresh(); query.text = ""; cur = 0; query.forceActiveFocus(); }

    readonly property string cache: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/glassrice/clip"
    readonly property var cfg: Config.store.clipboard
    readonly property var pins: cfg.pins || []

    // ---------- данные ----------
    property var entries: []              // [{ id, text, image, meta }]
    property bool loading: true
    property bool missing: false
    Process {
        id: listProc
        command: ["sh", "-c", "command -v cliphist >/dev/null || { echo '@@MISSING@@'; exit 0; }; cliphist list 2>/dev/null | head -n 300"]
        stdout: StdioCollector {
            onStreamFinished: {
                w.loading = false;
                if (text.indexOf("@@MISSING@@") === 0) { w.missing = true; w.entries = []; return; }
                w.missing = false;
                var l = text.split("\n"), out = [];
                for (var i = 0; i < l.length; i++) {
                    if (l[i] === "") continue;
                    var t = l[i].indexOf("\t"), id = l[i].substring(0, t), pv = l[i].substring(t + 1);
                    var img = pv.indexOf("[[ binary data") === 0;
                    out.push({ id: id, text: img ? "" : pv.replace(/\s+/g, " ").trim(), image: img, meta: img ? pv.replace("[[ binary data ", "").replace(" ]]", "") : "" });
                }
                w.entries = out;
                if (out.length) thumbProc.start();
            }
        }
    }
    function refresh() { loading = true; if (!listProc.running) listProc.running = true; }

    // миниатюры изображений: декодируются в кэш (первые 16)
    Process {
        id: thumbProc
        function start() {
            var ids = w.entries.filter(function (e) { return e.image; }).slice(0, 16).map(function (e) { return e.id; });
            if (!ids.length) return;
            command = ["sh", "-c", "mkdir -p \"$1\"; shift; for id in \"$@\"; do [ -s \"$0/$id.img\" ] || cliphist decode \"$id\" > \"$0/$id.img\" 2>/dev/null; done; echo done", w.cache].concat(ids);
            running = true;
        }
        stdout: StdioCollector { onStreamFinished: w.thumbTick++ }
    }
    property int thumbTick: 0

    // ---------- поиск и выбор ----------
    readonly property string q: query.text.trim().toLowerCase()
    readonly property var shown: entries.filter(function (e) { return q === "" || (!e.image && e.text.toLowerCase().indexOf(q) >= 0); }).slice(0, 150)
    readonly property var pinShown: pins.filter(function (t) { return q === "" || t.toLowerCase().indexOf(q) >= 0; })
    property int cur: 0
    // единый список для клавиатуры: сперва закреплённое, затем история
    readonly property int total: pinShown.length + shown.length
    function pickAt(i) {
        if (i < pinShown.length) copyText(pinShown[i]);
        else copyId(shown[i - pinShown.length].id);
    }
    function copyId(id) { Quickshell.execDetached(["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", id]); close(); }
    function copyText(t) { Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", t]); close(); }
    function remove(e) { Quickshell.execDetached(["sh", "-c", "printf '%s\\t%s\\n' \"$1\" \"$2\" | cliphist delete", "sh", e.id, e.image ? "[[ binary data" : e.text]); entries = entries.filter(function (x) { return x.id !== e.id; }); }
    property string armed: ""
    Timer { id: disarm; interval: 3000; onTriggered: w.armed = "" }
    function wipe() { if (armed !== "wipe") { armed = "wipe"; disarm.restart(); return; } Quickshell.execDetached(["cliphist", "wipe"]); entries = []; armed = ""; }

    // закрепить: полный текст записи — в настройки
    property string pinId: ""
    Process {
        id: pinProc
        stdout: StdioCollector {
            onStreamFinished: {
                var t = text.replace(/\n$/, "");
                if (t !== "" && w.pins.indexOf(t) < 0) Config.set("clipboard.pins", [t.substring(0, 4000)].concat(w.pins).slice(0, 30));
            }
        }
    }
    function pin(e) { pinProc.command = ["sh", "-c", "cliphist decode \"$1\"", "sh", e.id]; pinProc.running = true; }
    function unpin(t) { Config.set("clipboard.pins", w.pins.filter(function (x) { return x !== t; })); }

    // ---------- окно ----------
    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * w.progress }
    MouseArea { anchors.fill: parent; onClicked: w.close() }

    Surface {
        id: box
        alpha: Theme.overlayAlpha
        width: Math.min(parent.width - 40, 580)
        height: Math.min(parent.height - 60, 680)
        anchors.horizontalCenter: parent.horizontalCenter
        y: (parent.height - height) / 2 - 30 * (1 - w.progress)
        opacity: Math.min(1, w.progress * 2)
        radius: Theme.ios ? 30 : 22
        MouseArea { anchors.fill: parent }
        MoveArea { win: box; anchors { left: parent.left; right: parent.right; top: parent.top } height: 56 }
        focus: w.open
        Keys.onEscapePressed: { if (query.text !== "") query.text = ""; else w.close(); }

        // шапка
        Item {
            id: head
            x: 18; y: 14
            width: parent.width - 36; height: 40
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text { anchors.verticalCenter: parent.verticalCenter; text: "󰅌"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 22 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: Tr.t("Буфер обмена"); color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
                    Text { text: w.entries.length + Tr.t(" в истории · ") + w.pins.length + Tr.t(" закреплено"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 8
                GButton { ui: Theme; height: 34; icon: "󰆴"; label: w.armed === "wipe" ? Tr.t("Точно очистить?") : Tr.t("Очистить"); danger: true; on: w.armed === "wipe"; visible: w.entries.length > 0; onClicked: w.wipe() }
                GTile { ui: Theme; width: 36; height: 36; radius: 18; Text { anchors.centerIn: parent; text: "✕"; color: Theme.text; font.pixelSize: 13 } onClicked: w.close() }
            }
        }

        // поиск
        Rectangle {
            id: sbox
            anchors { top: head.bottom; topMargin: 12; left: parent.left; right: parent.right; leftMargin: 18; rightMargin: 18 }
            height: 38; radius: 19
            color: Theme.fill(0.08); border.width: 1; border.color: query.activeFocus ? Theme.accent : Theme.line(0.2)
            Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "󰍉"; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 14 }
            TextInput {
                id: query
                anchors { fill: parent; leftMargin: 38; rightMargin: 14 }
                verticalAlignment: TextInput.AlignVCenter; clip: true
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                onTextChanged: w.cur = 0
                onAccepted: if (w.total > 0) w.pickAt(Math.min(w.cur, w.total - 1))
                Keys.onUpPressed: w.cur = Math.max(0, w.cur - 1)
                Keys.onDownPressed: w.cur = Math.min(w.total - 1, w.cur + 1)
                Keys.onEscapePressed: { if (text !== "") text = ""; else w.close(); }
                Text { visible: query.text === ""; anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Поиск по истории"); color: Theme.sub; font: query.font }
            }
        }

        // список: закреплённое сверху, дальше история
        ListView {
            id: list
            anchors { top: sbox.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 18; rightMargin: 18; bottomMargin: 18 }
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: w.total
            currentIndex: w.cur
            highlightFollowsCurrentItem: false
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            delegate: Rectangle {
                id: row
                required property int index
                readonly property bool isPin: index < w.pinShown.length
                readonly property var e: isPin ? null : w.shown[index - w.pinShown.length]
                readonly property string txt: isPin ? w.pinShown[index] : (e ? e.text : "")
                readonly property bool img: !isPin && e && e.image
                width: ListView.view.width
                height: img ? 92 : 48
                radius: Theme.r(14)
                color: index === w.cur ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20) : (rma.containsMouse ? Theme.fill(0.12) : Theme.fill(0.06))
                border.width: isPin ? 1 : 0; border.color: Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, 0.5)
                Image {
                    visible: row.img
                    x: 8; y: 8; width: 120; height: 76
                    source: row.img ? "file://" + w.cache + "/" + row.e.id + ".img?" + w.thumbTick : ""
                    sourceSize: Qt.size(240, 152); fillMode: Image.PreserveAspectFit; asynchronous: true; cache: false
                }
                Text {
                    anchors { left: parent.left; leftMargin: row.img ? 140 : 14; right: acts.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: row.img ? Tr.t("Изображение · ") + row.e.meta : row.txt
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                    wrapMode: Text.WrapAnywhere; maximumLineCount: row.img ? 1 : 2; elide: Text.ElideRight
                }
                MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.pickAt(row.index) }
                Row {
                    id: acts
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    opacity: rma.containsMouse || row.index === w.cur ? 1 : 0.35
                    // булавка: закрепить; у закреплённого — открепить
                    Item {
                        width: 28; height: 28
                        visible: !row.img
                        Text { anchors.centerIn: parent; text: row.isPin ? "󰐃" : "󰤱"; color: row.isPin ? Theme.accent2 : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 14 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (row.isPin) w.unpin(row.txt); else w.pin(row.e) }
                    }
                    Item {
                        width: 28; height: 28
                        visible: !row.isPin
                        Text { anchors.centerIn: parent; text: "󰆴"; color: Theme.red; font.family: Theme.iconFont; font.pixelSize: 14 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.remove(row.e) }
                    }
                }
            }
            // пусто / нет cliphist
            Column {
                anchors.centerIn: parent
                visible: w.total === 0
                spacing: 8
                width: parent.width - 40
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: w.loading ? "󰑓" : "󰅌"; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 34 }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    text: w.missing ? Tr.t("Не установлен cliphist") : (w.loading ? Tr.t("Читаю историю…") : (w.q !== "" ? Tr.t("Ничего не найдено") : Tr.t("История пока пуста: скопируйте что-нибудь")))
                    color: Theme.sub; font.family: Theme.font; font.pixelSize: 13
                }
                GButton {
                    visible: w.missing
                    anchors.horizontalCenter: parent.horizontalCenter
                    ui: Theme; height: 34; icon: "󰇚"; label: Tr.t("Установить cliphist и wl-clipboard"); on: true
                    onClicked: if (w.shell) w.shell.installPkgs(["cliphist", "wl-clipboard"], "clipboard")       // терминал поверх, окно вернётся само
                }
            }
        }
    }
}
