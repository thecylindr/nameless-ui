import QtQuick
import Quickshell

// Помодоро: работа и перерыв по очереди (длительности — Config.store.timer), кольцо оставшегося времени,
// уведомление в конце этапа; клик по кольцу — старт / пауза, правый клик — сброс
WCard {
    id: w
    readonly property int workMin: Math.max(1, Config.store.timer.work || 25)
    readonly property int restMin: Math.max(1, Config.store.timer.rest || 5)
    property string phase: "work"          // work | rest
    property bool running: false
    property int remain: workMin * 60
    property int done: 0                   // завершённых рабочих этапов
    readonly property int total: (phase === "work" ? workMin : restMin) * 60
    onWorkMinChanged: if (!running && phase === "work") remain = workMin * 60
    onRestMinChanged: if (!running && phase === "rest") remain = restMin * 60

    implicitHeight: 132

    Timer {
        interval: 1000; repeat: true; running: w.running
        onTriggered: {
            if (w.remain > 1) { w.remain--; return; }
            // этап окончен: уведомление и следующий
            if (w.phase === "work") w.done++;
            Quickshell.execDetached(["notify-send", "-a", Tr.t("Помодоро"), w.phase === "work" ? Tr.t("Перерыв") : Tr.t("За работу"),
                                     w.phase === "work" ? Tr.t("Отдохните ") + w.restMin + Tr.t(" мин") : Tr.t("Следующий этап — ") + w.workMin + Tr.t(" мин")]);
            w.phase = w.phase === "work" ? "rest" : "work";
            w.remain = w.total;
        }
    }
    function reset() { running = false; phase = "work"; remain = workMin * 60; }
    function fmt(s) { var m = Math.floor(s / 60), x = s % 60; return m + ":" + (x < 10 ? "0" : "") + x; }

    Item {
        id: ringBox
        width: 100; height: 100
        anchors.verticalCenter: parent.verticalCenter
        Canvas {
            anchors.fill: parent
            property real v: 1 - w.remain / Math.max(1, w.total)
            property color tone: w.phase === "work" ? Theme.red : Theme.green
            onVChanged: requestPaint()
            onToneChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d"), r = width / 2 - 6;
                ctx.reset(); ctx.lineWidth = 7; ctx.lineCap = "round";
                ctx.strokeStyle = Theme.fill(0.14);
                ctx.beginPath(); ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2); ctx.stroke();
                ctx.strokeStyle = tone;
                ctx.beginPath(); ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * v); ctx.stroke();
            }
        }
        Column {
            anchors.centerIn: parent
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: w.fmt(w.remain); color: Theme.text; font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold; font.features: { "tnum": 1 } }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: w.running ? (w.phase === "work" ? Tr.t("работа") : Tr.t("перерыв")) : Tr.t("пауза"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (m) => { if (m.button === Qt.RightButton) w.reset(); else w.running = !w.running; }
        }
    }
    Column {
        anchors { left: ringBox.right; leftMargin: 16; right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 6
        Text { text: Tr.t("󰔛  Помодоро"); color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold }
        Text { text: w.workMin + " / " + w.restMin + Tr.t(" мин"); color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
        // завершённые этапы — помидорки
        Row {
            spacing: 4
            Repeater { model: Math.min(8, w.done); Text { text: "󰄯"; color: Theme.red; font.family: Theme.iconFont; font.pixelSize: 12 } }
            Text { visible: w.done === 0; text: Tr.t("этапов пока нет"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
        }
        Row {
            spacing: 6
            GButton { ui: Theme; height: 30; implicitWidth: 74; label: w.running ? Tr.t("Пауза") : Tr.t("Старт"); on: !w.running; onClicked: w.running = !w.running }
            GButton { ui: Theme; height: 30; implicitWidth: 64; label: Tr.t("Сброс"); onClicked: w.reset() }
        }
    }
}
