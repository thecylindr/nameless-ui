import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Мастер программ (SUPER+I, Пункт управления → «Программы»): каталог сборки по категориям, «Мои программы»,
// остальные установленные, поиск новых в репозиториях и AUR. Данные — scripts/apps/pkg.sh сборки
// (путь — ~/.config/glassrice/rice, его пишет install.sh). Установка, удаление, обновление и очистка идут в окне
// терминала: видны пароль sudo и ход работы; по закрытию терминала список перечитывается.
//   клик — подробности, флажок — выбрать несколько, правый клик — меню (открыть, в каталог, убрать из каталога)
PanelWindow {
    id: w
    property var shell: null
    property bool open: false
    property real progress: open ? 1 : 0
    Behavior on progress { NumberAnimation { duration: Theme.dur(w.open); easing.type: Easing.OutCubic } }

    visible: progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-programs"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    function toggle() { open = !open; }
    onOpenChanged: if (open) { if (script === "") locate.running = true; else { reload(); loadTab(); if (!updProc.running) updProc.running = true; } query.forceActiveFocus(); }

    // ---------- данные ----------
    property string script: ""
    // не «data»: так называется свойство окна, куда QML кладёт дочерние элементы
    property var pk: ({ categories: [], other: [], hasYay: false })
    property bool loading: false
    property string section: "all"        // all | <категория> | other | search
    property string filter: "all"         // all | installed | missing
    property var found: []
    property bool searching: false
    property string note: ""              // строка состояния: итог действия
    property var picked: ({})             // ключ «кат:ключ» → пункт
    readonly property int pickedCount: Object.keys(picked).length
    property string expanded: ""
    readonly property string view: Config.store.programs.view || "list"
    readonly property bool compact: view === "compact"

    Process {
        id: locate
        command: ["sh", "-c", "for d in \"$(cat \"$HOME/.config/glassrice/rice\" 2>/dev/null)\" \"$HOME/newdesign/glassrice\" \"$HOME/glassrice\"; do " +
                  "[ -n \"$d\" ] && [ -x \"$d/scripts/apps/pkg.sh\" ] && { echo \"$d/scripts/apps/pkg.sh\"; exit; }; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                w.script = text.trim();
                if (w.script === "") w.note = Tr.t("Не найдена сборка: укажите путь к glassrice в ~/.config/glassrice/rice");
                else { w.reload(); w.loadTab(); }
            }
        }
    }
    // копия последнего списка: окно заполняется сразу, свежий список приходит следом
    FileView {
        id: cache
        path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/glassrice/pkg.json"
        printErrors: false
        onLoaded: { if ((w.pk.categories || []).length === 0) { try { w.pk = JSON.parse(text()); } catch (e) { } } }
    }
    Process {
        id: lister
        command: [w.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                w.loading = false;
                try { w.pk = JSON.parse(text); } catch (e) { w.note = Tr.t("Не удалось прочитать список пакетов"); }
            }
        }
    }
    function reload() { if (script !== "" && !lister.running) { loading = true; lister.running = true; } }

    Process {
        id: searcher
        property string q: ""
        property int lim: 60
        command: [w.script, "search", q, String(lim)]
        stdout: StdioCollector {
            onStreamFinished: { w.searching = false; try { w.found = JSON.parse(text); } catch (e) { w.found = []; } }
        }
    }
    Timer { id: searchT; interval: 450; onTriggered: w.runSearch() }
    function runSearch() {
        var q = query.text.trim();
        if (q.length < 2) { found = []; return; }
        if (searcher.running) { searchT.restart(); return; }
        if (searcher.q !== q) searcher.lim = 60;
        searcher.q = q; searching = true; searcher.running = true;
    }

    // быстрые действия без терминала: снимок, правка каталога
    Process {
        id: quick
        stdout: StdioCollector {
            onStreamFinished: {
                try { var r = JSON.parse(text); if (r.added !== undefined) w.note = Tr.t("Снимок: добавлено программ — ") + r.added; } catch (e) { }
                w.reload();
            }
        }
    }
    function quickRun(args) { if (!quick.running && script !== "") { quick.command = [script].concat(args); quick.running = true; } }

    // действия в терминале
    property string busy: ""
    Process {
        id: term
        onExited: {
            w.busy = ""; w.picked = ({}); w.reload(); w.loadTab(); if (w.section === "search") w.runSearch();
            // окно убиралось, пока работал терминал, — вернуть на ту же вкладку
            if (w.reopen) { w.reopen = false; w.open = true; }
        }
    }
    // терминал поверх окон не виден под этим окном (слой поверх всего) — окно убирается и вернётся само
    property bool reopen: false
    function runTerm(title, cmd) {
        if (term.running) return;
        busy = title;
        term.command = cmd;
        term.running = true;
        reopen = true;
        open = false;
    }
    function inTerminal(title, args) {
        if (script === "") return;
        runTerm(title, ["kitty", "--class", "glassrice-pkg", "--title", Tr.t("Программы — ") + title, script, "run"].concat(args));
    }
    function install(items) {
        var t = items.map(function (x) { return x.cat + ":" + x.key; });
        if (t.length > 0) inTerminal(Tr.t("установка"), ["install"].concat(t));
    }
    function remove(items) {
        var p = [];
        items.forEach(function (x) { x.pkgs.forEach(function (n) { if (p.indexOf(n) < 0) p.push(n); }); });
        if (p.length > 0) inTerminal(Tr.t("удаление"), ["remove"].concat(p));
    }

    // ---------- вкладки: обновления, патчи, система ----------
    property int ptab: 0
    property var updates: []
    property bool updatesTool: true
    property bool updatesLoading: false
    property var patches: []
    property var sys: ({ orphans: 0, cache: "…", journal: "…" })
    function loadTab() {
        if (script === "") return;
        if (ptab === 1 && !updProc.running) { updatesLoading = true; updProc.running = true; }
        if (ptab === 2 && !patchProc.running) patchProc.running = true;
        if (ptab === 3 && !compProc.running) compProc.running = true;
        if (ptab === 4 && !devProc.running) devProc.running = true;
        if (ptab === 5 && !rgbProc.running) rgbProc.running = true;
        if (ptab === 6) { if (!sysProc.running) sysProc.running = true; if (!orphProc.running) orphProc.running = true; }
    }
    // компьютер, устройства, подсветка, зависимости
    property var comp: ({})
    property var devs: ({})
    property var rgb: ({})
    property var orphans: []
    property var orphPick: []
    property int rgbBright: 100
    property string rgbNote: ""
    readonly property string rgbScript: script.replace(/scripts\/apps\/pkg\.sh$/, "scripts/system/rgb.sh")
    function gib(kib) { return ((kib || 0) / 1048576).toFixed(1); }
    function gb(b) { return ((b || 0) / 1073741824).toFixed(0); }
    Process { id: compProc; command: [w.script, "computer"]; stdout: StdioCollector { onStreamFinished: { try { w.comp = JSON.parse(text); } catch (e) { } } } }
    Process { id: devProc; command: [w.script, "devices"]; stdout: StdioCollector { onStreamFinished: { try { w.devs = JSON.parse(text); } catch (e) { } } } }
    Process {
        id: rgbProc; command: [w.rgbScript, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    w.rgb = JSON.parse(text);
                    // яркость и эффект из сохранённого — только при первом чтении: дальше ими управляет окно
                    if (!w.rgbLoaded && w.rgb.saved) {
                        if (w.rgb.saved.brightness !== undefined) w.rgbBright = w.rgb.saved.brightness;
                        if (w.rgb.saved.effect) w.rgbEffect = w.rgb.saved.effect;
                        if (w.rgb.saved.speed) w.rgbSpeed = w.rgb.saved.speed;
                        if (w.rgb.saved.color) w.rgbColor = w.rgb.saved.color;
                    }
                    w.rgbLoaded = true;
                } catch (e) { }
            }
        }
    }
    Process { id: orphProc; command: [w.script, "orphans"]; stdout: StdioCollector { onStreamFinished: { try { w.orphans = JSON.parse(text); w.orphPick = []; } catch (e) { } } } }
    // применение: из нескольких быстрых изменений уходит последнее, следующее — когда закончилось предыдущее
    property bool rgbLoaded: false
    property string rgbEffect: "static"
    property int rgbSpeed: 5
    property string rgbColor: "ffffff"
    property var rgbPending: null
    Process {
        id: rgbSet
        stdout: StdioCollector {
            onStreamFinished: {
                var r = text.trim();
                w.rgbNote = r === "ok" ? Tr.t("Применено") : (r === "denied" ? Tr.t("Нет прав на подсветку: нажмите «Поставить драйверы и права»") : Tr.t("Подсветка не найдена"));
            }
        }
        onExited: if (w.rgbPending) { var c = w.rgbPending; w.rgbPending = null; rgbSet.command = c; rgbSet.running = true; }
    }
    function rgbRun(cmd) { if (rgbSet.running) rgbPending = cmd; else { rgbSet.command = cmd; rgbSet.running = true; } }
    function setRgb(hex, pct) {
        rgbColor = hex; rgbBright = Math.round(pct);
        if (rgbEffect === "static") rgbRun([rgbScript, "set", hex, String(rgbBright)]);
        else applyEffect();
    }
    function applyEffect() {
        if (rgbEffect === "static") { rgbRun([rgbScript, "set", rgbColor, String(rgbBright)]); return; }
        var cols = rgbEffect === "gradient" ? (Config.store.rgb.gradient || []) : [rgbColor];
        rgbRun([rgbScript, "effect", rgbEffect, String(rgbSpeed)].concat(cols));
    }
    // свой цвет: оттенок, насыщенность, яркость → RRGGBB
    property real pickH: 0
    property real pickS: 1
    property real pickV: 1
    readonly property string pickHex: {
        var c = Qt.hsva(pickH, pickS, pickV, 1);
        function h2(x) { var v = Math.round(x * 255).toString(16); return v.length < 2 ? "0" + v : v; }
        return h2(c.r) + h2(c.g) + h2(c.b);
    }
    Process {
        id: updProc
        command: [w.script, "updates"]
        stdout: StdioCollector { onStreamFinished: { w.updatesLoading = false; try { var r = JSON.parse(text); w.updates = r.list; w.updatesTool = r.tool; } catch (e) { } } }
    }
    Process {
        id: patchProc
        command: [w.script, "patches"]
        stdout: StdioCollector { onStreamFinished: { try { w.patches = JSON.parse(text); } catch (e) { } } }
    }
    Process {
        id: sysProc
        command: [w.script, "sysinfo"]
        stdout: StdioCollector { onStreamFinished: { try { w.sys = JSON.parse(text); } catch (e) { } } }
    }
    // патч без sudo — сразу, с sudo — в терминале (виден запрос пароля)
    Process {
        id: patchRun
        onExited: patchProc.running = true
    }
    function setPatch(x, on) {
        if (x.sudo) { inTerminal(Tr.t("настройка «") + x.title + "»", ["patch", x.id, on ? "on" : "off"]); return; }
        if (patchRun.running) return;
        patchRun.command = [script, "patch", x.id, on ? "on" : "off"];
        patchRun.running = true;
    }

    // ---------- список раздела ----------
    readonly property var catalog: pk.categories || []
    function catTitle(id) {
        for (var i = 0; i < catalog.length; i++) if (catalog[i].id === id) return catalog[i].title;
        return id === "other" ? Tr.t("Остальные в системе") : (id === "search" ? Tr.t("Поиск") : id);
    }
    readonly property var rows: {
        var out = [], q = query.text.trim().toLowerCase();
        if (section === "search") return found.map(function (x) { return Object.assign({ cat: "search" }, x); });
        if (section === "other") out = (pk.other || []).map(function (x) { return Object.assign({ cat: "other" }, x); });
        else for (var i = 0; i < catalog.length; i++) {
            var c = catalog[i];
            if (section !== "all" && section !== c.id) continue;
            for (var j = 0; j < c.items.length; j++) out.push(Object.assign({ cat: c.id }, c.items[j]));
        }
        out = out.filter(function (x) {
            if (filter === "installed" && x.state !== "installed" && x.state !== "partial") return false;
            if (filter === "missing" && x.state === "installed") return false;
            return q === "" || x.key.toLowerCase().indexOf(q) >= 0 || (x.desc || "").toLowerCase().indexOf(q) >= 0;
        });
        // сортировка: установленные сначала, по имени или по размеру
        var srt = Config.store.programs.sort || "state";
        function bytes(sz) {
            var m = /([\d.]+)\s*(B|KiB|MiB|GiB)/.exec(sz || ""); if (!m) return 0;
            return parseFloat(m[1]) * ({ B: 1, KiB: 1024, MiB: 1048576, GiB: 1073741824 })[m[2]];
        }
        if (srt === "name") out.sort(function (a, b) { return a.key < b.key ? -1 : (a.key > b.key ? 1 : 0); });
        else if (srt === "size") out.sort(function (a, b) { return bytes(b.size) - bytes(a.size); });
        else out.sort(function (a, b) { var r = { installed: 0, partial: 1, missing: 2, list: 3 }; return (r[a.state] || 0) - (r[b.state] || 0); });
        return out;
    }
    function count(items, st) { return items.filter(function (x) { return st === "" || x.state === st; }).length; }
    readonly property int totalInstalled: { var n = 0; for (var i = 0; i < catalog.length; i++) n += count(catalog[i].items, "installed"); return n; }
    readonly property string totalSize: {
        var b = 0, seen = {};
        function bytes(sz) { var m = /([\d.]+)\s*(B|KiB|MiB|GiB)/.exec(sz || ""); return m ? parseFloat(m[1]) * ({ B: 1, KiB: 1024, MiB: 1048576, GiB: 1073741824 })[m[2]] : 0; }
        for (var i = 0; i < catalog.length; i++) for (var j = 0; j < catalog[i].items.length; j++) {
            var x = catalog[i].items[j]; if (x.state === "installed" && !seen[x.key]) { seen[x.key] = true; b += bytes(x.size); }
        }
        return b >= 1073741824 ? (b / 1073741824).toFixed(1) + Tr.t(" ГБ") : (b / 1048576).toFixed(0) + Tr.t(" МБ");
    }
    readonly property int totalItems: { var n = 0; for (var i = 0; i < catalog.length; i++) n += catalog[i].items.length; return n; }

    // значок: ярлык по имени пакета без суффиксов -bin / -git / -beta
    readonly property var apps: DesktopEntries.applications.values
    function entryOf(name) {
        if (apps.length < 0) return null;
        var base = name.replace(/-(bin|git|beta|stable|desktop|appimage)$/, "");
        return DesktopEntries.byId(name) || DesktopEntries.byId(base) || DesktopEntries.heuristicLookup(base);
    }
    function iconOf(x) {
        var e = x.pkgs.length > 0 ? entryOf(x.pkgs[0]) : null, n = e ? e.icon : "";
        if (n && n.charAt(0) === "/") return "file://" + n;
        return Quickshell.iconPath(n || "", true) || Quickshell.iconPath("package-x-generic", true) || Quickshell.iconPath("application-x-executable", true);
    }
    function togglePick(x) {
        var p = Object.assign({}, picked), k = x.cat + ":" + x.key;
        if (p[k]) delete p[k]; else p[k] = x;
        picked = p;
    }
    readonly property var pickedList: Object.keys(picked).map(function (k) { return picked[k]; })

    // ---------- окно ----------
    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * w.progress }
    MouseArea { anchors.fill: parent; onClicked: w.open = false }

    Surface {
        id: box
        alpha: Theme.overlayAlpha
        // шторка: выезжает сверху, как шторка оформления
        width: Math.min(parent.width - 60, 1200)
        height: Math.min(parent.height - 40, 860)
        // перетаскивание за шапку: смещение от исходного места (по центру сверху)
        property real dx: 0
        property real dy: 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: dx
        // по центру экрана, при открытии — короткий выезд сверху
        y: (parent.height - height) / 2 + dy - 40 * (1 - w.progress)
        opacity: Math.min(1, w.progress * 2)
        radius: Theme.ios ? 30 : 22
        MouseArea { anchors.fill: parent }
        focus: w.open
        Keys.onEscapePressed: { if (menu.visible) menu.visible = false; else w.open = false; }

        // ---------- шапка: знак, вкладки, закрыть ----------
        Item {
            id: topBar
            x: 18; y: 14
            width: parent.width - 36
            height: 40
            // шапка — ручка окна: перетащить по экрану, двойной клик — вернуть на место
            DragHandler {
                id: moveDrag
                target: null
                property real sx: 0
                property real sy: 0
                onActiveChanged: if (active) { sx = box.dx; sy = box.dy; }
                onTranslationChanged: if (active) {
                    box.dx = Math.max(-(w.width - box.width) / 2, Math.min((w.width - box.width) / 2, sx + translation.x));
                    box.dy = Math.max(-(w.height - box.height) / 2 + 8, Math.min((w.height - box.height) / 2 - 8, sy + translation.y));
                }
                cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            }
            TapHandler { onDoubleTapped: { box.dx = 0; box.dy = 0; } }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text { anchors.verticalCenter: parent.verticalCenter; text: "󰏖"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 24 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: Tr.t("Программы и система"); color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
                    Text { text: w.totalInstalled + Tr.t(" из ") + w.totalItems + Tr.t(" · занято ") + w.totalSize + Tr.t(" · обновлений ") + w.updates.length; color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                }
            }
            GSegment {
                ui: Theme
                width: Math.min(820, parent.width - 340)
                anchors { right: topClose.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                options: [{ v: "0", t: Tr.t("Программы"), icon: "󰏖" }, { v: "1", t: Tr.t("Обновления") + (w.updates.length ? " " + w.updates.length : ""), icon: "󰚰" },
                          { v: "2", t: Tr.t("Патчи"), icon: "󰒓" }, { v: "3", t: Tr.t("Компьютер"), icon: "󰌢" }, { v: "4", t: Tr.t("Устройства"), icon: "󰾰" },
                          { v: "5", t: Tr.t("Подсветка"), icon: "󰌌" }, { v: "6", t: Tr.t("Система"), icon: "󰋊" }]
                value: String(w.ptab)
                onPicked: (v) => { w.ptab = Number(v); w.loadTab(); }
            }
            GTile {
                id: topClose
                ui: Theme
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 36; height: 36; radius: 18
                Text { anchors.centerIn: parent; text: "✕"; color: Theme.text; font.pixelSize: 13 }
                onClicked: w.open = false
            }
        }

        // ---------- обновления ----------
        Item {
            visible: w.ptab === 1
            anchors { fill: parent; topMargin: 66; leftMargin: 18; rightMargin: 18; bottomMargin: 16 }
            Row {
                id: updHead
                spacing: 10
                Text { anchors.verticalCenter: parent.verticalCenter; text: w.updatesLoading ? Tr.t("Проверка обновлений…") : (w.updates.length ? Tr.t("Ждут обновления: ") + w.updates.length : Tr.t("Система свежая")); color: Theme.text; font.family: Theme.font; font.pixelSize: 19; font.weight: Font.Bold }
                Text { anchors.verticalCenter: parent.verticalCenter; visible: !w.updatesTool; text: "репозитории не проверены: нужен pacman-contrib (checkupdates)"; color: Theme.yellow; font.family: Theme.font; font.pixelSize: 11 }
            }
            Row {
                anchors { right: parent.right; verticalCenter: updHead.verticalCenter }
                spacing: 8
                GButton { ui: Theme; height: 36; icon: "󰑓"; label: Tr.t("Проверить"); onClicked: { w.updatesLoading = true; updProc.running = true; } }
                GButton { ui: Theme; height: 36; icon: "󰚰"; label: Tr.t("Обновить всё"); on: true; enabled: w.busy === ""; onClicked: w.inTerminal(Tr.t("обновление"), ["update"]) }
            }
            ListView {
                anchors { top: updHead.bottom; topMargin: 14; left: parent.left; right: parent.right; bottom: parent.bottom }
                clip: true
                spacing: 4
                model: w.updates
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true
                delegate: Item {
                    required property var modelData
                    width: ListView.view.width
                    height: 40
                    Rectangle { anchors.fill: parent; radius: Theme.r(12); color: Theme.fill(0.06) }
                    Text { x: 14; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.4; elide: Text.ElideRight; text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text { x: parent.width * 0.42; anchors.verticalCenter: parent.verticalCenter; text: (modelData.old || "") + "  →  " + (modelData.new || ""); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 } }
                    Rectangle {
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        width: srcT.implicitWidth + 14; height: 20; radius: 10
                        color: Qt.rgba((modelData.aur ? Theme.peach : Theme.teal).r, (modelData.aur ? Theme.peach : Theme.teal).g, (modelData.aur ? Theme.peach : Theme.teal).b, 0.18)
                        Text { id: srcT; anchors.centerIn: parent; text: modelData.aur ? "AUR" : Tr.t("репозиторий"); color: modelData.aur ? Theme.peach : Theme.teal; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold }
                    }
                }
            }
        }

        // ---------- патчи: настройки установщика ----------
        Flickable {
            visible: w.ptab === 2
            anchors { fill: parent; topMargin: 66; leftMargin: 18; rightMargin: 18; bottomMargin: 16 }
            contentHeight: patchCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: patchCol
                width: parent.width
                spacing: 10
                Text { width: parent.width; wrapMode: Text.WordWrap; text: Tr.t("Всё, что установщик настраивает под систему: состояние проверяется на лету. Переключатель применяет или откатывает настройку; помеченные 󰌾 требуют пароль и идут в терминале."); color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 12 }
                Repeater {
                    model: [Tr.t("Система"), Tr.t("Видеокарта"), Tr.t("Приложения"), Tr.t("Оболочка")]
                    Column {
                        required property string modelData
                        readonly property var rows: w.patches.filter(function (x) { return x.group === modelData; })
                        visible: rows.length > 0
                        width: patchCol.width
                        spacing: 4
                        Text { text: parent.modelData; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7; topPadding: 6 }
                        Repeater {
                            model: parent.rows
                            Item {
                                required property var modelData
                                width: patchCol.width
                                height: 54
                                opacity: modelData.state === "na" ? 0.45 : 1
                                Rectangle { anchors.fill: parent; radius: Theme.r(14); color: Theme.fill(0.06); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.12) }
                                Rectangle {
                                    x: 14; anchors.verticalCenter: parent.verticalCenter
                                    width: 10; height: 10; radius: 5
                                    color: modelData.state === "on" ? Theme.green : (modelData.state === "off" ? Theme.yellow : Theme.sub)
                                }
                                Column {
                                    anchors { left: parent.left; leftMargin: 34; right: pSw.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    Text { width: parent.width; elide: Text.ElideRight; text: (modelData.sudo ? "󰌾  " : "") + modelData.title; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Text { width: parent.width; elide: Text.ElideRight; text: modelData.state === "na" ? Tr.t("не нужно: ") + modelData.about : modelData.about; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                                }
                                GSwitch {
                                    id: pSw
                                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    width: 56
                                    ui: Theme
                                    active: modelData.state !== "na" && (modelData.state === "off" || modelData.canOff) && w.busy === ""
                                    checked: modelData.state === "on"
                                    onToggled: (v) => w.setPatch(modelData, v)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---------- компьютер: железо и память ----------
        Flickable {
            visible: w.ptab === 3
            anchors { fill: parent; topMargin: 66; leftMargin: 18; rightMargin: 18; bottomMargin: 16 }
            contentHeight: compCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: compCol
                width: parent.width
                spacing: 14
                readonly property var c: w.comp
                readonly property var m: c.memory || ({})
                readonly property real usedK: (m.total || 0) - (m.available || 0)
                Row {
                    spacing: 14
                    Text { text: (compCol.c.laptop ? "󰌢" : "󰇄"); color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 40 }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: (compCol.c.vendor || "") + " " + (compCol.c.product || ""); color: Theme.text; font.family: Theme.font; font.pixelSize: 20; font.weight: Font.Bold }
                        Text { text: (compCol.c.os || "") + Tr.t(" · ядро ") + (compCol.c.kernel || "") + Tr.t(" · работает ") + (compCol.c.uptime || ""); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
                    }
                }
                // карточки железа
                Flow {
                    width: parent.width
                    spacing: 10
                    Repeater {
                        model: [
                            { i: "󰻠", t: Tr.t("Процессор"), v: compCol.c.cpu ? compCol.c.cpu.model : "", d: compCol.c.cpu ? compCol.c.cpu.cores + Tr.t(" ядер · ") + compCol.c.cpu.threads + Tr.t(" потоков · до ") + (compCol.c.cpu.mhz / 1000).toFixed(1) + Tr.t(" ГГц") : "" },
                            { i: "󰍛", t: Tr.t("Память"), v: w.gib(compCol.m.total) + Tr.t(" ГБ"), d: Tr.t("занято ") + w.gib(compCol.usedK) + Tr.t(" · кэш ") + w.gib(compCol.m.cached) + Tr.t(" · подкачка ") + w.gib(compCol.m.swapTotal) + Tr.t(" ГБ") },
                            { i: "󰻂", t: Tr.t("Плата"), v: compCol.c.board || "", d: "BIOS " + (compCol.c.bios || "") }
                        ].concat((compCol.c.gpus || []).map(function (g) { return { i: "󰢮", t: Tr.t("Видеокарта"), v: g.name, d: Tr.t("драйвер: ") + (g.driver || Tr.t("нет")) }; }))
                        Item {
                            required property var modelData
                            width: (compCol.width - 10) / 2; height: 72
                            Rectangle { anchors.fill: parent; radius: Theme.r(16); color: Theme.fill(0.07); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.12) }
                            Text { id: hi; x: 14; anchors.verticalCenter: parent.verticalCenter; text: modelData.i; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 24 }
                            Column {
                                anchors { left: hi.right; leftMargin: 14; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                Text { text: modelData.t; color: Theme.sub; font.family: Theme.font; font.pixelSize: 10; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6 }
                                Text { width: parent.width; elide: Text.ElideRight; text: modelData.v; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                                Text { width: parent.width; elide: Text.ElideRight; text: modelData.d; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                            }
                        }
                    }
                }
                // память: шкала и что чем занято
                Text { text: Tr.t("Память по программам"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7 }
                Rectangle {
                    width: parent.width; height: 14; radius: 7
                    color: Theme.fill(0.12)
                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: (compCol.c.byProgram || []).slice(0, 8)
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: compCol.m.total ? parent.width * modelData.mib * 1024 / compCol.m.total : 0
                                height: parent.height
                                color: [Theme.accent, Theme.accent2, Theme.teal, Theme.peach, Theme.green, Theme.yellow, Theme.red, Theme.sub][index]
                            }
                        }
                    }
                }
                Grid {
                    columns: 2; columnSpacing: 30; rowSpacing: 6
                    Repeater {
                        model: compCol.c.byProgram || []
                        Row {
                            required property var modelData
                            required property int index
                            spacing: 8
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 3; color: index < 8 ? [Theme.accent, Theme.accent2, Theme.teal, Theme.peach, Theme.green, Theme.yellow, Theme.red, Theme.sub][index] : Theme.fill(0.3) }
                            Text { width: 220; elide: Text.ElideRight; text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                            Text { width: 90; horizontalAlignment: Text.AlignRight; text: modelData.mib >= 1024 ? (modelData.mib / 1024).toFixed(1) + Tr.t(" ГБ") : modelData.mib + Tr.t(" МБ"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 } }
                        }
                    }
                }
                // диски
                Text { text: Tr.t("Диски"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7 }
                Repeater {
                    model: compCol.c.disks || []
                    Item {
                        required property var modelData
                        width: compCol.width; height: 44
                        Text { id: dn; text: "󰋊  " + modelData.mount + "  ·  " + modelData.dev + " (" + modelData.fs + ")"; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 12 }
                        Text { anchors.right: parent.right; text: w.gb(modelData.used) + Tr.t(" из ") + w.gb(modelData.size) + Tr.t(" ГБ"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 } }
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 6 }
                            height: 8; radius: 4; color: Theme.fill(0.12)
                            Rectangle { width: parent.width * modelData.used / Math.max(1, modelData.size); height: parent.height; radius: 4; color: modelData.used / modelData.size > 0.9 ? Theme.red : Theme.accent }
                        }
                    }
                }
            }
        }

        // ---------- устройства: как диспетчер устройств ----------
        Flickable {
            visible: w.ptab === 4
            anchors { fill: parent; topMargin: 66; leftMargin: 18; rightMargin: 18; bottomMargin: 16 }
            contentHeight: devCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: devCol
                width: parent.width
                spacing: 8
                // проблемы — сверху
                Rectangle {
                    visible: (w.devs.problems || []).length > 0
                    width: parent.width
                    height: probCol.implicitHeight + 20
                    radius: Theme.r(16)
                    color: Qt.rgba(Theme.yellow.r, Theme.yellow.g, Theme.yellow.b, 0.12)
                    Column {
                        id: probCol
                        x: 14; y: 10
                        width: parent.width - 28
                        spacing: 4
                        Text { text: Tr.t("󰀦  Найдено: ") + (w.devs.problems || []).length; color: Theme.yellow; font.family: Theme.iconFont; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Repeater {
                            model: w.devs.problems || []
                            Text { required property var modelData; width: probCol.width; wrapMode: Text.WordWrap; text: "• " + modelData.text; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                        }
                    }
                }
                Text {
                    visible: (w.devs.problems || []).length === 0 && (w.devs.groups || []).length > 0
                    text: Tr.t("󰄬  Проблем не найдено: у видеокарт, сети и звука есть драйверы, службы запущены")
                    color: Theme.green; font.family: Theme.iconFont; font.pixelSize: 13
                }
                // разделы: заголовок раскрывает список
                Repeater {
                    model: w.devs.groups || []
                    Column {
                        id: grp
                        required property var modelData
                        property bool open: false
                        width: devCol.width
                        spacing: 2
                        Rectangle {
                            width: parent.width; height: 40; radius: Theme.r(12)
                            color: gma.containsMouse ? Theme.fill(0.12) : Theme.fill(0.07)
                            Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: (grp.open ? "󰅀" : "󰅂") + "  " + grp.modelData.group; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } text: grp.modelData.items.length; color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
                            MouseArea { id: gma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: grp.open = !grp.open }
                        }
                        Repeater {
                            model: grp.open ? grp.modelData.items : []
                            Item {
                                required property var modelData
                                width: grp.width; height: 34
                                Text { x: 34; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.6; elide: Text.ElideRight; text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                                Text { x: parent.width * 0.62; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.22; elide: Text.ElideRight; text: modelData.detail; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                                Rectangle {
                                    visible: modelData.driver !== ""
                                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                    width: drvT.implicitWidth + 14; height: 20; radius: 10
                                    color: Qt.rgba(Theme.teal.r, Theme.teal.g, Theme.teal.b, 0.18)
                                    Text { id: drvT; anchors.centerIn: parent; text: modelData.driver; color: Theme.teal; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---------- подсветка и её драйверы ----------
        Flickable {
            visible: w.ptab === 5
            anchors { fill: parent; topMargin: 66; leftMargin: 18; rightMargin: 18; bottomMargin: 16 }
            contentHeight: rgbCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: rgbCol
                width: parent.width
                spacing: 14
                readonly property var r: w.rgb
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: (rgbCol.r.laptop ? Tr.t("Ноутбук ") : Tr.t("ПК ")) + (rgbCol.r.vendor || "") + " " + (rgbCol.r.product || "") + ": "
                          + ((rgbCol.r.leds || []).length ? Tr.t("подсветка клавиатуры найдена") + ((rgbCol.r.leds[0] || {}).rgb ? " (RGB)" : "") : Tr.t("подсветки клавиатуры нет"))
                          + ((rgbCol.r.openrgb || []).length ? " · OpenRGB: " + rgbCol.r.openrgb.join(", ") : "")
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                // драйверы под это устройство
                Repeater {
                    model: rgbCol.r.drivers || []
                    Item {
                        required property var modelData
                        width: rgbCol.width; height: 50
                        Rectangle { anchors.fill: parent; radius: Theme.r(14); color: Theme.fill(0.06); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.12) }
                        Rectangle { x: 14; anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5; color: modelData.installed ? Theme.green : Theme.yellow }
                        Column {
                            anchors { left: parent.left; leftMargin: 34; verticalCenter: parent.verticalCenter }
                            Text { text: modelData.pkg + (modelData.installed ? Tr.t(" — установлен") : Tr.t(" — не установлен")); color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { text: modelData.why; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                        }
                    }
                }
                Row {
                    spacing: 8
                    GButton {
                        ui: Theme; icon: "󰇚"; on: true
                        label: (rgbCol.r.drivers || []).some(function (d) { return !d.installed; }) || !rgbCol.r.rule ? Tr.t("Поставить драйверы и права") : Tr.t("Переустановить права")
                        enabled: w.busy === ""
                        onClicked: w.runTerm(Tr.t("установка драйверов подсветки"), ["kitty", "--class", "glassrice-pkg", "--title", Tr.t("Подсветка — драйверы"), w.rgbScript, "install"])
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: (rgbCol.r.leds || []).length > 0 && !((rgbCol.r.leds[0] || {}).writable)
                        text: Tr.t("󰌾 для цвета без пароля нужны права (правило udev) — кнопка слева")
                        color: Theme.yellow; font.family: Theme.iconFont; font.pixelSize: 11
                    }
                }
                // эффект
                Text { text: Tr.t("Эффект"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7 }
                GSegment {
                    ui: Theme
                    width: parent.width
                    options: [{ v: "static", t: Tr.t("Статичный"), icon: "󰝤" }, { v: "rainbow", t: Tr.t("Радуга"), icon: "󰃟" }, { v: "wave", t: Tr.t("Волна"), icon: "󰖟" },
                              { v: "gradient", t: Tr.t("Перелив"), icon: "󰸌" }, { v: "breathe", t: Tr.t("Дыхание"), icon: "󰖔" }]
                    value: w.rgbEffect
                    onPicked: (v) => { w.rgbEffect = v; w.applyEffect(); }
                }
                PillSlider {
                    visible: w.rgbEffect !== "static"
                    ui: Theme; width: parent.width; icon: "󰓅"; label: Tr.t("Скорость")
                    from: 1; to: 10; stepSize: 1; decimals: 0; value: w.rgbSpeed
                    onCommitted: (v) => { w.rgbSpeed = v; w.applyEffect(); }
                }
                // цвет (для статичного и дыхания) или цвета перелива
                Text { text: w.rgbEffect === "gradient" ? Tr.t("Цвета перелива — клик добавляет, × убирает") : Tr.t("Цвет"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7 }
                Row {
                    visible: w.rgbEffect === "gradient"
                    spacing: 6
                    Repeater {
                        model: Config.store.rgb.gradient || []
                        Rectangle {
                            required property string modelData
                            required property int index
                            width: 44; height: 44; radius: 22; color: "#" + modelData
                            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.3)
                            Rectangle {
                                anchors { right: parent.right; top: parent.top; margins: -4 }
                                width: 18; height: 18; radius: 9; color: Theme.red
                                visible: (Config.store.rgb.gradient || []).length > 2
                                Text { anchors.centerIn: parent; text: "×"; color: "white"; font.pixelSize: 12; font.bold: true }
                                MouseArea { anchors.fill: parent; onClicked: { var l = Config.store.rgb.gradient.slice(); l.splice(parent.parent.index, 1); Config.set("rgb.gradient", l); w.applyEffect(); } }
                            }
                        }
                    }
                }
                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: [String(Theme.accent).substring(1), String(Theme.accent2).substring(1), "ffffff", "ff3b30", "ff9500", "ffcc00", "34c759", "00c7be", "0a84ff", "5e5ce6", "bf5af2", "ff2d55"]
                            .concat(Config.store.rgb.custom || [])
                        Rectangle {
                            required property string modelData
                            required property int index
                            readonly property bool cur: w.rgbEffect !== "gradient" && w.rgbColor.toLowerCase() === modelData.toLowerCase()
                            readonly property bool mine: index >= 12
                            width: 44; height: 44; radius: 22
                            color: "#" + modelData
                            border.width: cur ? 3 : 1
                            border.color: cur ? Theme.text : Qt.rgba(1, 1, 1, 0.25)
                            Text { visible: index < 2; anchors.centerIn: parent; text: index === 0 ? "A" : "A2"; color: "white"; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold; style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.4) }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: (m) => {
                                    // правый клик по своему цвету — убрать его
                                    if (m.button === Qt.RightButton && parent.mine) { var c = Config.store.rgb.custom.slice(); c.splice(parent.index - 12, 1); Config.set("rgb.custom", c); return; }
                                    if (w.rgbEffect === "gradient") { Config.set("rgb.gradient", (Config.store.rgb.gradient || []).concat([parent.modelData])); w.applyEffect(); }
                                    else w.setRgb(parent.modelData, w.rgbBright);
                                }
                            }
                        }
                    }
                }
                // свой цвет
                Rectangle {
                    width: parent.width
                    height: pickCol.implicitHeight + 24
                    radius: Theme.r(16)
                    color: Theme.fill(0.06)
                    border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.12)
                    Column {
                        id: pickCol
                        x: 14; y: 12
                        width: parent.width - 28
                        spacing: 8
                        Row {
                            spacing: 12
                            Rectangle { width: 54; height: 54; radius: 27; color: "#" + w.pickHex; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.3) }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text { text: Tr.t("Свой цвет"); color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                                Rectangle {
                                    width: 130; height: 28; radius: Theme.r(10); color: Theme.fill(0.1)
                                    TextInput {
                                        id: hexIn
                                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                        verticalAlignment: TextInput.AlignVCenter
                                        text: "#" + w.pickHex
                                        color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                                        onAccepted: {
                                            var h = text.replace("#", "");
                                            if (/^[0-9a-fA-F]{6}$/.test(h)) { var c = Qt.color("#" + h); w.pickH = Math.max(0, c.hsvHue); w.pickS = c.hsvSaturation; w.pickV = c.hsvValue; }
                                        }
                                    }
                                }
                            }
                            GButton { anchors.verticalCenter: parent.verticalCenter; ui: Theme; height: 34; icon: "󰐊"; label: Tr.t("Применить"); on: true
                                      onClicked: { if (w.rgbEffect === "gradient") { Config.set("rgb.gradient", (Config.store.rgb.gradient || []).concat([w.pickHex])); w.applyEffect(); } else w.setRgb(w.pickHex, w.rgbBright); } }
                            GButton { anchors.verticalCenter: parent.verticalCenter; ui: Theme; height: 34; icon: "󰐕"; label: Tr.t("В мои цвета")
                                      onClicked: if ((Config.store.rgb.custom || []).indexOf(w.pickHex) < 0) Config.set("rgb.custom", (Config.store.rgb.custom || []).concat([w.pickHex])) }
                        }
                        // оттенок — радужная полоса, насыщенность и яркость — ползунки
                        Item {
                            width: parent.width; height: 26
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                height: 14; radius: 7
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#ff0000" }
                                    GradientStop { position: 0.17; color: "#ffff00" }
                                    GradientStop { position: 0.33; color: "#00ff00" }
                                    GradientStop { position: 0.5; color: "#00ffff" }
                                    GradientStop { position: 0.67; color: "#0000ff" }
                                    GradientStop { position: 0.83; color: "#ff00ff" }
                                    GradientStop { position: 1.0; color: "#ff0000" }
                                }
                            }
                            Rectangle { x: w.pickH * (parent.width - width); anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; radius: 11; color: "#" + w.pickHex; border.width: 3; border.color: "white" }
                            MouseArea {
                                anchors.fill: parent; preventStealing: true
                                onPressed: (m) => w.pickH = Math.max(0, Math.min(1, m.x / width))
                                onPositionChanged: (m) => { if (pressed) w.pickH = Math.max(0, Math.min(1, m.x / width)); }
                            }
                        }
                        PillSlider { ui: Theme; width: parent.width; implicitHeight: 40; icon: "󰝤"; label: Tr.t("Насыщенность"); from: 0; to: 100; stepSize: 1; decimals: 0; value: w.pickS * 100; suffix: " %"; onCommitted: (v) => w.pickS = v / 100 }
                        PillSlider { ui: Theme; width: parent.width; implicitHeight: 40; icon: "󰃠"; label: Tr.t("Светлота"); from: 0; to: 100; stepSize: 1; decimals: 0; value: w.pickV * 100; suffix: " %"; onCommitted: (v) => w.pickV = v / 100 }
                    }
                }
                PillSlider {
                    ui: Theme; width: parent.width; icon: "󰃠"; label: Tr.t("Яркость подсветки")
                    from: 0; to: 100; stepSize: 5; decimals: 0; value: w.rgbBright; suffix: " %"
                    onCommitted: (v) => w.setRgb(w.rgbColor, v)
                }
                Row {
                    spacing: 8
                    GButton { ui: Theme; icon: "󰏘"; label: Tr.t("Цвет темы"); onClicked: { w.rgbEffect = "static"; w.setRgb(String(Theme.accent).substring(1), w.rgbBright); } }
                    GButton { ui: Theme; icon: "󰹏"; label: Tr.t("Выключить"); onClicked: { w.rgbEffect = "static"; w.rgbRun([w.rgbScript, "off"]); } }
                    GButton { ui: Theme; icon: "󰑓"; label: Tr.t("Найти устройства заново"); onClicked: rgbProc.running = true }
                }
                Text { visible: w.rgbNote !== ""; text: w.rgbNote; color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
            }
        }

        // ---------- система: обслуживание ----------
        Flickable {
            visible: w.ptab === 6
            anchors { fill: parent; topMargin: 66; leftMargin: 18; rightMargin: 18; bottomMargin: 16 }
            contentHeight: sysCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: sysCol
                width: parent.width
                spacing: 12
                Row {
                    spacing: 12
                    Repeater {
                        model: [
                            { i: "󰆴", t: Tr.t("Ненужные зависимости"), v: w.orphans.filter(function (x) { return x.safe; }).length + Tr.t(" из ") + w.orphans.length + Tr.t(" можно убрать"), c: Theme.yellow },
                            { i: "󰋊", t: Tr.t("Кэш пакетов"), v: w.sys.cache, c: Theme.accent },
                            { i: "󰈙", t: Tr.t("Журнал системы"), v: w.sys.journal, c: Theme.accent2 },
                            { i: "󰚰", t: Tr.t("Ждут обновления"), v: String(w.updates.length), c: Theme.green }
                        ]
                        Item {
                            required property var modelData
                            width: (sysCol.width - 36) / 4; height: 92
                            Rectangle { anchors.fill: parent; radius: Theme.r(18); color: Theme.fill(0.07); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.12) }
                            Text { x: 16; y: 14; text: modelData.i; color: modelData.c; font.family: Theme.iconFont; font.pixelSize: 20 }
                            Text { x: 16; y: 40; width: parent.width - 24; elide: Text.ElideRight; text: modelData.v; color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.Bold }
                            Text { x: 16; anchors { bottom: parent.bottom; bottomMargin: 10 } text: modelData.t; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                        }
                    }
                }
                Row {
                    spacing: 8
                    GButton { ui: Theme; icon: "󰚰"; label: Tr.t("Обновить систему"); on: true; enabled: w.busy === ""; onClicked: w.inTerminal(Tr.t("обновление"), ["update"]) }
                    GButton { ui: Theme; icon: "󰃢"; label: Tr.t("Очистить кэш пакетов"); enabled: w.busy === ""; onClicked: w.inTerminal(Tr.t("очистка кэша"), ["clean"]) }
                    GButton { ui: Theme; icon: "󰈙"; label: Tr.t("Сжать журнал до 2 недель"); enabled: w.busy === ""; onClicked: w.inTerminal(Tr.t("журнал"), ["journal"]) }
                    GButton { ui: Theme; icon: "󰄄"; label: Tr.t("Снять список своих"); onClicked: w.quickRun(["snapshot"]) }
                }

                // ненужные зависимости: выбор, причины защиты
                Text { text: Tr.t("Ненужные зависимости"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7 }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "Пакеты, которые поставились как зависимости и больше никому не нужны. Защищены (их не предложит удалить): необязательные зависимости других программ, пакеты из каталога сборки, ядро, прошивки, графика, инструменты сборки, библиотеки с заголовками для разработки и всё, что поставлено меньше недели назад. Удаляется только отмеченное, pacman покажет список и спросит подтверждение."
                    color: Theme.sub; font.family: Theme.font; font.pixelSize: 12
                }
                Repeater {
                    model: w.orphans
                    Item {
                        id: orow
                        required property var modelData
                        readonly property bool sel: w.orphPick.indexOf(modelData.name) >= 0
                        width: sysCol.width; height: 46
                        opacity: modelData.safe ? 1 : 0.6
                        Rectangle { anchors.fill: parent; radius: Theme.r(12); color: orow.sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : Theme.fill(0.06) }
                        Rectangle {
                            id: ochk
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18; radius: Theme.r(5)
                            color: orow.sel ? Theme.accent : "transparent"
                            border.width: orow.sel ? 0 : 1.5; border.color: Theme.line(0.4)
                            Text { visible: orow.sel; anchors.centerIn: parent; text: "󰄬"; color: "white"; font.family: Theme.iconFont; font.pixelSize: 12 }
                        }
                        Column {
                            anchors { left: ochk.right; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            Text { width: parent.width; elide: Text.ElideRight; text: modelData.name + "  ·  " + modelData.size; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { width: parent.width; elide: Text.ElideRight; text: modelData.safe ? (modelData.desc || "") : Tr.t("󰒃  защищён: ") + modelData.reason; color: modelData.safe ? Theme.sub : Theme.teal; font.family: Theme.iconFont; font.pixelSize: 11 }
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var l = w.orphPick.slice(), i = l.indexOf(orow.modelData.name);
                                if (i >= 0) l.splice(i, 1); else l.push(orow.modelData.name);
                                w.orphPick = l;
                            }
                        }
                    }
                }
                Row {
                    spacing: 8
                    visible: w.orphans.length > 0
                    GButton { ui: Theme; icon: "󰄲"; label: Tr.t("Отметить безопасные"); onClicked: w.orphPick = w.orphans.filter(function (x) { return x.safe; }).map(function (x) { return x.name; }) }
                    GButton { ui: Theme; icon: "󰄱"; label: Tr.t("Снять отметки"); onClicked: w.orphPick = [] }
                    GButton {
                        ui: Theme; icon: "󰆴"; danger: true
                        visible: w.orphPick.length > 0
                        label: Tr.t("Удалить отмеченные: ") + w.orphPick.length
                        enabled: w.busy === ""
                        onClicked: w.inTerminal(Tr.t("удаление зависимостей"), ["remove"].concat(w.orphPick))
                    }
                }
            }
        }

        // ---------- боковая панель ----------
        Item {
            id: side
            visible: w.ptab === 0
            x: 14; y: 66
            width: 230
            height: parent.height - 80

            Row {
                id: brand
                visible: false
                x: 6; spacing: 10
                height: 0
                Text { anchors.verticalCenter: parent.verticalCenter; text: "󰏖"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 24 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: Tr.t("Программы"); color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
                    Text { text: w.totalInstalled + Tr.t(" из ") + w.totalItems + Tr.t(" в каталоге установлено"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                }
            }

            Flickable {
                anchors { top: brand.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: tools.top; bottomMargin: 10 }
                contentHeight: nav.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: nav
                    width: parent.width
                    spacing: 2
                    NavRow { sid: "all"; icon: "󰕰"; label: Tr.t("Все из каталога"); n: w.totalItems }
                    NavRow { sid: "search"; icon: "󰍉"; label: Tr.t("Найти новые"); n: -1 }
                    NavRow { sid: "other"; icon: "󰏗"; label: Tr.t("Остальные в системе"); n: (w.pk.other || []).length }
                    Rectangle { width: parent.width; height: 1; color: Theme.fill(0.12) }
                    Repeater {
                        model: w.catalog
                        NavRow {
                            required property var modelData
                            sid: modelData.id
                            icon: modelData.id === "mine" ? "󰋑" : "󰉋"
                            label: modelData.title
                            n: modelData.items.length
                            done: w.count(modelData.items, "installed")
                        }
                    }
                }
            }

            // система целиком
            Column {
                id: tools
                anchors.bottom: parent.bottom
                width: parent.width
                spacing: 6
                GButton { ui: Theme; width: parent.width; icon: "󰄄"; label: Tr.t("Снять список своих"); onClicked: w.quickRun(["snapshot"]) }
            }
        }

        // ---------- основная часть ----------
        Item {
            id: main
            visible: w.ptab === 0
            anchors { left: side.right; leftMargin: 16; right: parent.right; rightMargin: 16; top: parent.top; topMargin: 66; bottom: parent.bottom; bottomMargin: 14 }

            // шапка: поиск, фильтр, обновить, закрыть
            Item {
                id: head
                width: parent.width
                height: 40
                Item {
                    anchors { left: parent.left; right: seg.left; rightMargin: 10; top: parent.top; bottom: parent.bottom }
                    Rectangle { anchors.fill: parent; radius: Theme.r(14); color: Theme.fill(0.08); border.width: Theme.ios ? 0 : 1; border.color: query.activeFocus ? Theme.accent : Theme.line(0.18) }
                    Text { id: lens; x: 14; anchors.verticalCenter: parent.verticalCenter; text: "󰍉"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 16 }
                    TextInput {
                        id: query
                        anchors { left: lens.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        color: Theme.text
                        selectionColor: Theme.accent
                        clip: true
                        font.family: Theme.font
                        font.pixelSize: 14
                        onTextChanged: if (w.section === "search") searchT.restart()
                        Keys.onEscapePressed: { if (text !== "") text = ""; else w.open = false; }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: query.text === ""
                            text: w.section === "search" ? Tr.t("Имя пакета в репозиториях") + (w.pk.hasYay ? Tr.t(" и AUR") : "") : Tr.t("Фильтр по имени и описанию")
                            color: Theme.sub
                            font: query.font
                        }
                    }
                }
                GSegment {
                    id: seg
                    ui: Theme
                    width: 330
                    anchors { right: reloadBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    options: [{ v: "all", t: Tr.t("Все") }, { v: "installed", t: Tr.t("Установлены") }, { v: "missing", t: Tr.t("Нет") }]
                    value: w.filter
                    onPicked: (v) => w.filter = v
                }
                GTile {
                    id: reloadBtn
                    ui: Theme
                    anchors { right: closeBtn.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    width: 36; height: 36; radius: 18
                    Text { anchors.centerIn: parent; text: "󰑓"; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 16; RotationAnimation on rotation { running: w.loading || w.searching; loops: Animation.Infinite; from: 0; to: 360; duration: 900 } }
                    onClicked: { w.reload(); if (w.section === "search") w.runSearch(); }
                }
                Item { id: closeBtn; anchors.right: parent.right; width: 0; height: 36 }
            }

            // заголовок раздела
            Row {
                id: title
                anchors { top: head.bottom; topMargin: 14 }
                spacing: 10
                Text { text: w.catTitle(w.section === "all" ? "" : w.section) || Tr.t("Все из каталога"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.ios ? 22 : 19; font.weight: Font.Bold }
                Text {
                    anchors.baseline: parent.children[0].baseline
                    text: w.rows.length + (w.section === "search" && w.found.length >= 60 ? Tr.t("+ (уточните запрос)") : "")
                    color: Theme.sub; font.family: Theme.font; font.pixelSize: 13
                }
            }

            // строка состояния: идёт действие / итог
            Rectangle {
                id: banner
                visible: w.busy !== "" || w.note !== ""
                anchors { top: title.bottom; topMargin: 10 }
                width: parent.width
                height: visible ? 34 : 0
                radius: Theme.r(12)
                color: w.busy !== "" ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : Theme.fill(0.08)
                Text {
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 50
                    elide: Text.ElideRight
                    text: w.busy !== "" ? Tr.t("󰔟  Идёт ") + w.busy + Tr.t(" — в окне терминала; список обновится, когда оно закроется") : "󰋽  " + w.note
                    color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 12
                }
                Text {
                    visible: w.busy === ""
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: "✕"; color: Theme.sub; font.pixelSize: 11
                    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: w.note = "" }
                }
            }

            // список
            ListView {
                id: list
                visible: w.view !== "grid"
                anchors { top: banner.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: foot.top; bottomMargin: 8 }
                // подгрузка результатов поиска: в конце списка — «ещё»
                footer: moreBtn
                clip: true
                spacing: 6
                model: w.rows
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true
                delegate: Item {
                    id: row
                    required property var modelData
                    readonly property var x0: modelData
                    readonly property string pid: x0.cat + ":" + x0.key
                    readonly property bool sel: w.picked[pid] !== undefined
                    readonly property bool isOpen: w.expanded === pid
                    readonly property bool inst: x0.state === "installed"
                    width: list.width
                    readonly property real rowH: w.compact ? 44 : 62
                    height: rowH + (isOpen ? details.implicitHeight + 6 : 0)
                    Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    clip: true

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.r(16)
                        color: row.sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : Theme.fill(rowMa.containsMouse ? 0.10 : 0.06)
                        border.width: Theme.ios ? 0 : 1
                        border.color: row.sel ? Theme.accent : Theme.line(0.12)
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (m) => {
                            if (m.button === Qt.RightButton) {
                                // точка клика в координатах окна
                                var p = rowMa.mapToItem(null, m.x, m.y);
                                menu.show(row.x0, p.x, p.y);
                            }
                            else w.expanded = row.isOpen ? "" : row.pid;
                        }
                    }

                    // флажок выбора
                    Rectangle {
                        id: check
                        x: 12; y: (row.rowH - 20) / 2
                        width: 20; height: 20; radius: Theme.r(6)
                        color: row.sel ? Theme.accent : "transparent"
                        border.width: row.sel ? 0 : 1.5
                        border.color: Theme.line(0.4)
                        Text { anchors.centerIn: parent; visible: row.sel; text: "󰄬"; color: "white"; font.family: Theme.iconFont; font.pixelSize: 13 }
                        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: w.togglePick(row.x0) }
                    }
                    Image {
                        id: ic
                        x: 44; y: (row.rowH - width) / 2
                        width: w.compact ? 24 : 32; height: width
                        sourceSize: Qt.size(32, 32)
                        asynchronous: true
                        source: w.iconOf(row.x0)
                        opacity: row.inst ? 1 : 0.55
                    }
                    Column {
                        anchors { left: ic.right; leftMargin: 12; right: act.left; rightMargin: 10 }
                        y: w.compact ? 12 : 12
                        Row {
                            spacing: 8
                            Text { text: row.x0.key; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                            Badge { visible: row.x0.aur === true || row.x0.repo === "aur"; text: "AUR"; tint: Theme.peach }
                            Badge { visible: row.x0.repo !== undefined && row.x0.repo !== "aur"; text: row.x0.repo || ""; tint: Theme.teal }
                            Badge { visible: row.x0.def === true && !row.inst; text: Tr.t("рекомендуется"); tint: Theme.accent2 }
                            Badge { visible: row.x0.state === "partial"; text: Tr.t("частично"); tint: Theme.yellow }
                            Badge { visible: w.section === "all"; text: w.catTitle(row.x0.cat); tint: Theme.sub }
                        }
                        Text {
                            width: parent.width
                            visible: !w.compact
                            text: row.x0.desc || ""
                            elide: Text.ElideRight
                            color: Theme.sub; font.family: Theme.font; font.pixelSize: 12
                        }
                    }
                    // состояние и действие
                    Row {
                        id: act
                        anchors { right: parent.right; rightMargin: 12 }
                        y: (row.rowH - 36) / 2
                        spacing: 10
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.inst
                            Text { anchors.right: parent.right; text: row.x0.ver || ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 } }
                            Text { anchors.right: parent.right; text: row.x0.size || ""; color: Theme.sub; opacity: 0.7; font.family: Theme.font; font.pixelSize: 10; font.features: { "tnum": 1 } }
                        }
                        GButton {
                            height: 36
                            ui: Theme
                            enabled: w.busy === "" && row.x0.pkgs.length > 0
                            icon: row.inst ? "󰆴" : "󰇚"
                            label: row.inst ? Tr.t("Удалить") : Tr.t("Установить")
                            danger: row.inst
                            on: !row.inst
                            onClicked: row.inst ? w.remove([row.x0]) : w.install([row.x0])
                        }
                    }
                    // подробности
                    Column {
                        id: details
                        x: 88; y: 64
                        width: parent.width - 100
                        spacing: 3
                        Text { width: parent.width; wrapMode: Text.WordWrap; text: row.x0.desc || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                        Text {
                            width: parent.width; wrapMode: Text.WordWrap
                            text: Tr.t("Пакеты: ") + (row.x0.pkgs.join(", ") || row.x0.key) + (row.x0.ver ? Tr.t("  ·  версия ") + row.x0.ver : "") + (row.x0.size ? "  ·  " + row.x0.size : "")
                                  + (row.x0.cat !== "search" && row.x0.cat !== "other" ? Tr.t("  ·  категория «") + w.catTitle(row.x0.cat) + "»" : "")
                            color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: w.section === "search" ? (w.searching ? Tr.t("Поиск…") : (query.text.trim().length < 2 ? Tr.t("Введите название программы") : Tr.t("Ничего не найдено")))
                                                 : (w.loading ? Tr.t("Загрузка…") : Tr.t("Пусто"))
                    color: Theme.sub; font.family: Theme.font; font.pixelSize: 14
                }
            }

            // плитки
            GridView {
                id: grid
                visible: w.view === "grid"
                anchors.fill: list
                clip: true
                model: w.rows
                cellWidth: width / Math.max(1, Math.floor(width / 190))
                cellHeight: 176
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true
                footer: moreBtn
                delegate: Item {
                    id: card
                    required property var modelData
                    readonly property var x0: modelData
                    readonly property bool inst: x0.state === "installed"
                    readonly property bool sel: w.picked[x0.cat + ":" + x0.key] !== undefined
                    width: grid.cellWidth; height: grid.cellHeight
                    Rectangle {
                        anchors { fill: parent; margins: 5 }
                        radius: Theme.r(20)
                        color: card.sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : Theme.fill(cma.containsMouse ? 0.10 : 0.06)
                        border.width: Theme.ios && !card.sel ? 0 : 1
                        border.color: card.sel ? Theme.accent : Theme.line(0.12)
                    }
                    MouseArea {
                        id: cma
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (m) => { var p = cma.mapToItem(null, m.x, m.y); if (m.button === Qt.RightButton) menu.show(card.x0, p.x, p.y); else w.togglePick(card.x0); }
                    }
                    Image {
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 18 }
                        width: 46; height: 46; sourceSize: Qt.size(46, 46)
                        asynchronous: true
                        source: w.iconOf(card.x0)
                        opacity: card.inst ? 1 : 0.55
                    }
                    Text {
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 72 }
                        width: parent.width - 24; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                        text: card.x0.key; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Text {
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 92 }
                        width: parent.width - 24; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                        text: card.inst ? (card.x0.size || card.x0.ver || Tr.t("установлено")) : (card.x0.aur || card.x0.repo === "aur" ? "AUR" : (card.x0.repo || Tr.t("не установлено")))
                        color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
                    }
                    GButton {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
                        height: 32
                        ui: Theme
                        enabled: w.busy === "" && card.x0.pkgs.length > 0
                        icon: card.inst ? "󰆴" : "󰇚"
                        label: card.inst ? Tr.t("Удалить") : Tr.t("Установить")
                        danger: card.inst
                        on: !card.inst
                        onClicked: card.inst ? w.remove([card.x0]) : w.install([card.x0])
                    }
                }
            }

            // поиск: показать ещё
            Component {
                id: moreBtn
                Item {
                    width: list.width
                    height: w.section === "search" && w.found.length >= searcher.lim ? 56 : 0
                    visible: height > 0
                    GButton {
                        anchors.centerIn: parent
                        ui: Theme; height: 36; icon: "󰁅"
                        label: w.searching ? Tr.t("Загрузка…") : Tr.t("Показать ещё")
                        onClicked: { searcher.lim += 60; w.searching = true; searcher.running = true; }
                    }
                }
            }

            // вид и сортировка — справа от заголовка
            Row {
                anchors { right: parent.right; verticalCenter: title.verticalCenter }
                spacing: 6
                Repeater {
                    model: [["list", "󰉹", Tr.t("Список")], ["compact", "󰘤", Tr.t("Компактно")], ["grid", "󰕰", Tr.t("Плитки")]]
                    ViewChip {
                        required property var modelData
                        text: modelData[1]; hint: modelData[2]
                        on: w.view === modelData[0]
                        onClicked: Config.set("programs.view", modelData[0])
                    }
                }
                Item { width: 8; height: 1 }
                Repeater {
                    model: [["state", Tr.t("Сначала установленные")], ["name", Tr.t("По имени")], ["size", Tr.t("По размеру")]]
                    ViewChip {
                        required property var modelData
                        visible: w.section !== "search"
                        text: modelData[1]; mono: false
                        on: (Config.store.programs.sort || "state") === modelData[0]
                        onClicked: Config.set("programs.sort", modelData[0])
                    }
                }
            }

            // выбранное
            Item {
                id: foot
                anchors.bottom: parent.bottom
                width: parent.width
                height: w.pickedCount > 0 ? 44 : 0
                visible: height > 0
                Rectangle { anchors.fill: parent; radius: Theme.r(16); color: Theme.fill(0.10) }
                Text {
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    text: Tr.t("Выбрано: ") + w.pickedCount
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                Row {
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    GButton { ui: Theme; height: 36; label: Tr.t("Снять выбор"); onClicked: w.picked = ({}) }
                    GButton {
                        ui: Theme; height: 36; icon: "󰆴"; danger: true
                        readonly property var l: w.pickedList.filter(function (x) { return x.state !== "missing"; })
                        visible: l.length > 0
                        label: Tr.t("Удалить ") + l.length
                        onClicked: w.remove(l)
                    }
                    GButton {
                        ui: Theme; height: 36; icon: "󰇚"; on: true
                        readonly property var l: w.pickedList.filter(function (x) { return x.state !== "installed"; })
                        visible: l.length > 0
                        label: Tr.t("Установить ") + l.length
                        onClicked: w.install(l)
                    }
                }
            }
        }
    }

    // ---------- меню пункта ----------
    // обычный элемент поверх окна (оно и так во весь экран): PopupWindow здесь роняет Quickshell 0.3 при выгрузке
    MouseArea {
        anchors.fill: parent
        visible: menu.visible
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: menu.visible = false
    }
    Item {
        id: menu
        property var it: null
        visible: false
        width: 260
        height: mcol.implicitHeight + 16
        z: 10
        function show(item, px, py) {
            it = item;
            x = Math.min(px, w.width - width - 8);
            y = Math.min(py, w.height - height - 8);
            visible = true;
        }
        readonly property bool inCatalog: it !== null && it.cat !== "search" && it.cat !== "other"
        function run(f) { menu.visible = false; f(); }

        Rectangle {
            anchors.fill: parent
            radius: Theme.r(16)
            color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.97)
            border.width: 1
            border.color: Theme.glass ? Qt.rgba(1, 1, 1, 0.16) : Theme.line(0.22)
        }
        Column {
            id: mcol
            x: 8; y: 8
            width: parent.width - 16
            spacing: 2
            Text { width: parent.width; leftPadding: 10; topPadding: 4; bottomPadding: 6; text: menu.it ? menu.it.key : ""; color: Theme.sub; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
            MenuRow {
                readonly property var e: menu.it && menu.it.state === "installed" && menu.it.pkgs.length > 0 ? w.entryOf(menu.it.pkgs[0]) : null
                visible: e !== null
                icon: "󰐊"; label: Tr.t("Открыть")
                onClicked: { var x = e; menu.run(function () { AppRun.run(x); w.open = false; }); }
            }
            MenuRow {
                icon: w.picked[menu.it ? menu.it.cat + ":" + menu.it.key : ""] ? "󰄱" : "󰄲"
                label: w.picked[menu.it ? menu.it.cat + ":" + menu.it.key : ""] ? Tr.t("Снять выбор") : Tr.t("Выбрать")
                onClicked: { var x = menu.it; menu.run(function () { w.togglePick(x); }); }
            }
            MenuRow {
                visible: menu.inCatalog
                icon: "󰆴"; danger: true; label: Tr.t("Убрать из каталога")
                onClicked: { var x = menu.it; menu.run(function () { w.quickRun(["catalog-drop", x.cat, x.key]); }); }
            }
            // в каталог: «Мои программы» или категория
            Text { visible: !menu.inCatalog; width: parent.width; leftPadding: 10; topPadding: 6; text: Tr.t("Добавить в каталог"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
            Repeater {
                model: !menu.inCatalog ? [{ id: "mine", title: Tr.t("Мои программы") }].concat(w.catalog.filter(function (c) { return c.id !== "mine"; })) : []
                MenuRow {
                    required property var modelData
                    icon: modelData.id === "mine" ? "󰋑" : "󰉋"
                    label: modelData.title
                    onClicked: { var x = menu.it, c = modelData.id; menu.run(function () { w.quickRun(["catalog-add", c, x.key, x.desc || ""]); w.note = x.key + " → «" + modelData.title + "»"; }); }
                }
            }
        }
    }

    // ---------- части ----------
    component NavRow: Item {
        id: nr
        property string sid
        property string icon
        property string label
        property int n: 0
        property int done: -1
        readonly property bool cur: w.section === sid
        width: parent ? parent.width : 200
        height: 36
        Rectangle {
            anchors.fill: parent
            radius: Theme.r(12)
            color: nr.cur ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : (nrMa.containsMouse ? Theme.fill(0.10) : "transparent")
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Text { id: nrIcon; x: 10; anchors.verticalCenter: parent.verticalCenter; text: nr.icon; color: nr.cur ? Theme.accent : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 15 }
        Text {
            anchors { left: nrIcon.right; leftMargin: 10; right: cnt.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
            text: nr.label; elide: Text.ElideRight
            color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: nr.cur ? Font.DemiBold : Font.Normal
        }
        Text {
            id: cnt
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            visible: nr.n >= 0
            text: nr.done >= 0 ? nr.done + "/" + nr.n : nr.n
            color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 }
        }
        MouseArea {
            id: nrMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { w.section = nr.sid; w.expanded = ""; if (nr.sid === "search") { query.forceActiveFocus(); w.runSearch(); } }
        }
    }

    component ViewChip: Rectangle {
        id: vc
        property string text
        property string hint: ""
        property bool on: false
        property bool mono: true
        signal clicked
        width: Math.max(32, vt.implicitWidth + 18); height: 30; radius: 15
        color: on ? Theme.accent : (vma.containsMouse ? Theme.fill(0.16) : Theme.fill(0.08))
        Text { id: vt; anchors.centerIn: parent; text: vc.text; color: vc.on ? "white" : Theme.text; font.family: vc.mono ? Theme.iconFont : Theme.font; font.pixelSize: vc.mono ? 15 : 11 }
        MouseArea { id: vma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: vc.clicked() }
    }

    component Badge: Rectangle {
        property alias text: bt.text
        property color tint: Theme.accent
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: bt.implicitWidth + 12
        height: 18
        radius: 9
        color: Qt.rgba(tint.r, tint.g, tint.b, 0.18)
        Text { id: bt; anchors.centerIn: parent; color: parent.tint; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold }
    }
}
