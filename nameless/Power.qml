pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Режим питания ноутбука (power.sh сборки): eco — процессор бережёт заряд и дискретная видеокарта спит, balanced — обычный,
// perf — процессор на максимум и всё рисует дискретная. Плитки «Эко-режим» и «Производительный» в Пункте управления.
// Работа от батареи не в «эко» — suggest: карточка-предложение над плитками и уведомление при отключении зарядки
// (с выбором: включить эко-режим, не сейчас, не спрашивать); зарядку вернули после такого перехода — предложение вернуть прежний.
// Настройки — Config.store.gpu ({ ask, prev })
Singleton {
    id: pw
    property string rice: ""
    readonly property string script: rice !== "" ? rice + "/scripts/system/power.sh" : ""
    property var st: ({ mode: "balanced", cpu: { tool: "none" }, battery: false, laptop: false, percent: -1 })
    readonly property string mode: st.mode || "balanced"
    readonly property bool laptop: st.laptop === true || Sys.hasBattery
    readonly property bool onBattery: Sys.hasBattery && !Sys.charging
    readonly property bool cpuControl: st.cpu && st.cpu.tool !== "none"
    readonly property var o: Config.store.gpu || ({})
    // предложить эко-режим: от батареи, режим не «эко», спрашивать не запрещено и в этот раз не отказались
    property bool dismissed: false
    readonly property bool suggest: laptop && onBattery && mode !== "eco" && o.ask !== false && !dismissed && script !== ""

    Process {
        running: true
        // папка, где скрипт действительно есть: сборка (~/.config/glassrice/rice) могла быть старой, без него — тогда копия установщика
        command: ["sh", "-c", "r=$(cat \"$HOME/.config/glassrice/rice\" 2>/dev/null); for d in \"$r\" \"$HOME/.local/share/nameless\" \"$HOME/newdesign/glassrice\" \"$HOME/glassrice\"; do [ -n \"$d\" ] && [ -f \"$d/scripts/system/power.sh\" ] && { echo \"$d\"; exit; }; done"]
        stdout: StdioCollector { onStreamFinished: { pw.rice = text.trim(); pw.refresh(); } }
    }
    Process {
        id: stProc
        command: [pw.script, "status"]
        stdout: StdioCollector { onStreamFinished: { try { pw.st = JSON.parse(text); } catch (e) { } } }
    }
    function refresh() { if (script !== "" && !stProc.running) stProc.running = true; }
    Process {
        id: setProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "none") pw.tell(Tr.t("Процессор не переключён"), Tr.t("Нет управления процессором без пароля — «Функции» → «Графика и питание» → «Поставить управление процессором»"));
                pw.refresh(); Gpu.refresh();
            }
        }
    }
    // режим: Perf (живые фоны, частота опроса) следует за ним — в эко 30 кадров и реже опросы
    function setMode(m) {
        if (script === "") return;
        setProc.command = [script, "set", m]; setProc.running = true;
        Config.set("perf.mode", m === "eco" ? "eco" : (m === "perf" ? "normal" : "auto"));
        st = Object.assign({}, st, { mode: m });
    }
    function toggle(m) { setMode(mode === m ? "balanced" : m); }
    // установка в терминале: пароль sudo вводится там — терминал плавающий и по центру (правило glassrice-pkg), окна NameLess
    // перед ним закрываются (раньше диспетчер задач оставался поверх и закрывал запрос пароля); по окончании состояние перечитывается
    signal installing()
    Process {
        id: instProc
        onExited: { pw.refresh(); Gpu.refresh(); }
    }
    function installCpu() {
        if (script === "" || instProc.running) return;
        installing();
        instProc.command = ["kitty", "--class", "glassrice-pkg", "--title", Tr.t("Управление процессором"), "bash", script, "install"];
        instProc.running = true;
    }

    // ---------- журнал батареи (аналитика режимов в диспетчере задач, вкладка «Батарея») ----------
    // раз в минуту: время, заряд, мощность (Вт), режим, на зарядке ли; файл обрезается до последних 30 000 записей
    readonly property string logFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/nameless/battery.jsonl"
    signal logged()
    Timer {
        interval: 60000; repeat: true; triggeredOnStart: true
        running: Sys.hasBattery
        onTriggered: {
            var b = Sys.bat, rate = b && b.changeRate !== undefined ? Math.abs(b.changeRate) : 0;
            var line = JSON.stringify({ t: Math.round(Date.now() / 1000), p: Sys.batPct, w: Math.round(rate * 10) / 10, m: pw.mode, ac: Sys.charging });
            Quickshell.execDetached(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\"; printf '%s\\n' \"$2\" >> \"$1\"; n=$(wc -l < \"$1\"); [ \"$n\" -gt 30000 ] && tail -n 30000 \"$1\" > \"$1.tmp\" && mv \"$1.tmp\" \"$1\"; exit 0", "sh", pw.logFile, line]);
            pw.logged();
        }
    }

    // ---------- зарядка ----------
    Connections {
        target: Sys
        function onChargingChanged() {
            pw.dismissed = false;
            if (!Sys.hasBattery || pw.o.ask === false || pw.script === "") return;
            pw.refresh();
            if (!Sys.charging && pw.mode !== "eco") pw.ask(false);
            else if (Sys.charging && pw.o.prev && pw.mode === "eco") pw.ask(true);
        }
    }
    Process {
        id: askProc
        stdout: StdioCollector {
            onStreamFinished: {
                var a = text.trim();
                if (a === "eco") { Config.set("gpu.prev", pw.mode); pw.setMode("eco"); }
                else if (a === "later") pw.dismissed = true;
                else if (a === "never") Config.set("gpu.ask", false);
                else if (a === "back") { pw.setMode(pw.o.prev || "balanced"); Config.set("gpu.prev", ""); }
            }
        }
    }
    function ask(back) {
        if (askProc.running) return;
        if (back) askProc.command = ["notify-send", "-a", "NameLess", "-i", "battery-full-charging", "-A", "back=" + Tr.t("Вернуть прежний"), "-A", "stay=" + Tr.t("Оставить эко"), "--wait",
                                     Tr.t("Зарядка подключена"), Tr.t("Вернуть прежний режим процессора и видеокарты?")];
        else askProc.command = ["notify-send", "-a", "NameLess", "-i", "battery-caution", "-A", "eco=" + Tr.t("Эко-режим"), "-A", "later=" + Tr.t("Не сейчас"), "-A", "never=" + Tr.t("Не спрашивать"), "--wait",
                                Tr.t("Работа от батареи"), Tr.t("Включить эко-режим? Процессор будет беречь заряд, дискретная видеокарта уснёт.")];
        askProc.running = true;
    }
    function tell(title, body) { Quickshell.execDetached(["notify-send", "-a", "NameLess", "-i", "battery", title, body]); }
}
