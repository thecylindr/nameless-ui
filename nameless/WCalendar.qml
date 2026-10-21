import QtQuick

// Календарь: месяц с понедельника, сегодня — акцентом, выходные — красным; колесо и стрелки листают месяцы,
// «сегодня» возвращает; по желанию — номера недель (Config.store.calendar.weeks)
WCard {
    id: cal
    property int shift: 0
    readonly property bool weeks: Config.store.calendar.weeks === true
    readonly property date today: new Date()
    readonly property date first: new Date(today.getFullYear(), today.getMonth() + shift, 1)
    readonly property int lead: (first.getDay() + 6) % 7
    readonly property int days: new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate()
    readonly property int cols: weeks ? 8 : 7
    readonly property real cell: width / cols
    readonly property int rowsN: Math.ceil((lead + days) / 7)
    implicitHeight: pad * 2 + 22 + 8 + 18 + rowsN * cell * 0.8

    // номер недели ISO по дате
    function isoWeek(d) {
        var t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        var day = t.getUTCDay() || 7; t.setUTCDate(t.getUTCDate() + 4 - day);
        var y = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - y) / 86400000 + 1) / 7);
    }

    Item {
        id: head
        width: parent.width; height: 22
        Text {
            anchors.verticalCenter: parent.verticalCenter
            // именительный падеж: «Октябрь 2026»
            text: Qt.locale("ru_RU").standaloneMonthName(cal.first.getMonth(), Locale.LongFormat) + " " + cal.first.getFullYear()
            color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold; font.capitalization: Font.Capitalize
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 6
            Repeater {
                model: [{ i: "󰅁", d: -1 }, { i: "󰃭", d: 0 }, { i: "󰅂", d: 1 }]
                Text {
                    required property var modelData
                    text: modelData.i
                    color: modelData.d === 0 && cal.shift === 0 ? Theme.sub : Theme.accent
                    font.family: Theme.iconFont; font.pixelSize: 16
                    MouseArea { anchors.fill: parent; anchors.margins: -5; cursorShape: Qt.PointingHandCursor; onClicked: cal.shift = parent.modelData.d === 0 ? 0 : cal.shift + parent.modelData.d }
                }
            }
        }
    }
    Grid {
        anchors { top: head.bottom; topMargin: 8 }
        columns: cal.cols
        Repeater {
            model: (cal.weeks ? ["№"] : []).concat([Tr.t("Пн"), Tr.t("Вт"), Tr.t("Ср"), Tr.t("Чт"), Tr.t("Пт"), Tr.t("Сб"), Tr.t("Вс")])
            Text {
                required property string modelData
                required property int index
                width: cal.cell; height: 18
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: modelData === "Сб" || modelData === "Вс" ? Theme.red : Theme.sub
                font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold
            }
        }
        Repeater {
            model: cal.rowsN * cal.cols
            Item {
                required property int index
                readonly property int col: index % cal.cols
                readonly property bool weekCol: cal.weeks && col === 0
                readonly property int dayIdx: Math.floor(index / cal.cols) * 7 + (col - (cal.weeks ? 1 : 0))
                readonly property int day: dayIdx - cal.lead + 1
                readonly property bool inMonth: !weekCol && day > 0 && day <= cal.days
                readonly property bool isToday: inMonth && cal.shift === 0 && day === cal.today.getDate()
                readonly property bool weekend: !weekCol && (col - (cal.weeks ? 1 : 0)) >= 5
                width: cal.cell; height: cal.cell * 0.8
                Rectangle {
                    visible: parent.isToday
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) - 2; height: width; radius: width / 2
                    color: Theme.accent
                }
                Text {
                    anchors.centerIn: parent
                    visible: parent.inMonth || parent.weekCol
                    text: parent.weekCol ? cal.isoWeek(new Date(cal.first.getFullYear(), cal.first.getMonth(), Math.max(1, Math.min(cal.days, parent.day + 7 - 1)))) : parent.day
                    color: parent.isToday ? "white" : (parent.weekCol ? Theme.sub : (parent.weekend ? Theme.red : Theme.text))
                    opacity: parent.weekCol ? 0.7 : 1
                    font.family: Theme.font; font.pixelSize: parent.weekCol ? 10 : 12
                    font.weight: parent.isToday ? Font.Bold : Font.Normal
                    font.features: { "tnum": 1 }
                }
            }
        }
    }
    WheelHandler { onWheel: (e) => cal.shift += e.angleDelta.y > 0 ? -1 : 1 }
}
