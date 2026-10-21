import QtQuick
import Quickshell
import Quickshell.Io

// Погода: сейчас, ощущается, ветер, влажность и прогноз на 1–3 дня. Данные — weather.sh рядом (один вид у всех):
// Open-Meteo (по умолчанию), MET Norway (yr.no) или wttr.in — бесплатные, без ключей. Опрос — раз в 30 мин
// и при смене города или источника. Город и источник выбираются прямо в виджете: клик по месту
WCard {
    id: w
    readonly property var o: Config.store.weather
    property var wx: null
    property string err: ""
    property string errKind: ""           // timeout | offline | server | failed — сервис не ответил
    property bool timedOut: false
    property bool editing: false
    readonly property string provider: o.provider || "open-meteo"
    readonly property var providers: [{ v: "open-meteo", t: "Open-Meteo" }, { v: "metno", t: "MET Norway" }, { v: "wttr", t: "wttr.in" }]
    readonly property var cities: [Tr.t("Москва"), Tr.t("Санкт-Петербург"), Tr.t("Новосибирск"), Tr.t("Екатеринбург"), Tr.t("Казань"), Tr.t("Нижний Новгород"),
                                   Tr.t("Краснодар"), Tr.t("Сочи"), Tr.t("Владивосток"), Tr.t("Минск"), Tr.t("Алматы"), Tr.t("Ереван"), Tr.t("Тбилиси"), Tr.t("Берлин"), Tr.t("Лондон"), Tr.t("Токио")]
    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/nameless/weather.sh"
    readonly property var days: wx ? wx.days.slice(0, Math.max(1, Math.min(3, o.days || 3))) : []
    function t(x) { return x === undefined || x === null ? "" : x + "°"; }
    function icon(k) { return ({ clear: "󰖙", partly: "󰖕", cloudy: "󰖐", fog: "󰖑", drizzle: "󰖗", rain: "󰖖", snow: "󰖘", storm: "󰖓" })[k] || "󰖐"; }
    function pick(c) { Config.set("weather.city", c); editing = false; }

    implicitHeight: editing ? cityCol.implicitHeight + pad * 2 : (wx ? 168 : (errKind !== "" ? 150 : 76))

    Process {
        id: proc
        command: [w.script, w.provider, w.o.city || "", w.o.units || "C", String(w.o.days || 3)]
        stdout: StdioCollector {
            onStreamFinished: {
                if (w.timedOut) { w.timedOut = false; return; }
                watchdog.stop();
                var d = null;
                try { d = JSON.parse(text); } catch (e) { d = null; }
                if (d && d.temp !== undefined) { w.wx = d; w.err = ""; w.errKind = ""; return; }
                w.errKind = d && d.error ? d.error : "failed";
                w.err = Tr.t("Нет данных от ") + w.providerName;
            }
        }
    }
    readonly property string providerName: (providers.filter(function (p) { return p.v === provider; })[0] || { t: provider }).t
    // сторож: сервис молчит дольше 25 с — запрос обрывается, виджет предлагает сменить источник или включить VPN
    Timer { id: watchdog; interval: 25000; onTriggered: { if (proc.running) { w.timedOut = true; proc.running = false; w.errKind = "timeout"; w.err = Tr.t("Нет данных от ") + w.providerName; } } }
    function reload() { if (proc.running) return; errKind = ""; timedOut = false; watchdog.restart(); proc.running = true; }
    // следующий источник по кругу
    function nextProvider() { var i = 0; for (var k = 0; k < providers.length; k++) if (providers[k].v === provider) i = k; Config.set("weather.provider", providers[(i + 1) % providers.length].v); }
    Timer { interval: 1800000; repeat: true; running: w.visible; triggeredOnStart: true; onTriggered: w.reload() }
    // новый город, источник, единицы — перезапрос
    readonly property string key: [o.city, provider, o.units, o.days].join("|")
    onKeyChanged: retry.restart()
    Timer { id: retry; interval: 600; onTriggered: w.reload() }

    // загрузка / нет данных: причина и что можно сделать — сменить источник, повторить, включить VPN
    Column {
        visible: !w.wx && !w.editing
        anchors.centerIn: parent
        width: parent.width
        spacing: 6
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            text: w.errKind === "" ? Tr.t("󰑓  Загрузка погоды…") : "󰖪  " + w.providerName + ({ timeout: Tr.t(" не отвечает"), offline: Tr.t(": нет соединения"), server: Tr.t(" вернул ошибку"), failed: Tr.t(": нет данных") })[w.errKind]
            color: w.errKind === "" ? Theme.sub : Theme.yellow; font.family: Theme.iconFont; font.pixelSize: 12
        }
        Text {
            visible: w.errKind !== ""
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            text: Tr.t("Смените источник или включите VPN")
            color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
        }
        Flow {
            visible: w.errKind !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width, 300)
            spacing: 6
            layoutDirection: Qt.LeftToRight
            Chip { text: Tr.t("󰑓 Повторить"); onClicked: w.reload() }
            Chip { text: "󰒝 " + (w.providers[(w.providers.map(function (p) { return p.v; }).indexOf(w.provider) + 1) % w.providers.length].t); on: true; onClicked: w.nextProvider() }
            Chip { visible: Vpn.available; text: "󰦝 " + Vpn.name; onClicked: Vpn.open() }
            Chip { text: Tr.t("󰍎 Город"); onClicked: { w.editing = true; cityInput.forceActiveFocus(); } }
        }
        Text {
            visible: w.errKind === ""
            width: parent.width; horizontalAlignment: Text.AlignHCenter
            text: Tr.t("нажмите, чтобы выбрать город")
            color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { w.editing = true; cityInput.forceActiveFocus(); } }
        }
    }

    // ---------- выбор города и источника ----------
    Column {
        id: cityCol
        visible: w.editing
        width: parent.width
        spacing: 8
        Row {
            width: parent.width
            Text { text: Tr.t("󰍎  Город и источник"); color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold; width: parent.width - 20 }
            Text { text: "✕"; color: Theme.sub; font.pixelSize: 12; MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: w.editing = false } }
        }
        Rectangle {
            width: parent.width; height: 34; radius: Theme.r(12)
            color: Theme.fill(0.08); border.width: 1; border.color: cityInput.activeFocus ? Theme.accent : Theme.line(0.2)
            TextInput {
                id: cityInput
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; clip: true
                onAccepted: if (text.trim() !== "") w.pick(text.trim())
                Keys.onEscapePressed: w.editing = false
                Text { visible: cityInput.text === ""; anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Любой город, Enter — выбрать"); color: Theme.sub; font: cityInput.font }
            }
        }
        Flow {
            width: parent.width
            spacing: 6
            Repeater {
                model: [""].concat(w.cities.filter(function (c) { return cityInput.text === "" || c.toLowerCase().indexOf(cityInput.text.toLowerCase()) === 0; }))
                Chip {
                    required property string modelData
                    text: modelData === "" ? Tr.t("󰩟 По IP") : modelData
                    on: (w.o.city || "") === modelData
                    onClicked: w.pick(modelData)
                }
            }
        }
        Text { text: Tr.t("Источник"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
        Row {
            spacing: 6
            Repeater {
                model: w.providers
                Chip {
                    required property var modelData
                    text: modelData.t
                    on: w.provider === modelData.v
                    onClicked: Config.set("weather.provider", modelData.v)
                }
            }
        }
    }

    // ---------- погода ----------
    Item {
        visible: w.wx !== null && !w.editing
        anchors.fill: parent
        // обновление не удалось: данные прежние, значок рядом с местом
        Text { visible: w.errKind !== ""; anchors { right: parent.right; top: parent.top } text: "󰖪"; color: Theme.yellow; font.family: Theme.iconFont; font.pixelSize: 13
               MouseArea { anchors { fill: parent; margins: -6 } cursorShape: Qt.PointingHandCursor; onClicked: w.reload() } }
        Text { id: ico; text: w.wx ? w.icon(w.wx.icon) : ""; color: Theme.yellow; font.family: Theme.iconFont; font.pixelSize: 44 }
        Column {
            anchors { left: ico.right; leftMargin: 12; right: parent.right; top: parent.top }
            Row {
                spacing: 8
                Text { id: tnow; text: w.wx ? w.t(w.wx.temp) : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 32; font.weight: Font.Bold }
                Text { anchors.baseline: tnow.baseline; text: w.wx ? w.wx.desc : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: w.wx ? "󰍎 " + (w.o.city || w.wx.place) + Tr.t("  ·  ощущается ") + w.t(w.wx.feels) : ""
                color: placeMa.containsMouse ? Theme.accent : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 11
                // клик по месту — выбрать город и источник
                MouseArea { id: placeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { w.editing = true; cityInput.text = ""; cityInput.forceActiveFocus(); } }
            }
            Text {
                text: w.wx ? "󰖝 " + w.wx.wind + Tr.t(" км/ч   󰖎 ") + w.wx.humidity + "%" : ""
                color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 11
            }
        }
        Row {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            Repeater {
                model: w.days
                Column {
                    required property var modelData
                    required property int index
                    width: parent.width / Math.max(1, w.days.length)
                    spacing: 2
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: index === 0 ? Tr.t("Сегодня") : new Date(modelData.date).toLocaleString(Qt.locale("ru_RU"), "ddd")
                        color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.capitalization: Font.Capitalize
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: w.icon(modelData.icon) + "  " + w.t(modelData.max) + " / " + w.t(modelData.min)
                        color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 12
                    }
                }
            }
        }
    }

    component Chip: Rectangle {
        id: ch
        property alias text: ctx.text
        property bool on: false
        signal clicked
        width: ctx.implicitWidth + 18; height: 26; radius: 13
        color: on ? Theme.accent : (cma.containsMouse ? Theme.fill(0.16) : Theme.fill(0.08))
        Text { id: ctx; anchors.centerIn: parent; color: ch.on ? "white" : Theme.text; font.family: Theme.iconFont; font.pixelSize: 11 }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
    }
}
