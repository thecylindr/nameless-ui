pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Профили: «Обычный», «Работа», «Игры», «Ночь» и свои. Профиль — набор значений, которые ставятся одним нажатием:
// «не беспокоить», «кофеин», ночной свет, анимации и размытие Hyprland, яркость, подсветка клавиатуры.
// Значение "keep" не трогает настройку. Список и активный профиль — в Config.store.profiles
Singleton {
    id: p
    readonly property var cfg: Config.store.profiles
    readonly property var list: cfg.items || []
    readonly property string active: cfg.active || "normal"
    readonly property var current: find(active)
    function find(id) { for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]; return null; }

    readonly property string rgbScript: Quickshell.env("HOME") + "/.config/glassrice/rice"
    Process { id: rgbProc }

    function apply(id) {
        var pr = find(id);
        if (!pr) return;
        Config.set("profiles.active", id);
        if (pr.dnd === "on" || pr.dnd === "off") Notifs.dnd = pr.dnd === "on";
        if (pr.caffeine === "on" || pr.caffeine === "off") Sys.setCaffeine(pr.caffeine === "on");
        // ночной свет: hyprsunset с температурой профиля; выкл — останавливается
        if (pr.night === "on") Quickshell.execDetached(["sh", "-c", "pkill -x hyprsunset; command -v hyprsunset >/dev/null && setsid -f hyprsunset -t " + (pr.nightTemp || 4000) + " >/dev/null 2>&1"]);
        else if (pr.night === "off") Quickshell.execDetached(["sh", "-c", "pkill -x hyprsunset"]);
        // анимации и размытие — параметры темы Hyprland; меняются, только если отличаются (смена перечитывает правила)
        var hy = (Theme.th && Theme.th.hypr) ? Theme.th.hypr : ({});
        if ((pr.animations === "on" || pr.animations === "off") && hy.animations !== (pr.animations === "on")) Quickshell.execDetached([Theme.script, "set-auto", ".hypr.animations", pr.animations === "on" ? "true" : "false"]);
        if ((pr.blur === "on" || pr.blur === "off") && hy.blur !== (pr.blur === "on")) Quickshell.execDetached([Theme.script, "set-auto", ".hypr.blur", pr.blur === "on" ? "true" : "false"]);
        if ((pr.brightness || 0) > 0) Sys.setBrightness(pr.brightness);
        // подсветка: выкл — погасить, вкл — вернуть сохранённый цвет
        if (pr.rgb === "off" || pr.rgb === "on")
            Quickshell.execDetached(["sh", "-c", "for d in \"$(cat \"$HOME/.config/glassrice/rice\" 2>/dev/null)\" \"$HOME/.local/share/nameless\"; do [ -n \"$d\" ] && [ -f \"$d/scripts/system/rgb.sh\" ] && exec bash \"$d/scripts/system/rgb.sh\" " + (pr.rgb === "off" ? "off" : "restore") + "; done"]);
        Quickshell.execDetached(["notify-send", "-a", Tr.t("Профили"), Tr.t("Профиль «") + pr.name + "»", summary(pr)]);
    }
    function next() { var i = 0; for (var k = 0; k < list.length; k++) if (list[k].id === active) i = k; apply(list[(i + 1) % list.length].id); }

    // кратко: что профиль меняет
    function summary(pr) {
        var a = [];
        if (pr.dnd === "on") a.push(Tr.t("тишина")); else if (pr.dnd === "off") a.push(Tr.t("уведомления"));
        if (pr.caffeine === "on") a.push(Tr.t("кофеин"));
        if (pr.night === "on") a.push(Tr.t("ночной свет ") + (pr.nightTemp || 4000) + " K");
        if (pr.animations === "off") a.push(Tr.t("без анимаций"));
        if (pr.blur === "off") a.push(Tr.t("без размытия"));
        if ((pr.brightness || 0) > 0) a.push(Tr.t("яркость ") + pr.brightness + "%");
        if (pr.rgb === "off") a.push(Tr.t("подсветка выкл"));
        return a.join(" · ");
    }
    // правка списка
    function save(arr) { Config.set("profiles.items", arr); }
    function update(id, key, val) {
        var arr = list.map(function (x) { if (x.id !== id) return x; var n = Object.assign({}, x); n[key] = val; return n; });
        save(arr);
    }
    function add() {
        var arr = list.slice(), n = 1;
        while (find("custom" + n)) n++;
        arr.push({ id: "custom" + n, name: Tr.t("Мой профиль ") + n, icon: "󰣆", dnd: "keep", caffeine: "keep", night: "keep", animations: "keep", blur: "keep", rgb: "keep", brightness: 0, nightTemp: 4000 });
        save(arr);
        return "custom" + n;
    }
    function remove(id) { if (list.length <= 1) return; save(list.filter(function (x) { return x.id !== id; })); if (active === id) Config.set("profiles.active", list[0].id); }

    IpcHandler {
        target: "profiles"
        function apply(id: string): void { p.apply(id); }
        function next(): void { p.next(); }
    }
}
