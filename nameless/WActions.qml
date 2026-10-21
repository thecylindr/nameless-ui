import QtQuick
import Quickshell

// Быстрые действия: плитки-кнопки; набор — Config.store.actions.list (выбирается в панели «Рабочий стол»)
WCard {
    id: w
    // все доступные действия: значок, подпись, команда
    readonly property var all: ({
        terminal:   { i: "󰆍", t: Tr.t("Терминал"),  c: ["kitty"] },
        files:      { i: "󰉋", t: Tr.t("Файлы"),     c: ["dolphin"] },
        browser:    { i: "󰖟", t: Tr.t("Браузер"),   c: ["sh", "-c", "xdg-open https://"] },
        screenshot: { i: "󰹑", t: Tr.t("Скриншот"),  c: [Theme.script, "action", "screenshot"] },
        lock:       { i: "󰌾", t: Tr.t("Блок"),      c: [Theme.script, "action", "lock"] },
        drawer:     { i: "󰏘", t: Tr.t("Темы"),      c: [Theme.script, "action", "drawer"] },
        programs:   { i: "󰏖", t: Tr.t("Программы"), c: ["qs", "-c", "nameless", "ipc", "call", "programs", "toggle"] },
        wallpaper:  { i: "󰸉", t: Tr.t("Обои"),      c: [Theme.script, "action", "wallpaper-next"] },
        dnd:        { i: "󰂛", t: Tr.t("Тишина"),    c: ["qs", "-c", "nameless", "ipc", "call", "notifs", "dnd"] },
        monitor:    { i: "󰍛", t: Tr.t("Диспетчер"), c: ["qs", "-c", "nameless", "ipc", "call", "tasks", "toggle"] },
        settings:   { i: "󰒓", t: Tr.t("Стол"),      c: ["qs", "-c", "nameless", "ipc", "call", "desktop", "toggle"] },
        power:      { i: "󰐥", t: Tr.t("Питание"),   c: ["qs", "-c", "nameless", "ipc", "call", "control", "toggle"] }
    })
    readonly property var list: (Config.store.actions.list || []).filter(function (k) { return w.all[k] !== undefined; })
    readonly property int cols: 4
    // ширина плитки — от внутренней области карточки (за вычетом полей), иначе правый столбец вылезает за рамку
    readonly property real cw: Math.floor((width - pad * 2 - (cols - 1) * 8) / cols)
    implicitHeight: pad * 2 + Math.max(1, Math.ceil(list.length / cols)) * (cw * 0.86 + 8) - 8
    empty: list.length === 0

    Grid {
        columns: w.cols
        spacing: 8
        Repeater {
            model: w.list
            GTile {
                id: tile
                required property string modelData
                readonly property var a: w.all[modelData]
                ui: Theme
                width: w.cw; height: w.cw * 0.86; radius: 18
                on: modelData === "dnd" && Notifs.dnd
                Column {
                    anchors.centerIn: parent
                    spacing: 3
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.a.i; color: tile.on ? "white" : Theme.accent; font.family: Theme.iconFont; font.pixelSize: 20 }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.a.t; color: tile.on ? "white" : Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                }
                onClicked: Quickshell.execDetached(a.c)
            }
        }
    }
}
