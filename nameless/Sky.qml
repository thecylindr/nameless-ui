import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

// Фон вместо обоев. Два разных режима:
//   stars — звёздное небо с Земли (Config.store.sky): горизонт, сумерки, Луна, метеоры, созвездия — всё ниже;
//   solar — глубокий космос под солнечной системой (Config.store.space): ровное поле звёзд без горизонта и атмосферы,
//           далёкие галактики, туманности; без Луны, сумерек и метеоров — в космосе их нет
// Звёздное небо с Земли:
//   • фон, туманности, Млечный Путь, сотни неподвижных звёзд и созвездия — одна картинка (Canvas), рисуется один раз
//     и при смене параметров; палитра неба — цвета темы, глубокий синий, фиолетовая, бирюзовая или закатная
//   • мерцающие звёзды со свечением и лучами — аниматоры в потоке отрисовки
//   • падающие звёзды с хвостом цвета акцента — через случайные промежутки, частота настраивается
//   • Луна в настоящей фазе: моря, кратеры, пепельный свет тёмной части; сумерки и рассвет по времени суток
// Экономия: мерцание и метеоры стоят, пока рабочий стол закрыт окнами, и при батарее ниже 25 %
Variants {
    // на виртуальном мониторе (второй экран) живое небо не рисуется: 60 кадров в секунду там тратили видеокарту впустую и мешали кодеру показа
    model: Quickshell.screens.filter(function (s) { return String(s.name).indexOf("HEADLESS") !== 0; })

    PanelWindow {
        id: sky
        required property var modelData
        screen: modelData
        visible: Theme.cosmos !== "off"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: top
        // не «nameless-…»: правило размытия ^nameless стеклянных тем считало бы размытие под непрозрачным небом
        WlrLayershell.namespace: "glassrice-sky"
        WlrLayershell.layer: WlrLayer.Background
        mask: Region {}

        readonly property var o: Config.store.sky
        readonly property var so: Config.store.space
        readonly property bool space: Theme.cosmos === "solar" || Theme.cosmos === "apps"
        // псевдослучайное, но постоянное для каждой звезды: небо не прыгает при перерисовке
        function rnd(i, k) { var x = Math.sin(i * 12.9898 + k * 78.233) * 43758.5453; return x - Math.floor(x); }

        // ---------- когда анимировать ----------
        readonly property bool covered: Compositor.covered
        readonly property bool lowBattery: Sys.hasBattery && !Sys.charging && Sys.batPct < 25
        readonly property bool live: visible && !covered && !lowBattery
        // мерцание: один общий шаг 15 раз в секунду вместо десятков бесконечных анимаций —
        // небо перерисовывается 15 раз в секунду, а не на каждом кадре экрана (165 Гц)
        property real tw: 0
        Timer { interval: 66; repeat: true; running: sky.live && !sky.space && sky.o.twinkle !== false && !Perf.eco; onTriggered: sky.tw += 0.066 }

        // ---------- палитра и время суток ----------
        property int hour: new Date().getHours()
        Timer { interval: 60000; repeat: true; running: sky.visible; onTriggered: sky.hour = new Date().getHours() }
        // сумерки и рассвет: 0 — ночь, 1 — пик (6 и 19:30)
        readonly property real twilight: space || o.daytime === false ? 0
                                       : (hour >= 4 && hour <= 8) ? Math.max(0, 1 - Math.abs(hour - 6) / 2.5)
                                       : ((hour >= 17 && hour <= 22) ? Math.max(0, 1 - Math.abs(hour - 19.5) / 2.5) : 0)
        readonly property bool morning: hour < 12
        readonly property var pal: ({
            theme:  { top: "#03050c", mid: Qt.tint("#0a1030", Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, 0.12)), hor: "#121a3d", n1: Theme.accent2, n2: Theme.accent },
            deep:   { top: "#01030a", mid: "#06143a", hor: "#0d2a5e", n1: "#3d6bff", n2: "#7fb2ff" },
            violet: { top: "#05020c", mid: "#1a0b36", hor: "#3b1660", n1: "#b06cff", n2: "#ff6fb5" },
            teal:   { top: "#010708", mid: "#062a2c", hor: "#0b4a46", n1: "#2fe0c0", n2: "#4aa8ff" },
            ember:  { top: "#06030a", mid: "#2a0f2c", hor: "#5a2224", n1: "#ff8a5c", n2: "#ffcf6b" }
        })[o.palette || "theme"] || null
        readonly property color top: space ? "#010208" : (pal ? pal.top : "#03050c")
        readonly property color mid: space ? "#03061a" : (pal ? pal.mid : "#0a1030")
        readonly property color horizon: Qt.tint(pal ? pal.hor : "#121a3d", morning ? Qt.rgba(1.0, 0.62, 0.38, 0.42 * twilight)
                                                                                   : Qt.rgba(0.95, 0.45, 0.62, 0.42 * twilight))

        // ---------- неподвижная часть: одна картинка ----------
        Canvas {
            id: field
            anchors.fill: parent
            renderTarget: Canvas.Image
            readonly property string key: [sky.space, sky.mid, sky.horizon, sky.pal ? sky.pal.n1 : "", sky.pal ? sky.pal.n2 : "", sky.o.stars, sky.o.nebula,
                                           sky.o.milkyway, sky.o.constellations, sky.so.bgStars, sky.so.bgNebula, sky.so.galaxies].join()
            onKeyChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
            function nebula(ctx, cx, cy, r, c, a) {
                if (a <= 0) return;
                var g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
                g.addColorStop(0.0, rgba(c, a));
                g.addColorStop(0.3, rgba(c, a * 0.68));
                g.addColorStop(0.6, rgba(c, a * 0.28));
                g.addColorStop(0.85, rgba(c, a * 0.07));
                g.addColorStop(1.0, rgba(c, 0));
                ctx.fillStyle = g;
                ctx.fillRect(0, 0, width, height);
            }
            // глубокий космос: ровное поле звёзд, галактики, туманности — без горизонта
            function paintSpace(ctx, w, h) {
                var so = sky.so, k = so.bgStars || 1, nb = so.bgNebula === undefined ? 1 : so.bgNebula, i;
                var bg = ctx.createRadialGradient(w * 0.5, h * 0.5, 0, w * 0.5, h * 0.5, Math.max(w, h) * 0.75);
                bg.addColorStop(0, "#050a22"); bg.addColorStop(1, "#010208");
                ctx.fillStyle = bg; ctx.fillRect(0, 0, w, h);
                nebula(ctx, w * 0.18, h * 0.3, w * 0.3, Theme.accent2, 0.09 * nb);
                nebula(ctx, w * 0.82, h * 0.72, w * 0.26, Theme.accent, 0.07 * nb);
                nebula(ctx, w * 0.62, h * 0.12, w * 0.16, Qt.color("#ff6fb5"), 0.04 * nb);
                // далёкие галактики: спиральные и эллиптические пятнышки
                if (so.galaxies !== false) for (i = 0; i < 14; i++) {
                    var gx = sky.rnd(i, 61) * w, gy = sky.rnd(i, 62) * h, gr = 6 + sky.rnd(i, 63) * 16;
                    ctx.save(); ctx.translate(gx, gy); ctx.rotate(sky.rnd(i, 64) * Math.PI); ctx.scale(1, 0.35 + sky.rnd(i, 65) * 0.4);
                    var gg = ctx.createRadialGradient(0, 0, 0, 0, 0, gr);
                    gg.addColorStop(0, Qt.rgba(1, 0.95, 0.85, 0.5)); gg.addColorStop(0.3, Qt.rgba(0.8, 0.85, 1, 0.16)); gg.addColorStop(1, Qt.rgba(0.6, 0.7, 1, 0));
                    ctx.fillStyle = gg; ctx.beginPath(); ctx.arc(0, 0, gr, 0, Math.PI * 2); ctx.fill();
                    ctx.restore();
                }
                // звёзды: равномерно, цвета по классам (голубые, белые, жёлтые, красные)
                var n = Math.round(w * h / 3200 * k);
                for (i = 0; i < n; i++) {
                    var t = sky.rnd(i, 75), r = 0.3 + Math.pow(sky.rnd(i, 73), 4) * 1.6;
                    ctx.fillStyle = t < 0.15 ? Qt.rgba(0.7, 0.8, 1, 0.9) : (t > 0.9 ? Qt.rgba(1, 0.75, 0.6, 0.85) : (t > 0.75 ? Qt.rgba(1, 0.93, 0.75, 0.85) : Qt.rgba(1, 1, 1, 0.25 + sky.rnd(i, 74) * 0.6)));
                    ctx.beginPath(); ctx.arc(sky.rnd(i, 71) * w, sky.rnd(i, 72) * h, r, 0, Math.PI * 2); ctx.fill();
                }
            }
            onPaint: {
                var ctx = getContext("2d"), w = width, h = height, o = sky.o;
                ctx.reset();
                if (w <= 0 || h <= 0) return;
                if (sky.space) { paintSpace(ctx, w, h); return; }
                // небо
                var bg = ctx.createLinearGradient(0, 0, 0, h);
                bg.addColorStop(0.0, sky.top);
                bg.addColorStop(0.55, sky.mid);
                bg.addColorStop(1.0, sky.horizon);
                ctx.fillStyle = bg;
                ctx.fillRect(0, 0, w, h);
                // туманности
                var nb = o.nebula === undefined ? 1 : o.nebula;
                if (sky.pal) {
                    nebula(ctx, w * 0.24, h * 0.38, w * 0.34, sky.pal.n1, 0.16 * nb);
                    nebula(ctx, w * 0.7, h * 0.62, w * 0.28, sky.pal.n2, 0.11 * nb);
                    nebula(ctx, w * 0.55, h * 0.18, w * 0.18, sky.pal.n1, 0.06 * nb);
                }
                // Млечный Путь: наклонная полоса — мягкое свечение и густые слабые звёзды
                if (o.milkyway !== false) {
                    ctx.save();
                    ctx.translate(w / 2, h / 2);
                    ctx.rotate(-0.42);
                    var band = ctx.createLinearGradient(0, -h * 0.16, 0, h * 0.16);
                    band.addColorStop(0.0, Qt.rgba(0.8, 0.85, 1, 0));
                    band.addColorStop(0.5, Qt.rgba(0.85, 0.88, 1, 0.075));
                    band.addColorStop(1.0, Qt.rgba(0.8, 0.85, 1, 0));
                    ctx.fillStyle = band;
                    ctx.fillRect(-w, -h * 0.16, w * 2, h * 0.32);
                    // тёмные пылевые прожилки по центру полосы
                    for (var d = 0; d < 26; d++) {
                        ctx.fillStyle = Qt.rgba(0, 0, 0, 0.05 + sky.rnd(d, 41) * 0.05);
                        ctx.beginPath();
                        ctx.ellipse(-w * 0.9 + sky.rnd(d, 42) * w * 1.8, -h * 0.02 + (sky.rnd(d, 43) - 0.5) * h * 0.06, w * 0.08, h * 0.015, 0, 0, Math.PI * 2);
                        ctx.fill();
                    }
                    var mn = Math.round(w * h / 1800 * (o.stars || 1));
                    for (var m = 0; m < mn; m++) {
                        var gx = (sky.rnd(m, 31) - 0.5) * w * 2, u = sky.rnd(m, 32) + sky.rnd(m, 33) + sky.rnd(m, 34) - 1.5;
                        ctx.fillStyle = Qt.rgba(0.9, 0.92, 1, 0.12 + sky.rnd(m, 35) * 0.35);
                        ctx.fillRect(gx, u * h * 0.1, 1, 1);
                    }
                    ctx.restore();
                }
                // звёзды
                var n = Math.round(w * h / 6500 * (o.stars || 1)), bright = [];
                for (var i = 0; i < n; i++) {
                    var x = sky.rnd(i, 1) * w;
                    var y = Math.pow(sky.rnd(i, 2), 1.3) * h;          // у горизонта звёзд меньше
                    var r = 0.35 + Math.pow(sky.rnd(i, 3), 3) * 1.4;
                    var a = 0.25 + sky.rnd(i, 4) * 0.6;
                    var t = sky.rnd(i, 5);                               // оттенок: голубоватые, белые, тёплые
                    var cr = t < 0.3 ? 0.78 : (t > 0.85 ? 1.0 : 0.95), cg = t < 0.3 ? 0.86 : (t > 0.85 ? 0.88 : 0.96), cb = t > 0.85 ? 0.78 : 1.0;
                    ctx.fillStyle = Qt.rgba(cr, cg, cb, a);
                    ctx.beginPath();
                    ctx.arc(x, y, r, 0, Math.PI * 2);
                    ctx.fill();
                    if (r > 1.3 && y < h * 0.7) bright.push([x, y]);
                }
                // созвездия: несколько цепочек из ближайших ярких звёзд, едва заметно
                if (o.constellations !== false) {
                    ctx.strokeStyle = Qt.rgba(0.75, 0.82, 1.0, 0.08);
                    ctx.lineWidth = 1;
                    for (var g = 0; g < Math.min(5, bright.length); g++) {
                        var cur = bright[Math.floor(sky.rnd(g, 7) * bright.length)], used = [cur];
                        ctx.beginPath();
                        ctx.moveTo(cur[0], cur[1]);
                        for (var s = 0; s < 4; s++) {
                            var best = null, bd = 1e9;
                            for (var b = 0; b < bright.length; b++) {
                                if (used.indexOf(bright[b]) >= 0) continue;
                                var dd = Math.hypot(bright[b][0] - cur[0], bright[b][1] - cur[1]);
                                if (dd < bd && dd > 30) { bd = dd; best = bright[b]; }
                            }
                            if (!best || bd > w * 0.12) break;
                            ctx.lineTo(best[0], best[1]);
                            used.push(best); cur = best;
                        }
                        ctx.stroke();
                    }
                }
            }
        }

        // ---------- мерцающие звёзды ----------
        Repeater {
            model: sky.space || sky.o.twinkle === false ? 0 : Math.round(sky.width * sky.height / 60000 * (sky.o.stars || 1))
            Item {
                id: st
                required property int index
                readonly property real sz: 1.6 + sky.rnd(index, 13) * 2.2
                readonly property color tone: sky.rnd(index, 17) > 0.75 ? Theme.accent : Qt.rgba(0.9, 0.94, 1, 1)
                x: sky.rnd(index, 11) * sky.width - width / 2
                y: Math.pow(sky.rnd(index, 12), 1.25) * sky.height * 0.88 - height / 2
                width: sz * 8
                height: width
                // плавное мерцание: своя частота и фаза у каждой звезды
                readonly property real speed: 0.6 + sky.rnd(index, 15) * 1.2
                readonly property real phase: sky.rnd(index, 14) * 6.283
                opacity: 0.6 + 0.4 * Math.sin(sky.tw * speed + phase)

                Rectangle { anchors.centerIn: parent; width: st.sz * 5; height: width; radius: width / 2; color: Qt.rgba(st.tone.r, st.tone.g, st.tone.b, 0.10) }
                Rectangle { anchors.centerIn: parent; width: st.sz * 2.2; height: width; radius: width / 2; color: Qt.rgba(st.tone.r, st.tone.g, st.tone.b, 0.25) }
                Rectangle { anchors.centerIn: parent; width: st.sz; height: width; radius: width / 2; color: "white" }
                // лучи у самых ярких
                Rectangle { visible: st.sz > 3.1; anchors.centerIn: parent; width: st.sz * 7; height: 1; color: Qt.rgba(1, 1, 1, 0.35) }
                Rectangle { visible: st.sz > 3.1; anchors.centerIn: parent; width: 1; height: st.sz * 7; color: Qt.rgba(1, 1, 1, 0.35) }

            }
        }

        // ---------- падающие звёзды ----------
        property int nextMeteor: 0
        Repeater {
            id: meteors
            model: 3
            Item {
                id: m
                required property int index
                property real sx: 0
                property real sy: 0
                property real dx: 0
                property real dy: 0
                property int dur: 900
                visible: false
                width: 240
                height: 2
                opacity: 0

                // хвост: прозрачный → акцент → белая голова
                Rectangle {
                    anchors.fill: parent
                    radius: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.7; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) }
                        GradientStop { position: 1.0; color: "white" }
                    }
                }
                Rectangle { anchors { right: parent.right; verticalCenter: parent.verticalCenter } width: 12; height: 12; radius: 6; color: Qt.rgba(1, 1, 1, 0.18) }
                Rectangle { anchors { right: parent.right; rightMargin: 3; verticalCenter: parent.verticalCenter } width: 4; height: 4; radius: 2; color: "white" }

                function launch() {
                    var a = (22 + Math.random() * 18) * Math.PI / 180, dist = sky.width * (0.22 + Math.random() * 0.18);
                    sx = sky.width * (0.25 + Math.random() * 0.7);
                    sy = sky.height * Math.random() * 0.4;
                    dx = -Math.cos(a) * dist;
                    dy = Math.sin(a) * dist;
                    rotation = 180 - a * 180 / Math.PI;      // голова впереди: летит влево-вниз
                    dur = 700 + Math.random() * 700;
                    visible = true;
                    flight.restart();
                }
                ParallelAnimation {
                    id: flight
                    XAnimator { target: m; from: m.sx; to: m.sx + m.dx; duration: m.dur; easing.type: Easing.InQuad }
                    YAnimator { target: m; from: m.sy; to: m.sy + m.dy; duration: m.dur; easing.type: Easing.InQuad }
                    SequentialAnimation {
                        OpacityAnimator { target: m; from: 0; to: 1; duration: m.dur * 0.2 }
                        PauseAnimation { duration: m.dur * 0.45 }
                        OpacityAnimator { target: m; from: 1; to: 0; duration: m.dur * 0.35 }
                    }
                    onFinished: m.visible = false
                }
            }
        }
        Timer {
            interval: 3500
            repeat: true
            running: sky.live && !sky.space && sky.o.meteors !== false && !Perf.eco
            onTriggered: {
                interval = (3000 + Math.random() * 8000) / Math.max(0.3, sky.o.meteorRate || 1);
                var it = meteors.itemAt(sky.nextMeteor % 3);
                sky.nextMeteor++;
                if (it) it.launch();
            }
        }

        // ---------- Луна: фаза на сегодня ----------
        // в солнечной системе Луна летает у Земли — на небе её нет
        Item {
            id: moon
            visible: sky.o.moon !== false && Theme.cosmos !== "solar"
            // от новолуния 6 января 2000 18:14 UTC, синодический месяц 29.530588 суток
            readonly property real phase: {
                var days = (Date.now() - Date.UTC(2000, 0, 6, 18, 14)) / 86400000;
                var p = (days % 29.530588) / 29.530588;
                return p < 0 ? p + 1 : p;
            }
            readonly property real k: phase * 2      // 0 — новолуние, 1 — полнолуние, 2 — снова новолуние
            width: 72; height: 72
            x: sky.width * 0.84 - width / 2
            y: sky.height * 0.14 - height / 2

            Shape {
                anchors.centerIn: parent
                width: 260; height: 260
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: 130; centerY: 130; centerRadius: 130
                        focalX: 130; focalY: 130
                        GradientStop { position: 0.0; color: Qt.rgba(0.85, 0.9, 1, 0.16 * Math.max(0.2, 1 - Math.abs(moon.k - 1))) }
                        GradientStop { position: 0.28; color: Qt.rgba(0.85, 0.9, 1, 0.09 * Math.max(0.2, 1 - Math.abs(moon.k - 1))) }
                        GradientStop { position: 0.55; color: Qt.rgba(0.85, 0.9, 1, 0.035) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                    startX: 0; startY: 0
                    PathLine { x: 260; y: 0 }
                    PathLine { x: 260; y: 260 }
                    PathLine { x: 0; y: 260 }
                    PathLine { x: 0; y: 0 }
                }
            }
            ClippingRectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                // диск: моря и кратеры рисуются один раз
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d"), w = width, r = w / 2;
                        ctx.reset();
                        var g = ctx.createRadialGradient(r * 0.7, r * 0.6, 0, r, r, r);
                        g.addColorStop(0, "#f7f8ff"); g.addColorStop(1, "#c3c9df");
                        ctx.fillStyle = g; ctx.fillRect(0, 0, w, w);
                        // моря
                        var seas = [[0.32, 0.30, 0.17], [0.55, 0.42, 0.13], [0.42, 0.62, 0.11], [0.66, 0.24, 0.08], [0.28, 0.55, 0.07]];
                        for (var i = 0; i < seas.length; i++) {
                            ctx.fillStyle = Qt.rgba(0.5, 0.55, 0.68, 0.32);
                            ctx.beginPath(); ctx.ellipse((seas[i][0] - seas[i][2]) * w, (seas[i][1] - seas[i][2] * 0.8) * w, seas[i][2] * 2 * w, seas[i][2] * 1.6 * w, 0, 0, Math.PI * 2); ctx.fill();
                        }
                        // кратеры: тень и светлый край
                        for (var c = 0; c < 22; c++) {
                            var cx = sky.rnd(c, 51) * w, cy = sky.rnd(c, 52) * w, cr = 1 + sky.rnd(c, 53) * 3.2;
                            ctx.fillStyle = Qt.rgba(0.45, 0.5, 0.62, 0.35);
                            ctx.beginPath(); ctx.arc(cx, cy, cr, 0, Math.PI * 2); ctx.fill();
                            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.35); ctx.lineWidth = 0.7;
                            ctx.beginPath(); ctx.arc(cx - 0.4, cy - 0.4, cr, Math.PI * 0.9, Math.PI * 1.7); ctx.stroke();
                        }
                    }
                }
                // тень фазы: тёмный диск сдвигается по ходу месяца; пепельный свет — тень не совсем чёрная
                Rectangle {
                    width: parent.width; height: parent.height
                    radius: width / 2
                    x: moon.k <= 1 ? -parent.width * moon.k : parent.width * (2 - moon.k)
                    color: Qt.rgba(0.03, 0.04, 0.09, 0.9)
                }
            }
        }
    }
}
