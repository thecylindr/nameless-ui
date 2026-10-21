pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Язык интерфейса NameLess UI: русский — исходные тексты в коде, английский — словарь i18n/en.json («русская строка» → «английская»).
// Текст оборачивается в Tr.t("…"); нет строки в словаре — остаётся русская, интерфейс не пустеет. Язык — Config.store.lang (ru | en),
// меняется на лету: привязки читают lang и dict внутри t() и пересчитываются сами
Singleton {
    id: tr
    readonly property string lang: Config.store.lang === "en" ? "en" : "ru"
    property var dict: ({})
    FileView {
        path: Quickshell.shellPath("i18n/en.json")
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
