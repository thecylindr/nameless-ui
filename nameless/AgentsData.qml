pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Данные мониторов помощников, общие для виджета «Помощники», пункта в баре и окна монитора:
//   usage — лимиты Claude Code (окно 5 часов, неделя) через usage.py; stats — расход токенов по журналам (claude_stats.py).
// Запросы идут только пока кому-то нужны (окно открыто, виджет включён или пункт в баре включён) и только если не выключено
// agents.quota (Features → «Лимиты Claude»); раз в 2 минуты. Токен Claude Code используется только для запроса лимитов и не сохраняется
Singleton {
    id: d
    readonly property string dir: Quickshell.shellDir || (Quickshell.env("HOME") + "/.config/quickshell/nameless")
    readonly property var cfg: Config.store.agents
    readonly property bool enabled: cfg.quota !== false
    readonly property bool barOn: cfg.bar === true
    readonly property bool widgetOn: (Config.widgets.items || []).some(function (i) { return (i.type === "agents" || i.type === "claude" || i.type === "tokens") && i.on; })
    readonly property bool statsOn: (Config.widgets.items || []).some(function (i) { return (i.type === "agents" || i.type === "tokens") && i.on; })
    property bool panelOpen: false
    readonly property bool need: enabled && (panelOpen || widgetOn || barOn)
    readonly property bool needStats: enabled && (panelOpen || statsOn)

    property var usage: null          // ответ usage.py
    property string err: ""
    property var codexStats: null
    readonly property var codexUsage: codexStats ? codexStats.usage : null
    readonly property bool codexEnabled: cfg.codexStats !== false
    readonly property bool needCodex: codexEnabled && (panelOpen || widgetOn)
    property var stats: null
    property bool loading: false

    readonly property real util5: usage && usage.ok ? usage.five.util : -1
    readonly property real util7: usage && usage.ok ? usage.seven.util : -1
    function level(p) { return p < 0 ? Theme.sub : (p >= 90 ? Theme.red : (p >= 70 ? Theme.yellow : Theme.green)); }

    Process {
        id: uProc
        stdout: StdioCollector {
            onStreamFinished: {
                d.loading = false;
                try {
                    var r = JSON.parse(text);
                    d.usage = r.ok || !d.usage ? r : d.usage;     // при ошибке остаются прежние данные
                    d.err = r.ok ? (r.err || "") : (r.err || "failed");
                } catch (e) { d.err = "failed"; }
            }
        }
    }
    Process {
        id: sProc
        stdout: StdioCollector { onStreamFinished: { try { d.stats = JSON.parse(text); } catch (e) { } } }
    }
    Process {
        id: cProc
        stdout: StdioCollector { onStreamFinished: { try { d.codexStats = JSON.parse(text); } catch (e) { } } }
    }
    function refreshCodex() {
        if (codexEnabled && !cProc.running) { cProc.command = ["nice", "-n", "10", "python3", dir + "/codex_stats.py"]; cProc.running = true; }
    }
    Timer { interval: 60000; repeat: true; running: d.needCodex; triggeredOnStart: true; onTriggered: d.refreshCodex() }
    function quotaWindows(u, codex) {
        if (!u || !u.ok) return [];
        if (!codex) return [{ t: Tr.t("5 часов"), u: u.five }, { t: Tr.t("Неделя"), u: u.seven }];
        var result = [];
        [u.primary, u.secondary].forEach(function (v) {
            if (v && v.util >= 0) result.push({ t: v.minutes === 10080 ? Tr.t("Неделя") : (v.minutes >= 60 ? Math.round(v.minutes / 60) + Tr.t(" ч") : v.minutes + Tr.t(" мин")), u: v });
        });
        return result;
    }
    function refresh(force) {
        if (needCodex) refreshCodex();
        if (!enabled) return;
        if (!uProc.running) { loading = true; uProc.command = ["python3", dir + "/usage.py"].concat(force ? ["--force"] : []); uProc.running = true; }
        if (needStats && !sProc.running) { sProc.command = ["nice", "-n", "10", "python3", dir + "/claude_stats.py"]; sProc.running = true; }
    }
    Timer { interval: 120000; repeat: true; running: d.need; triggeredOnStart: true; onTriggered: d.refresh(false) }
    onNeedChanged: if (need && !usage) refresh(false)

    // ---------- подписи ----------
    function errText(e) {
        return ({ no_credentials: Tr.t("Claude Code не входил в аккаунт"), expired: Tr.t("токен истёк — откройте Claude Code, он обновится сам"), auth: Tr.t("доступ отклонён — войдите в Claude Code заново"),
                  rate: Tr.t("слишком частые запросы, данные немного устарели"), offline: Tr.t("нет связи с Anthropic (VPN?)"), timeout: Tr.t("Anthropic не отвечает"), failed: Tr.t("не удалось получить") })[e] || e;
    }
    function left(ts) {
        var s = Math.max(0, Math.round(ts - Date.now() / 1000));
        if (s < 90) return s + Tr.t(" с");
        if (s < 3600) return Math.round(s / 60) + Tr.t(" мин");
        if (s < 86400) return Math.floor(s / 3600) + Tr.t(" ч ") + Math.floor(s / 60) % 60 + Tr.t(" мин");
        return Math.floor(s / 86400) + Tr.t(" д ") + Math.floor(s / 3600) % 24 + Tr.t(" ч");
    }
    function clock(ts) { return new Date(ts * 1000).toLocaleString(Qt.locale("ru_RU"), "ddd d MMM, HH:mm"); }
    function tok(n) {
        n = n || 0;
        if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1).replace(".", ",") + Tr.t(" млн");
        if (n >= 1e3) return Math.round(n / 1e3) + Tr.t(" тыс.");
        return String(n);
    }
    function etaText(sec) { return sec < 3600 ? Math.max(1, Math.round(sec / 60)) + Tr.t(" мин") : Math.floor(sec / 3600) + Tr.t(" ч ") + Math.round(sec % 3600 / 60) + Tr.t(" мин"); }
}
