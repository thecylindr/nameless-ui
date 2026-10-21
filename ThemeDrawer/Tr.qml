pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Язык шторки «Оформление»: берётся из настроек NameLess UI (~/.config/glassrice/nameless.json, поле lang), словарь — тот же i18n/en.json
// (рабочая папка NameLess UI). Меняется на лету: файл настроек отслеживается
Singleton {
    id: tr
    property string lang: "ru"
    property var dict: ({})
    FileView {
        path: Quickshell.env("HOME") + "/.config/glassrice/nameless.json"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { tr.lang = JSON.parse(text()).lang === "en" ? "en" : "ru"; } catch (e) { } }
    }
    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/nameless/i18n/en.json"
        blockLoading: true
        printErrors: false
        onLoaded: { try { tr.dict = JSON.parse(text()); } catch (e) { } }
    }
    function t(s) {
        if (lang !== "en") return s;
        var v = dict[s];
        return v === undefined ? s : v;
    }
}
