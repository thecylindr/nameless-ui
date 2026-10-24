pragma Singleton
import QtQuick
import Quickshell

// Значки приложений: тема иконок (QS_ICON_THEME, «Программы» → «Иконки») и свои замены для отдельных приложений.
// Замена — Config.store.icons.overrides { «имя значка»: «имя в теме» | «/путь/к/файлу» }; задаётся в той же вкладке
Singleton {
    readonly property var overrides: (Config.store.icons || {}).overrides || ({})
    // путь картинки для значка name; fallback — имя запасного значка
    function app(name, fallback) {
        var n = overrides[name] || name || "";
        if (n.charAt(0) === "/") return "file://" + n;
        return Quickshell.iconPath(n, true) || (n !== name && name ? Quickshell.iconPath(name, true) : "")
            || Quickshell.iconPath(fallback || "application-x-executable", true);
    }
    function setOverride(name, value) {
        var o = Object.assign({}, overrides);
        if (value) o[name] = value; else delete o[name];
        Config.set("icons.overrides", o);
    }
}
