import QtQuick

// Кольцевой индикатор: дуга по доле (0–100), в центре — крупный текст и подпись. Перерисовывается только при смене значения
Item {
    id: g
    property real value: 0
    property color tone: Theme.accent
    property string text: ""
    property string caption: ""
    property real thickness: 7
    implicitWidth: 84; implicitHeight: 84

    Canvas {
        id: cv
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        property real v: Math.max(0, Math.min(100, g.value)) / 100
        property color col: g.tone
        onVChanged: requestPaint()
        onColChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d"), r = Math.min(width, height) / 2 - g.thickness / 2 - 1;
            ctx.reset();
            ctx.lineWidth = g.thickness; ctx.lineCap = "round";
            ctx.strokeStyle = Theme.fill(0.14);
            ctx.beginPath(); ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2); ctx.stroke();
            if (v > 0.003) {
                ctx.strokeStyle = col;
                ctx.beginPath(); ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * v); ctx.stroke();
            }
        }
    }
    Column {
        anchors.centerIn: parent
        spacing: 0
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: g.text; color: Theme.text; font.family: Theme.font; font.pixelSize: Math.round(g.width * 0.24); font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
        Text { anchors.horizontalCenter: parent.horizontalCenter; visible: g.caption !== ""; text: g.caption; color: Theme.sub; font.family: Theme.font; font.pixelSize: Math.round(g.width * 0.12) }
    }
}
