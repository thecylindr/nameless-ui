import QtQuick
import Quickshell
import Quickshell.Io

// Нагрузка: процессор (с частотой), память, подкачка, температура, диск, сеть, батарея, видеокарты (NVIDIA и встроенная), время работы.
// Вид — полосы, кольца или графики за последнюю минуту; что показывать и как часто опрашивать — Config.store.system.
// Данные — /proc и /sys напрямую (FileView, без процессов); диск — df раз в минуту; видеокарта NVIDIA — nvidia-smi, только если включена
// и только пока карта не спит (спящую не будим); встроенная графика — частота из /sys/class/drm. Подробности — «Диспетчер»
WCard {
    id: w
    readonly property var o: Config.store.system
    readonly property int every: Math.max(Perf.eco ? 5 : 1, o.interval || 2)

    // ---------- данные ----------
    property var last: null
    property var cur: ({ cpu: 0, ram: 0, ramUsed: 0, ramTotal: 1, swap: 0, swapUsed: 0, temp: 0, disk: 0, diskUsed: 0, diskTotal: 1,
                         down: 0, up: 0, gpu: -1, gpuTemp: 0, mhz: 0, igpuMhz: 0, igpuMax: 0, uptime: 0 })
    property var hist: ({ cpu: [], ram: [], temp: [], net: [] })
    readonly property int histLen: Math.max(10, Math.round(60 / every))

    // чтение /proc и /sys без запуска процессов: раньше каждые 2 с запускалось около 10 программ (head, grep, awk, df…)
    FileView { id: fStat; path: "/proc/stat"; blockLoading: true; printErrors: false }
    FileView { id: fMem; path: "/proc/meminfo"; blockLoading: true; printErrors: false }
    FileView { id: fNet; path: "/proc/net/dev"; blockLoading: true; printErrors: false }
    FileView { id: fUp; path: "/proc/uptime"; blockLoading: true; printErrors: false }
    FileView { id: fTemp; path: w.tempPath; blockLoading: true; printErrors: false }
    // частота процессора: средняя по потокам из /proc/cpuinfo
    FileView { id: fCpuInfo; path: "/proc/cpuinfo"; blockLoading: true; printErrors: false }
    // видеокарты: встроенная (частота) и NVIDIA (состояние питания); пути ищутся один раз
    property string igpuPath: ""
    property string nvPath: ""
    FileView { id: fIgpuAct; path: w.igpuPath !== "" ? w.igpuPath + "/gt_act_freq_mhz" : ""; blockLoading: true; printErrors: false }
    FileView { id: fIgpuMax; path: w.igpuPath !== "" ? w.igpuPath + "/gt_RP0_freq_mhz" : ""; blockLoading: true; printErrors: false }
    FileView { id: fNvState; path: w.nvPath !== "" ? w.nvPath + "/device/power/runtime_status" : ""; blockLoading: true; printErrors: false }
    Process {
        running: true
        command: ["sh", "-c", "for c in /sys/class/drm/card[0-9]; do v=$(cat $c/device/vendor 2>/dev/null); case $v in 0x8086) echo \"igpu $c\";; 0x10de) echo \"nv $c\";; esac; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.trim().split("\n");
                for (var i = 0; i < l.length; i++) {
                    var f = l[i].split(" ");
                    if (f[0] === "igpu") w.igpuPath = f[1]; else if (f[0] === "nv") w.nvPath = f[1];
                }
            }
        }
    }
    // датчик температуры процессора выбирается один раз: x86_pkg_temp, иначе самый горячий
    property string tempPath: "/sys/class/thermal/thermal_zone0/temp"
    Process {
        running: true
        command: ["sh", "-c", "for z in /sys/class/thermal/thermal_zone*; do echo \"$(cat $z/type 2>/dev/null) $(cat $z/temp 2>/dev/null) $z/temp\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                var best = "", bt = -1, l = text.trim().split("\n");
                for (var i = 0; i < l.length; i++) {
                    var f = l[i].split(" ");
                    if (f[0] === "x86_pkg_temp") { best = f[2]; break; }
                    if (parseInt(f[1]) > bt) { bt = parseInt(f[1]); best = f[2]; }
                }
                if (best !== "") w.tempPath = best;
            }
        }
    }
    // диск — раз в минуту (df — единственный внешний вызов), видеокарта — только если включена
    Process {
        id: dfProc
        command: ["df", "-Pk", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d = (text.trim().split("\n")[1] || "").split(/\s+/).map(Number), c = Object.assign({}, w.cur);
                if (d.length > 3) { c.diskTotal = d[1] / 1048576; c.diskUsed = d[2] / 1048576; c.disk = d[1] > 0 ? d[2] / d[1] : 0; }
                w.cur = c;
            }
        }
    }
    Timer { interval: 60000; repeat: true; running: w.visible && w.o.disk; triggeredOnStart: true; onTriggered: if (!dfProc.running) dfProc.running = true }
    Process {
        id: gpuProc
        command: ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu", "--format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                var g = (text.trim().split("\n")[0] || "").split(",").map(function (x) { return parseInt(x); }), c = Object.assign({}, w.cur);
                c.gpu = isNaN(g[0]) ? -1 : g[0]; c.gpuTemp = g[1] || 0; w.cur = c;
            }
        }
    }
    // спящая карта (runtime_status ≠ active) не опрашивается: nvidia-smi разбудил бы её; -2 — «спит»
    function pollGpu() {
        if (w.nvPath !== "") {
            fNvState.reload();
            if (fNvState.text().trim() !== "active") { var c = Object.assign({}, w.cur); c.gpu = -2; w.cur = c; return; }
        }
        if (!gpuProc.running) gpuProc.running = true;
    }
    Timer { interval: Math.max(5, w.every) * 1000; repeat: true; running: w.visible && w.o.gpu === true; triggeredOnStart: true; onTriggered: w.pollGpu() }

    function sample() {
        var now = Date.now(), c = Object.assign({}, cur);
        fStat.reload(); fMem.reload(); fNet.reload(); fUp.reload(); fTemp.reload();
        if (o.freq !== false) {
            fCpuInfo.reload();
            var mm = fCpuInfo.text().match(/cpu MHz\s*:\s*[\d.]+/g) || [], sum = 0;
            for (var m = 0; m < mm.length; m++) sum += parseFloat(mm[m].split(":")[1]);
            c.mhz = mm.length ? Math.round(sum / mm.length) : 0;
        }
        if (o.igpu === true && w.igpuPath !== "") {
            fIgpuAct.reload(); fIgpuMax.reload();
            c.igpuMhz = parseInt(fIgpuAct.text()) || 0; c.igpuMax = parseInt(fIgpuMax.text()) || 0;
        }
        var f = (fStat.text().split("\n")[0] || "").split(/\s+/).slice(1).map(Number);
        var total = f.slice(0, 8).reduce(function (a, b) { return a + b; }, 0), idle = f[3] + f[4];
        var mi = {}, ml = fMem.text().split("\n");
        for (var i = 0; i < ml.length; i++) { var p = ml[i].split(/:\s+/); if (p.length > 1) mi[p[0]] = parseInt(p[1]); }
        var rx = 0, tx = 0, nl = fNet.text().split("\n").slice(2);
        for (var j = 0; j < nl.length; j++) {
            var q = nl[j].trim().split(/[:\s]+/);
            if (q.length < 10 || /^(lo|docker|veth|br-|virbr)/.test(q[0])) continue;
            rx += Number(q[1]); tx += Number(q[9]);
        }
        if (last) {
            var dt = total - last.t, di = idle - last.i, sec = Math.max(0.5, (now - last.when) / 1000);
            if (dt > 0) c.cpu = Math.round(100 * (dt - di) / dt);
            c.down = Math.max(0, (rx - last.rx) / sec);
            c.up = Math.max(0, (tx - last.tx) / sec);
        }
        last = { t: total, i: idle, rx: rx, tx: tx, when: now };
        c.ramTotal = (mi.MemTotal || 0) / 1048576; c.ramUsed = ((mi.MemTotal || 0) - (mi.MemAvailable || 0)) / 1048576; c.ram = c.ramUsed / Math.max(0.01, c.ramTotal);
        c.swapUsed = ((mi.SwapTotal || 0) - (mi.SwapFree || 0)) / 1048576; c.swap = mi.SwapTotal > 0 ? (mi.SwapTotal - mi.SwapFree) / mi.SwapTotal : 0;
        c.temp = Math.round((parseInt(fTemp.text()) || 0) / 1000);
        c.uptime = parseFloat(fUp.text()) || 0;
        cur = c;
        // история для графиков
        function push(a, v) { var x = a.slice(-(histLen - 1)); x.push(v); return x; }
        hist = { cpu: push(hist.cpu, c.cpu / 100), ram: push(hist.ram, c.ram), temp: push(hist.temp, Math.min(1, c.temp / 100)), net: push(hist.net, c.down + c.up) };
    }
    Timer { interval: w.every * 1000; repeat: true; running: w.visible; triggeredOnStart: true; onTriggered: w.sample() }

    function ghz(m) { return m >= 1000 ? (m / 1000).toFixed(2).replace(".", ",") + Tr.t(" ГГц") : m + Tr.t(" МГц"); }
    function speed(b) { return b >= 1048576 ? (b / 1048576).toFixed(1) + Tr.t(" МБ/с") : (b / 1024).toFixed(0) + Tr.t(" КБ/с"); }
    function upTime(s) { var d = Math.floor(s / 86400), h = Math.floor(s / 3600) % 24, m = Math.floor(s / 60) % 60; return (d > 0 ? d + Tr.t(" д ") : "") + h + Tr.t(" ч ") + m + Tr.t(" мин"); }

    // строки по включённым метрикам
    readonly property var rows: {
        var c = cur, r = [];
        if (o.cpu) r.push({ k: "cpu", i: "󰻠", t: Tr.t("Процессор"), v: c.cpu / 100, s: c.cpu + "%" + (o.freq !== false && c.mhz > 0 ? " · " + ghz(c.mhz) : ""), c: Theme.accent });
        if (o.ram) r.push({ k: "ram", i: "󰍛", t: Tr.t("Память"), v: c.ram, s: c.ramUsed.toFixed(1) + " / " + c.ramTotal.toFixed(0) + Tr.t(" ГБ"), c: Theme.accent2 });
        if (o.swap) r.push({ k: "swap", i: "󰾴", t: Tr.t("Подкачка"), v: c.swap, s: c.swapUsed.toFixed(1) + Tr.t(" ГБ"), c: Theme.teal });
        if (o.temp) r.push({ k: "temp", i: "󰔏", t: Tr.t("Температура"), v: Math.min(1, c.temp / 100), s: c.temp + "°", c: c.temp >= 80 ? Theme.red : Theme.peach });
        if (o.gpu) r.push({ k: "gpu", i: "󰢮", t: Tr.t("Видеокарта"), v: Math.max(0, c.gpu) / 100, s: c.gpu === -2 ? Tr.t("спит") : (c.gpu < 0 ? Tr.t("нет данных") : c.gpu + "% · " + c.gpuTemp + "°"), c: Theme.green });
        if (o.igpu === true && w.igpuPath !== "") r.push({ k: "igpu", i: "󰢮", t: Tr.t("Встроенная графика"), v: c.igpuMax > 0 ? c.igpuMhz / c.igpuMax : 0, s: ghz(c.igpuMhz), c: Theme.teal });
        if (o.disk) r.push({ k: "disk", i: "󰋊", t: Tr.t("Диск /"), v: c.disk, s: c.diskUsed.toFixed(0) + " / " + c.diskTotal.toFixed(0) + Tr.t(" ГБ"), c: c.disk > 0.9 ? Theme.red : Theme.teal });
        if (o.battery && Sys.hasBattery) r.push({ k: "bat", i: Sys.batIcon, t: Tr.t("Батарея"), v: Sys.batPct / 100, s: Sys.batPct + "%" + (Sys.charging ? Tr.t(" · заряд") : ""), c: Sys.batPct <= 15 ? Theme.red : Theme.green });
        return r;
    }

    implicitHeight: pad * 2 + head.height + 10
                    + (o.view === "rings" ? 96 : rows.length * (o.view === "graph" ? 46 : 22))
                    + (o.net ? 26 : 0) + (o.uptime ? 18 : 0)

    Row {
        id: head
        spacing: 8
        Text { text: "󰓅"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 14 }
        Text { text: Tr.t("Нагрузка"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6 }
    }
    // переход в диспетчер задач: подробные графики, потоки процессора, видеокарты, процессы
    Text {
        anchors { right: parent.right; top: parent.top }
        text: Tr.t("Диспетчер ›")
        color: tmMa.containsMouse ? Theme.accent : Theme.sub
        font.family: Theme.font; font.pixelSize: 11
        MouseArea { id: tmMa; anchors { fill: parent; margins: -6 } hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["qs", "-c", "nameless", "ipc", "call", "tasks", "perf"]) }
    }

    Column {
        anchors { top: head.bottom; topMargin: 10 }
        width: parent.width
        spacing: 6

        // полосы
        Repeater {
            model: w.o.view === "bars" || !w.o.view ? w.rows : []
            Row {
                required property var modelData
                width: parent.width
                height: 16
                spacing: 8
                Text { width: 16; text: modelData.i; color: modelData.c; font.family: Theme.iconFont; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 128; height: 6; radius: 3
                    color: Theme.fill(0.14)
                    Rectangle { width: parent.width * Math.max(0.02, Math.min(1, modelData.v)); height: parent.height; radius: 3; color: modelData.c; Behavior on width { NumberAnimation { duration: 400 } } }
                }
                Text { width: 96; horizontalAlignment: Text.AlignRight; text: modelData.s; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 }; anchors.verticalCenter: parent.verticalCenter }
            }
        }

        // кольца
        Row {
            visible: w.o.view === "rings"
            spacing: Math.max(6, (parent.width - Math.min(4, w.rows.length) * 64) / Math.max(1, Math.min(4, w.rows.length) - 1))
            Repeater {
                model: w.o.view === "rings" ? w.rows.slice(0, 4) : []
                Column {
                    required property var modelData
                    width: 64
                    spacing: 4
                    Item {
                        width: 64; height: 64
                        Canvas {
                            id: ring
                            anchors.fill: parent
                            property real v: Math.max(0, Math.min(1, parent.parent.modelData.v))
                            property color tone: parent.parent.modelData.c
                            onVChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d"), r = width / 2 - 5;
                                ctx.reset();
                                ctx.lineWidth = 6; ctx.lineCap = "round";
                                ctx.strokeStyle = Theme.fill(0.16);
                                ctx.beginPath(); ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2); ctx.stroke();
                                ctx.strokeStyle = tone;
                                ctx.beginPath(); ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * v); ctx.stroke();
                            }
                        }
                        Text { anchors.centerIn: parent; text: parent.parent.modelData.i; color: parent.parent.modelData.c; font.family: Theme.iconFont; font.pixelSize: 17 }
                    }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: parent.modelData.s.split(" ")[0]; color: Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
                }
            }
        }

        // графики за минуту
        Repeater {
            model: w.o.view === "graph" ? w.rows : []
            Item {
                id: gr
                required property var modelData
                width: parent.width
                height: 40
                readonly property var series: w.hist[modelData.k] || []
                Text { text: modelData.i + "  " + modelData.t; color: modelData.c; font.family: Theme.iconFont; font.pixelSize: 11 }
                Text { anchors.right: parent.right; text: modelData.s; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 } }
                Canvas {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 22
                    property var s: gr.series.length > 0 ? gr.series : [gr.modelData.v]
                    onSChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d"), n = Math.max(2, w.histLen), dx = width / (n - 1), off = n - s.length;
                        ctx.reset();
                        ctx.beginPath();
                        ctx.moveTo(off * dx, height);
                        for (var i = 0; i < s.length; i++) ctx.lineTo((off + i) * dx, height - Math.max(0, Math.min(1, s[i])) * (height - 2));
                        ctx.lineTo((off + s.length - 1) * dx, height);
                        ctx.closePath();
                        ctx.fillStyle = Qt.rgba(gr.modelData.c.r, gr.modelData.c.g, gr.modelData.c.b, 0.22);
                        ctx.fill();
                        ctx.beginPath();
                        for (var j = 0; j < s.length; j++) {
                            var x = (off + j) * dx, y = height - Math.max(0, Math.min(1, s[j])) * (height - 2);
                            if (j === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                        }
                        ctx.strokeStyle = gr.modelData.c; ctx.lineWidth = 1.5; ctx.stroke();
                    }
                }
            }
        }

        // сеть
        Row {
            visible: w.o.net === true
            spacing: 14
            height: 20
            Text { text: "󰇚 " + w.speed(w.cur.down); color: Theme.green; font.family: Theme.iconFont; font.pixelSize: 12; font.features: { "tnum": 1 } }
            Text { text: "󰕒 " + w.speed(w.cur.up); color: Theme.accent2; font.family: Theme.iconFont; font.pixelSize: 12; font.features: { "tnum": 1 } }
        }
        Text {
            visible: w.o.uptime === true
            text: Tr.t("󰅐  работает ") + w.upTime(w.cur.uptime)
            color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 11
        }
    }
}
