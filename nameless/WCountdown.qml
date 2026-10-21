import QtQuick

// Отсчёт: сколько дней осталось до даты (Config.store.countdown: подпись и дата ГГГГ-ММ-ДД); прошедшая — «прошло»
WCard {
    id: w
    readonly property var o: Config.store.countdown
    property date today: new Date()
    Timer { interval: 3600000; repeat: true; running: w.visible; onTriggered: w.today = new Date() }
    readonly property date target: {
        var p = (o.date || "").split("-").map(Number);
        return p.length === 3 && !isNaN(p[0]) ? new Date(p[0], p[1] - 1, p[2]) : new Date();
    }
    readonly property int days: Math.round((new Date(target.getFullYear(), target.getMonth(), target.getDate()) - new Date(today.getFullYear(), today.getMonth(), today.getDate())) / 86400000)
    function plural(n) { n = Math.abs(n); return n % 10 === 1 && n % 100 !== 11 ? Tr.t("день") : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20) ? Tr.t("дня") : Tr.t("дней")); }
    implicitHeight: 104

    Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text { text: "󰔟  " + (w.o.title || Tr.t("Событие")); color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold }
        Row {
            spacing: 8
            Text { text: w.days === 0 ? Tr.t("Сегодня!") : Math.abs(w.days); color: w.days === 0 ? Theme.accent : Theme.text; font.family: Theme.font; font.pixelSize: 40; font.weight: Font.Bold; font.features: { "tnum": 1 } }
            Text { visible: w.days !== 0; anchors.baseline: parent.children[0].baseline; text: w.plural(w.days) + (w.days < 0 ? Tr.t(" прошло") : Tr.t(" осталось")); color: Theme.sub; font.family: Theme.font; font.pixelSize: 14 }
        }
        Text { text: w.target.toLocaleString(Qt.locale("ru_RU"), "d MMMM yyyy, dddd"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
    }
}
