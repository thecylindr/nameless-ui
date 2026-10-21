pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// «Claude закончил работу» → уведомление на подключённые устройства Orbit (телефон, второй компьютер).
// Раз в 4 секунды (только пока включено и есть подключённые устройства) спрашивается agents.py — тот же источник, что у виджета
// «Помощники»: статус каждой сессии Claude Code и его последнее сообщение. Уведомление уходит, когда помощник, работавший
// дольше claudeMin секунд, перестал работать или остановился в ожидании ответа. Ничего в настройках Claude Code менять не нужно
Singleton {
    id: n
    readonly property bool on: Config.store.orbit.claude !== false
    readonly property int minBusy: Config.store.orbit.claudeMin || 20           // меньше этого — быстрый ответ, не стоит отвлекать
    readonly property bool active: on && OrbitData.enabled && OrbitData.running && OrbitData.connected.length > 0
    readonly property string script: (Quickshell.shellDir || (Quickshell.env("HOME") + "/.config/quickshell/nameless")) + "/agents.py"

    property var seen: ({})            // id → { status, busySince, notifiedAt }

    function waiting(s) { return /wait|input|permission|approval/i.test(s || ""); }

    // чистый текст: без разметки markdown, переводов строк и управляющих символов; в телефоне это один-два аккуратных предложения
    function plain(t) {
        return (t || "").replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/```[\s\S]*?```/g, " ").replace(/[`*_#>]+/g, "").replace(/^[\s\-–•]+/, "").replace(/\s+/g, " ").trim();
    }

    function sendFor(a, kind, busySecs) {
        var last = plain(a.last);
        var project = a.project || "Claude Code";
        var title, body;
        if (kind === "ask") {
            title = Tr.t("Claude ждёт ответа · ") + project;
            body = last !== "" ? last : Tr.t("Нужно ваше решение");
        } else {
            // тесты упомянуты и прошли — так и пишем: ради этого уведомление чаще всего и нужно
            var ok = /(тест|test)[^.]{0,40}(прош|успеш|pass|ok|зелен)|all tests|tests? passed/i.test(last);
            title = (ok ? Tr.t("✅ Тесты пройдены · ") : Tr.t("Claude закончил · ")) + project;
            body = last !== "" ? last : (plain(a.prompt) !== "" ? Tr.t("Задача: ") + plain(a.prompt) : Tr.t("Работа завершена"));
            var m = Math.round(busySecs / 60);
            if (busySecs >= 60) body += Tr.t(" (работал ") + m + Tr.t(" мин)");
        }
        if (body === "") body = title;                  // пустого уведомления не бывает
        OrbitData.notifyReply(title, body.slice(0, 400));
    }

    Process {
        id: poll
        command: ["python3", n.script]
        stdout: StdioCollector {
            onStreamFinished: {
                var d;
                try { d = JSON.parse(text); } catch (e) { return; }
                var now = Date.now(), cur = {}, list = d.agents || [];
                for (var i = 0; i < list.length; i++) {
                    var a = list[i];
                    if (a.kind !== "claude") continue;
                    var p = n.seen[a.id];
                    var e2 = { status: a.status, busySince: p && p.status === "busy" ? p.busySince : (a.status === "busy" ? now : 0), notifiedAt: p ? p.notifiedAt : 0 };
                    if (p && now - e2.notifiedAt > 10000) {
                        var busyFor = p.busySince ? (now - p.busySince) / 1000 : 0;
                        if (p.status === "busy" && a.status !== "busy" && busyFor >= n.minBusy) {
                            n.sendFor(a, n.waiting(a.status) ? "ask" : "done", busyFor);
                            e2.notifiedAt = now;
                        }
                    }
                    cur[a.id] = e2;
                }
                n.seen = cur;
            }
        }
    }
    Timer {
        interval: 4000; repeat: true; running: n.active
        onTriggered: if (!poll.running) poll.running = true
    }
    onActiveChanged: if (!active) seen = ({})       // включили заново — прежние состояния не должны давать «ложных» завершений
}
