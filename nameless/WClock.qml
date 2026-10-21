import QtQuick

// Часы: digital — цифры, analog — стрелки, words — словами («Без четверти четыре»), stack — часы над минутами.
// Параметры — Config.store.clock: 12/24 ч, секунды, дата (длинная / короткая / нет), второй пояс (подпись и смещение от UTC)
WCard {
    id: w
    readonly property var o: Config.store.clock
    readonly property real k: width / 300            // масштаб по размеру виджета
    property date now: new Date()
    readonly property bool sec: o.seconds === true
    readonly property string hfmt: o.h24 === false ? "h" : "HH"

    implicitHeight: o.style === "analog" ? 150 * k + 32 : (o.style === "stack" ? 230 * k : (o.style === "words" ? 128 * k : 118 * k)) + (o.zone ? 22 : 0)

    // без секунд — обновление на границе минуты
    Timer {
        interval: w.sec || w.o.style === "analog" ? 1000 : (60 - w.now.getSeconds()) * 1000
        repeat: true; running: w.visible
        onTriggered: w.now = new Date()
    }

    function dateText(d) {
        if (o.date === "none") return "";
        return d.toLocaleString(Qt.locale("ru_RU"), o.date === "short" ? "ddd, d MMM" : "dddd, d MMMM");
    }
    function ampm(d) { return o.h24 === false ? (d.getHours() < 12 ? " AM" : " PM") : ""; }

    // время словами, по 5 минут
    function words(d) {
        var H = [Tr.t("двенадцать"), Tr.t("час"), Tr.t("два"), Tr.t("три"), Tr.t("четыре"), Tr.t("пять"), Tr.t("шесть"), Tr.t("семь"), Tr.t("восемь"), Tr.t("девять"), Tr.t("десять"), Tr.t("одиннадцать")];
        var G = [Tr.t("двенадцатого"), Tr.t("первого"), Tr.t("второго"), Tr.t("третьего"), Tr.t("четвёртого"), Tr.t("пятого"), Tr.t("шестого"), Tr.t("седьмого"), Tr.t("восьмого"), Tr.t("девятого"), Tr.t("десятого"), Tr.t("одиннадцатого")];
        var m = Math.round(d.getMinutes() / 5) * 5, h = d.getHours() % 12;
        if (m === 60) { m = 0; h = (h + 1) % 12; }
        var nx = (h + 1) % 12, t;
        if (m === 0) t = Tr.t("Ровно ") + H[h];
        else if (m === 15) t = Tr.t("Четверть ") + G[nx];
        else if (m === 30) t = Tr.t("Половина ") + G[nx];
        else if (m === 45) t = Tr.t("Без четверти ") + H[nx];
        else if (m < 30) t = ({ 5: Tr.t("Пять"), 10: Tr.t("Десять"), 20: Tr.t("Двадцать"), 25: Tr.t("Двадцать пять") })[m] + Tr.t(" минут ") + G[nx];
        else t = Tr.t("Без ") + ({ 35: Tr.t("двадцати пяти"), 40: Tr.t("двадцати"), 50: Tr.t("десяти"), 55: Tr.t("пяти") })[m] + " " + H[nx];
        return t;
    }
    // второй пояс: время по смещению от UTC
    readonly property date zoned: new Date(now.getTime() + now.getTimezoneOffset() * 60000 + (o.offset || 0) * 3600000)

    // ---------- цифры ----------
    Column {
        visible: w.o.style === "digital" || !w.o.style
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: w.o.zone ? -10 : 0
        Row {
            spacing: 4
            Text {
                id: hhmm
                text: w.now.toLocaleString(Qt.locale("ru_RU"), w.hfmt + ":mm")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 58 * w.k
                font.weight: Theme.ios ? Font.DemiBold : Font.Bold
                font.letterSpacing: Theme.ios ? -2 : 0
                font.features: { "tnum": 1 }
            }
            Text {
                visible: w.sec || w.o.h24 === false
                anchors.baseline: hhmm.baseline
                text: (w.sec ? w.now.toLocaleString(Qt.locale("ru_RU"), "ss") : "") + w.ampm(w.now)
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: 22 * w.k
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
        }
        Text {
            visible: text !== ""
            text: w.dateText(w.now)
            color: Theme.sub
            font.family: Theme.font
            font.pixelSize: 14 * Math.max(0.85, w.k)
            font.capitalization: Font.Capitalize
        }
    }

    // ---------- столбиком: часы над минутами, часы акцентом ----------
    Column {
        visible: w.o.style === "stack"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: w.o.zone ? -10 : 0
        spacing: -26 * w.k
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: w.now.toLocaleString(Qt.locale("ru_RU"), w.hfmt)
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 96 * w.k; font.weight: Font.Black; font.features: { "tnum": 1 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: w.now.toLocaleString(Qt.locale("ru_RU"), "mm")
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 96 * w.k; font.weight: Font.Black; font.features: { "tnum": 1 }
        }
        Text {
            visible: text !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 30 * w.k
            text: w.dateText(w.now)
            color: Theme.sub; font.family: Theme.font; font.pixelSize: 13; font.capitalization: Font.Capitalize
        }
    }

    // ---------- словами ----------
    Column {
        visible: w.o.style === "words"
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: w.o.zone ? -10 : 0
        width: parent.width
        spacing: 4
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: w.words(w.now)
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 26 * w.k; font.weight: Font.Bold
            lineHeight: 0.95
        }
        Text {
            text: w.now.toLocaleString(Qt.locale("ru_RU"), "HH:mm") + (w.dateText(w.now) ? " · " + w.dateText(w.now) : "")
            color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.capitalization: Font.Capitalize
        }
    }

    // ---------- стрелки ----------
    Row {
        visible: w.o.style === "analog"
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: w.o.zone ? -10 : 0
        spacing: 18
        Item {
            id: face
            width: 140 * w.k; height: width
            readonly property real h: w.now.getHours() % 12 + w.now.getMinutes() / 60
            readonly property real m: w.now.getMinutes() + w.now.getSeconds() / 60
            Rectangle { anchors.fill: parent; radius: width / 2; color: Theme.fill(0.08); border.width: 1; border.color: Theme.line(0.25) }
            // деления: часовые длинные
            Repeater {
                model: 60
                Item {
                    required property int index
                    anchors.fill: parent
                    rotation: index * 6
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 5
                        width: index % 5 === 0 ? 2.5 : 1
                        height: index % 5 === 0 ? face.width * 0.08 : face.width * 0.035
                        radius: width / 2
                        color: index % 15 === 0 ? Theme.text : Theme.sub
                        opacity: index % 5 === 0 ? 0.9 : 0.4
                    }
                }
            }
            component Hand: Item {
                property real angle
                property real len
                property real thick
                property color tone: Theme.text
                anchors.fill: parent
                rotation: angle
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 - parent.len
                    width: parent.thick; height: parent.len + parent.thick * 2
                    radius: width / 2
                    color: parent.tone
                    antialiasing: true
                }
            }
            Hand { angle: face.h * 30; len: face.width * 0.27; thick: 4.5 }
            Hand { angle: face.m * 6; len: face.width * 0.38; thick: 3 }
            Hand { visible: w.sec; angle: w.now.getSeconds() * 6; len: face.width * 0.42; thick: 1.4; tone: Theme.accent }
            Rectangle { anchors.centerIn: parent; width: 9; height: 9; radius: 4.5; color: Theme.accent }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text { text: w.now.toLocaleString(Qt.locale("ru_RU"), w.hfmt + ":mm") + w.ampm(w.now); color: Theme.text; font.family: Theme.font; font.pixelSize: 24 * w.k; font.weight: Font.Bold; font.features: { "tnum": 1 } }
            Text { width: 110 * w.k; wrapMode: Text.WordWrap; text: w.dateText(w.now); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.capitalization: Font.Capitalize }
        }
    }

    // ---------- второй пояс ----------
    Text {
        visible: !!w.o.zone
        anchors { left: parent.left; bottom: parent.bottom }
        text: "󰥔  " + (w.o.zone || "") + "  " + w.zoned.toLocaleString(Qt.locale("ru_RU"), w.hfmt + ":mm") + w.ampm(w.zoned)
              + "  ·  UTC" + ((w.o.offset || 0) >= 0 ? "+" : "") + (w.o.offset || 0)
        color: Theme.sub
        font.family: Theme.iconFont
        font.pixelSize: 12
    }
}
