import QtQuick

// Луна: настоящая фаза на сегодня — освещённая часть с линией терминатора и мягкими кратерами, название фазы,
// освещённость и сколько дней до полнолуния. Возраст Луны — от новолуния 6 января 2000 (18:14 UTC), синодический месяц 29,53 сут.
// Перерисовывается раз в час
WCard {
    id: w
    readonly property real k: Math.max(0.6, width / 300)
    implicitHeight: 132 * Math.max(0.85, k)
    readonly property real period: 29.530588853
    property real age: 0
    function update() {
        var d = (Date.now() - Date.UTC(2000, 0, 6, 18, 14)) / 86400000;
        age = ((d % period) + period) % period;
        disk.requestPaint();
    }
    readonly property real phase: age / period                          // 0 — новолуние, 0,5 — полнолуние
    readonly property int lit: Math.round((1 - Math.cos(2 * Math.PI * phase)) / 2 * 100)
    readonly property string name: {
        var p = phase;
        if (p < 0.03 || p > 0.97) return Tr.t("Новолуние");
        if (p < 0.22) return Tr.t("Растущий серп");
        if (p < 0.28) return Tr.t("Первая четверть");
        if (p < 0.47) return Tr.t("Растущая Луна");
        if (p < 0.53) return Tr.t("Полнолуние");
        if (p < 0.72) return Tr.t("Убывающая Луна");
        if (p < 0.78) return Tr.t("Последняя четверть");
        return Tr.t("Убывающий серп");
    }
    readonly property int toFull: Math.round(((0.5 - phase + 1) % 1) * period)
    Component.onCompleted: update()
    Timer { interval: 3600000; repeat: true; running: w.visible; onTriggered: w.update() }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16 * w.k
        Canvas {
            id: disk
            width: 96 * Math.max(0.85, w.k); height: width
            onPaint: {
                var ctx = getContext("2d"), r = width / 2 - 2, cx = width / 2, cy = height / 2, k = Math.cos(2 * Math.PI * w.phase), waxing = w.phase < 0.5;
                ctx.reset();
                // тёмная часть — пепельный свет
                ctx.fillStyle = Qt.rgba(0.55, 0.6, 0.72, 0.18);
                ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.fill();
                // освещённая часть — построчно: от терминатора до края диска
                ctx.fillStyle = "#f4ecd6";
                for (var y = -r; y <= r; y += 1) {
                    var s = Math.sqrt(Math.max(0, r * r - y * y)), a, b;
                    if (waxing) { a = k * s; b = s; } else { a = -s; b = -k * s; }
                    if (b > a) ctx.fillRect(cx + a, cy + y, b - a, 1.2);
                }
                // моря и кратеры — лёгкие пятна поверх (видны только на светлом)
                ctx.save();
                ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.clip();
                ctx.globalCompositeOperation = "source-atop";
                var spots = [[-0.3, -0.25, 0.22], [0.2, -0.1, 0.16], [0.05, 0.3, 0.2], [-0.35, 0.25, 0.1], [0.38, 0.32, 0.08]];
                for (var i = 0; i < spots.length; i++) {
                    ctx.fillStyle = Qt.rgba(0.55, 0.52, 0.45, 0.28);
                    ctx.beginPath(); ctx.arc(cx + spots[i][0] * r, cy + spots[i][1] * r, spots[i][2] * r, 0, Math.PI * 2); ctx.fill();
                }
                ctx.restore();
            }
        }
        // подписи — в оставшуюся ширину, с переносом: в размере S «До полнолуния» вылезало за карточку
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: w.cw - disk.width - 16 * w.k
            spacing: 4
            Text { width: parent.width; elide: Text.ElideRight; text: w.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 18 * Math.max(0.85, w.k); font.weight: Font.Bold }
            Text { width: parent.width; elide: Text.ElideRight; text: Tr.t("Освещено ") + w.lit + " %"; color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
            Text {
                width: parent.width; wrapMode: Text.WordWrap
                text: w.toFull === 0 ? Tr.t("Сегодня полнолуние") : Tr.t("До полнолуния: ") + w.toFull + Tr.t(" дн.")
                color: Theme.accent; font.family: Theme.font; font.pixelSize: 12
            }
        }
    }
}
