import QtQuick
import Quickshell
import Quickshell.Io

// Батарея (диспетчер задач, вкладка для ноутбуков): заряд, время работы и до полной зарядки, мощность и износ;
// режимы питания с прогнозом; аналитика по журналу Power.qml (battery.jsonl) — сколько тратит каждый режим и насколько
// эко-режим продлевает работу; график заряда за сутки, окрашенный по режимам
Item {
    id: bp
    readonly property var b: Sys.bat
    readonly property real rate: b && b.changeRate !== undefined ? Math.abs(b.changeRate) : 0
    readonly property real toEmpty: b && b.timeToEmpty !== undefined ? b.timeToEmpty : 0
    readonly property real toFull: b && b.timeToFull !== undefined ? b.timeToFull : 0
    readonly property real health: b && b.healthPercentage !== undefined ? b.healthPercentage : -1
    readonly property var modeInfo: ({ eco: { t: Tr.t("Эко"), c: Theme.green, i: "󰌪" }, balanced: { t: Tr.t("Обычный"), c: Theme.accent, i: "󰾅" }, perf: { t: Tr.t("Производительный"), c: Theme.red, i: "󰓅" } })

    function hm(sec) {
        if (!(sec > 0)) return "—";
        var h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
        return h > 0 ? h + Tr.t(" ч ") + m + Tr.t(" мин") : m + Tr.t(" мин");
    }

    // ---------- журнал ----------
    property var samples: []
    Process {
        id: rd
        command: ["sh", "-c", "tail -n 6000 \"$1\" 2>/dev/null", "sh", Power.logFile]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [];
                text.split("\n").forEach(function (l) { if (l === "") return; try { out.push(JSON.parse(l)); } catch (e) { } });
                bp.samples = out;
            }
        }
    }
    function reload() { if (!rd.running) rd.running = true; }
    Component.onCompleted: reload()
    onVisibleChanged: if (visible) reload()
    Connections { target: Power; function onLogged() { if (bp.visible) bp.reload(); } }

    // по соседним записям (одна и та же разрядка, один режим): время, проценты, энергия
    readonly property var stats: {
        var st = { eco: { s: 0, d: 0, ws: 0 }, balanced: { s: 0, d: 0, ws: 0 }, perf: { s: 0, d: 0, ws: 0 } };
        for (var i = 1; i < samples.length; i++) {
            var a = samples[i - 1], c = samples[i], dt = c.t - a.t;
            if (dt < 30 || dt > 300 || a.ac || c.ac || a.m !== c.m || !st[a.m]) continue;
            var dp = a.p - c.p;
            if (dp < 0) continue;
            st[a.m].s += dt; st[a.m].d += dp; st[a.m].ws += (a.w || 0) * dt;
        }
        var out = {};
        for (var m in st) {
            var x = st[m], h = x.s / 3600;
            out[m] = { hours: h, pph: h > 0 ? x.d / h : 0, watts: x.s > 0 ? x.ws / x.s : 0, full: x.d > 0 ? 100 / (x.d / h) : 0, ok: h >= 0.25 && x.d >= 2 };
        }
        return out;
    }
    readonly property real ecoGain: stats.eco.ok && stats.balanced.ok && stats.balanced.full > 0 ? (stats.eco.full / stats.balanced.full - 1) * 100 : NaN

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
            spacing: 14

            // ---------- сводка ----------
            Row {
                width: parent.width; spacing: 14
                // заряд: крупная «батарейка»
                Rectangle {
                    width: 220; height: 120; radius: Theme.r(18)
                    color: Theme.fill(0.06); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.14)
                    Rectangle {
                        id: cell
                        x: 16; y: 20; width: 150; height: 52; radius: 10
                        color: "transparent"; border.width: 3; border.color: Theme.text
                        Rectangle {
                            x: 5; y: 5; height: parent.height - 10; radius: 6
                            width: (parent.width - 10) * Sys.batPct / 100
                            color: Sys.charging ? Theme.green : (Sys.batPct < 20 ? Theme.red : (Sys.batPct < 40 ? Theme.yellow : Theme.accent))
                            Behavior on width { NumberAnimation { duration: 400 } }
                        }
                        Text { anchors.centerIn: parent; text: Sys.batPct + "%"; color: Theme.text; style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.35); font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold }
                    }
                    Rectangle { x: cell.x + cell.width; y: cell.y + 16; width: 6; height: 20; radius: 2; color: Theme.text }
                    Text {
                        x: 16; y: 84
                        text: Sys.charging ? (Sys.batPct >= 99 ? Tr.t("󰂄 заряжена") : Tr.t("󰂄 заряжается")) : Tr.t("󰁹 от батареи")
                        color: Sys.charging ? Theme.green : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 12
                    }
                }
                Grid {
                    width: parent.width - 234
                    columns: 2; columnSpacing: 10; rowSpacing: 10
                    Repeater {
                        model: [
                            { t: Sys.charging ? Tr.t("До полной зарядки") : Tr.t("Осталось работы"), v: Sys.charging ? bp.hm(bp.toFull) : bp.hm(bp.toEmpty), i: "󰔟" },
                            { t: Sys.charging ? Tr.t("Мощность зарядки") : Tr.t("Потребление"), v: bp.rate > 0 ? bp.rate.toFixed(1) + Tr.t(" Вт") : "—", i: "󱐋" },
                            { t: Tr.t("Режим"), v: (bp.modeInfo[Power.mode] || bp.modeInfo.balanced).t, i: (bp.modeInfo[Power.mode] || bp.modeInfo.balanced).i },
                            { t: Tr.t("Здоровье батареи"), v: bp.health > 0 ? Math.round(bp.health) + "%" : "—", i: "󰂑" }
                        ]
                        Rectangle {
                            required property var modelData
                            width: (parent.width - 10) / 2; height: 55; radius: Theme.r(14)
                            color: Theme.fill(0.06); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.12)
                            Text { x: 12; y: 9; text: parent.modelData.i + "  " + parent.modelData.t; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 11 }
                            Text { x: 12; y: 26; text: parent.modelData.v; color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
                        }
                    }
                }
            }

            // ---------- режимы ----------
            Text { text: Tr.t("Режим питания"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7 }
            Row {
                width: parent.width; spacing: 10
                Repeater {
                    model: ["eco", "balanced", "perf"]
                    Rectangle {
                        id: mc
                        required property string modelData
                        readonly property var mi: bp.modeInfo[modelData]
                        readonly property var sx: bp.stats[modelData]
                        readonly property bool cur: Power.mode === modelData
                        width: (parent.width - 20) / 3; height: 96; radius: Theme.r(16)
                        color: cur ? Qt.rgba(mi.c.r, mi.c.g, mi.c.b, 0.18) : (mcMa.containsMouse ? Theme.fill(0.12) : Theme.fill(0.06))
                        border.width: cur ? 2 : (Theme.ios ? 0 : 1); border.color: cur ? mi.c : Theme.line(0.12)
                        Column {
                            x: 14; y: 12; width: parent.width - 28; spacing: 3
                            Text { text: mc.mi.i + "  " + mc.mi.t; color: mc.cur ? mc.mi.c : Theme.text; font.family: Theme.iconFont; font.pixelSize: 14; font.weight: Font.DemiBold }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: mc.modelData === "eco" ? Tr.t("процессор бережёт заряд, дискретная спит") : (mc.modelData === "perf" ? Tr.t("процессор и видеокарта на максимум") : Tr.t("как обычно"))
                                color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
                            }
                            Text {
                                text: mc.sx.ok ? Tr.t("≈ ") + bp.hm(Sys.batPct / mc.sx.pph * 3600) + Tr.t(" от текущего заряда") : Tr.t("нет данных — поработайте в этом режиме от батареи")
                                color: mc.sx.ok ? Theme.text : Theme.sub; font.family: Theme.font; font.pixelSize: 11; opacity: mc.sx.ok ? 1 : 0.7
                            }
                        }
                        MouseArea { id: mcMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Power.setMode(mc.modelData) }
                    }
                }
            }
            Text {
                visible: !Power.cpuControl
                width: parent.width; wrapMode: Text.WordWrap
                text: Tr.t("󰍃 Процессором пока нечем управлять без пароля — режимы меняют только видеокарту.")
                color: Theme.yellow; font.family: Theme.iconFont; font.pixelSize: 11
            }
            GButton { visible: !Power.cpuControl; ui: Theme; height: 34; icon: "󰇚"; label: Tr.t("Поставить управление процессором"); onClicked: Power.installCpu() }

            // ---------- аналитика ----------
            Text { text: Tr.t("Как режимы помогают"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7 }
            Rectangle {
                width: parent.width; height: anCol.implicitHeight + 24; radius: Theme.r(16)
                color: Theme.fill(0.06); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.12)
                readonly property real maxFull: Math.max(1, bp.stats.eco.full, bp.stats.balanced.full, bp.stats.perf.full)
                Column {
                    id: anCol
                    x: 14; y: 12; width: parent.width - 28; spacing: 10
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: !isNaN(bp.ecoGain) ? (bp.ecoGain > 0 ? Tr.t("Эко-режим продлевает работу от батареи примерно на ") + Math.round(bp.ecoGain) + Tr.t("% по сравнению с обычным.")
                                                                  : Tr.t("Пока эко-режим не дал выигрыша — данных мало или нагрузка была разной."))
                              : Tr.t("Аналитика копится сама: NameLess раз в минуту записывает заряд, мощность и режим, пока ноутбук работает от батареи.")
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Repeater {
                        model: ["eco", "balanced", "perf"]
                        Row {
                            id: ar
                            required property string modelData
                            readonly property var sx: bp.stats[modelData]
                            readonly property var mi: bp.modeInfo[modelData]
                            width: anCol.width; spacing: 10
                            Text { width: 130; anchors.verticalCenter: parent.verticalCenter; text: ar.mi.i + "  " + ar.mi.t; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 12 }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 130 - 230 - 20; height: 12; radius: 6; color: Theme.fill(0.10)
                                Rectangle { width: parent.width * (ar.sx.ok ? ar.sx.full / anCol.parent.maxFull : 0); height: parent.height; radius: 6; color: ar.mi.c; Behavior on width { NumberAnimation { duration: 400 } } }
                            }
                            Text {
                                width: 230; anchors.verticalCenter: parent.verticalCenter
                                text: ar.sx.ok ? bp.hm(ar.sx.full * 3600) + Tr.t(" от полной · ") + ar.sx.pph.toFixed(1) + Tr.t(" %/ч") + (ar.sx.watts > 0 ? " · " + ar.sx.watts.toFixed(1) + Tr.t(" Вт") : "")
                                              : (ar.sx.hours > 0 ? Tr.t("копится: ") + Math.round(ar.sx.hours * 60) + Tr.t(" мин") : Tr.t("нет данных"))
                                color: ar.sx.ok ? Theme.text : Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 }
                            }
                        }
                    }
                }
            }

            // ---------- заряд за сутки ----------
            Text { text: Tr.t("Заряд за сутки"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7 }
            Rectangle {
                width: parent.width; height: 170; radius: Theme.r(16)
                color: Theme.fill(0.06); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.12)
                Canvas {
                    id: chart
                    anchors { fill: parent; margins: 14 }
                    property var pts: bp.samples
                    onPtsChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d"), W = width, H = height;
                        ctx.reset();
                        var now = Date.now() / 1000, t0 = now - 86400;
                        ctx.strokeStyle = Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08); ctx.lineWidth = 1;
                        for (var g = 0; g <= 4; g++) { ctx.beginPath(); ctx.moveTo(0, H * g / 4); ctx.lineTo(W, H * g / 4); ctx.stroke(); }
                        var p = pts.filter(function (s) { return s.t >= t0; });
                        if (p.length < 2) return;
                        function X(t) { return (t - t0) / 86400 * W; }
                        function Y(v) { return H - v / 100 * H; }
                        var cols = { eco: Theme.green, balanced: Theme.accent, perf: Theme.red };
                        for (var i = 1; i < p.length; i++) {
                            var a = p[i - 1], c = p[i];
                            if (c.t - a.t > 600) continue;                       // разрыв (компьютер спал)
                            if (a.ac) { ctx.fillStyle = Qt.rgba(Theme.green.r, Theme.green.g, Theme.green.b, 0.10); ctx.fillRect(X(a.t), 0, X(c.t) - X(a.t) + 1, H); }
                            var col = cols[a.m] || Theme.accent;
                            ctx.strokeStyle = col; ctx.lineWidth = 2.5;
                            ctx.beginPath(); ctx.moveTo(X(a.t), Y(a.p)); ctx.lineTo(X(c.t), Y(c.p)); ctx.stroke();
                        }
                    }
                }
                Text { anchors { right: parent.right; rightMargin: 14; top: parent.top; topMargin: 8 } text: Tr.t("сейчас"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                Text { anchors { left: parent.left; leftMargin: 14; top: parent.top; topMargin: 8 } text: Tr.t("24 ч назад"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
            }
            Row {
                spacing: 14
                Repeater {
                    model: [["eco", Theme.green], ["balanced", Theme.accent], ["perf", Theme.red], ["ac", Theme.green]]
                    Row {
                        required property var modelData
                        spacing: 6
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 14; height: modelData[0] === "ac" ? 10 : 3; radius: 1; color: modelData[1]; opacity: modelData[0] === "ac" ? 0.3 : 1 }
                        Text { text: modelData[0] === "ac" ? Tr.t("на зарядке") : bp.modeInfo[modelData[0]].t; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                    }
                }
            }
        }
    }
}
