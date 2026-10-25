import QtQuick

// Ёлочка: пиксельная новогодняя ель со звездой, игрушками и гирляндой, под ней подарки, вокруг падает снег.
// Ель рисуется один раз (Canvas, перерисовка — только при смене размера или цветов), огоньки — отдельные квадратики:
// один общий шаг 2–3 раза в секунду (в экономном режиме реже), стол закрыт окнами — всё стоит.
// Настройки — Config.store.tree:
//   garland — вид гирлянды: chase (бегущие огни) | twinkle (мерцание) | wave (волна снизу вверх)
//   colors  — multi (разноцветная) | warm (тёплая) | accent (цвета темы)
//   snow    — падающий снег; gifts — подарки под ёлкой; speed — скорость гирлянды 1–10
// Подпись — сколько дней до Нового года (в праздники — поздравление)
WCard {
    id: w
    readonly property var o: Config.store.tree || ({})
    readonly property string mode: o.garland || "chase"
    readonly property bool snow: o.snow !== false
    readonly property bool gifts: o.gifts !== false
    readonly property int speed: Math.max(1, Math.min(10, o.speed || 5))
    readonly property var palette: o.colors === "warm" ? ["#ffd27a", "#ffb347", "#fff1c1", "#ff9e4a"]
                                 : (o.colors === "accent" ? [Theme.accent, Theme.accent2, Qt.lighter(Theme.accent, 1.4), Qt.lighter(Theme.accent2, 1.4)]
                                 : ["#ff4d5e", "#ffd23f", "#3fa7ff", "#5ee27a", "#ff7ad9"])

    // сетка ели: COLS × ROWS пикселей, размер пикселя — по ширине карточки
    readonly property int cols: 21
    readonly property int rows: 25
    readonly property real px: Math.max(3, Math.floor(Math.min(cw * 0.7 / cols, 9)))
    readonly property real treeW: cols * px
    readonly property real treeH: rows * px
    implicitHeight: pad * 2 + treeH + 26

    property int tick: 0
    Timer {
        interval: Math.round((Perf.eco ? 1400 : 900) / (0.5 + w.speed / 5))
        repeat: true
        running: w.visible && !Compositor.covered
        onTriggered: w.tick++
    }

    // ---------- форма ели ----------
    // ярусы: верхняя строка, высота, ширина первой строки; каждая следующая строка шире на 2 пикселя
    readonly property var tiers: [{ y: 3, h: 5, w0: 3 }, { y: 7, h: 6, w0: 5 }, { y: 12, h: 7, w0: 7 }]
    // клетка ели (в пределах яруса) — для огоньков и игрушек
    function inTree(x, y) {
        for (var t = 0; t < tiers.length; t++) {
            var tr = tiers[t], r = y - tr.y;
            if (r < 0 || r >= tr.h) continue;
            var half = Math.floor((tr.w0 + r * 2) / 2);
            if (Math.abs(x - Math.floor(cols / 2)) <= half) return true;
        }
        return false;
    }
    // огоньки: гирлянда идёт по ярусам наискосок, через пиксель
    readonly property var lights: {
        var out = [], mid = Math.floor(cols / 2);
        for (var t = 0; t < tiers.length; t++) {
            var tr = tiers[t];
            for (var r = 1; r < tr.h; r += 2) {
                var half = Math.floor((tr.w0 + r * 2) / 2), y = tr.y + r;
                // косая нить: смещение от строки, огонёк через два пикселя
                for (var x = mid - half + 1 + (r % 4 === 1 ? 0 : 1); x <= mid + half - 1; x += 3) out.push({ x: x, y: y, row: y });
            }
        }
        return out;
    }
    // игрушки — неподвижные шары
    readonly property var balls: [{ x: 9, y: 6, c: "#ff4d5e" }, { x: 12, y: 10, c: "#3fa7ff" }, { x: 7, y: 11, c: "#ffd23f" },
                                  { x: 13, y: 15, c: "#ff7ad9" }, { x: 6, y: 16, c: "#5ee27a" }, { x: 10, y: 17, c: "#ff4d5e" }]

    // горит ли огонёк i на шаге tick и каким цветом
    function lit(i, l) {
        if (mode === "twinkle") return ((i * 7 + tick * 3) % 5) !== 0 && ((i * 13 + tick) % 3) !== 0;
        if (mode === "wave") return ((rows - l.row) + tick * 2) % 8 < 5;
        return (i + tick) % 3 !== 0;
    }
    function colorOf(i) { return palette[(i + (mode === "chase" ? tick : 0)) % palette.length]; }

    Item {
        id: scene
        width: parent.width; height: w.treeH
        clip: true

        // снег: пиксели падают с лёгким покачиванием
        Repeater {
            model: w.snow ? 16 : 0
            Rectangle {
                required property int index
                readonly property real fall: ((w.tick * (1 + index % 3) + index * 37) % 100) / 100
                width: Math.max(2, w.px * 0.5); height: width
                x: ((index * 53) % 100) / 100 * (scene.width - width) + Math.sin((w.tick + index) * 0.9) * w.px * 0.5
                y: fall * (scene.height - height)
                color: "white"
                opacity: 0.35 + (index % 3) * 0.2
            }
        }

        Canvas {
            id: tree
            width: w.treeW; height: w.treeH
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property real p: w.px
            readonly property bool gifts: w.gifts
            onPChanged: requestPaint()
            onGiftsChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d"), P = p, mid = Math.floor(w.cols / 2);
                ctx.reset();
                function px(x, y, c) { ctx.fillStyle = c; ctx.fillRect(x * P, y * P, P, P); }
                // звезда
                px(mid, 0, "#ffe066"); px(mid - 1, 1, "#ffe066"); px(mid, 1, "#fff3a8"); px(mid + 1, 1, "#ffe066"); px(mid, 2, "#ffd23f");
                // ярусы: тёмный край слева и снизу — объём
                for (var t = 0; t < w.tiers.length; t++) {
                    var tr = w.tiers[t];
                    for (var r = 0; r < tr.h; r++) {
                        var half = Math.floor((tr.w0 + r * 2) / 2), y = tr.y + r;
                        for (var x = mid - half; x <= mid + half; x++) {
                            var edge = x === mid - half || r === tr.h - 1;
                            var light = x > mid && x < mid + half - 1 && r < tr.h - 2;
                            px(x, y, edge ? "#1f6b3a" : (light ? "#3aa15a" : "#2e8a4b"));
                        }
                        // снег на ветках — по краям яруса
                        if (r === tr.h - 1) { px(mid - half, y, "#e8f4ff"); px(mid + half, y, "#e8f4ff"); }
                    }
                }
                // ствол
                for (var ty = 19; ty < 22; ty++) { px(mid - 1, ty, "#6b3f22"); px(mid, ty, "#8a5530"); px(mid + 1, ty, "#6b3f22"); }
                // игрушки
                for (var b = 0; b < w.balls.length; b++) { px(w.balls[b].x, w.balls[b].y, w.balls[b].c); }
                // подарки
                if (gifts) {
                    function box(x0, y0, wd, ht, c, rib) {
                        for (var yy = 0; yy < ht; yy++) for (var xx = 0; xx < wd; xx++) px(x0 + xx, y0 + yy, (xx === Math.floor(wd / 2) || yy === 1) ? rib : c);
                    }
                    box(mid - 7, 20, 4, 4, "#d6334a", "#ffd23f");
                    box(mid + 3, 21, 5, 3, "#3f7cff", "#ffffff");
                    box(mid - 3, 22, 3, 2, "#5ee27a", "#ff4d5e");
                }
                // земля
                ctx.fillStyle = "rgba(232, 244, 255, 0.55)";
                ctx.fillRect(0, 24 * P, w.cols * P, P);
            }
        }

        // гирлянда: огонёк и мягкий ореол
        Repeater {
            model: w.lights
            Item {
                required property var modelData
                required property int index
                readonly property bool on: w.lit(index, modelData)
                readonly property color c: w.colorOf(index)
                x: tree.x + modelData.x * w.px; y: modelData.y * w.px
                width: w.px; height: w.px
                Rectangle {
                    visible: parent.on && !Perf.eco
                    anchors.centerIn: parent
                    width: w.px * 2.6; height: width; radius: width / 2
                    color: parent.c; opacity: 0.28
                }
                Rectangle {
                    anchors.fill: parent
                    color: parent.on ? parent.c : Qt.darker(parent.c, 2.6)
                }
            }
        }
        // звезда мерцает вместе с гирляндой
        Rectangle {
            x: tree.x + Math.floor(w.cols / 2) * w.px - w.px; y: 0
            width: w.px * 3; height: w.px * 3; radius: width / 2
            color: "#ffe066"
            opacity: w.tick % 2 ? 0.35 : 0.15
        }
    }

    // подпись: дни до Нового года
    Text {
        anchors { left: parent.left; right: parent.right; top: scene.bottom; topMargin: 8 }
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        readonly property date now: new Date()
        readonly property int days: {
            var ny = new Date(now.getFullYear() + 1, 0, 1);
            return Math.ceil((ny - new Date(now.getFullYear(), now.getMonth(), now.getDate())) / 86400000);
        }
        // с 31 декабря по 7 января — поздравление
        readonly property bool holiday: (now.getMonth() === 11 && now.getDate() === 31) || (now.getMonth() === 0 && now.getDate() <= 7)
        text: holiday ? Tr.t("С Новым годом!") : Tr.t("До Нового года: ") + days + " " + Tr.t(days % 10 === 1 && days % 100 !== 11 ? "день" : (days % 10 >= 2 && days % 10 <= 4 && (days % 100 < 10 || days % 100 >= 20) ? "дня" : "дней"))
        color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
    }
}
