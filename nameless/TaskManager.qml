import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Диспетчер задач (SUPER+CTRL+ESC, Пункт управления → «Диспетчер», плитка «Процессы»):
//   Производительность — процессор (загрузка и частота по потокам, P/E-ядра, температура), память, видеокарты
//                        (NVIDIA, Intel, AMD: загрузка, память, частоты, температура, приложения), диск, сеть, батарея
//   Процессы           — список с загрузкой процессора, памятью и видеокартой по процессам; группировка по приложениям,
//                        поиск, сортировка по любому столбцу, завершение процесса
// Данные даёт taskmon.py рядом: он запускается при открытии окна и останавливается при закрытии, так что в закрытом виде
// диспетчер ничего не читает. Окно создаётся лениво (LazyLoader в shell.qml) и выгружается после закрытия.
PanelWindow {
    id: w
    property var shell: null
    readonly property bool open: shell ? shell.tasksOpen : false
    function close() { if (shell) shell.tasksOpen = false; }
    // выезд при первом показе: прогресс стартует с нуля, привязка — после создания
    property real progress: 0
    Component.onCompleted: { progress = Qt.binding(function () { return w.open ? 1 : 0; }); if (open && ptab === 0) search.forceActiveFocus(); }
    Behavior on progress { NumberAnimation { duration: Theme.dur(w.open); easing.type: Easing.OutCubic } }

    visible: progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-tasks"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // ---------- данные ----------
    readonly property string script: (Quickshell.shellDir || (Quickshell.env("HOME") + "/.config/quickshell/nameless")) + "/taskmon.py"
    property var hello: null
    property var snap: null
    property var h: ({})                    // истории за минуту по ключам
    property int histTick: 0
    property var resources: []
    property string sel: "cpu"
    readonly property var cfg: Config.store.tasks
    readonly property int ptab: cfg.tab === 0 ? 0 : 1
    readonly property int ncpu: hello ? hello.threads : 1
    readonly property var cur: {
        for (var i = 0; i < resources.length; i++) if (resources[i].id === sel) return resources[i];
        return resources.length ? resources[0] : null;
    }

    // сборщик работает, только пока окно открыто
    Process {
        id: mon
        running: w.open
        command: ["python3", w.script, Perf.eco ? "2" : "1"]
        stdout: SplitParser { onRead: (line) => w.ingest(line) }
    }
    onVisibleChanged: if (!visible) { snap = null; h = ({}); rows.clear(); connRows.clear(); lastConns = []; selObj = null; }

    readonly property var colors: ({ cpu: "#4da3ff", mem: "#b57bff", nvidia: "#76b900", intel: "#2bb3e0", amd: "#ed1c24", disk: "#f5b83d", net: "#ff7a59", bat: "#34c759", other: "#9aa" })
    function buildResources(hl) {
        var r = [{ id: "cpu", kind: "cpu", t: Tr.t("Процессор"), c: colors.cpu }, { id: "mem", kind: "mem", t: Tr.t("Память"), c: colors.mem }];
        for (var i = 0; i < hl.gpus.length; i++) {
            var g = hl.gpus[i];
            r.push({ id: "gpu" + i, kind: "gpu", gi: i, t: Tr.t("ГП ") + i + " · " + ({ nvidia: "NVIDIA", intel: "Intel", amd: "AMD" })[g.vendor], c: colors[g.vendor] || colors.other });
        }
        r.push({ id: "disk", kind: "disk", t: Tr.t("Диск"), c: colors.disk }, { id: "net", kind: "net", t: Tr.t("Сеть"), c: colors.net }, { id: "bat", kind: "bat", t: Tr.t("Батарея"), c: colors.bat });
        return r;
    }
    function push(key, v) {
        var a = h[key] || [];
        a = a.length >= 60 ? a.slice(a.length - 59) : a.slice();
        a.push(v);
        h[key] = a;
    }
    function ingest(line) {
        var d;
        try { d = JSON.parse(line); } catch (e) { return; }
        if (d.hello) { hello = d.hello; resources = buildResources(d.hello); return; }
        snap = d;
        push("cpu", d.cpu.total);
        push("mem", d.mem.total > 0 ? d.mem.used / d.mem.total * 100 : 0);
        push("disk.r", d.disk.read); push("disk.w", d.disk.write);
        push("net.rx", d.net.rx); push("net.tx", d.net.tx);
        for (var i = 0; i < d.gpus.length; i++) {
            var g = d.gpus[i];
            push("gpu" + i, g.util || 0);
            push("gpu" + i + ".mem", g.memTotal ? g.memUsed / g.memTotal * 100 : 0);
        }
        if (d.bat) push("bat", d.bat.watts);
        histTick++;
        if (d.conns && d.conns !== lastConns) { lastConns = d.conns; if (ptab === 1 && sel === "net") syncConns(); }
        if (ptab === 0) syncRows();
    }
    function seriesFor(id) {
        switch (id) {
        case "cpu": return [{ values: h.cpu || [], color: colors.cpu }];
        case "mem": return [{ values: h.mem || [], color: colors.mem }];
        case "disk": return [{ values: h["disk.r"] || [], color: colors.disk }, { values: h["disk.w"] || [], color: "#ff6b6b" }];
        case "net": return [{ values: h["net.rx"] || [], color: "#34c759" }, { values: h["net.tx"] || [], color: colors.net }];
        case "bat": return [{ values: h.bat || [], color: colors.bat }];
        }
        var m = /^gpu(\d+)(\.mem)?$/.exec(id);
        if (m) {
            var g = hello && hello.gpus[Number(m[1])];
            return [{ values: h[id] || [], color: colors[g ? g.vendor : "other"] || colors.other }];
        }
        return [];
    }

    // ---------- подписи ----------
    function bytes(n) {
        var u = [Tr.t("Б"), Tr.t("КБ"), Tr.t("МБ"), Tr.t("ГБ"), Tr.t("ТБ")], i = 0;
        n = n || 0;
        while (n >= 1024 && i < 4) { n /= 1024; i++; }
        return (i < 2 ? String(Math.round(n)) : n.toFixed(n >= 100 ? 0 : 1).replace(".", ",")) + " " + u[i];
    }
    function rate(n) { return bytes(n) + Tr.t("/с"); }
    function pct(v, d) { return v === undefined || v === null ? "—" : Number(v).toFixed(d === undefined ? 0 : d).replace(".", ",") + "%"; }
    function rateShort(n) { return n < 1 ? "—" : rate(n); }
    function mhz(v) { return v === undefined || v === null ? "—" : (v >= 1000 ? (v / 1000).toFixed(2).replace(".", ",") + Tr.t(" ГГц") : Math.round(v) + Tr.t(" МГц")); }
    function temp(v) { return v === undefined || v === null ? "—" : Math.round(v) + " °C"; }
    function uptime(s) {
        s = Math.floor(s || 0);
        var d = Math.floor(s / 86400), hh = Math.floor(s / 3600) % 24, mm = Math.floor(s / 60) % 60, ss = s % 60;
        return (d ? d + Tr.t(" д ") : "") + hh + ":" + (mm < 10 ? "0" : "") + mm + ":" + (ss < 10 ? "0" : "") + ss;
    }
    function vendorOf(res) { return hello && res && res.kind === "gpu" && hello.gpus[res.gi] ? hello.gpus[res.gi].vendor : ""; }
    function gpuOf(res) { return snap && res && res.kind === "gpu" ? snap.gpus[res.gi] : null; }
    function tileSub(res) {
        if (!snap) return "";
        switch (res.kind) {
        case "cpu": return pct(snap.cpu.total) + "  " + mhz(snap.cpu.mhz);
        case "mem": return bytes(snap.mem.used) + Tr.t(" из ") + bytes(snap.mem.total) + " (" + pct(snap.mem.used / snap.mem.total * 100) + ")";
        case "gpu":
            var g = gpuOf(res);
            if (!g) return "";
            return g.state !== "active" ? Tr.t("спит") : pct(g.util) + (g.temp !== undefined && g.temp !== null ? "  " + temp(g.temp) : "");
        case "disk": return "↓ " + rate(snap.disk.read) + "  ↑ " + rate(snap.disk.write);
        case "net": return "↓ " + rate(snap.net.rx) + "  ↑ " + rate(snap.net.tx);
        case "bat": return snap.bat ? snap.bat.pct + "%  " + (snap.bat.watts > 0 ? snap.bat.watts.toFixed(1).replace(".", ",") + Tr.t(" Вт") : snap.bat.status) : "";
        }
        return "";
    }
    // приложения, занимающие видеокарту вендора
    function gpuApps(vendor) {
        if (!snap) return [];
        return snap.procs.filter(function (p) { return p.gpuDev === vendor && ((p.gpu || 0) > 0.05 || (p.gpuMem || 0) > 0); })
            .sort(function (a, b) { return (b.gpu || 0) - (a.gpu || 0) || (b.gpuMem || 0) - (a.gpuMem || 0); }).slice(0, 6);
    }
    function topMem() { return snap ? snap.procs.slice().sort(function (a, b) { return b.rss - a.rss; }).slice(0, 6) : []; }

    // ---------- процессы ----------
    property string selKey: ""
    property var selObj: null
    property string armed: ""
    property string note: ""
    Timer { id: disarm; interval: 3000; onTriggered: w.armed = "" }
    Timer { id: noteT; interval: 3000; onTriggered: w.note = "" }
    readonly property string sortKey: cfg.sort || "cpu"
    readonly property bool sortDesc: cfg.desc !== false
    function sortBy(k) {
        if (sortKey === k) Config.set("tasks.desc", !sortDesc);
        else { Config.set("tasks.sort", k); Config.set("tasks.desc", k !== "name" && k !== "user"); }
        Qt.callLater(syncRows);
    }
    function buildRows() {
        if (!snap) return [];
        var q = search.text.trim().toLowerCase(), grp = cfg.group !== false, map = {}, out = [], src = snap.procs;
        for (var i = 0; i < src.length; i++) {
            var p = src[i];
            if (q !== "" && p.name.toLowerCase().indexOf(q) < 0 && p.cmd.toLowerCase().indexOf(q) < 0 && p.user.toLowerCase().indexOf(q) < 0 && String(p.pid) !== q) continue;
            var gp = p.gpu || 0;
            if (grp) {
                var o = map[p.name];
                if (!o) {
                    o = map[p.name] = { key: "n:" + p.name, pid: p.pid, name: p.name, user: p.user, cpu: 0, rss: 0, thr: 0, gpu: 0, gpuDev: "", count: 0, own: true, pids: "", cmd: p.cmd };
                    out.push(o);
                }
                o.cpu += p.cpu / ncpu; o.rss += p.rss; o.thr += p.thr; o.count++; o.own = o.own && p.own;
                o.pids += (o.pids ? "," : "") + p.pid;
                if (gp > o.gpu) { o.gpu = gp; o.gpuDev = p.gpuDev || ""; }
                if (o.user !== p.user) o.user = Tr.t("несколько");
            } else {
                out.push({ key: "p:" + p.pid, pid: p.pid, name: p.name, user: p.user, cpu: p.cpu / ncpu, rss: p.rss, thr: p.thr, gpu: gp, gpuDev: p.gpuDev || "", count: 1, own: p.own, pids: String(p.pid), cmd: p.cmd });
            }
        }
        var k = sortKey, sgn = sortDesc ? -1 : 1;
        out.sort(function (a, b) {
            var r = (k === "name" || k === "user") ? String(a[k]).localeCompare(String(b[k])) : (a[k] - b[k]);
            return r === 0 ? a.name.localeCompare(b.name) : r * sgn;
        });
        return out.slice(0, 200);
    }
    // ListModel обновляется по месту (вставка, перенос, удаление): строки не пересоздаются, прокрутка и выбор не сбиваются
    function syncRows() {
        var want = buildRows(), idx = {}, i, j;
        for (i = 0; i < want.length; i++) idx[want[i].key] = i;
        for (i = rows.count - 1; i >= 0; i--) if (idx[rows.get(i).key] === undefined) rows.remove(i);
        for (i = 0; i < want.length; i++) {
            var o = want[i];
            if (i < rows.count && rows.get(i).key === o.key) { rows.set(i, o); continue; }
            j = -1;
            for (var k = i + 1; k < rows.count; k++) if (rows.get(k).key === o.key) { j = k; break; }
            if (j >= 0) { rows.move(j, i, 1); rows.set(i, o); } else rows.insert(i, o);
        }
        selObj = null;
        for (i = 0; i < want.length; i++) if (want[i].key === selKey) { selObj = want[i]; break; }
    }
    function killSel(sig) {
        if (!selObj) return;
        Quickshell.execDetached(["kill", "-" + sig].concat(selObj.pids.split(",")));
        note = (sig === "KILL" ? Tr.t("Процесс остановлен: ") : Tr.t("Запрос на завершение отправлен: ")) + selObj.name;
        noteT.restart(); armed = "";
    }
    readonly property var protectedNames: ["Hyprland", "hyprland", "Xwayland", "qs", "quickshell", "systemd", "dbus-daemon", "pipewire", "wireplumber", "sddm", "login"]
    readonly property bool selProtected: selObj ? protectedNames.indexOf(selObj.name) >= 0 : false
    function act(kind) {
        if (!selObj || !selObj.own) return;
        if (kind === "TERM" && !selProtected) { killSel("TERM"); return; }
        if (armed !== kind) { armed = kind; disarm.restart(); return; }
        killSel(kind);
    }
    // ---------- сеть: кто, с кем и куда соединён ----------
    property string netView: "conns"          // conns — соединения, procs — по процессам
    property bool onlyWan: false              // только внешние адреса (без локальной сети и VPN-адресов)
    property var lastConns: []
    ListModel { id: connRows }
    function buildConns() {
        var src = lastConns, out = [], map = {}, i;
        for (i = 0; i < src.length; i++) {
            var c = src[i];
            if (c.k === "lo") continue;
            if (onlyWan && c.k !== "wan") continue;
            var nm = c.name || Tr.t("— (чужой процесс)");
            if (netView === "procs") {
                var o = map[nm];
                if (!o) { o = map[nm] = { key: "n:" + nm, name: nm, pid: c.pid, proto: "", st: "", where: "", ip: "", down: 0, up: 0, tot: 0, k: "wan", count: 0 }; out.push(o); }
                o.down += c.down; o.up += c.up; o.tot += c.rx + c.tx; o.count++;
                if (o.where === "") o.where = c.host || c.r;
            } else {
                out.push({ key: c.p + "|" + c.l + "|" + c.r, name: nm, pid: c.pid, proto: c.p.toUpperCase() + (c.svc ? " · " + c.svc : ""), st: c.st,
                           where: c.host || c.r, ip: c.host ? c.r : "", down: c.down, up: c.up, tot: c.rx + c.tx, k: c.k, count: 1 });
            }
        }
        if (netView === "procs") for (i = 0; i < out.length; i++) { out[i].proto = out[i].count + Tr.t(" соед."); out[i].ip = out[i].count > 1 ? Tr.t("и ещё ") + (out[i].count - 1) : ""; }
        out.sort(function (a, b) { return (b.down + b.up) - (a.down + a.up) || b.tot - a.tot; });
        return out.slice(0, 120);
    }
    function syncConns() {
        var want = buildConns(), idx = {}, i, j;
        for (i = 0; i < want.length; i++) idx[want[i].key] = i;
        for (i = connRows.count - 1; i >= 0; i--) if (idx[connRows.get(i).key] === undefined) connRows.remove(i);
        for (i = 0; i < want.length; i++) {
            var o = want[i];
            if (i < connRows.count && connRows.get(i).key === o.key) { connRows.set(i, o); continue; }
            j = -1;
            for (var k = i + 1; k < connRows.count; k++) if (connRows.get(k).key === o.key) { j = k; break; }
            if (j >= 0) { connRows.move(j, i, 1); connRows.set(i, o); } else connRows.insert(i, o);
        }
    }
    onNetViewChanged: Qt.callLater(syncConns)
    onOnlyWanChanged: Qt.callLater(syncConns)
    onPtabChanged: if (ptab === 0) { syncRows(); search.forceActiveFocus(); }
    onOpenChanged: if (open && ptab === 0) search.forceActiveFocus()
    ListModel { id: rows }

    // ---------- окно ----------
    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * w.progress }
    MouseArea { anchors.fill: parent; onClicked: w.close() }

    Surface {
        id: box
        alpha: Theme.overlayAlpha
        width: Math.min(parent.width - 60, 1180)
        height: Math.min(parent.height - 40, 780)
        property real dx: 0
        property real dy: 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: dx
        y: (parent.height - height) / 2 + dy - 40 * (1 - w.progress)
        opacity: Math.min(1, w.progress * 2)
        radius: Theme.ios ? 30 : 22
        MouseArea { anchors.fill: parent }
        focus: w.open
        Keys.onEscapePressed: { if (search.activeFocus && search.text !== "") search.text = ""; else w.close(); }

        // ---------- шапка ----------
        Item {
            id: topBar
            x: 18; y: 14
            width: parent.width - 36; height: 40
            DragHandler {
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
                Text { anchors.verticalCenter: parent.verticalCenter; text: "󰓅"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 24 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: Tr.t("Диспетчер задач"); color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
                    Text {
                        text: w.snap ? Tr.t("работает ") + w.uptime(w.snap.up) + Tr.t(" · процессов ") + w.snap.cpu.procs + Tr.t(" · потоков ") + w.snap.cpu.threads : Tr.t("собираю данные…")
                        color: Theme.sub; font.family: Theme.font; font.pixelSize: 10
                    }
                }
            }
            GSegment {
                ui: Theme
                width: 400
                anchors { right: tmClose.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                options: [{ v: "1", t: Tr.t("Производительность"), icon: "󰓅" }, { v: "0", t: Tr.t("Процессы"), icon: "󰒋" }]
                value: String(w.ptab)
                onPicked: (v) => Config.set("tasks.tab", Number(v))
            }
            GTile {
                id: tmClose
                ui: Theme
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 36; height: 36; radius: 18
                Text { anchors.centerIn: parent; text: "✕"; color: Theme.text; font.pixelSize: 13 }
                onClicked: w.close()
            }
        }

        // ================= Производительность =================
        Item {
            id: perf
            visible: w.ptab === 1
            x: 18; y: 66
            width: parent.width - 36; height: parent.height - 84

            // список ресурсов слева
            Column {
                id: side
                width: 262
                spacing: 8
                Repeater {
                    model: w.resources
                    Rectangle {
                        id: rt
                        required property var modelData
                        readonly property bool picked: w.cur !== null && w.cur.id === modelData.id
                        visible: modelData.kind !== "bat" || (w.snap !== null && w.snap.bat !== null)
                        width: side.width; height: visible ? 72 : 0; radius: Theme.r(16)
                        color: picked ? Theme.fill(0.16) : (rma.containsMouse ? Theme.fill(0.10) : Theme.fill(0.06))
                        border.width: 1; border.color: picked ? Qt.rgba(1, 1, 1, 0.3) : Theme.line(0.12)
                        Rectangle { x: 0; y: 14; width: 4; height: parent.height - 28; radius: 2; color: rt.modelData.c; opacity: rt.picked ? 1 : 0.5 }
                        Column {
                            x: 16; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 16 - 96
                            spacing: 3
                            Text { text: rt.modelData.t; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight; width: parent.width }
                            Text { text: w.tileSub(rt.modelData); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10; elide: Text.ElideRight; width: parent.width }
                        }
                        Graph {
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            width: 82; height: 42
                            grid: false; lineWidth: 1.5
                            maxValue: rt.modelData.kind === "disk" || rt.modelData.kind === "net" || rt.modelData.kind === "bat" ? 0 : 100
                            series: { var t = w.histTick; return w.seriesFor(rt.modelData.id); }
                        }
                        MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { w.sel = rt.modelData.id; if (rt.modelData.kind === "net") w.syncConns(); } }
                    }
                }
            }

            // сведения о выбранном ресурсе
            Item {
                id: detail
                anchors { left: side.right; leftMargin: 18; right: parent.right; top: parent.top; bottom: parent.bottom }
                readonly property var res: w.cur
                readonly property var g: w.gpuOf(w.cur)

                // заголовок
                Item {
                    id: dHead
                    width: parent.width; height: 46
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 150
                        Text { text: detail.res ? detail.res.t : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: {
                                if (!detail.res || !w.hello) return "";
                                var k = detail.res.kind;
                                if (k === "cpu") return w.hello.model + " · " + w.hello.cores + Tr.t(" ядер, ") + w.hello.threads + Tr.t(" потоков") + (w.hello.l3 ? " · L3 " + w.hello.l3 : "");
                                if (k === "mem") return w.bytes(w.hello.memTotal) + Tr.t(" · подкачка ") + (w.snap ? w.bytes(w.snap.mem.swapTotal) : "");
                                if (k === "gpu") return w.hello.gpus[detail.res.gi] ? w.hello.gpus[detail.res.gi].name : "";
                                if (k === "net") return w.snap && w.snap.net.iface ? Tr.t("интерфейс ") + w.snap.net.iface : Tr.t("нет физических интерфейсов");
                                if (k === "disk") return Tr.t("суммарно по всем накопителям");
                                return w.snap && w.snap.bat ? w.snap.bat.status : "";
                            }
                            color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
                        }
                    }
                    Text {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: {
                            if (!w.snap || !detail.res) return "";
                            var k = detail.res.kind;
                            if (k === "cpu") return w.pct(w.snap.cpu.total, 0);
                            if (k === "mem") return w.pct(w.snap.mem.used / w.snap.mem.total * 100, 0);
                            if (k === "gpu") return detail.g && detail.g.state === "active" ? w.pct(detail.g.util, 0) : Tr.t("спит");
                            if (k === "disk") return w.pct(w.snap.disk.busy, 0);
                            if (k === "net") return w.rate(w.snap.net.rx + w.snap.net.tx);
                            return w.snap.bat ? w.snap.bat.pct + "%" : "";
                        }
                        color: detail.res ? detail.res.c : Theme.text
                        font.family: Theme.font; font.pixelSize: 30; font.weight: Font.Light
                    }
                }

                Column {
                id: body
                y: dHead.height + 8
                width: parent.width
                spacing: 12

                // большой график
                Item {
                    id: bigWrap
                    width: parent.width
                    height: detail.res && detail.res.kind === "cpu" ? 150 : (detail.res && detail.res.kind === "net" ? 120 : 190)
                    visible: !(detail.g && detail.g.state !== "active")
                    Rectangle { anchors.fill: parent; radius: Theme.r(14); color: Theme.fill(0.05); border.width: 1; border.color: Theme.line(0.14) }
                    Graph {
                        id: big
                        anchors { fill: parent; margins: 6 }
                        maxValue: detail.res && (detail.res.kind === "disk" || detail.res.kind === "net" || detail.res.kind === "bat") ? 0 : 100
                        series: { var t = w.histTick; return detail.res ? w.seriesFor(detail.res.id) : []; }
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 8 }
                        text: big.maxValue > 0 ? "100%" : (detail.res && detail.res.kind === "bat" ? big.scaleMax + Tr.t(" Вт") : w.rate(big.scaleMax))
                        color: Theme.sub; font.family: Theme.font; font.pixelSize: 10
                    }
                    Text { anchors { left: parent.left; leftMargin: 12; bottom: parent.bottom; bottomMargin: 8 } text: Tr.t("60 секунд"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                }
                // спящая видеокарта
                Rectangle {
                    width: parent.width; height: 96; radius: Theme.r(14)
                    visible: detail.g !== null && detail.g.state !== "active"
                    color: Theme.fill(0.06); border.width: 1; border.color: Theme.line(0.14)
                    Text {
                        anchors { fill: parent; margins: 16 }
                        wrapMode: Text.WordWrap; verticalAlignment: Text.AlignVCenter
                        text: Tr.t("Видеокарта в режиме энергосбережения. Диспетчер её не опрашивает, чтобы не разбудить и не расходовать батарею: данные появятся, как только какое-нибудь приложение начнёт ей пользоваться.")
                        color: Theme.sub; font.family: Theme.font; font.pixelSize: 12
                    }
                }

                // потоки процессора
                Column {
                    id: threadsCol
                    visible: detail.res !== null && detail.res.kind === "cpu"
                    width: parent.width
                    spacing: 6
                    Text { text: Tr.t("Потоки · P — производительные ядра, E — энергоэффективные"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                    Grid {
                        id: thr
                        readonly property int n: w.ncpu
                        columns: n <= 8 ? 4 : (n <= 12 ? 6 : 8)
                        spacing: 6
                        readonly property real cw: Math.floor((threadsCol.width - spacing * (columns - 1)) / columns)
                        Repeater {
                            model: thr.n
                            Rectangle {
                                id: tc
                                required property int index
                                readonly property var c: w.snap ? w.snap.cpu.cores[index] : null
                                readonly property color tone: c && c.kind === "E" ? "#2bb3e0" : "#4da3ff"
                                width: thr.cw; height: 56; radius: Theme.r(10)
                                color: Theme.fill(0.06); border.width: 1; border.color: Theme.line(0.12)
                                clip: true
                                // заливка снизу вверх — доля загрузки
                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    height: parent.height * (tc.c ? tc.c.pct / 100 : 0)
                                    color: Qt.rgba(tc.tone.r, tc.tone.g, tc.tone.b, 0.35)
                                    Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                }
                                Text { x: 8; y: 6; text: (tc.c ? tc.c.kind : "") + tc.index; color: tc.tone; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Bold }
                                Text { anchors { right: parent.right; rightMargin: 8; top: parent.top; topMargin: 4 } text: tc.c ? w.pct(tc.c.pct) : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                                Text { anchors { left: parent.left; leftMargin: 8; bottom: parent.bottom; bottomMargin: 5 } text: tc.c ? w.mhz(tc.c.mhz) : ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                            }
                        }
                    }
                }

                // память: состав
                Column {
                    visible: detail.res !== null && detail.res.kind === "mem" && w.snap !== null
                    width: parent.width
                    spacing: 6
                    Text { text: Tr.t("Состав памяти"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                    Rectangle {
                        width: parent.width; height: 22; radius: 11; clip: true
                        color: Theme.fill(0.08)
                        Row {
                            anchors.fill: parent
                            Rectangle { width: parent.width * (w.snap ? (w.snap.mem.used - 0) / w.snap.mem.total : 0); height: parent.height; color: "#b57bff" }
                            Rectangle { width: parent.width * (w.snap ? Math.min(w.snap.mem.cached, w.snap.mem.avail) / w.snap.mem.total : 0); height: parent.height; color: "#6e4aa8" }
                        }
                    }
                    Row {
                        spacing: 18
                        Text { text: Tr.t("■ занято"); color: "#b57bff"; font.family: Theme.font; font.pixelSize: 11 }
                        Text { text: Tr.t("■ кэш (можно освободить)"); color: "#8a63c9"; font.family: Theme.font; font.pixelSize: 11 }
                        Text { text: Tr.t("□ свободно"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                    }
                }

                // сведения
                Flow {
                    id: stats
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: w.statList(detail.res)
                        Item {
                            required property var modelData
                            width: Math.floor((stats.width - 6 * 3) / 4); height: 46
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                Text { text: modelData.l; color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                                Text { text: modelData.v; width: parent.width; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                            }
                        }
                    }
                }

                // сеть: соединения — процесс, куда, протокол, скорость каждого
                Column {
                    id: netBox
                    visible: detail.res !== null && detail.res.kind === "net"
                    width: parent.width
                    spacing: 6
                    Row {
                        width: parent.width; spacing: 8
                        GSegment {
                            ui: Theme; width: 280
                            options: [{ v: "conns", t: Tr.t("Соединения") }, { v: "procs", t: Tr.t("По процессам") }]
                            value: w.netView
                            onPicked: (v) => w.netView = v
                        }
                        Rectangle {
                            width: owT.implicitWidth + 26; height: 38; radius: 19
                            color: w.onlyWan ? Theme.accent : Theme.fill(0.08); border.width: w.onlyWan ? 0 : 1; border.color: Theme.line(0.2)
                            Text { id: owT; anchors.centerIn: parent; text: Tr.t("Только внешние"); color: w.onlyWan ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.onlyWan = !w.onlyWan }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; width: Math.max(80, parent.width - 280 - owT.implicitWidth - 26 - 24); elide: Text.ElideRight; text: Tr.t("Имя процесса видно у ваших сокетов; чужие — без имени (нужен root)"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                    }
                    Row {
                        width: parent.width; height: 22
                        readonly property real flex: width - 90 - 80 - 90 - 90 - 90
                        Text { width: parent.flex * 0.32; text: Tr.t("Процесс"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                        Text { width: parent.flex * 0.68; text: Tr.t("Куда"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                        Text { width: 90; text: Tr.t("Протокол"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                        Text { width: 80; text: Tr.t("Состояние"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                        Text { width: 90; horizontalAlignment: Text.AlignRight; text: Tr.t("↓ приём"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                        Text { width: 90; horizontalAlignment: Text.AlignRight; text: Tr.t("↑ отдача"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                        Text { width: 90; horizontalAlignment: Text.AlignRight; text: Tr.t("Всего"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; rightPadding: 6 }
                    }
                    ListView {
                        id: connList
                        width: parent.width
                        height: Math.max(150, detail.height - dHead.height - 8 - bigWrap.height - stats.height - 22 - 38 - 4 * 12 - 24)
                        clip: true
                        model: connRows
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Rectangle {
                            id: cr
                            required property int index
                            required property string name
                            required property string proto
                            required property string st
                            required property string where
                            required property string ip
                            required property real down
                            required property real up
                            required property real tot
                            required property string k
                            width: ListView.view.width; height: 34; radius: Theme.r(8)
                            color: index % 2 ? Theme.fill(0.04) : "transparent"
                            Row {
                                anchors.fill: parent
                                readonly property real flex: width - 90 - 80 - 90 - 90 - 90
                                Text { width: parent.flex * 0.32; anchors.verticalCenter: parent.verticalCenter; leftPadding: 8; elide: Text.ElideRight; text: cr.name; color: cr.name.indexOf("—") === 0 ? Theme.sub : Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                                Column {
                                    width: parent.flex * 0.68; anchors.verticalCenter: parent.verticalCenter
                                    Text { width: parent.width; elide: Text.ElideRight; text: cr.where; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                                    Text { width: parent.width; elide: Text.ElideRight; visible: cr.ip !== ""; text: cr.ip; color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                                }
                                Text { width: 90; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: cr.proto; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                                Text { width: 80; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: cr.st; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                                Text { width: 90; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; text: w.rateShort(cr.down); color: cr.down > 0 ? "#34c759" : Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
                                Text { width: 90; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; text: w.rateShort(cr.up); color: cr.up > 0 ? "#ff7a59" : Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
                                Text { width: 90; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; rightPadding: 6; text: w.bytes(cr.tot); color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                            }
                        }
                        Text { visible: connRows.count === 0; anchors.centerIn: parent; text: Tr.t("Нет активных соединений"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
                    }
                }

                // приложения на видеокарте / в памяти
                Column {
                    id: apps
                    visible: detail.res !== null && (detail.res.kind === "gpu" || detail.res.kind === "mem") && !(detail.g && detail.g.state !== "active")
                    width: parent.width
                    spacing: 2
                    readonly property var list: { var t = w.histTick; return !detail.res ? [] : (detail.res.kind === "mem" ? w.topMem() : (detail.res.kind === "gpu" ? w.gpuApps(w.vendorOf(detail.res)) : [])); }
                    Text {
                        text: detail.res && detail.res.kind === "mem" ? Tr.t("Больше всего памяти") : (apps.list.length ? Tr.t("Приложения на видеокарте") : Tr.t("Сейчас видеокартой никто не пользуется") + (w.vendorOf(detail.res) !== "" && w.vendorOf(detail.res) !== "nvidia" ? Tr.t(" (учитываются процессы вашего пользователя)") : ""))
                        color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; bottomPadding: 4
                    }
                    Repeater {
                        model: apps.list
                        Row {
                            required property var modelData
                            width: apps.width; height: 24
                            Text { width: parent.width - 240; text: modelData.name; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                            Text { width: 120; horizontalAlignment: Text.AlignRight; text: detail.res.kind === "mem" ? w.bytes(modelData.rss) : w.pct(modelData.gpu || 0, 1); color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                            Text { width: 120; horizontalAlignment: Text.AlignRight; text: detail.res.kind === "gpu" && modelData.gpuMem ? Math.round(modelData.gpuMem) + Tr.t(" МБ") : ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
                        }
                    }
                }
                }
            }
        }

        // ================= Процессы =================
        Item {
            id: procs
            visible: w.ptab === 0
            x: 18; y: 66
            width: parent.width - 36; height: parent.height - 84

            Row {
                id: bar
                width: parent.width; height: 36
                spacing: 10
                Rectangle {
                    width: 320; height: 36; radius: 18
                    color: Theme.fill(0.08); border.width: 1; border.color: search.activeFocus ? Theme.accent : Theme.line(0.2)
                    Text { x: 13; anchors.verticalCenter: parent.verticalCenter; text: "󰍉"; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 14 }
                    TextInput {
                        id: search
                        anchors { fill: parent; leftMargin: 36; rightMargin: 14 }
                        verticalAlignment: TextInput.AlignVCenter; clip: true
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                        onTextChanged: w.syncRows()
                        Text { visible: search.text === ""; anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Поиск: имя, PID, пользователь"); color: Theme.sub; font: search.font }
                    }
                }
                Rectangle {
                    readonly property bool on: w.cfg.group !== false
                    width: grpT.implicitWidth + 28; height: 36; radius: 18
                    color: on ? Theme.accent : Theme.fill(0.08); border.width: on ? 0 : 1; border.color: Theme.line(0.2)
                    Text { id: grpT; anchors.centerIn: parent; text: Tr.t("󰙅  По приложениям"); color: parent.on ? "white" : Theme.text; font.family: Theme.iconFont; font.pixelSize: 12 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { Config.set("tasks.group", !(w.cfg.group !== false)); Qt.callLater(w.syncRows); } }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Tr.t("ЦП — доля всего процессора · память — занятая · ГП — доля видеокарты")
                    color: Theme.sub; font.family: Theme.font; font.pixelSize: 10
                }
            }

            // заголовки столбцов: нажатие — сортировка; под названием — итог
            Row {
                id: head
                y: bar.height + 10
                width: parent.width; height: 46
                readonly property real fixedW: 80 + 96 + 110 + 96 + 70 + 120
                HCell { key: "name"; title: Tr.t("Имя"); width: head.width - head.fixedW; alignLeft: true }
                HCell { key: "pid"; title: "PID"; width: 80; total: w.snap ? String(w.snap.cpu.procs) : "" }
                HCell { key: "cpu"; title: Tr.t("ЦП"); width: 96; total: w.snap ? w.pct(w.snap.cpu.total) : ""; level: w.snap ? w.snap.cpu.total / 100 : 0 }
                HCell { key: "rss"; title: Tr.t("Память"); width: 110; total: w.snap ? w.pct(w.snap.mem.used / w.snap.mem.total * 100) : ""; level: w.snap ? w.snap.mem.used / w.snap.mem.total : 0 }
                HCell { key: "gpu"; title: Tr.t("ГП"); width: 96; total: w.snap ? w.pct(w.maxGpu()) : ""; level: w.snap ? w.maxGpu() / 100 : 0 }
                HCell { key: "thr"; title: Tr.t("Потоки"); width: 70; total: w.snap ? String(w.snap.cpu.threads) : "" }
                HCell { key: "user"; title: Tr.t("Пользователь"); width: 120 }
            }

            ListView {
                id: list
                anchors { top: head.bottom; topMargin: 4; left: parent.left; right: parent.right; bottom: actions.top; bottomMargin: 8 }
                clip: true
                model: rows
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true
                delegate: Rectangle {
                    id: row
                    required property int index
                    required property string key
                    required property int pid
                    required property string name
                    required property string user
                    required property real cpu
                    required property real rss
                    required property int thr
                    required property real gpu
                    required property string gpuDev
                    required property int count
                    required property bool own
                    readonly property bool picked: w.selKey === key
                    width: ListView.view.width; height: 32; radius: Theme.r(8)
                    color: picked ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) : (rma2.containsMouse ? Theme.fill(0.10) : (index % 2 ? Theme.fill(0.03) : "transparent"))
                    Row {
                        anchors.fill: parent
                        Item {
                            width: head.width - head.fixedW; height: parent.height
                            Rectangle {
                                x: 8; anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 20; radius: 6
                                color: Qt.hsla((row.name.length * 37 % 360) / 360, 0.5, 0.45, 1)
                                Text { anchors.centerIn: parent; text: row.name.substring(0, 1).toUpperCase(); color: "white"; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold }
                                Image {
                                    anchors.fill: parent; anchors.margins: -1
                                    source: Quickshell.iconPath(row.name.toLowerCase(), true)
                                    sourceSize: Qt.size(20, 20); asynchronous: true
                                    visible: status === Image.Ready
                                }
                            }
                            Text {
                                anchors { left: parent.left; leftMargin: 38; right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                text: row.name + (row.count > 1 ? "  (" + row.count + ")" : "")
                                elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                            }
                        }
                        Cell { width: 80; text: row.count > 1 ? "" : String(row.pid) }
                        Cell { width: 96; text: row.cpu < 0.05 ? "0%" : w.pct(row.cpu, 1); heat: Math.min(1, row.cpu / 40); dim: row.cpu < 0.05 }
                        Cell { width: 110; text: w.bytes(row.rss); heat: w.snap ? Math.min(1, row.rss / (w.snap.mem.total * 0.25)) : 0 }
                        Cell { width: 96; text: row.gpu < 0.05 ? "" : w.pct(row.gpu, 1) + (row.gpuDev === "nvidia" ? " N" : (row.gpuDev === "intel" ? " i" : "")); heat: Math.min(1, row.gpu / 50) }
                        Cell { width: 70; text: String(row.thr) }
                        Cell { width: 120; text: row.user; alignLeft: true }
                    }
                    MouseArea { id: rma2; anchors.fill: parent; hoverEnabled: true; onClicked: { w.selKey = row.key; w.armed = ""; w.syncRows(); } }
                }
            }
            Text { visible: rows.count === 0; anchors.centerIn: list; text: w.snap ? Tr.t("Ничего не найдено") : Tr.t("Загрузка…"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 13 }

            // действия над выбранным процессом
            Rectangle {
                id: actions
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 52; radius: Theme.r(14)
                color: Theme.fill(0.06); border.width: 1; border.color: Theme.line(0.14)
                Column {
                    anchors { left: parent.left; leftMargin: 16; right: btns.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: w.note !== "" ? w.note : (w.selObj ? w.selObj.name + (w.selObj.count > 1 ? Tr.t(" · процессов: ") + w.selObj.count : " · PID " + w.selObj.pid) + " · " + w.bytes(w.selObj.rss) : Tr.t("Выберите процесс"))
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: !w.selObj ? "" : (!w.selObj.own ? Tr.t("Процесс чужого пользователя: завершить может только администратор") : (w.selProtected ? Tr.t("Это часть сессии: завершение подтверждается вторым нажатием") : w.selObj.cmd))
                        color: Theme.sub; font.family: Theme.font; font.pixelSize: 10
                    }
                }
                Row {
                    id: btns
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Repeater {
                        model: [{ k: "TERM", t: Tr.t("Завершить"), c: Theme.accent }, { k: "KILL", t: Tr.t("Принудительно"), c: Theme.red }]
                        Rectangle {
                            required property var modelData
                            readonly property bool ok: w.selObj !== null && w.selObj.own
                            readonly property bool arm: w.armed === modelData.k
                            width: bt.implicitWidth + 28; height: 34; radius: 17
                            opacity: ok ? 1 : 0.4
                            color: arm ? modelData.c : (bma.containsMouse && ok ? Theme.fill(0.18) : Theme.fill(0.10))
                            border.width: 1; border.color: arm ? modelData.c : Theme.line(0.25)
                            Text { id: bt; anchors.centerIn: parent; text: parent.arm ? Tr.t("Ещё раз") : modelData.t; color: parent.arm ? "white" : (modelData.k === "KILL" ? Theme.red : Theme.text); font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                            MouseArea { id: bma; anchors.fill: parent; hoverEnabled: ok; cursorShape: ok ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: w.act(modelData.k) }
                        }
                    }
                }
            }
        }
    }

    // ---------- вспомогательное ----------
    function maxGpu() {
        var m = 0;
        if (snap) for (var i = 0; i < snap.gpus.length; i++) m = Math.max(m, snap.gpus[i].util || 0);
        return m;
    }
    // сведения справа от графика: массив {l, v}
    function statList(res) {
        if (!res || !snap) return [];
        var s = snap, out = [];
        function add(l, v) { out.push({ l: l, v: v }); }
        switch (res.kind) {
        case "cpu":
            add(Tr.t("Загрузка"), pct(s.cpu.total, 1)); add(Tr.t("Частота (средняя)"), mhz(s.cpu.mhz)); add(Tr.t("Максимальная"), mhz(hello.maxMhz)); add(Tr.t("Температура"), temp(s.cpu.temp));
            add(Tr.t("Процессов"), String(s.cpu.procs)); add(Tr.t("Потоков"), String(s.cpu.threads)); add(Tr.t("Нагрузка 1 / 5 / 15 мин"), s.load.map(function (x) { return x.toFixed(2).replace(".", ","); }).join(" · "));
            add(Tr.t("Режим"), s.cpu.gov + (s.cpu.epp ? " · " + s.cpu.epp : ""));
            break;
        case "mem":
            add(Tr.t("Занято"), bytes(s.mem.used)); add(Tr.t("Доступно"), bytes(s.mem.avail)); add(Tr.t("Кэш"), bytes(s.mem.cached)); add(Tr.t("Буферы"), bytes(s.mem.buffers));
            add(Tr.t("Подкачка занята"), s.mem.swapTotal ? bytes(s.mem.swapUsed) + Tr.t(" из ") + bytes(s.mem.swapTotal) : Tr.t("нет"));
            break;
        case "gpu":
            var g = s.gpus[res.gi];
            if (!g || g.state !== "active") break;
            add(Tr.t("Загрузка"), pct(g.util, 0));
            if (g.video !== undefined) add(Tr.t("Видео (кодирование)"), pct(g.video, 0));
            if (g.memTotal) add(Tr.t("Видеопамять"), Math.round(g.memUsed) + Tr.t(" из ") + Math.round(g.memTotal) + Tr.t(" МБ"));
            if (g.shared) add(Tr.t("Память"), Tr.t("общая с системной"));
            add(Tr.t("Частота ядра"), g.mhz ? mhz(g.mhz) + (g.mhzMax ? Tr.t(" из ") + mhz(g.mhzMax) : "") : "—");
            if (g.memMhz) add(Tr.t("Частота памяти"), mhz(g.memMhz));
            if (g.temp !== undefined && g.temp !== null) add(Tr.t("Температура"), temp(g.temp));
            if (g.power !== undefined && g.power !== null) add(Tr.t("Мощность"), g.power.toFixed(1).replace(".", ",") + Tr.t(" Вт"));
            if (g.pstate) add(Tr.t("Состояние"), g.pstate);
            break;
        case "disk": add(Tr.t("Чтение"), rate(s.disk.read)); add(Tr.t("Запись"), rate(s.disk.write)); add(Tr.t("Занятость"), pct(s.disk.busy, 0)); break;
        case "net":
            add(Tr.t("Приём"), rate(s.net.rx)); add(Tr.t("Передача"), rate(s.net.tx)); add(Tr.t("Интерфейс"), s.net.iface || "—");
            add(Tr.t("Пакетов в секунду"), "↓ " + s.net.rxp + " · ↑ " + s.net.txp); add(Tr.t("Ошибки / потери"), String(s.net.errs).replace(".", ",") + " / " + String(s.net.drops).replace(".", ","));
            add(Tr.t("Соединений"), String((lastConns || []).filter(function (c) { return c.k !== "lo"; }).length));
            break;
        case "bat": if (s.bat) { add(Tr.t("Заряд"), s.bat.pct + "%"); add(Tr.t("Состояние"), s.bat.status); add(Tr.t("Мощность"), s.bat.watts.toFixed(1).replace(".", ",") + Tr.t(" Вт")); } break;
        }
        return out;
    }

    // ячейка заголовка: название, итог, нажатие — сортировка
    component HCell: Rectangle {
        id: hc
        property string key
        property string title
        property string total: ""
        property real level: 0
        property bool alignLeft: false
        readonly property bool cur: w.sortKey === key
        height: 46; radius: Theme.r(8)
        color: level > 0 ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Math.min(0.5, level * 0.6)) : "transparent"
        Column {
            anchors { verticalCenter: parent.verticalCenter; left: hc.alignLeft ? parent.left : undefined; leftMargin: 10; horizontalCenter: hc.alignLeft ? undefined : parent.horizontalCenter }
            Text { text: hc.total; visible: hc.total !== ""; anchors.horizontalCenter: hc.alignLeft ? undefined : parent.horizontalCenter; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Light }
            Text { text: hc.title + (hc.cur ? (w.sortDesc ? " ↓" : " ↑") : ""); anchors.horizontalCenter: hc.alignLeft ? undefined : parent.horizontalCenter; color: hc.cur ? Theme.accent : Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: hc.cur ? Font.Bold : Font.Normal }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.sortBy(hc.key) }
    }
    // ячейка строки: heat — подсветка по значению
    component Cell: Item {
        property string text
        property real heat: 0
        property bool dim: false
        property bool alignLeft: false
        height: 32
        Rectangle {
            anchors { fill: parent; topMargin: 2; bottomMargin: 2 }
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, heat * 0.45)
            visible: heat > 0.02
        }
        Text {
            anchors { verticalCenter: parent.verticalCenter; left: alignLeft ? parent.left : undefined; leftMargin: 10; right: alignLeft ? parent.right : parent.right; rightMargin: alignLeft ? 4 : 12 }
            horizontalAlignment: alignLeft ? Text.AlignLeft : Text.AlignRight
            text: parent.text; elide: Text.ElideRight
            color: dim ? Theme.sub : Theme.text; font.family: Theme.font; font.pixelSize: 12
        }
    }
}
