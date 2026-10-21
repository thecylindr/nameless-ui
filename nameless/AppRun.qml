pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Запуск программ из лаунчера, дока и мастера программ. Через qs-app.sh: программа получает окружение сессии, а не
// облегчённое окружение самого Quickshell (qs-light.sh). Без скрипта или для приложений в терминале — обычный execute()
//
// Программы с одним экземпляром (Telegram, Discord, Incy…) при повторном запуске лишь передают команду «показать окно» работающей копии,
// а Hyprland сам на её рабочий стол не переключается — казалось, что программа «не запускается». Поэтому после запуска (через секунду)
// проверяется: если новых окон программы не появилось, а старое есть — фокус переходит на него (вместе с переходом на его рабочий стол).
// Программы, открывающие новое окно при каждом запуске (терминал, браузер), этим не затрагиваются
Singleton {
    readonly property string wrapper: Quickshell.env("HOME") + "/.config/hypr/Scripts/qs-app.sh"

    property var cur: null            // запускаемая программа
    property int before: 0            // сколько окон этой программы было до запуска

    // окно принадлежит программе: класс окна совпадает с идентификатором ярлыка или StartupWMClass, либо заголовок равен названию программы
    function same(c, e) {
        var cls = String(c["class"] || "").toLowerCase(), ti = String(c.title || "").toLowerCase();
        var id = String(e.id || "").toLowerCase().replace(/\.desktop$/, ""), sc = String(e.startupClass || "").toLowerCase();
        var nm = String(e.name || "").toLowerCase();
        return (cls !== "" && (cls === id || cls === sc)) || (ti !== "" && nm !== "" && ti === nm);
    }
    function mine(list) {
        var out = [];
        for (var i = 0; i < list.length; i++) if (cur && same(list[i], cur) && list[i].mapped !== false) out.push(list[i]);
        return out;
    }

    Process {
        id: beforeProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = []; try { l = JSON.parse(text); } catch (e) { }
                var app = cur; if (!app) return;
                before = mine(l).length;
                afterT.restart();
            }
        }
    }
    Process {
        id: afterProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = []; try { l = JSON.parse(text); } catch (e) { }
                var w = mine(l);
                // окон не прибавилось, а старое есть — программа передала запуск работающей копии: показываем её
                if (w.length > 0 && w.length <= before) {
                    w.sort(function (a, b) { return (b.focusHistoryID !== undefined ? -b.focusHistoryID : 0) - (a.focusHistoryID !== undefined ? -a.focusHistoryID : 0); });
                    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"address:" + w[0].address + "\" })"]);
                }
                cur = null;
            }
        }
    }
    Timer { id: afterT; interval: 1100; onTriggered: afterProc.running = true }

    function doLaunch(e) {
        if (e.runInTerminal || !e.command || e.command.length === 0) { e.execute(); return; }
        Quickshell.execDetached({ command: [wrapper].concat(e.command), workingDirectory: e.workingDirectory || Quickshell.env("HOME") });
    }
    function run(e) {
        if (!e) return;
        // только Hyprland (hyprctl); в других композиторах — как раньше, без проверки окон
        if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") === "" || e.runInTerminal) { doLaunch(e); return; }
        // запуск не зависит от hyprctl: снимок окон делается параллельно (окно новой программы появляется заметно позже), проверка — через секунду
        cur = e;
        beforeProc.running = false;
        beforeProc.running = true;
        doLaunch(e);
    }
}
