import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Мастер обоев (SUPER+B, Пункт управления → «Обои»):
//   Мои обои  — папки из ~/wallpapers, миниатюры; клик — поставить, значок корзины (двойное нажатие) — удалить файл
//   Интернет  — источники с открытыми лицензиями (Wikimedia Commons, NASA, музей искусств Чикаго) и другие (Wallhaven, Bing,
//               Unsplash); у каждой картинки видны автор, лицензия, источник и описание; праздничные запросы;
//               клик — выбрать, затем «Поставить» (скачать и поставить) или «Скачать» в выбранную папку.
//               Кто автор скачанного — в ~/wallpapers/CREDITS.tsv, при наведении на обои во вкладке «Мои обои» показан автор
// Данные из сети даёт wallnet.sh рядом (бесплатные источники без ключей). Ставит обои wallpapers.sh — тот же сервис, что у ротации
PanelWindow {
    id: w
    property var shell: null
    readonly property bool open: shell ? shell.wallpapersOpen : false
    function close() { if (shell) shell.wallpapersOpen = false; }
    property real progress: 0
    Component.onCompleted: {
        progress = Qt.binding(function () { return w.open ? 1 : 0; });
        dirsProc.running = true; envProc.running = true;
    }
    Behavior on progress { NumberAnimation { duration: Theme.dur(w.open); easing.type: Easing.OutCubic } }

    visible: progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-wallpapers"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    readonly property string home: Quickshell.env("HOME")
    readonly property string wallRoot: home + "/wallpapers"
    readonly property string wallScript: home + "/wallpapers/wallpapers.sh"
    readonly property string net: (Quickshell.shellDir || (home + "/.config/quickshell/nameless")) + "/wallnet.sh"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/hypr-theme"

    property int tab: 0
    property string note: ""
    Timer { id: noteT; interval: 4000; onTriggered: w.note = "" }
    function say(t) { note = t; noteT.restart(); }

    // ---------- текущие обои и папка по умолчанию ----------
    property string current: ""
    FileView { id: curFile; path: w.stateDir + "/wallpaper"; watchChanges: true; printErrors: false
               onFileChanged: reload(); onLoaded: w.current = text().trim() }
    property string themeDir: w.wallRoot + "/everyday"
    property int interval: 30                  // смена обоев по таймеру, минут (из темы)
    Process {
        id: envProc
        command: ["sh", "-c", ". \"$1/wallpaper.env\" 2>/dev/null; echo \"${WALL_DIR:-$HOME/wallpapers/everyday}\"; echo \"${WALL_INTERVAL:-30}\"", "sh", w.stateDir]
        stdout: StdioCollector { onStreamFinished: { var l = text.trim().split("\n"), d = (l[0] || "").trim(); if (d !== "") { w.themeDir = d; if (w.curDir === "") w.curDir = d; } if (l.length > 1 && Number(l[1]) > 0) w.interval = Number(l[1]); } }
    }

    // ---------- авторы скачанных обоев: ~/wallpapers/CREDITS.tsv (файл, название, автор, лицензия, страница) ----------
    property var credits: ({})
    FileView {
        id: credFile
        path: w.wallRoot + "/CREDITS.tsv"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            var m = {}, l = text().split("\n");
            for (var i = 0; i < l.length; i++) { var f = l[i].split("\t"); if (f.length >= 3 && f[0] !== "") m[f[0]] = { title: f[1], author: f[2], license: f[3] || "", page: f[4] || "" }; }
            w.credits = m;
        }
    }

    // ---------- мои обои ----------
    property var dirs: []
    property var dirCount: ({})
    property string curDir: ""
    property var files: []
    // альбомы листаются по страницам: в папке могут быть сотни обоев
    property int lpage: 1
    readonly property int pageSize: 24
    property string filter: ""
    readonly property var shown: filter === "" ? files : files.filter(function (f) { return base(f).toLowerCase().indexOf(filter.toLowerCase()) >= 0; })
    readonly property int lpages: Math.max(1, Math.ceil(shown.length / pageSize))
    readonly property int curPage: Math.max(1, Math.min(lpage, lpages))
    readonly property var shownFiles: shown.slice((curPage - 1) * pageSize, curPage * pageSize)
    // папка отсутствует на диске (dirCount не знает её) — только для папки темы, которой ещё нет
    function dirMissing(p) { return p !== "" && w.dirCount[p] === undefined; }
    property bool newDirOpen: false
    function makeDir(name) {
        var n = name.trim().replace(/[\/]/g, "");
        if (n === "") return;
        var p = wallRoot + "/" + n;
        Quickshell.execDetached(["mkdir", "-p", "--", p]);
        newDirOpen = false;
        curDir = p;
        dirsT.restart();
        say(Tr.t("Папка создана: ") + n);
    }
    Timer { id: dirsT; interval: 500; onTriggered: { dirsProc.running = true; w.listFiles(); } }
    // интервал смены обоев по таймеру — настройка темы
    function setInterval2(m) {
        Quickshell.execDetached([Theme.script, "set", ".wallpaper.interval", String(m)]);
        interval = m;
        say(Tr.t("Смена обоев раз в ") + m + Tr.t(" мин"));
    }
    // файлы, перетащенные в окно, копируются в открытую папку
    function addFiles(urls) {
        if (curDir === "") return;
        var n = 0;
        for (var i = 0; i < urls.length; i++) {
            var p = decodeURIComponent(String(urls[i]).replace("file://", ""));
            if (/\.(jpe?g|png|webp)$/i.test(p)) { Quickshell.execDetached(["cp", "-n", "--", p, curDir + "/"]); n++; }
        }
        say(n > 0 ? Tr.t("Добавлено обоев: ") + n : Tr.t("Нужны картинки: jpg, png или webp"));
        dirsT.restart();
    }
    // папка темы: из неё берутся обои при смене темы и по таймеру
    function setThemeDir(path) {
        Quickshell.execDetached([Theme.script, "set", ".wallpaper.dir", JSON.stringify(path)]);
        say(Tr.t("Папка темы: ") + base(path));
        envT.restart();
    }
    Timer { id: envT; interval: 1500; onTriggered: envProc.running = true }
    Process {
        id: dirsProc
        command: ["sh", "-c", "find \"$1\" -maxdepth 1 -mindepth 1 -type d ! -name '.*' | sort | while read -r d; do printf '%s\\t%s\\n' \"$d\" \"$(find \"$d\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | wc -l)\"; done", "sh", w.wallRoot]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.trim() === "" ? [] : text.trim().split("\n"), d = [], c = {};
                for (var i = 0; i < l.length; i++) { var f = l[i].split("\t"); d.push(f[0]); c[f[0]] = Number(f[1]) || 0; }
                // папка темы показывается всегда: если её нет (удалили, тема новая), мастер предложит создать, а не пропадёт молча
                if (d.indexOf(w.themeDir) < 0 && w.themeDir.indexOf(w.wallRoot + "/") === 0) d.push(w.themeDir);
                w.dirs = d; w.dirCount = c;
                if (w.curDir === "") w.curDir = w.themeDir; else w.listFiles();
            }
        }
    }
    Process {
        id: filesProc
        stdout: StdioCollector { onStreamFinished: w.files = text.trim() === "" ? [] : text.trim().split("\n") }
    }
    function listFiles() {
        if (curDir === "") return;
        filesProc.command = ["sh", "-c", "find \"$1\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) -printf '%T@ %p\\n' | sort -rn | cut -d' ' -f2-", "sh", curDir];
        filesProc.running = true;
    }
    onCurDirChanged: { lpage = 1; listFiles(); }
    function base(p) { return p.substring(p.lastIndexOf("/") + 1); }
    function setWall(path) { Quickshell.execDetached([wallScript, "--set", path]); say(Tr.t("Обои установлены")); }
    property string delArm: ""
    Timer { id: delT; interval: 3000; onTriggered: w.delArm = "" }
    function del(path) {
        if (path.indexOf(wallRoot + "/") !== 0) return;      // удаляются только файлы из ~/wallpapers
        if (delArm !== path) { delArm = path; delT.restart(); return; }
        Quickshell.execDetached(["rm", "-f", "--", path]);
        delArm = ""; Qt.callLater(listFiles); dirsProc.running = true; say(Tr.t("Файл удалён"));
    }

    // ---------- интернет ----------
    property string src: "commons"
    property bool openOnly: false
    property string query: ""
    property int page: 1
    property var results: []
    property bool loading: false
    property string err: ""
    property string errKind: ""           // timeout | offline | server | failed — источник не ответил
    property bool timedOut: false
    // сторож: если источник молчит дольше 30 с, запрос обрывается и мастер подсказывает, что делать
    Timer { id: watchdog; interval: 30000; onTriggered: { if (w.loading) { w.timedOut = true; searchProc.running = false; w.loading = false; w.results = []; w.errKind = "timeout"; } } }
    property var pick: null
    property string dest: ""
    readonly property string destDir: dest !== "" ? dest : themeDir
    // open — свободная лицензия: автор указывается, использование разрешено
    readonly property var allSources: [
        { v: "commons", t: "Wikimedia Commons", open: true }, { v: "nasa", t: Tr.t("NASA: космос"), open: true }, { v: "artic", t: Tr.t("Музей искусств (CC0)"), open: true },
        { v: "cleveland", t: Tr.t("Музей Кливленда (CC0)"), open: true },
        { v: "wallhaven", t: "Wallhaven", open: false }, { v: "wallhaven_anime", t: Tr.t("Wallhaven: аниме"), open: false }, { v: "bing", t: Tr.t("Bing: картинки дня"), open: false },
        { v: "bingworld", t: Tr.t("Bing: другие страны"), open: false }, { v: "picsum", t: "Unsplash", open: false }]
    function srcName(v) { var a = allSources.filter(function (x) { return x.v === v; })[0]; return a ? a.t : v; }
    // следующий источник по кругу (с учётом фильтра «только открытые»)
    function nextSource() { var l = sources, i = 0; for (var k = 0; k < l.length; k++) if (l[k].v === src) i = k; src = l[(i + 1) % l.length].v; }
    readonly property var sources: openOnly ? allSources.filter(function (x) { return x.open; }) : allSources
    onOpenOnlyChanged: if (openOnly && !allSources.filter(function (x) { return x.v === src; })[0].open) src = "commons"
    readonly property var topics: [[Tr.t("Природа"), "nature"], [Tr.t("Космос"), "space"], [Tr.t("Горы"), "mountains"], [Tr.t("Город"), "city night"], [Tr.t("Океан"), "ocean"], [Tr.t("Минимализм"), "minimal"],
                                   [Tr.t("Абстракция"), "abstract"], [Tr.t("Аниме"), "anime"], [Tr.t("Машины"), "cars"], [Tr.t("Лес"), "forest"]]
    readonly property var holidays: [[Tr.t("󰉒 Новый год"), "new year winter"], [Tr.t("󰋑 14 февраля"), "valentine hearts"], [Tr.t("󰮯 Хэллоуин"), "halloween"]]
    // подборки: источник + тема одним нажатием (лучшее под каждую тему)
    readonly property var collections: [
        { t: Tr.t("󰽥 Глубокий космос"), src: "nasa", q: "nebula galaxy" }, { t: Tr.t("󰖨 Закаты"), src: "wallhaven", q: "sunset landscape" },
        { t: Tr.t("󰔱 Горы и туман"), src: "wallhaven", q: "misty mountains" }, { t: Tr.t("󰖐 Дождь в городе"), src: "wallhaven", q: "rain city night" },
        { t: Tr.t("󰟿 Пиксель-арт"), src: "wallhaven", q: "pixel art" }, { t: Tr.t("󰉏 Картины мастеров"), src: "artic", q: "landscape" },
        { t: Tr.t("󰌪 Природа (CC)"), src: "commons", q: "forest" }, { t: Tr.t("󰎆 Лоу-фай аниме"), src: "wallhaven_anime", q: "lofi" },
        { t: Tr.t("󰘚 Киберпанк"), src: "wallhaven", q: "cyberpunk city" }, { t: Tr.t("󰋙 Минимализм"), src: "wallhaven", q: "minimalist dark" },
        { t: Tr.t("󰼄 Японская осень"), src: "wallhaven", q: "japan autumn" }, { t: Tr.t("󰼬 Северное сияние"), src: "commons", q: "aurora borealis" }]
    function openCollection(c) { query = c.q; searchField.text = c.q; if (src !== c.src) src = c.src; else search(true); }
    // вся страница в папку: по одной, с записью авторов в CREDITS.tsv
    property int packLeft: 0
    Process {
        id: packProc
        stdout: SplitParser { onRead: line => { if (line.indexOf("/") >= 0) w.packLeft = Math.max(0, w.packLeft - 1); } }
        onExited: { w.say(Tr.t("Подборка скачана в ") + w.destDir); w.packLeft = 0; dirsProc.running = true; }
    }
    function downloadPage() {
        if (packProc.running || results.length === 0) return;
        var args = [];
        results.slice(0, 12).forEach(function (r) { args.push(r.full, src + "-" + r.id, r.title || "", r.author || "", r.license || "", r.page || ""); });
        packLeft = Math.min(12, results.length);
        packProc.command = ["bash", "-c", "n=\"$1\"; d=\"$2\"; shift 2; while [ $# -ge 6 ]; do bash \"$n\" get \"$1\" \"$d\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\" || echo fail; shift 6; done", "sh", net, destDir].concat(args);
        packProc.running = true;
    }

    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (w.timedOut) { w.timedOut = false; return; }
                watchdog.stop();
                w.loading = false;
                var d = null;
                try { d = JSON.parse(text); } catch (e) { d = null; }
                if (d && !Array.isArray(d) && d.error) { w.errKind = d.error; w.results = []; return; }
                if (!Array.isArray(d)) { w.errKind = "failed"; w.results = []; return; }
                w.errKind = "";
                if (d.length === 0 && w.page === 1) w.err = Tr.t("Ничего не найдено");
                else w.err = "";
                w.results = d;
                netGrid.contentY = 0;
            }
        }
    }
    property string lastKey: ""
    function search(reset) {
        if (reset) { page = 1; results = []; pick = null; }
        var key = src + "\n" + query + "\n" + page;
        if (loading && key === lastKey) return;       // тот же запрос уже идёт (сработали сразу два триггера)
        lastKey = key;
        loading = true; err = ""; errKind = ""; timedOut = false; watchdog.restart();
        searchProc.command = ["bash", net, "search", src, query, String(page)];
        searchProc.running = true;
    }
    function goPage(p) { if (loading || p < 1) return; page = p; pick = null; results = []; search(false); }
    function ask(q) { query = q; searchField.text = q; search(true); }
    onSrcChanged: if (tab === 1) search(true)
    onTabChanged: if (tab === 1 && results.length === 0 && !loading) search(true)

    property bool downloading: false
    property bool setAfter: true
    Process {
        id: getProc
        stdout: StdioCollector {
            onStreamFinished: {
                w.downloading = false;
                var p = text.trim();
                if (p === "") { w.say(Tr.t("Не удалось скачать")); return; }
                if (w.setAfter) w.setWall(p); else w.say(Tr.t("Скачано: ") + w.base(p));
                dirsProc.running = true;
            }
        }
    }
    function download(setIt) {
        if (!pick || downloading) return;
        setAfter = setIt; downloading = true;
        getProc.command = ["bash", net, "get", pick.full, destDir, src + "-" + pick.id, pick.title || "", pick.author || "", pick.license || "", pick.page || ""];
        getProc.running = true;
    }

    // ---------- окно ----------
    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * w.progress }
    MouseArea { anchors.fill: parent; onClicked: w.close() }

    Surface {
        id: box
        alpha: Theme.overlayAlpha
        width: Math.min(parent.width - 60, 1180)
        height: Math.min(parent.height - 40, 800)
        anchors.horizontalCenter: parent.horizontalCenter
        y: (parent.height - height) / 2 - 40 * (1 - w.progress)
        opacity: Math.min(1, w.progress * 2)
        radius: Theme.ios ? 30 : 22
        MouseArea { anchors.fill: parent }
        MoveArea { win: box; anchors { left: parent.left; right: parent.right; top: parent.top } height: 64 }
        focus: w.open
        Keys.onEscapePressed: { if (searchField.activeFocus && searchField.text !== "") searchField.text = ""; else w.close(); }
        // листание страниц клавишами: ← → и PageUp / PageDown (пока не набирается запрос)
        Keys.onPressed: (e) => {
            if (searchField.activeFocus) { e.accepted = false; return; }
            var dir = (e.key === Qt.Key_Left || e.key === Qt.Key_PageUp) ? -1 : ((e.key === Qt.Key_Right || e.key === Qt.Key_PageDown) ? 1 : 0);
            if (dir === 0) { e.accepted = false; return; }
            if (w.tab === 0) { var np = w.curPage + dir; if (np >= 1 && np <= w.lpages) { w.lpage = np; localGrid.contentY = 0; } }
            else if (dir < 0 || netPager.canNext) w.goPage(w.page + dir);
            e.accepted = true;
        }

        // ---------- шапка ----------
        Item {
            id: top
            x: 18; y: 14
            width: parent.width - 36; height: 40
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text { anchors.verticalCenter: parent.verticalCenter; text: "󰸉"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 24 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: Tr.t("Обои"); color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
                    Text {
                        text: w.note !== "" ? w.note : (Theme.cosmos !== "off" ? Tr.t("Включён космос: обои скрыты небом, но будут видны после выхода из него") : Tr.t("сейчас: ") + w.base(w.current) + (w.credits[w.base(w.current)] ? " · " + w.credits[w.base(w.current)].author : ""))
                        color: w.note !== "" ? Theme.accent : Theme.sub; font.family: Theme.font; font.pixelSize: 10
                    }
                }
            }
            GSegment {
                ui: Theme
                width: 330
                anchors { right: wClose.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                options: [{ v: "0", t: Tr.t("Мои обои"), icon: "󰉏" }, { v: "1", t: Tr.t("Интернет"), icon: "󰖟" }]
                value: String(w.tab)
                onPicked: (v) => w.tab = Number(v)
            }
            GTile {
                id: wClose
                ui: Theme
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 36; height: 36; radius: 18
                Text { anchors.centerIn: parent; text: "✕"; color: Theme.text; font.pixelSize: 13 }
                onClicked: w.close()
            }
        }

        // ================= мои обои =================
        Item {
            visible: w.tab === 0
            x: 18; y: 66
            width: parent.width - 36; height: parent.height - 84
            DropArea { anchors.fill: parent; keys: ["text/uri-list"]; onDropped: (d) => { if (d.hasUrls) w.addFiles(d.urls); } }

            // что стоит сейчас: картинка, имя, автор и переключение
            Rectangle {
                id: hero
                width: parent.width; height: 64; radius: Theme.r(16)
                color: Theme.fill(0.07)
                Rectangle {
                    id: heroThumb
                    x: 8; y: 8; width: 76; height: 48; radius: Theme.r(10); clip: true; color: Theme.fill(0.1)
                    Image { anchors.fill: parent; source: w.current !== "" ? "file://" + w.current : ""; sourceSize: Qt.size(160, 100); fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true }
                }
                Column {
                    x: 96; anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(60, parent.width - 96 - heroBtns.width - 20)
                    Text { text: Tr.t("Сейчас на столе"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: w.base(w.current) + (w.credits[w.base(w.current)] ? " · " + w.credits[w.base(w.current)].author : "")
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                }
                Row {
                    id: heroBtns
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Chip { text: Tr.t("󰒮 Назад"); onClicked: Quickshell.execDetached([w.wallScript, "--prev"]) }
                    Chip { text: Tr.t("󰒭 Дальше"); onClicked: { Quickshell.execDetached([w.wallScript, "--next"]); w.say(Tr.t("Следующие обои")); } }
                }
            }
            Flow {
                id: dirRow
                anchors { top: hero.bottom; topMargin: 10 }
                width: parent.width
                spacing: 6
                Repeater {
                    model: w.dirs
                    Chip {
                        required property string modelData
                        text: (modelData === w.themeDir ? "★ " : "") + w.base(modelData) + " · " + (w.dirMissing(modelData) ? Tr.t("нет папки") : (w.dirCount[modelData] || 0))
                        on: w.curDir === modelData
                        accent: modelData === w.themeDir
                        onClicked: w.curDir = modelData
                    }
                }
                Chip { text: Tr.t("＋ Новая папка"); on: w.newDirOpen; onClicked: { w.newDirOpen = !w.newDirOpen; if (w.newDirOpen) newDirField.forceActiveFocus(); } }
                Rectangle {
                    visible: w.newDirOpen
                    width: 190; height: 30; radius: 15
                    color: Theme.fill(0.08); border.width: 1; border.color: newDirField.activeFocus ? Theme.accent : Theme.line(0.2)
                    TextInput {
                        id: newDirField
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        verticalAlignment: TextInput.AlignVCenter; clip: true
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                        onAccepted: { w.makeDir(text); text = ""; }
                        Text { visible: newDirField.text === ""; anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Название папки, Enter"); color: Theme.sub; font: newDirField.font }
                    }
                }
                Chip { visible: w.curDir !== "" && w.curDir !== w.themeDir; text: Tr.t("★ Сделать папкой темы"); onClicked: w.setThemeDir(w.curDir) }
                Chip { text: Tr.t("󰉋 Открыть папку"); onClicked: Quickshell.execDetached(["xdg-open", w.curDir]) }
                Chip { text: Tr.t("󰒝 Случайные сейчас"); onClicked: { Quickshell.execDetached([w.wallScript, "--next"]); w.say(Tr.t("Следующие обои")); } }
                // смена по таймеру: настройка темы
                Repeater {
                    model: [5, 15, 30, 60]
                    Chip { required property int modelData; text: Tr.t("󰔛 ") + modelData + Tr.t(" мин"); on: w.interval === modelData; onClicked: w.setInterval2(modelData) }
                }
                // поиск по названию в открытой папке
                Rectangle {
                    width: 210; height: 30; radius: 15
                    color: Theme.fill(0.08); border.width: 1; border.color: filterField.activeFocus ? Theme.accent : Theme.line(0.2)
                    Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: "󰍉"; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 13 }
                    TextInput {
                        id: filterField
                        anchors { fill: parent; leftMargin: 34; rightMargin: 12 }
                        verticalAlignment: TextInput.AlignVCenter; clip: true
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                        onTextChanged: { w.filter = text.trim(); w.lpage = 1; }
                        Text { visible: filterField.text === ""; anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Поиск по названию"); color: Theme.sub; font: filterField.font }
                    }
                }
            }
            GridView {
                id: localGrid
                anchors { top: dirRow.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: localPager.top; bottomMargin: 8 }
                clip: true
                cellWidth: Math.floor(width / Math.max(2, Math.floor(width / 230)))
                cellHeight: Math.round(cellWidth * 0.62)
                model: w.shownFiles
                boundsBehavior: Flickable.StopAtBounds
                delegate: Item {
                    id: lc
                    required property string modelData
                    width: localGrid.cellWidth; height: localGrid.cellHeight
                    readonly property bool isCur: w.current === modelData
                    Rectangle {
                        anchors { fill: parent; margins: 5 }
                        radius: Theme.r(14); clip: true
                        color: Theme.fill(0.08)
                        border.width: lc.isCur ? 2 : 1; border.color: lc.isCur ? Theme.accent : Theme.line(0.16)
                        Placeholder { anchors.fill: parent; busy: limg.status !== Image.Ready }
                        Image {
                            id: limg
                            anchors.fill: parent
                            source: "file://" + lc.modelData
                            sourceSize: Qt.size(360, 220); fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                        }
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 24; color: Qt.rgba(0, 0, 0, 0.5); visible: lma.containsMouse || lc.isCur
                            Text { anchors { fill: parent; leftMargin: 8; rightMargin: 8 } verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: (lc.isCur ? "󰄬 " : "") + (w.credits[w.base(lc.modelData)] ? w.credits[w.base(lc.modelData)].title + " — " + w.credits[w.base(lc.modelData)].author : w.base(lc.modelData)); color: "white"; font.family: Theme.iconFont; font.pixelSize: 10 }
                        }
                        MouseArea { id: lma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.setWall(lc.modelData) }
                        // удаление: двойное нажатие
                        Rectangle {
                            visible: lma.containsMouse || delMa.containsMouse
                            anchors { right: parent.right; top: parent.top; margins: 6 }
                            width: dT.implicitWidth + 14; height: 24; radius: 12
                            color: w.delArm === lc.modelData ? Theme.red : Qt.rgba(0, 0, 0, 0.55)
                            Text { id: dT; anchors.centerIn: parent; text: w.delArm === lc.modelData ? Tr.t("Удалить?") : "󰆴"; color: "white"; font.family: Theme.iconFont; font.pixelSize: 12 }
                            MouseArea { id: delMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.del(lc.modelData) }
                        }
                    }
                }
                Column {
                    visible: w.shown.length === 0 && !filesProc.running
                    anchors.centerIn: parent; spacing: 10
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: w.filter !== "" ? Tr.t("Ничего не найдено") : (w.dirMissing(w.curDir) ? Tr.t("Папки «") + w.base(w.curDir) + Tr.t("» ещё нет") : Tr.t("В этой папке пока нет обоев — загляните во вкладку «Интернет»"))
                        color: Theme.sub; font.family: Theme.font; font.pixelSize: 13
                    }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; visible: w.filter === ""; text: Tr.t("Перетащите картинки в это окно, чтобы добавить их сюда"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter; spacing: 6; visible: w.filter === ""
                        Chip { visible: w.dirMissing(w.curDir); text: Tr.t("Создать папку"); on: true; onClicked: { Quickshell.execDetached(["mkdir", "-p", "--", w.curDir]); dirsT.restart(); } }
                        Chip { text: Tr.t("Интернет"); onClicked: w.tab = 1 }
                    }
                }
                Column { visible: filesProc.running && w.files.length === 0; anchors.centerIn: parent; spacing: 8; Spinner { anchors.horizontalCenter: parent.horizontalCenter; size: 30 } Text { text: Tr.t("Читаю альбом…"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 13 } }
            }
            Pager {
                id: localPager
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                page: w.curPage; pages: w.lpages
                info: w.shown.length + Tr.t(" обоев")
                onGo: (p) => { w.lpage = p; localGrid.contentY = 0; }
            }
        }

        // ================= интернет =================
        Item {
            visible: w.tab === 1
            x: 18; y: 66
            width: parent.width - 36; height: parent.height - 84

            Column {
                id: netTop
                width: parent.width
                spacing: 8
                Flow {
                    width: parent.width; spacing: 6
                    Repeater {
                        model: w.sources
                        Chip { required property var modelData; text: (modelData.open ? "󰄬 " : "") + modelData.t; on: w.src === modelData.v; accent: modelData.open; onClicked: w.src = modelData.v }
                    }
                    Chip { text: w.openOnly ? Tr.t("󰒓 Только открытые: вкл.") : Tr.t("󰒓 Только открытые лицензии"); on: w.openOnly; onClicked: w.openOnly = !w.openOnly }
                }
                Rectangle {
                    visible: w.src !== "bing" && w.src !== "bingworld" && w.src !== "picsum"
                    width: parent.width; height: 38; radius: 19
                    color: Theme.fill(0.08); border.width: 1; border.color: searchField.activeFocus ? Theme.accent : Theme.line(0.2)
                    Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "󰍉"; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 14 }
                    TextInput {
                        id: searchField
                        anchors { fill: parent; leftMargin: 38; rightMargin: 14 }
                        verticalAlignment: TextInput.AlignVCenter; clip: true
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                        onAccepted: { w.query = text.trim(); w.search(true); }
                        Text { visible: searchField.text === ""; anchors.verticalCenter: parent.verticalCenter; text: w.src === "commons" ? Tr.t("Поиск по-английски, Enter (пусто — избранные фото)") : Tr.t("Поиск по-английски, Enter"); color: Theme.sub; font: searchField.font }
                    }
                }
                // подборки: источник и тема сразу
                Flow {
                    width: parent.width; spacing: 6
                    Text { text: Tr.t("Подборки:"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; topPadding: 6 }
                    Repeater { model: w.collections; Chip { required property var modelData; text: modelData.t; on: w.src === modelData.src && w.query === modelData.q; accent: true; onClicked: w.openCollection(modelData) } }
                }
                // тематические запросы
                Flow {
                    width: parent.width; spacing: 6
                    visible: w.src !== "bing" && w.src !== "bingworld" && w.src !== "picsum"
                    Repeater { model: w.holidays; Chip { required property var modelData; text: modelData[0]; on: w.query === modelData[1]; accent: true; onClicked: w.ask(modelData[1]) } }
                    Repeater { model: w.topics; Chip { required property var modelData; text: modelData[0]; on: w.query === modelData[1]; onClicked: w.ask(modelData[1]) } }
                }
            }

            GridView {
                id: netGrid
                anchors { top: netTop.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: netPager.top; bottomMargin: 8 }
                clip: true
                cellWidth: Math.floor(width / Math.max(2, Math.floor(width / 250)))
                cellHeight: Math.round(cellWidth * 0.62)
                model: w.results
                boundsBehavior: Flickable.StopAtBounds
                delegate: Item {
                    id: nc
                    required property var modelData
                    width: netGrid.cellWidth; height: netGrid.cellHeight
                    readonly property bool picked: w.pick !== null && w.pick.id === modelData.id
                    Rectangle {
                        anchors { fill: parent; margins: 5 }
                        radius: Theme.r(14); clip: true
                        color: Theme.fill(0.08)
                        border.width: nc.picked ? 2 : 1; border.color: nc.picked ? Theme.accent : Theme.line(0.16)
                        Placeholder { anchors.fill: parent; busy: nimg.status !== Image.Ready }
                        Image {
                            id: nimg
                            anchors.fill: parent
                            source: nc.modelData.thumb
                            sourceSize: Qt.size(400, 240); fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                        }
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 24; color: Qt.rgba(0, 0, 0, 0.5); visible: nma.containsMouse || nc.picked
                            Text { anchors { fill: parent; leftMargin: 8; rightMargin: 8 } verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: nc.modelData.title; color: "white"; font.family: Theme.font; font.pixelSize: 10 }
                        }
                        MouseArea { id: nma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: w.pick = nc.modelData }
                    }
                }
                Text { visible: w.results.length === 0 && !w.loading && w.errKind === ""; anchors.centerIn: parent; text: w.err !== "" ? w.err : Tr.t("Выберите запрос"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 13 }
                // источник не ответил: что случилось и что можно сделать
                Column {
                    visible: w.errKind !== "" && !w.loading
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 40, 520)
                    spacing: 10
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰖪"; color: Theme.yellow; font.family: Theme.iconFont; font.pixelSize: 40 }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        text: "«" + w.srcName(w.src) + "» " + ({ timeout: Tr.t("не отвечает: истекло время ожидания"), offline: Tr.t("недоступен: нет соединения"), server: Tr.t("вернул ошибку сервера"), failed: Tr.t("не удалось получить") })[w.errKind]
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        text: Tr.t("Попробуйте другой источник или включите VPN / прокси: часть сервисов недоступна из некоторых регионов и сетей.")
                        color: Theme.sub; font.family: Theme.font; font.pixelSize: 12
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        GButton { ui: Theme; height: 34; icon: "󰑓"; label: Tr.t("Повторить"); onClicked: w.search(true) }
                        GButton { ui: Theme; height: 34; icon: "󰒝"; label: Tr.t("Другой источник"); on: true; onClicked: w.nextSource() }
                        GButton { visible: Vpn.available; ui: Theme; height: 34; icon: "󰦝"; label: Tr.t("Открыть ") + Vpn.name; onClicked: Vpn.open() }
                    }
                }
                Column { visible: w.loading; anchors.centerIn: parent; spacing: 8; Spinner { anchors.horizontalCenter: parent.horizontalCenter; size: 34 } Text { text: Tr.t("Загрузка…"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 13 } }
            }

            Pager {
                id: netPager
                anchors { horizontalCenter: parent.horizontalCenter; bottom: netBar.top; bottomMargin: 8 }
                page: w.page
                pages: 0
                canNext: w.results.length > 0 && !w.loading
                info: w.loading ? Tr.t("загрузка…") : (w.results.length + Tr.t(" на странице"))
                onGo: (p) => w.goPage(p)
            }
            // скачать всю страницу в выбранную папку
            Chip {
                anchors { right: parent.right; verticalCenter: netPager.verticalCenter }
                visible: w.results.length > 0
                text: w.packLeft > 0 ? Tr.t("󰇚 Скачиваю… осталось ") + w.packLeft : Tr.t("󰇚 Скачать всю страницу (") + Math.min(12, w.results.length) + ")"
                accent: true
                onClicked: w.downloadPage()
            }

            // выбранная картинка: кто автор, лицензия, откуда; куда сохранить и что сделать
            Rectangle {
                id: netBar
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: w.pick ? 112 : 54; radius: Theme.r(14)
                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                color: Theme.fill(0.06); border.width: 1; border.color: Theme.line(0.14)
                Column {
                    anchors { left: parent.left; leftMargin: 16; right: btnRow.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Text { width: parent.width; elide: Text.ElideRight; text: w.downloading ? Tr.t("Скачиваю…") : (w.pick ? w.pick.title : (w.loading ? Tr.t("Загрузка…") : Tr.t("Выберите картинку"))); color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text { visible: w.pick !== null; width: parent.width; elide: Text.ElideRight; text: w.pick ? Tr.t("Автор: ") + w.pick.author : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 11 }
                    Text { visible: w.pick !== null; width: parent.width; elide: Text.ElideRight; text: w.pick ? Tr.t("Лицензия: ") + w.pick.license + (w.pick.open ? Tr.t("  ✓ открытая") : "") : ""; color: w.pick && w.pick.open ? "#34c759" : Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                    Text { visible: w.pick !== null; width: parent.width; elide: Text.ElideRight; text: w.pick ? Tr.t("Источник: ") + w.pick.source + "  ·  " + w.pick.res : ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                    Text { visible: w.pick !== null && w.pick.desc !== ""; width: parent.width; elide: Text.ElideRight; text: w.pick ? w.pick.desc : ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                }
                Row {
                    id: btnRow
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    GButton { ui: Theme; height: 34; icon: "󰌹"; label: Tr.t("Страница"); active: w.pick !== null && (w.pick.page || "") !== ""; onClicked: Quickshell.execDetached(["xdg-open", w.pick.page]) }
                    // папка для сохранения: по кругу из имеющихся
                    GButton {
                        ui: Theme; height: 34; icon: "󰉋"
                        label: w.base(w.destDir)
                        onClicked: {
                            var all = w.dirs.length ? w.dirs : [w.destDir], i = all.indexOf(w.destDir);
                            w.dest = all[(i + 1) % all.length];
                        }
                    }
                    GButton { ui: Theme; height: 34; icon: "󰇚"; label: Tr.t("Скачать"); active: w.pick !== null && !w.downloading; onClicked: w.download(false) }
                    GButton { ui: Theme; height: 34; icon: "󰸉"; label: Tr.t("Поставить"); on: true; active: w.pick !== null && !w.downloading; onClicked: w.download(true) }
                }
            }
        }
    }

    // индикатор загрузки: вращающийся значок; крутится только пока виден
    component Spinner: Text {
        property real size: 22
        text: "󰑓"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: size
        RotationAnimation on rotation { running: parent !== null && visible; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
    }
    // заглушка миниатюры: мягкое «дыхание», пока картинка не загрузилась
    component Placeholder: Rectangle {
        property bool busy: true
        radius: Theme.r(14)
        color: Theme.fill(0.10)
        visible: busy
        SequentialAnimation on opacity {
            running: parent !== null && busy && visible
            loops: Animation.Infinite
            NumberAnimation { from: 0.45; to: 1; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
        }
        Spinner { anchors.centerIn: parent; size: 20 }
    }

    // чип: подпись, выбран / нет; accent — праздничные выделены
    component Chip: Rectangle {
        id: ch
        property alias text: ct.text
        property bool on: false
        property bool accent: false
        property bool dim: false
        signal clicked
        opacity: dim ? 0.4 : 1
        width: ct.implicitWidth + 24; height: 30; radius: 15
        color: on ? Theme.accent : (cma.containsMouse ? Theme.fill(0.18) : Theme.fill(0.08))
        border.width: on ? 0 : 1; border.color: accent ? Theme.accent : Theme.line(0.2)
        Text { id: ct; anchors.centerIn: parent; color: ch.on ? "white" : Theme.text; font.family: Theme.iconFont; font.pixelSize: 12 }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (!ch.dim) ch.clicked() }
    }

    // страницы: «‹ 1 2 [3] 4 5 ›»; pages = 0 — число страниц неизвестно (сеть): только назад и вперёд
    component Pager: Row {
        id: pg
        property int page: 1
        property int pages: 1
        property string info: ""
        property bool canNext: page < pages
        signal go(int p)
        spacing: 6
        // окно из семи номеров вокруг текущей страницы
        readonly property var nums: {
            var a = [], from = Math.max(1, Math.min(page - 3, pages - 6)), to = Math.min(pages, from + 6);
            for (var i = from; i <= to; i++) a.push(i);
            return a;
        }
        visible: pages !== 1 || page > 1
        Chip { text: "‹"; dim: pg.page <= 1; onClicked: pg.go(pg.page - 1) }
        Repeater { model: pg.pages > 0 ? pg.nums : []; Chip { required property int modelData; text: String(modelData); on: modelData === pg.page; onClicked: pg.go(modelData) } }
        Chip { visible: pg.pages === 0; text: Tr.t("Страница ") + pg.page; on: true }
        Chip { text: "›"; dim: !pg.canNext; onClicked: pg.go(pg.page + 1) }
        Text { anchors.verticalCenter: parent.verticalCenter; leftPadding: 8; text: (pg.pages > 0 ? Tr.t("из ") + pg.pages + " · " : "") + pg.info; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
    }
}
