pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Оформление NameLess UI: профиль темы из theme.sh (комплект, палитра, акцент, стекло) и производные — цвета,
// шрифты, радиусы, материалы. Перечитывается по IPC «theme reload» — его шлёт theme.sh после каждого изменения
Singleton {
    id: t

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/Scripts/theme.sh"
    property var st: ({ current: "", theme: null, themes: [], palettes: [] })
    readonly property var th: st.theme || ({})
    readonly property var pal: {
        for (var i = 0; i < st.palettes.length; i++) if (st.palettes[i].id === th.palette) return st.palettes[i];
        return null;
    }
    readonly property var c: pal ? pal.colors : null

    // комплект: classic — мой исходный дизайн, liquid — стекло как в клиенте, ios — как iOS
    readonly property string kit: th.kit ? th.kit : (th.style !== "glass" ? "classic" : "liquid")
    readonly property bool glass: kit !== "classic"
    readonly property bool ios: kit === "ios"
    readonly property bool dark: pal ? pal.dark : true
    // космос вместо обоев (поле sky темы): off | stars — звёздное небо | solar — небо и солнечная система (прежнее true)
    readonly property string cosmos: th.sky === true || th.sky === "solar" ? "solar" : (th.sky === "stars" || th.sky === "apps" ? th.sky : "off")

    // цвета
    readonly property color base: c ? c.base : "#24273a"
    readonly property color mantle: c ? c.mantle : "#1e2030"
    readonly property color crust: c ? c.crust : "#181926"
    readonly property color surface: c ? c.surface0 : "#363a4f"
    readonly property color text: glass ? (dark ? "#ffffff" : "#1d1d1f") : (c ? c.text : "#cad3f5")
    readonly property color sub: glass ? (dark ? Qt.rgba(1, 1, 1, 0.6) : Qt.rgba(0, 0, 0, 0.5)) : (c ? c.subtext0 : "#a5adcb")
    readonly property color accent: th.accent ? th.accent : (c ? c.blue : "#8aadf4")
    readonly property color accent2: th.accent2 ? th.accent2 : (c ? c.lavender : "#b7bdf8")
    readonly property color red: c ? c.red : "#ed8796"
    readonly property color green: c ? c.green : "#a6da95"
    readonly property color yellow: c ? c.yellow : "#eed49f"
    readonly property color peach: c ? c.peach : "#f5a97f"
    readonly property color teal: c ? c.teal : "#8bd5ca"
    readonly property real tint: th.glass && th.glass.tint !== undefined ? th.glass.tint : 0.22

    // шрифты: классика — как исходный waybar, стекло и iOS — первое доступное из Inter / SF Pro / системного
    readonly property string iconFont: "JetBrainsMono Nerd Font"
    readonly property string font: {
        if (!glass) return "CaskaydiaCove Nerd Font";
        var want = ["Inter Variable", "Inter", "SF Pro Display", "Noto Sans"], have = Qt.fontFamilies();
        for (var i = 0; i < want.length; i++) if (have.indexOf(want[i]) >= 0) return want[i];
        return Qt.application.font.family;
    }
    readonly property int fontSize: ios ? 13 : 13

    // заливка элементов: стекло — дымка, классика — поверхность палитры светлее фона
    function fill(a) {
        if (!glass) return Qt.tint(base, Qt.rgba(text.r, text.g, text.b, Math.min(0.5, 0.04 + a * 0.8)));
        return dark ? Qt.rgba(1, 1, 1, a) : Qt.rgba(1, 1, 1, Math.min(0.92, 0.32 + a * 2));
    }
    // рамка: классика — цвет текста, стекло клиента — белый кант, iOS — без рамок (объёмный край)
    function line(a) {
        if (kit === "classic") return Qt.rgba(text.r, text.g, text.b, a);
        if (kit === "liquid") return Qt.rgba(1, 1, 1, Math.min(0.5, a + 0.06));
        return "transparent";
    }
    // радиусы: iOS — как заданы, стекло клиента — 16 / 11, классика — 16 / 8
    function r(x) {
        if (kit === "ios") return x;
        return x > 20 ? 16 : (kit === "liquid" ? 11 : 8);
    }
    // плотность поверхности панели: классика как waybar (0.85), стекло — по матовости темы
    // выдвижные панели (лаунчер, уведомления, Пункт управления, справка) плотнее бара
    // выдвижные окна в стекле плотнее (не ниже 0.8): пёстрые обои не перетягивают внимание с содержимого
    readonly property real overlayAlpha: glass ? Math.min(0.94, Math.max(0.8, panelAlpha + 0.3)) : 0.96
    // затемнение экрана под окнами — одно на всех, как у менеджера программ
    readonly property real dimAlpha: glass ? 0.42 : 0.32
    // открытие плавное, закрытие короткое: окно исчезает сразу, как в других системах
    function dur(open) { return open ? 220 : 120; }
    readonly property real panelAlpha: glass ? Math.min(0.92, Math.max(0.30, 0.10 + tint * 0.9 + (ios ? 0.06 : 0.10))) : 0.92

    // автор сборки: портфолио и канал (приветствие и шапка Пункта управления)
    readonly property var links: [
        { i: "󰊤", t: "GitHub", d: "github.com/thecylindr", u: "https://github.com/thecylindr", c: "#24292f" },
        { i: "󰊢", t: "GitFlic", d: "gitflic.ru/user/cylindr", u: "https://gitflic.ru/user/cylindr", c: "#3b5bdb" },
        { i: "\uf2c6", t: "Telegram", d: "t.me/ITCylindr", u: "https://t.me/ITCylindr", c: "#2aabee" }
    ]

    Process {
        id: dump
        command: [t.script, "dump"]
        stdout: StdioCollector {
            onStreamFinished: { try { t.st = JSON.parse(text); } catch (e) { } }
        }
    }
    function reload() { if (!dump.running) dump.running = true; }
    Component.onCompleted: reload()

    IpcHandler {
        target: "theme"
        function reload(): void { t.reload(); }
    }
}
