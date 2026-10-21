import QtQuick

// График за последнюю минуту: одна или несколько линий с подкраской, сетка. Новые значения — справа.
//   series: [{ values: [...], color }]     maxValue: 0 — шкала подстраивается под значения (скорости), иначе фиксированная (проценты)
//   перерисовка — только при смене данных и пока график виден: на закрытом окне он ничего не рисует
Canvas {
    id: g
    property var series: []
    property real maxValue: 100
    property int points: 60
    property bool grid: true
    property bool fill: true
    property real lineWidth: 2
    // подпись шкалы в углу (например «100%» или «1,2 МБ/с»): считается снаружи
    property string scaleText: ""
    readonly property real scaleMax: {
        if (maxValue > 0) return maxValue;
        var m = 0;
        for (var i = 0; i < series.length; i++) {
            var v = series[i].values || [];
            for (var j = 0; j < v.length; j++) if (v[j] > m) m = v[j];
        }
        // «круглая» верхняя граница, чтобы шкала не дёргалась от каждого значения
        if (m <= 0) return 1;
        var p = Math.pow(2, Math.ceil(Math.log(m) / Math.LN2));
        return p;
    }
    // цвет линии: строка «#rrggbb» или значение color
    function rgb(c) {
        if (typeof c === "string") {
            var n = parseInt(c.charAt(0) === "#" ? c.substring(1, 7) : c.substring(0, 6), 16);
            return { r: ((n >> 16) & 255) / 255, g: ((n >> 8) & 255) / 255, b: (n & 255) / 255 };
        }
        return { r: c.r, g: c.g, b: c.b };
    }
    renderStrategy: Canvas.Cooperative
    onSeriesChanged: if (visible) requestPaint()
    onScaleMaxChanged: if (visible) requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onWidthChanged: if (visible) requestPaint()
    onHeightChanged: if (visible) requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var W = width, H = height;
        if (W < 4 || H < 4) return;
        if (grid) {
            ctx.lineWidth = 1;
            ctx.strokeStyle = Theme.line(0.10);
            ctx.beginPath();
            for (var r = 1; r < 4; r++) { var y = Math.round(H * r / 4) + 0.5; ctx.moveTo(0, y); ctx.lineTo(W, y); }
            for (var c = 1; c < 6; c++) { var x = Math.round(W * c / 6) + 0.5; ctx.moveTo(x, 0); ctx.lineTo(x, H); }
            ctx.stroke();
        }
        var step = W / (points - 1);
        for (var s = 0; s < series.length; s++) {
            var vals = series[s].values || [], col = rgb(series[s].color), n = vals.length;
            if (n < 2) continue;
            var x0 = W - (n - 1) * step;       // график растёт справа налево, пока истории меньше минуты
            ctx.beginPath();
            for (var i = 0; i < n; i++) {
                var vx = x0 + i * step, vy = H - Math.min(1, Math.max(0, vals[i] / scaleMax)) * (H - 2) - 1;
                if (i === 0) ctx.moveTo(vx, vy); else ctx.lineTo(vx, vy);
            }
            if (fill) {
                ctx.save();
                ctx.lineTo(W, H); ctx.lineTo(x0, H); ctx.closePath();
                ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, 0.22);
                ctx.fill();
                ctx.restore();
                ctx.beginPath();
                for (var k = 0; k < n; k++) {
                    var ux = x0 + k * step, uy = H - Math.min(1, Math.max(0, vals[k] / scaleMax)) * (H - 2) - 1;
                    if (k === 0) ctx.moveTo(ux, uy); else ctx.lineTo(ux, uy);
                }
            }
            ctx.lineWidth = lineWidth;
            ctx.lineJoin = "round";
            ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 1);
            ctx.stroke();
        }
    }
}
