import QtQuick

// Фон-карточка для питомцев (WPets): уютные пиксельные сцены с объёмом — градиенты неба и стен, светотень на деревьях и мебели,
// тёплое свечение огня и гирлянд. Сцены: park, home, night, winter, beach, newyear, halloween, spring, autumn, valentine;
// auto — по дате (Новый год, Хэллоуин, День влюблённых, времена года).
// Неподвижное рисуется один раз (Canvas) при смене сцены, времени суток и размера; живое — частицы и мерцание —
// несколько элементов на общем шаге сцены (tick), без перерисовки холста
Item {
    id: sc
    property string scene: "park"
    property int tick: 0
    property real p: 3                       // размер «пикселя» сцены
    property real groundTop: height - 34     // где начинается земля (по ней ходят питомцы)
    property real radius: 20
    readonly property int hour: new Date().getHours()
    readonly property string daytime: hour >= 7 && hour < 18 ? "day" : (hour >= 18 && hour < 21 ? "evening" : "night")

    // «авто»: праздник или время года по дате
    readonly property string kind: {
        if (scene !== "auto") return scene;
        var d = new Date(), m = d.getMonth() + 1, day = d.getDate();
        if ((m === 12 && day >= 15) || (m === 1 && day <= 15)) return "newyear";
        if ((m === 10 && day >= 25) || (m === 11 && day <= 2)) return "halloween";
        if (m === 2 && day >= 10 && day <= 15) return "valentine";
        if (m >= 3 && m <= 5) return "spring";
        if (m >= 9 && m <= 11) return "autumn";
        if (m === 12 || m <= 2) return "winter";
        return "park";
    }
    readonly property bool indoor: kind === "home" || kind === "newyear" || kind === "valentine"

    // места для поведения питомцев в доме: лукошко у печки/камина
    readonly property real stoveX: width * 0.04
    readonly property real stoveW: Math.max(70, width * 0.2)
    readonly property real basketX: stoveX + stoveW + Math.max(12, width * 0.04)
    readonly property real basketW: Math.max(78, width * 0.2)
    readonly property real treeX: width * 0.8               // новогодняя ёлка

    function q(v) { return Math.round(v / p) * p; }

    Canvas {
        id: cv
        anchors.fill: parent
        readonly property string key: [sc.kind, sc.daytime, sc.width, sc.height, sc.p].join()
        onKeyChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d"), W = width, H = height, p = sc.p, g = sc.groundTop, i;
            ctx.reset();
            if (W <= 0 || H <= 0) return;
            ctx.save();
            ctx.beginPath(); ctx.roundedRect(0, 0, W, H, sc.radius, sc.radius); ctx.clip();
            // ---------- кисти ----------
            function px(x, y, w, h, c) { ctx.fillStyle = c; ctx.fillRect(sc.q(x), sc.q(y), Math.max(p, sc.q(w)), Math.max(p, sc.q(h))); }
            function vgrad(x, y, w, h, a, b) { var gr = ctx.createLinearGradient(0, y, 0, y + h); gr.addColorStop(0, a); gr.addColorStop(1, b); ctx.fillStyle = gr; ctx.fillRect(x, y, w, h); }
            function glow(cx, cy, r, c, a) {
                var gr = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
                gr.addColorStop(0, Qt.rgba(c.r, c.g, c.b, a)); gr.addColorStop(0.5, Qt.rgba(c.r, c.g, c.b, a * 0.35)); gr.addColorStop(1, Qt.rgba(c.r, c.g, c.b, 0));
                ctx.fillStyle = gr; ctx.fillRect(cx - r, cy - r, r * 2, r * 2);
            }
            function blob(cx, cy, r, c) { for (var yy = -r; yy <= r; yy += p) { var hw = Math.sqrt(Math.max(0, r * r - yy * yy)); px(cx - hw, cy + yy, hw * 2, p, c); } }
            // шар со светом слева сверху: основной цвет, тень снизу справа, блик
            function ball(cx, cy, r, c, dark, light) { blob(cx, cy, r, c); blob(cx + r * 0.25, cy + r * 0.3, r * 0.7, dark); blob(cx - r * 0.1, cy - r * 0.05, r * 0.72, c); blob(cx - r * 0.35, cy - r * 0.35, r * 0.25, light); }
            function hill(y0, amp, freq, phase, a, b) {
                for (var xx = 0; xx < W; xx += p) { var hy = y0 - Math.sin(xx / W * 6.28 * freq + phase) * amp; vgrad(xx, sc.q(hy), p, g - hy + 2, a, b); }
            }
            function tree(x, top, c, dark, light) {
                px(x - p, top + 30, p * 3, g - top - 30, "#5a3b22"); px(x - p, top + 30, p, g - top - 30, "#7a5230");
                ball(x, top + 18, 20, c, dark, light); ball(x - 13, top + 26, 13, c, dark, light); ball(x + 13, top + 25, 12, c, dark, light);
            }
            function pine(x, top, snow, scale) {
                var k = scale || 1;
                px(x - p, g - 10 * k, p * 2, 10 * k, "#5a3b22");
                for (var t = 0; t < 4; t++) {
                    var w = (12 + t * 9) * k, y = top + t * 11 * k;
                    px(x - w / 2, y, w, 13 * k, "#2f6b45"); px(x, y, w / 2, 13 * k, "#255a39");
                    if (snow) { px(x - w / 2, y, w, p, "#f2f6ff"); px(x - w / 2, y + p, w * 0.4, p, "#dce8f8"); }
                }
            }
            function star(x, y, c) { px(x, y - p, p, p * 3, c); px(x - p, y, p * 3, p, c); }
            function room(wall1, wall2, pattern) {
                vgrad(0, 0, W, g, wall1, wall2);
                for (var yy = p * 4; yy < g - 50; yy += p * 8) for (var xx = ((yy / p / 8) % 2) * p * 5; xx < W; xx += p * 10) px(xx, yy, p, p, pattern);
                // деревянные панели внизу стены с рейкой и тенью
                vgrad(0, g - 44, W, 44, "#a0683a", "#7e5030");
                for (var pxx = p * 4; pxx < W; pxx += p * 18) { px(pxx, g - 40, p * 14, 34, "rgba(255,230,190,0.07)"); px(pxx, g - 40, p * 14, p, "rgba(255,230,190,0.18)"); px(pxx, g - 7, p * 14, p, "rgba(0,0,0,0.18)"); }
                px(0, g - 46, W, p * 2, "#6e4526"); px(0, g - 46, W, p, "#b9824e");
                px(0, g - p * 3, W, p * 3, "#5a3920"); px(0, g - p * 3, W, p, "#8d5c34");
                // пол: доски, дальние темнее, блик на ближних
                vgrad(0, g, W, H - g, "#9a6a3c", "#c48d55");
                for (var fy = g + p * 3, k2 = 0; fy < H; fy += p * (3 + k2), k2++) px(0, fy, W, p, "rgba(60,30,10,0.32)");
                for (var fx = 0; fx < W; fx += p * 22) px(fx + ((fx / p) % 3) * p * 4, g + p, p, H - g, "rgba(60,30,10,0.18)");
                // мягкая тень по низу стены — пол и стена не сливаются
                vgrad(0, g, W, p * 4, "rgba(0,0,0,0.25)", "rgba(0,0,0,0)");
            }
            // луч света из окна на пол
            function beam(wx, ww, night) {
                ctx.save();
                ctx.globalAlpha = night ? 0.06 : 0.14;
                ctx.fillStyle = night ? "#c8d8ff" : "#fff3c4";
                ctx.beginPath(); ctx.moveTo(wx, 70); ctx.lineTo(wx + ww, 70); ctx.lineTo(wx + ww * 1.6, H); ctx.lineTo(wx + ww * 0.3, H); ctx.closePath(); ctx.fill();
                ctx.restore();
            }
            function clock(x, y) {
                blob(x, y, 11, "#6e4526"); blob(x, y, 9, "#fbf3e4");
                for (var i2 = 0; i2 < 12; i2 += 3) { var aa = i2 / 12 * 6.283; px(x + Math.sin(aa) * 7, y - Math.cos(aa) * 7, p, p, "#6e4526"); }
                px(x, y - 6, p, 6, "#2a1a10"); px(x, y, 5, p, "#2a1a10");
                px(x - p / 2, y + 11, p, 14, "#6e4526"); blob(x, y + 27, 4, "#e8a93c");
            }
            function picture(x, y, w, h) {
                ctx.fillStyle = "rgba(0,0,0,0.2)"; ctx.fillRect(x + 3, y + 3, w, h);
                px(x, y, w, h, "#8a5a2e"); px(x + p, y + p, w - p * 2, h - p * 2, "#d9b46a");
                vgrad(x + p * 2, y + p * 2, w - p * 4, (h - p * 4) * 0.6, "#7cc6ff", "#d6f0ff");
                vgrad(x + p * 2, y + p * 2 + (h - p * 4) * 0.6, w - p * 4, (h - p * 4) * 0.4, "#5fb466", "#3f8f4a");
                blob(x + w * 0.7, y + h * 0.3, 3, "#ffe36b");
            }
            function logs(x) {
                for (var r = 0; r < 3; r++) for (var c = 0; c < 3 - r; c++) { var lx = x + c * 12 + r * 6, ly = g - 10 - r * 9; blob(lx, ly, 5, "#8a5a2e"); blob(lx, ly, 3, "#d9a86a"); px(lx - p / 2, ly - p / 2, p, p, "#a8783e"); }
            }
            function kettle(x, y) {
                ball(x, y, 8, "#c8443c", "#8e2a24", "#ff8a7a"); px(x + 7, y - 3, 6, p, "#8e2a24"); px(x - 4, y - 10, 8, p, "#2a1a10"); px(x - p / 2, y - 12, p, 3, "#2a1a10");
            }
            function windowAt(wx, wy, ww, wh, night, snowy) {
                px(wx - p * 2, wy - p * 2, ww + p * 4, wh + p * 4, "#6e4526");
                vgrad(sc.q(wx), sc.q(wy), sc.q(ww), sc.q(wh), night ? "#0b1434" : "#7cc6ff", night ? "#2a3a72" : "#d6f0ff");
                if (night) { blob(wx + ww * 0.7, wy + wh * 0.3, 5, "#f4ecd6"); star(wx + 8, wy + 10, "#ffffff"); px(wx + ww * 0.4, wy + wh * 0.6, p, p, "#fff"); }
                if (snowy) { px(wx, wy + wh - p * 3, ww, p * 3, "#f2f6ff"); }
                px(wx + ww / 2 - p / 2, wy, p, wh, "#6e4526"); px(wx, wy + wh / 2, ww, p, "#6e4526");
                px(wx - p * 3, wy + wh + p * 2, ww + p * 6, p * 2, "#8d5c34");
                // шторы
                vgrad(sc.q(wx - p * 5), sc.q(wy - p * 3), p * 5, wh + p * 6, "#c8443c", "#8e2a24");
                vgrad(sc.q(wx + ww), sc.q(wy - p * 3), p * 5, wh + p * 6, "#c8443c", "#8e2a24");
                px(wx - p * 6, wy - p * 4, ww + p * 12, p * 2, "#5a3b22");
            }
            function stove(sx, sw) {
                vgrad(sx, g - 80, sw, 80, "#fbf7ef", "#e2d9c9");
                for (var by = g - 76; by < g; by += p * 3) for (var bx = sx + ((by / p) % 2 ? 0 : p * 2); bx < sx + sw - p; bx += p * 5) px(bx, by, p * 4, p, "rgba(150,130,100,0.18)");
                px(sx + sw - p * 2, g - 80, p * 2, 80, "rgba(120,100,70,0.25)");
                px(sx + sw * 0.2, g - 36, sw * 0.6, 28, "#1a0f0b");
                px(sx + sw * 0.16, g - 40, sw * 0.68, p, "#a99c87");
                px(sx + sw * 0.33, 0, sw * 0.34, g - 80, "#f1ebdf"); px(sx + sw * 0.6, 0, p * 2, g - 80, "rgba(120,100,70,0.2)");
                glow(sx + sw / 2, g - 20, sw * 1.1, Qt.color("#ff9a3c"), 0.28);
            }
            function basket() {
                var bx = sc.basketX, bw = sc.basketW, cx = bx + bw / 2;
                ctx.fillStyle = "rgba(0,0,0,0.22)"; ctx.beginPath(); ctx.ellipse(bx - 4, g + 2, bw + 8, 10); ctx.fill();
                // ручка
                for (var a = 0; a <= 28; a++) { var t = a / 28 * Math.PI; px(cx - Math.cos(t) * bw * 0.4, g - 16 - Math.sin(t) * 28, p, p, a % 2 ? "#8a5a2e" : "#a8783e"); }
                // корпус: плетение в шахматку, к краям темнее (объём)
                for (var yy = 0; yy < 16; yy += p) {
                    var hw = bw / 2 - (yy > 10 ? (yy - 10) * 1.2 : 0);
                    for (var xx = -hw; xx < hw; xx += p) {
                        var edge = Math.abs(xx) / hw;
                        var c = ((Math.floor((xx + hw) / (p * 2)) + Math.floor(yy / p)) % 2) ? "#b98546" : "#9a6a35";
                        px(cx + xx, g - 16 + yy, p, p, c);
                        if (edge > 0.82) px(cx + xx, g - 16 + yy, p, p, "rgba(40,20,5,0.35)");
                    }
                }
                // подушка внутри и край
                ball(cx, g - 17, Math.min(10, bw * 0.12), "#f3e3c4", "#d9c39a", "#fffaf0");
                px(bx + p, g - 20, bw - p * 2, p * 2, "#f3e3c4"); px(bx + p, g - 20, bw - p * 2, p, "#fffaf0");
                px(bx, g - 17, bw, p, "#7d5428");
            }
            function rug(cx, w, c1, c2) {
                // овальный коврик с каймой и узором
                ctx.fillStyle = "rgba(0,0,0,0.18)"; ctx.beginPath(); ctx.ellipse(cx - w / 2 + 3, g + 6, w, 16); ctx.fill();
                ctx.fillStyle = c2; ctx.beginPath(); ctx.ellipse(cx - w / 2, g + 3, w, 15); ctx.fill();
                ctx.fillStyle = c1; ctx.beginPath(); ctx.ellipse(cx - w / 2 + 4, g + 5, w - 8, 11); ctx.fill();
                for (var rx = -w * 0.35; rx <= w * 0.35; rx += p * 4) px(cx + rx, g + 9, p, p, c2);
            }
            function shelf(x, y, w) {
                px(x, y + 18, w, p * 2, "#6e4526"); px(x, y + 18, w, p, "#a8783e"); px(x + 4, y + 18 + p * 2, p, 4, "#5a3b22"); px(x + w - 6, y + 18 + p * 2, p, 4, "#5a3b22");
                ctx.fillStyle = "rgba(0,0,0,0.15)"; ctx.fillRect(x, y + 18 + p * 2, w, p * 2);
                // кружка
                px(x + w - 12, y + 10, 8, 8, "#f6f1e8"); px(x + w - 4, y + 12, 2, 4, "#f6f1e8");
                var cols = ["#c8443c", "#3d6bff", "#e8a93c", "#34a86b", "#9b59d0"];
                for (var b = 0; b < w / (p * 3) - 1; b++) { var hb = 12 + (b * 7) % 6; px(x + p + b * p * 3, y + 18 - hb, p * 2, hb, cols[b % cols.length]); }
            }
            function lamp(x) {
                px(x, g - 46, p, 46, "#3a2a20"); px(x - 10, g - 58, 22, 12, "#f6d48a"); px(x - 8, g - 58, 18, p, "#fff0c4");
                glow(x + 1, g - 48, 60, Qt.color("#ffcc66"), 0.3);
            }
            function plant(x) {
                ctx.fillStyle = "rgba(0,0,0,0.2)"; ctx.fillRect(x - 6, g + 1, 18, p);
                vgrad(x - 7, g - 18, 16, 18, "#d07a48", "#a85a30"); px(x - 8, g - 18, 18, p * 2, "#e08a5c");
                ball(x + 1, g - 30, 11, "#3f9c5a", "#2e7d45", "#6bd08a"); ball(x - 8, g - 24, 7, "#3f9c5a", "#2e7d45", "#6bd08a"); ball(x + 10, g - 25, 7, "#3f9c5a", "#2e7d45", "#6bd08a");
            }
            function gift(x, w, h, c, r) { vgrad(x, g - h, w, h, c, Qt.darker(c, 1.3)); px(x + w / 2 - p / 2, g - h, p, h, r); px(x, g - h + h / 3, w, p, r); px(x + w / 2 - p * 2, g - h - p * 2, p * 4, p * 2, r); }

            var k = sc.kind, d = sc.daytime, night = d === "night";
            // ---------- улица ----------
            if (k === "park" || k === "spring" || k === "autumn") {
                vgrad(0, 0, W, g, night ? "#0d1530" : (d === "evening" ? "#ff8f6b" : "#7cc8ff"), night ? "#2b3a6e" : (d === "evening" ? "#ffd59a" : "#dff4ff"));
                if (night) { for (i = 0; i < 30; i++) px((i * 97) % W, (i * 53) % (g - 40), p, p, "#ffffff"); glow(W * 0.82, 28, 40, Qt.color("#f4ecd6"), 0.35); blob(W * 0.82, 28, 11, "#f4ecd6"); }
                else { glow(W * 0.84, 30, 60, Qt.color(d === "day" ? "#fff2a8" : "#ff9a5a"), 0.55); blob(W * 0.84, 30, 13, d === "day" ? "#ffe36b" : "#ff7a4a"); }
                for (i = 0; i < 3; i++) { var cx = W * (0.12 + i * 0.3), cy = 18 + (i % 2) * 12; ball(cx, cy, 8, "rgba(255,255,255,0.92)", "rgba(220,230,245,0.9)", "#ffffff"); ball(cx + 12, cy + 2, 10, "rgba(255,255,255,0.92)", "rgba(220,230,245,0.9)", "#ffffff"); ball(cx + 24, cy + 3, 7, "rgba(255,255,255,0.92)", "rgba(220,230,245,0.9)", "#ffffff"); }
                var grass = k === "autumn" ? ["#a7a046", "#8c8a3a"] : (night ? ["#1f3a2a", "#162b1f"] : ["#6cc06f", "#4a9b55"]);
                hill(g - 26, 10, 1.2, 1.0, night ? "#1b3326" : (k === "autumn" ? "#c9a04f" : "#86cf86"), night ? "#152a1f" : (k === "autumn" ? "#a7883e" : "#5fb466"));
                hill(g - 12, 6, 2.0, 2.2, grass[0], grass[1]);
                var leaf = k === "spring" ? ["#ffb3cf", "#ff8fb8", "#ffe0ec"] : (k === "autumn" ? ["#ff8a2a", "#c8443c", "#ffd34a"] : ["#3f9c5a", "#2e7d45", "#6bd08a"]);
                tree(W * 0.1, g - 76, leaf[0], leaf[1], leaf[2]); tree(W * 0.9, g - 70, leaf[0], leaf[1], leaf[2]);
                vgrad(0, g, W, H - g, grass[0], grass[1]);
                for (i = 0; i < W; i += p * 5) px(i + (i % 3) * p, g + p * ((i / p) % 3), p, p, grass[1]);
                // дорожка, лавочка с тенью, фонарь, цветы или грибы
                vgrad(W * 0.3, g + 2, W * 0.28, H - g, "#d9c39a", "#bfa676");
                var bx = W * 0.58;
                ctx.fillStyle = "rgba(0,0,0,0.18)"; ctx.fillRect(bx + 4, g + 2, 72, p * 2);
                px(bx, g - 24, 72, p * 2, "#b77a46"); px(bx, g - 24, 72, p, "#d39a62"); px(bx, g - 15, 72, p * 2, "#9a6436");
                px(bx + 6, g - 9, p * 2, 9, "#4a3020"); px(bx + 62, g - 9, p * 2, 9, "#4a3020");
                px(W * 0.26, g - 60, p * 2, 60, "#2d2d36"); px(W * 0.26 - 6, g - 66, 15, 9, night || d === "evening" ? "#ffe9a8" : "#d8dde8");
                if (night || d === "evening") glow(W * 0.26 + 2, g - 60, 70, Qt.color("#ffd27a"), 0.35);
                var fl = k === "autumn" ? ["#c8443c", "#e8d4b0", "#a0522d"] : ["#ff5a7a", "#ffd34a", "#ffffff", "#b07cff"];
                for (i = 0; i < 12; i++) { var fx = (i * 137 + 40) % W; if (fx > W * 0.3 && fx < W * 0.58) continue; px(fx, g + 6 + (i % 3) * p * 2, p, p, fl[i % fl.length]); px(fx, g + 6 + (i % 3) * p * 2 + p, p, p, grass[1]); }
                if (k === "spring") { vgrad(W * 0.68, g + 8, W * 0.18, 10, "#7cc6ff", "#4aa8ff"); px(W * 0.7, g + 9, W * 0.08, p, "#cfeeff"); }
            } else if (k === "night" || k === "halloween") {
                var hw = k === "halloween";
                vgrad(0, 0, W, g, hw ? "#1a0d2e" : "#050a1e", hw ? "#4a1f3a" : "#1c2a5a");
                for (i = 0; i < 40; i++) px((i * 89) % W, (i * 41) % (g - 30), p, p, i % 5 ? "rgba(255,255,255,0.65)" : "#ffffff");
                var mc = Qt.color(hw ? "#ffb04a" : "#f4ecd6");
                glow(W * 0.22, 32, 70, mc, 0.4); blob(W * 0.22, 32, hw ? 18 : 15, hw ? "#ffb04a" : "#f4ecd6");
                if (!hw) blob(W * 0.22 + 7, 28, 13, "#0a1230");
                else { blob(W * 0.22 + 5, 28, 4, "rgba(200,110,40,0.5)"); blob(W * 0.22 - 6, 38, 3, "rgba(200,110,40,0.5)"); }
                hill(g - 20, 12, 1.3, 0.5, hw ? "#1c0f22" : "#0d1d18", hw ? "#140a18" : "#0a1612");
                // домик с окнами
                var hx = W * 0.62;
                px(hx, g - 40, 48, 40, hw ? "#2a1a2a" : "#1a2420"); for (i = 0; i < 12; i++) px(hx - 4 + i * 4.5, g - 40 - i * 2.2 + (i > 6 ? (i - 6) * 4.4 : 0), p * 2, p, hw ? "#3a2236" : "#26332e");
                px(hx + 8, g - 30, 10, 10, "#ffcf6b"); px(hx + 30, g - 30, 10, 10, "#ffcf6b"); glow(hx + 24, g - 25, 50, Qt.color("#ffcf6b"), 0.3);
                px(0, g, W, H - g, hw ? "#140a18" : "#0a1612");
                if (hw) {
                    // кривое дерево и забор
                    px(W * 0.08, g - 70, p * 2, 70, "#140a10"); for (i = 0; i < 5; i++) px(W * 0.08 - i * 4, g - 70 + i * 3, p * 2, p, "#140a10"); for (i = 0; i < 5; i++) px(W * 0.08 + i * 4, g - 60 + i * 2, p * 2, p, "#140a10");
                    for (i = 0; i < W; i += p * 6) px(i, g - 14, p * 2, 16, "#22121e");
                    px(0, g - 10, W, p, "#22121e");
                }
            } else if (k === "winter") {
                vgrad(0, 0, W, g, night ? "#0e1a3a" : "#a9cdee", night ? "#3a4f86" : "#eef6ff");
                if (night) for (i = 0; i < 25; i++) px((i * 101) % W, (i * 47) % (g - 40), p, p, "#ffffff");
                hill(g - 24, 12, 1.1, 0.3, "#ffffff", "#dbe7f5"); hill(g - 10, 6, 2, 1.8, "#f5f9ff", "#cddbef");
                pine(W * 0.1, g - 60, true, 1.1); pine(W * 0.2, g - 40, true, 0.8); pine(W * 0.92, g - 52, true, 1.0);
                // домик с горящим окном и трубой
                var hx2 = W * 0.38;
                vgrad(hx2, g - 42, 56, 42, "#a0522d", "#7a3e22");
                for (i = 0; i < 14; i++) px(hx2 - 6 + i * 4.8, g - 42 - (i < 7 ? i * 2.6 : (13 - i) * 2.6), p * 2, p * 2, "#ffffff");
                px(hx2 + 40, g - 70, 8, 16, "#6e3a22");
                px(hx2 + 10, g - 30, 12, 12, "#ffd27a"); glow(hx2 + 16, g - 24, 50, Qt.color("#ffd27a"), 0.35);
                vgrad(0, g, W, H - g, "#f5f9ff", "#d4e2f4");
                // снеговик с шарфом
                var sx2 = W * 0.72;
                ball(sx2, g - 10, 12, "#ffffff", "#d6e2f2", "#ffffff"); ball(sx2, g - 30, 9, "#ffffff", "#d6e2f2", "#ffffff"); ball(sx2, g - 44, 7, "#ffffff", "#d6e2f2", "#ffffff");
                px(sx2 - p, g - 46, p, p, "#222"); px(sx2 + p, g - 46, p, p, "#222"); px(sx2 + p * 2, g - 44, p * 2, p, "#ff8a2a");
                px(sx2 - 9, g - 38, 18, p * 2, "#c8443c"); px(sx2 + 4, g - 36, p * 2, 8, "#c8443c");
                px(sx2 - 8, g - 52, 16, p, "#2a2a2a"); px(sx2 - 5, g - 60, 10, 8, "#2a2a2a");
            } else if (k === "beach") {
                vgrad(0, 0, W, g - 26, d === "evening" ? "#ff8a5a" : "#6fc6ff", d === "evening" ? "#ffd59a" : "#d9f4ff");
                glow(W * 0.84, 30, 70, Qt.color("#fff2a8"), 0.6); blob(W * 0.84, 30, 14, "#ffe36b");
                vgrad(0, g - 26, W, 26, "#2f8fd6", "#1e6fb0");
                for (i = 0; i < 6; i++) px(W * 0.78 + (i % 2) * 6, g - 24 + i * 4, 16 - i * 2, p, "rgba(255,240,170,0.7)");
                vgrad(0, g, W, H - g, "#f6dca4", "#e2bd7c");
                for (i = 0; i < W; i += p * 6) px(i + p, g + p * 2 + (i / p % 3) * p, p, p, "#d4ad6a");
                // пальма
                var pl = W * 0.08; for (i = 0; i < 14; i++) px(pl + i * 0.8, g - i * 5, p * 2, 6, i % 2 ? "#8a5a32" : "#a06a3c");
                for (i = 0; i < 5; i++) { var ang = -2.6 + i * 0.55; for (var r = 0; r < 26; r += p) px(pl + 11 + Math.cos(ang) * r, g - 70 + Math.sin(ang) * r * 0.6 + r * r / 120, p * 2, p, "#2f8f4f"); }
                // зонтик с тенью
                var ux = W * 0.3; ctx.fillStyle = "rgba(0,0,0,0.15)"; ctx.fillRect(ux - 20, g + 6, 50, p * 2);
                px(ux, g - 44, p, 50, "#8a5a32");
                for (i = 0; i < 7; i++) px(ux - 26 + i * 8, g - 50 + Math.abs(i - 3) * 2, 9, 7, i % 2 ? "#ffffff" : "#ff5a5a");
                px(W * 0.55, g + 10, p * 2, p, "#ffb3c4"); px(W * 0.72, g + 14, p * 2, p, "#ffffff"); px(W * 0.62, g + 18, p * 3, p * 2, "#ff7a5a");
            }
            // ---------- в доме ----------
            else if (k === "home" || k === "newyear" || k === "valentine") {
                var ny = k === "newyear", vl = k === "valentine";
                room(vl ? "#f7d6e0" : "#efd9b6", vl ? "#e8b8c8" : "#dcc29b", vl ? "rgba(220,90,130,0.35)" : "rgba(150,110,60,0.25)");
                beam(W * 0.42, Math.max(54, W * 0.18), night || ny);
                windowAt(W * 0.42, 16, Math.max(54, W * 0.18), 46, night || ny, ny);
                stove(sc.stoveX, sc.stoveW);
                kettle(sc.stoveX + sc.stoveW * 0.72, g - 89);
                if (!ny) logs(sc.basketX + sc.basketW + 10);
                basket();
                rug(W * 0.55, W * 0.26, vl ? "#e84a7a" : "#c8443c", "#e8a93c");
                if (ny) {
                    // носки на печке и ёлка с игрушками
                    for (i = 0; i < 3; i++) { px(sc.stoveX + 8 + i * 18, g - 76, 8, 12, i % 2 ? "#ffffff" : "#c8443c"); px(sc.stoveX + 8 + i * 18, g - 66, 12, 5, i % 2 ? "#ffffff" : "#c8443c"); }
                    var tx = sc.treeX;
                    for (i = 0; i < 5; i++) { var tw = 16 + i * 11, ty = g - 92 + i * 15; vgrad(tx - tw / 2, ty, tw, 17, "#2f8f4f", "#1f5f35"); px(tx, ty, tw / 2, 17, "rgba(0,0,0,0.12)"); }
                    px(tx - p, g - 16, p * 3, 16, "#5a3b22");
                    var orn = ["#ff5a5a", "#ffd34a", "#4aa8ff", "#ff8fd0"];
                    for (i = 0; i < 12; i++) blob(tx - 24 + ((i * 17) % 48) * (0.4 + Math.floor(i / 4) * 0.3), g - 76 + Math.floor(i / 3) * 16, 3, orn[i % orn.length]);
                    glow(tx, g - 98, 34, Qt.color("#ffe36b"), 0.5); star(tx, g - 98, "#ffe36b"); px(tx - p * 2, g - 98, p * 5, p, "#ffe36b");
                    gift(tx - 46, 18, 14, Qt.color("#4aa8ff"), "#ffd34a"); gift(tx + 22, 16, 12, Qt.color("#c8443c"), "#ffffff"); gift(tx - 26, 12, 9, Qt.color("#34a86b"), "#ff5a5a");
                } else {
                    shelf(W * 0.66, 14, Math.max(60, W * 0.2));
                    picture(W * 0.66 + 4, 42, 34, 26);
                    clock(W * 0.66 + Math.max(60, W * 0.2) - 10, 58);
                    lamp(W * 0.93);
                    plant(W * 0.86);
                    if (vl) for (i = 0; i < 6; i++) { var hx3 = W * (0.2 + i * 0.13), hy3 = 20 + (i % 2) * 12; blob(hx3 - 3, hy3, 4, "#ff5a8a"); blob(hx3 + 3, hy3, 4, "#ff5a8a"); px(hx3 - 6, hy3 + 2, 12, 4, "#ff5a8a"); px(hx3 - 3, hy3 + 6, 6, 3, "#ff5a8a"); }
                }
                // мягкая виньетка — комната кажется глубже
                var vg = ctx.createRadialGradient(W / 2, H * 0.55, Math.min(W, H) * 0.3, W / 2, H * 0.55, Math.max(W, H) * 0.75);
                vg.addColorStop(0, "rgba(0,0,0,0)"); vg.addColorStop(1, "rgba(40,20,10,0.28)");
                ctx.fillStyle = vg; ctx.fillRect(0, 0, W, H);
            }
            ctx.restore();
        }
    }

    // ---------- живое ----------
    // мерцающий тёплый свет от огня (печка, камин)
    Rectangle {
        visible: sc.indoor
        x: sc.stoveX + sc.stoveW * 0.1; y: sc.groundTop - 34
        width: sc.stoveW * 0.8; height: 30; radius: 10
        color: "#ff9a3c"
        opacity: 0.12 + ((sc.tick * 7) % 5) * 0.025
    }
    // огонь: языки разной высоты
    Repeater {
        model: sc.indoor ? 4 : 0
        Rectangle {
            required property int index
            readonly property real hh: 8 + ((sc.tick + index * 3) % 5) * 3
            x: sc.stoveX + sc.stoveW * (0.27 + index * 0.13)
            y: sc.groundTop - 9 - hh
            width: sc.p * 2; height: hh
            color: index % 2 ? "#ffd34a" : "#ff7a2a"
        }
    }
    // гирлянда на ёлке и в окне: огоньки по очереди
    Repeater {
        model: sc.kind === "newyear" ? 14 : 0
        Rectangle {
            required property int index
            readonly property var cols: ["#ff5a5a", "#ffd34a", "#4aff9a", "#4aa8ff", "#ff8fd0"]
            x: index < 9 ? sc.treeX - 28 + (index * 13) % 56 * (0.5 + Math.floor(index / 3) * 0.25) : sc.width * 0.42 + (index - 9) * 12
            y: index < 9 ? sc.groundTop - 84 + Math.floor(index / 3) * 18 : 10
            width: sc.p + 1; height: width; radius: width / 2
            color: cols[(index + Math.floor(sc.tick / 3)) % cols.length]
            opacity: (index + Math.floor(sc.tick / 2)) % 3 === 0 ? 0.35 : 1
            Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: parent.color; opacity: 0.25 }
        }
    }
    // тыквы со светящимися лицами
    Repeater {
        model: sc.kind === "halloween" ? 3 : 0
        Item {
            required property int index
            x: sc.width * (0.12 + index * 0.33); y: sc.groundTop - 14 + index % 2 * 2
            width: 22; height: 16
            Rectangle { anchors.fill: parent; radius: 8; color: "#ff8a1a" }
            Rectangle { x: 2; width: 4; height: 16; radius: 2; color: "#e0700f" }
            Rectangle { x: 16; width: 4; height: 16; radius: 2; color: "#e0700f" }
            Rectangle { x: 9; y: -4; width: 3; height: 5; color: "#3f7a2a" }
            Repeater { model: 3; Rectangle { required property int index; x: [5, 14, 8][index]; y: [4, 4, 10][index]; width: index === 2 ? 7 : 3; height: index === 2 ? 2 : 3; color: "#ffe36b"; opacity: 0.6 + ((sc.tick + index) % 4) * 0.12 } }
        }
    }
    // частицы: снег, лепестки, листья, сердечки, светлячки, летучие мыши
    readonly property string particles: kind === "winter" || kind === "newyear" ? "snow" : (kind === "spring" ? "petal" : (kind === "autumn" ? "leaf"
                                         : (kind === "valentine" ? "heart" : (kind === "night" || (kind === "park" && daytime === "night") ? "firefly" : (kind === "halloween" ? "bat" : "")))))
    Repeater {
        model: sc.particles === "" ? 0 : (sc.particles === "bat" ? 4 : 14)
        Item {
            id: pt
            required property int index
            readonly property int period: 40 + (index * 7) % 30
            readonly property real t: ((sc.tick + index * 13) % period) / period
            // в доме снег идёт только за окном
            readonly property bool inWindow: sc.kind === "newyear"
            x: inWindow ? sc.width * 0.42 + (index * 7) % Math.max(1, sc.width * 0.18) : (index * 73) % Math.max(1, sc.width) + Math.sin((sc.tick + index * 4) / 6) * 8
            y: sc.particles === "firefly" ? sc.groundTop - 16 - Math.cos((sc.tick + index * 5) / 7) * 14
               : (sc.particles === "bat" ? 14 + index * 12 + Math.sin(sc.tick / 3 + index) * 6
               : (inWindow ? 16 + t * 44 : t * (sc.groundTop + 12)))
            visible: !inWindow || index % 2 === 0
            Rectangle {
                visible: sc.particles === "snow" || sc.particles === "firefly"
                width: sc.p; height: sc.p; radius: sc.particles === "firefly" ? sc.p : 0
                color: sc.particles === "firefly" ? "#d8ff6b" : "#ffffff"
                opacity: sc.particles === "firefly" ? 0.4 + 0.6 * Math.abs(Math.sin((sc.tick + pt.index * 3) / 4)) : 0.9
            }
            Rectangle { visible: sc.particles === "petal"; width: sc.p * 2; height: sc.p; radius: sc.p / 2; color: pt.index % 2 ? "#ffb3cf" : "#ffe0ec"; rotation: sc.tick * 9 + pt.index * 40 }
            Rectangle { visible: sc.particles === "leaf"; width: sc.p * 2; height: sc.p * 2; color: ["#ff8a2a", "#c8443c", "#ffd34a"][pt.index % 3]; rotation: sc.tick * 7 + pt.index * 30 }
            Text { visible: sc.particles === "heart"; text: "♥"; color: pt.index % 2 ? "#ff5a8a" : "#ff8fb8"; font.pixelSize: 9 + pt.index % 3 * 2; opacity: 1 - pt.t; y: -pt.t * 20 }
            // летучая мышь: крылья вверх-вниз
            Row {
                visible: sc.particles === "bat"
                x: ((sc.tick * 3 + pt.index * 90) % (sc.width + 40)) - 20
                Rectangle { width: 6; height: 3; color: "#1a0d1a"; rotation: sc.tick % 2 ? -25 : 15 }
                Rectangle { width: 4; height: 4; radius: 2; color: "#1a0d1a" }
                Rectangle { width: 6; height: 3; color: "#1a0d1a"; rotation: sc.tick % 2 ? 25 : -15 }
            }
        }
    }
    // дым из трубы зимнего домика
    Repeater {
        model: sc.kind === "winter" ? 4 : 0
        Rectangle {
            required property int index
            readonly property real t: ((sc.tick + index * 6) % 24) / 24
            x: sc.width * 0.38 + 44 + Math.sin(t * 6) * 4 + t * 10
            y: sc.groundTop - 72 - t * 40
            width: 6 + t * 8; height: width; radius: width / 2
            color: "#eef2f8"; opacity: 0.7 * (1 - t)
        }
    }
    // волны на пляже
    Repeater {
        model: sc.kind === "beach" ? 6 : 0
        Rectangle {
            required property int index
            x: ((index * sc.width / 6) + (sc.tick % 24) * sc.p / 2) % sc.width
            y: sc.groundTop - 18 + (index % 2) * sc.p * 2
            width: sc.p * 5; height: sc.p
            color: "#cfeeff"; opacity: 0.8
        }
    }
}
