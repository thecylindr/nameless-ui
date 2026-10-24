.pragma library
// Пиксельные спрайты питомцев: кадр — сетка символов (ключ цвета на клетку), строится кодом из простых фигур,
// контур дорисовывается сам вокруг залитых клеток. Рисует PixelPet.qml — каждый кадр один раз, анимация только переключает кадры.
//   виды: cat (кот/кошка, окрас — палитрой), dog (корги, лиса — opt.fox), clawd (Клод — персонаж Claude Code)
//   позы: cat/dog — stand, walk, sit, sleep, jump; clawd — idle, work, wait, sleep, jump
// Ключи цветов: b — основной, s — полоски/тень, w — светлое (грудь, лапки), p — розовое (нос, уши), e — глаза, k — контур/зрачки

var W = 26, H = 18;

function grid(w, h) { var g = []; for (var y = 0; y < h; y++) { var r = []; for (var x = 0; x < w; x++) r.push(""); g.push(r); } return g; }
function put(g, x, y, c) { if (y >= 0 && y < g.length && x >= 0 && x < g[0].length) g[y][x] = c; }
function rect(g, x, y, w, h, c) { for (var j = 0; j < h; j++) for (var i = 0; i < w; i++) put(g, x + i, y + j, c); }
// прямоугольник со срезанными углами — «округлый» в пикселях
function blob(g, x, y, w, h, c) { rect(g, x, y, w, h, c); put(g, x, y, ""); put(g, x + w - 1, y, ""); put(g, x, y + h - 1, ""); put(g, x + w - 1, y + h - 1, ""); }
function pts(g, list, c) { for (var i = 0; i < list.length; i++) put(g, list[i][0], list[i][1], c); }

// контур: пустая клетка рядом с залитой (по четырём сторонам) становится контуром
function outline(g) {
    var h = g.length, w = g[0].length, out = grid(w, h);
    for (var y = 0; y < h; y++) for (var x = 0; x < w; x++) {
        out[y][x] = g[y][x];
        if (g[y][x] !== "") continue;
        var n = (y > 0 && g[y - 1][x] !== "" && g[y - 1][x] !== "k") || (y < h - 1 && g[y + 1][x] !== "" && g[y + 1][x] !== "k")
             || (x > 0 && g[y][x - 1] !== "" && g[y][x - 1] !== "k") || (x < w - 1 && g[y][x + 1] !== "" && g[y][x + 1] !== "k");
        if (n) out[y][x] = "o";
    }
    return out;
}

// ---------- кошки и собака (смотрят вправо) ----------
// opt: striped — полоски, socks — белые лапки, dog — собака (уши выше, морда длиннее, лапы короче, хвост-обрубок)
function legs(g, pose, f, dog) {
    var top = dog ? 14 : 14, len = dog ? 2 : 3;
    var xs = [6, 9, 13, 16];
    var dx = [0, 0, 0, 0], lift = [0, 0, 0, 0];
    if (pose === "walk") {
        var ph = f % 4;
        if (ph === 0) { dx = [1, -1, 1, -1]; }
        if (ph === 1) { lift = [1, 0, 1, 0]; }
        if (ph === 2) { dx = [-1, 1, -1, 1]; }
        if (ph === 3) { lift = [0, 1, 0, 1]; }
    }
    for (var i = 0; i < 4; i++) {
        var far = i === 1 || i === 2;
        rect(g, xs[i] + dx[i], top, 2, len - lift[i], far ? "s" : "b");
        rect(g, xs[i] + dx[i], top + len - lift[i] - 1, 2, 1, "w");
    }
}

function head(g, x, y, f, opt, blink) {
    if (opt.dog) {
        blob(g, x, y + 1, 7, 6, "b");
        rect(g, x + 6, y + 3, 3, 3, "w");             // морда
        put(g, x + 8, y + 3, "k");                     // нос
        pts(g, [[x + 1, y - 1], [x + 1, y], [x + 2, y], [x + 5, y - 1], [x + 5, y], [x + 4, y]], "b");   // уши торчком
        pts(g, [[x + 2, y - 0], [x + 4, y - 0]], "p");
        if (f % 4 === 1) put(g, x + 7, y + 6, "p");    // язык
    } else {
        blob(g, x, y + 1, 7, 6, "b");
        pts(g, [[x + 1, y - 1], [x + 1, y], [x + 2, y], [x + 5, y - 1], [x + 5, y], [x + 4, y]], "b");
        pts(g, [[x + 1, y], [x + 5, y]], "p");          // уши внутри
        rect(g, x + 5, y + 4, 2, 2, "w");               // мордочка
        put(g, x + 6, y + 4, "p");                      // нос
        if (opt.striped) pts(g, [[x + 2, y + 1], [x + 3, y + 1], [x + 3, y + 2]], "s");
    }
    if (blink) pts(g, [[x + 4, y + 3]], "k");
    else pts(g, [[x + 4, y + 2], [x + 4, y + 3]], "e");
}

function tail(g, pose, f, opt) {
    if (opt.fox) {
        // пушистый хвост с белым кончиком: толщина 2, покачивается
        var ft = f % 2 === 0 ? [[5, 10], [4, 10], [3, 9], [2, 9], [1, 8], [1, 7]] : [[5, 10], [4, 11], [3, 11], [2, 11], [1, 10], [0, 10]];
        for (var i = 0; i < ft.length; i++) { put(g, ft[i][0], ft[i][1], "b"); put(g, ft[i][0], ft[i][1] + 1, i < 3 ? "b" : "s"); }
        put(g, ft[ft.length - 1][0], ft[ft.length - 1][1], "w"); put(g, ft[ft.length - 1][0], ft[ft.length - 1][1] + 1, "w");
        return;
    }
    if (opt.dog) { pts(g, [[5, 9], [4, 8]], "b"); if (f % 2) put(g, 4, 7, "b"); return; }
    var t;
    if (pose === "walk") t = [[5, 9], [4, 8], [4, 7], [4, 6], [5, 5]];
    else if (f % 2 === 0) t = [[5, 9], [4, 8], [3, 7], [3, 6], [3, 5], [4, 4]];
    else t = [[5, 9], [4, 9], [3, 8], [2, 7], [2, 6], [2, 5]];
    // хвост в два пикселя толщиной; у светлой полосатой кошки (opt.darkTail) — тёмный, как на фото
    var tc = opt.darkTail ? "d" : "b";
    for (var i = 0; i < t.length; i++) { put(g, t[i][0], t[i][1], tc); if (i > 0 && i < t.length - 1) put(g, t[i][0] + 1, t[i][1], tc); }
    if (opt.striped) { put(g, t[1][0], t[1][1], "s"); put(g, t[3][0], t[3][1], "s"); put(g, t[t.length - 1][0], t[t.length - 1][1], opt.darkTail ? "k" : "s"); }
}

function animal(pose, f, opt) {
    var g = grid(W, H);
    var blink = (pose === "stand" || pose === "sit") && f === 3;
    if (pose === "sleep") {
        blob(g, 5, 11, 15, 6, "b");
        rect(g, 8, 16, 9, 1, "w");
        blob(g, 15, 10, 7, 6, "b");
        pts(g, [[16, 9], [20, 9]], "b"); pts(g, [[16, 9]], "p");
        pts(g, [[18, 13], [19, 13]], "k");             // закрытые глаза
        if (!opt.dog) put(g, 21, 14, "p");
        pts(g, [[4, 16], [5, 16], [6, 16], [7, 17], [8, 17], [9, 17], [10, 17]], opt.dog ? "" : (opt.darkTail ? "d" : "b"));     // хвост вокруг
        if (opt.striped) { pts(g, [[8, 12], [11, 12], [14, 12], [8, 13], [11, 13]], "s"); }
        if (f % 2) put(g, 5, 12, "s");                  // дыхание — чуть меняется спина
        return outline(g);
    }
    if (pose === "sit") {
        blob(g, 8, 8, 9, 7, "b");                       // туловище
        rect(g, 13, 9, 4, 5, "w");                      // грудь
        rect(g, 13, 14, 2, 3, "b"); rect(g, 16, 14, 2, 3, "b");      // передние лапы
        rect(g, 13, 16, 2, 1, "w"); rect(g, 16, 16, 2, 1, "w");
        blob(g, 7, 13, 6, 4, "b");                      // задняя лапа
        if (!opt.dog) pts(g, f % 2 ? [[6, 16], [5, 16], [4, 15], [4, 14]] : [[6, 16], [5, 16], [4, 16], [3, 15]], "b");
        else pts(g, [[7, 9], [6, 8]], "b");
        if (opt.striped) pts(g, [[9, 9], [9, 10], [11, 9], [11, 10]], "s");
        head(g, 12, 2, f, opt, blink);
        return outline(g);
    }
    var oy = pose === "jump" ? -2 : 0;
    blob(g, 6, 9 + oy, 12, 5, "b");                    // туловище
    rect(g, 9, 13 + oy, 7, 1, "w");                     // живот
    rect(g, 16, 10 + oy, 2, 3, "w");                    // грудь
    if (opt.striped) for (var sx = 8; sx <= 14; sx += 3) rect(g, sx, 9 + oy, 1, 2, "s");
    if (pose === "jump") { rect(g, 6, 13, 2, 2, "b"); rect(g, 16, 13, 2, 2, "b"); rect(g, 9, 13, 2, 2, "s"); rect(g, 13, 13, 2, 2, "s"); }
    else legs(g, pose, f, opt.dog);
    tail(g, pose, f, opt);
    head(g, 16, 3 + oy, f, opt, blink);
    return outline(g);
}

// ---------- Клод: оранжевый пиксельный персонаж Claude Code ----------
function clawd(pose, f) {
    var g = grid(20, 16);
    var oy = pose === "sleep" ? 2 : (pose === "jump" ? -2 : ((pose === "idle" || pose === "wait") && f % 2 ? 1 : 0));
    rect(g, 4, 3 + oy, 12, 8, "b");                     // тело-кирпичик
    rect(g, 4, 10 + oy, 12, 1, "s");                    // тень снизу
    // глаза: вертикальные палочки; моргание и сон — линия
    if (pose === "sleep" || (pose === "idle" && f === 3)) pts(g, [[6, 6 + oy], [7, 6 + oy], [12, 6 + oy], [13, 6 + oy]], "k");
    else if (pose === "work") rect(g, 7, 5 + oy, 1, 2, "k"), rect(g, 13, 5 + oy, 1, 2, "k");          // смотрит в «экран» — глаза вправо
    else rect(g, 6, 5 + oy, 1, 2, "k"), rect(g, 13, 5 + oy, 1, 2, "k");
    // руки-клешни по бокам
    if (pose === "work") {
        rect(g, 2, (f % 2 ? 5 : 7) + oy, 2, 2, "b"); rect(g, 16, (f % 2 ? 7 : 5) + oy, 2, 2, "b");
    } else if (pose === "wait") {
        rect(g, 2, 6 + oy, 2, 2, "b");
        rect(g, 16, (f % 2 ? 1 : 2) + oy, 2, 3, "b");  // машет
    } else rect(g, 2, 6 + oy, 2, 2, "b"), rect(g, 16, 6 + oy, 2, 2, "b");
    // ножки
    var ly = 11 + oy;
    if (pose !== "sleep") for (var i = 0; i < 4; i++) rect(g, 5 + i * 3, ly, 1, (pose === "work" && (i + f) % 2) ? 1 : 2, "b");
    return outline(g);
}

// ---------- рыбка для аквариума (смотрит вправо): хвост виляет ----------
function fish(f) {
    var g = grid(12, 7);
    blob(g, 3, 1, 7, 5, "b");
    rect(g, 5, 2, 1, 3, "s");                           // полоска
    put(g, 8, 2, "e");                                  // глаз
    put(g, 10, 3, "b"); put(g, 9, 4, "w");              // нос и брюшко
    if (f % 2 === 0) pts(g, [[2, 2], [1, 1], [1, 2], [2, 3], [1, 4], [1, 5], [2, 4]], "s");
    else pts(g, [[2, 3], [1, 2], [0, 2], [1, 3], [0, 4], [1, 4]], "s");
    pts(g, [[6, 0], [7, 0]], "s");                      // спинной плавник
    return outline(g);
}

// кадры позы: список сеток
function frames(species, pose, opt) {
    var n = ({ stand: 4, walk: 4, sit: 4, sleep: 2, jump: 1, idle: 4, work: 2, wait: 2 })[pose] || 1;
    var out = [];
    if (species === "fish") n = 2;
    for (var f = 0; f < n; f++) out.push(species === "fish" ? fish(f) : (species === "clawd" ? clawd(pose, f) : animal(pose, f, opt || {})));
    return out;
}

// окрасы: ключ → цвет; «o» — контур
var palettes = {
    // по фото: рыжий — насыщенный рыжий с тёмными полосками, светлая мордочка и грудка, жёлто-зелёные глаза
    ginger: { b: "#e39a52", s: "#c0682c", w: "#fbe4c6", p: "#e98f8a", e: "#b8c75a", k: "#2a160c", o: "#4a2612", d: "#c0682c" },
    // по фото: «белая» — светлая кремово-серая полосатая, тёмные хвост и спинка, светлые лапки, серо-голубые глаза, розовый нос
    white:  { b: "#e9e1d6", s: "#a99a88", w: "#fbf8f3", p: "#e8a3a6", e: "#8fb0c4", k: "#2b2723", o: "#5a5048", d: "#6b5f55" },
    corgi:  { b: "#d98a3f", s: "#a9652a", w: "#fff6ea", p: "#ff8fa0", e: "#2b1a10", k: "#1d120b", o: "#3a2414" },
    fox:    { b: "#e8742a", s: "#a8481a", w: "#fff4e8", p: "#2a1a12", e: "#2a1a12", k: "#1b100b", o: "#3a1d0e" },
    black:  { b: "#2d2b36", s: "#1d1c24", w: "#43414f", p: "#e58aa0", e: "#f2d14a", k: "#0c0b10", o: "#0c0b10" },
    goldfish: { b: "#ff9a2e", s: "#e0561c", w: "#ffd9a0", p: "#ff9a2e", e: "#101018", k: "#101018", o: "#5a2410" },
    bluefish: { b: "#4aa8ff", s: "#1f5fd1", w: "#bfe3ff", p: "#4aa8ff", e: "#101018", k: "#101018", o: "#0f2a5a" },
    clownfish:{ b: "#ff7a2e", s: "#ffffff", w: "#ffd2b0", p: "#ff7a2e", e: "#101018", k: "#101018", o: "#1a0f0a" },
    clawd:  { b: "#d97757", s: "#b85e41", w: "#f3d1c2", p: "#f3a48b", e: "#1b1110", k: "#1b1110", o: "#5a2c1f" }
};
