import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Виджеты рабочего стола: слой под окнами во весь экран. Набор, размер (S / M / L) и место — Config.widgets:
// виджет без сохранённого места стоит в колонке (слева или справа), перетащенный — где оставили.
//   правый клик по пустому столу — меню: расставить виджеты, «Добавить виджеты…» (отдельное окно со списком), обои, оформление, настройки
//   режим правки (shell.widgetsEdit, меню или панель «Рабочий стол»): перетаскивание с привязкой к сетке,
//   размер, выключить, добавить; Esc или «Готово» — выход. На время правки слой поднимается над окнами
PanelWindow {
    id: w
    property var shell: null
    readonly property bool edit: shell ? shell.widgetsEdit : false
    function done() { if (shell) shell.widgetsEdit = false; }

    screen: Compositor.mainScreen
    // солнечная система космических тем живёт в этом же слое: здесь окно принимает мышь
    readonly property bool space: Theme.cosmos === "solar" || Theme.cosmos === "apps"
    visible: cardsOn || space
    // карточки виджетов: включены в теме или идёт правка
    readonly property bool cardsOn: Theme.th.widgets === true || edit
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "nameless-widgets"
    WlrLayershell.layer: edit ? WlrLayer.Overlay : WlrLayer.Bottom
    // клавиатура — только при правке и пока пишется заметка
    WlrLayershell.keyboardFocus: edit || typing || addDlg.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    // клавиатура нужна, пока в каком-то виджете идёт ввод (заметка, город погоды)
    readonly property bool typing: {
        for (var i = 0; i < rep.count; i++) { var s = rep.itemAt(i); if (s && s.wantsKeys) return true; }
        return false;
    }

    // ---------- расстановка: привязка к краям соседей и экрана, без наложения ----------
    property string sel: ""          // выбранный в режиме правки: двигается стрелками
    property real guideX: -1         // направляющие во время перетаскивания
    property real guideY: -1
    readonly property int snapDist: 10
    function slots() { var out = []; for (var i = 0; i < rep.count; i++) { var s = rep.itemAt(i); if (s && s.shown) out.push(s); } return out; }
    // ближайшая к x линия привязки: края и центры соседей, поля экрана
    function snapTo(slot, x, y) {
        var xs = [16, w.width - slot.width - 16, (w.width - slot.width) / 2], ys = [top0, w.height - slot.height - 16];
        var gx = [16, w.width - 16, w.width / 2], gy = [top0, w.height - 16];
        var others = slots().filter(function (o) { return o !== slot; });
        for (var i = 0; i < others.length; i++) {
            var o = others[i];
            xs.push(o.x, o.x + o.width + 12, o.x - slot.width - 12, o.x + o.width - slot.width, o.x + (o.width - slot.width) / 2);
            gx.push(o.x, o.x + o.width + 6, o.x - 6, o.x + o.width, o.x + o.width / 2);
            ys.push(o.y, o.y + o.height + 12, o.y - slot.height - 12, o.y + o.height - slot.height);
            gy.push(o.y, o.y + o.height + 6, o.y - 6, o.y + o.height);
        }
        var r = { x: x, y: y, gx: -1, gy: -1 }, bx = snapDist + 1, by = snapDist + 1;
        for (var a = 0; a < xs.length; a++) { var d = Math.abs(xs[a] - x); if (d < bx) { bx = d; r.x = xs[a]; r.gx = gx[a]; } }
        for (var b = 0; b < ys.length; b++) { var e = Math.abs(ys[b] - y); if (e < by) { by = e; r.y = ys[b]; r.gy = gy[b]; } }
        if (r.gx < 0) r.x = Math.round(x / grid) * grid;
        if (r.gy < 0) r.y = Math.round(y / grid) * grid;
        r.x = Math.max(8, Math.min(w.width - slot.width - 8, r.x));
        r.y = Math.max(8, Math.min(w.height - slot.height - 8, r.y));
        return r;
    }
    // наложение: виджет сдвигается вниз под того, на кого лёг
    function freeSpot(slot, x, y) {
        var others = slots().filter(function (o) { return o !== slot; });
        for (var guard = 0; guard < 20; guard++) {
            var hit = null;
            for (var i = 0; i < others.length; i++) {
                var o = others[i];
                if (x < o.x + o.width + 6 && x + slot.width > o.x - 6 && y < o.y + o.height + 6 && y + slot.height > o.y - 6) { hit = o; break; }
            }
            if (!hit) return Qt.point(x, y);
            y = hit.y + hit.height + 12;
            if (y + slot.height > w.height - 8) return Qt.point(x, Math.max(8, w.height - slot.height - 8));
        }
        return Qt.point(x, y);
    }
    function slotOf(type) { for (var i = 0; i < rep.count; i++) { var s = rep.itemAt(i); if (s && s.it.type === type) return s; } return null; }
    // сетка: колонка по x и виджет той же колонки, перед которым встать по y
    function gridDrop(slot, cx, y) {
        var best = 0, bd = 1e9;
        for (var c = 0; c < cols; c++) { var d = Math.abs(colX(c) + cellW / 2 - cx); if (d < bd) { bd = d; best = c; } }
        var before = "";
        for (var i = 0; i < items.length; i++) {
            var m = gridMap[items[i].type];
            if (!m || items[i].type === slot.it.type || m.c !== best) continue;
            if (m.y + 20 > y) { before = items[i].type; break; }
        }
        return { col: best, before: before };
    }
    function nudge(dx, dy) {
        // сетка: стрелки влево-вправо — соседняя колонка, вверх-вниз — место в колонке
        if (gridMode) {
            var it = Config.item(sel); if (!it) return;
            var c = Math.max(0, Math.min(cols - 1, (it.col || 0) + (dx > 0 ? 1 : dx < 0 ? -1 : 0) * (right ? -1 : 1)));
            if (dx !== 0) { Config.gridMove(sel, c, ""); return; }
            var same = items.filter(function (x) { var m = gridMap[x.type]; return m && m.c === (it.col || 0); });
            var k = -1; for (var i = 0; i < same.length; i++) if (same[i].type === sel) k = i;
            var j = k + (dy > 0 ? 1 : -1);
            if (j < 0 || j >= same.length) return;
            Config.gridMove(sel, it.col || 0, dy > 0 ? (same[j + 1] ? same[j + 1].type : "") : same[j].type);
            return;
        }
        var s = slotOf(sel); if (!s) return;
        var nx = Math.max(8, Math.min(w.width - s.width - 8, s.x + dx)), ny = Math.max(top0, Math.min(w.height - s.height - 8, s.y + dy));
        Config.placeWidget(sel, nx, ny, nx / w.width, ny / w.height);
    }

    readonly property var files: ({ clock: "WClock.qml", system: "WSystem.qml", player: "WPlayer.qml", calendar: "WCalendar.qml",
                                    notifs: "WNotifs.qml", weather: "WWeather.qml", notes: "WNotes.qml", timer: "WTimer.qml",
                                    actions: "WActions.qml", photo: "WPhoto.qml", updates: "WUpdates.qml", countdown: "WCountdown.qml", agents: "WAgents.qml", claude: "WClaude.qml", tokens: "WTokens.qml", orbit: "WOrbit.qml", touch: "WTouch.qml",
                                    pets: "WPets.qml", clawd: "WClawd.qml", gif: "WGif.qml",
                                    fish: "WFish.qml", moon: "WMoon.qml", quote: "WQuote.qml" })
    readonly property var items: Config.widgets.items
    readonly property bool right: Config.widgets.side === "right"
    readonly property int top0: 56            // под баром
    // ---------- сетка ----------
    // режимы расстановки: auto — по рядам на всю ширину экрана, grid — сетка по двум осям (узлы с шагом pitch),
    // columns — колонки списком, free — свободно
    readonly property string layoutMode: Config.widgets.layout || "auto"
    readonly property bool autoMode: layoutMode === "auto"
    readonly property bool gridMode: layoutMode === "columns"
    readonly property bool grid2: layoutMode === "grid"
    readonly property int pitch: 84
    function snapCell(v, lo, hi) { return Math.max(lo, Math.min(hi, 16 + Math.round((v - 16) / pitch) * pitch)); }
    // узел сетки без наложения: если занят — следующий узел вниз, затем следующая колонка
    function freeCell(slot, x, y) {
        var others = slots().filter(function (o) { return o !== slot; });
        function hits(px, py) {
            for (var i = 0; i < others.length; i++) {
                var o = others[i];
                if (px < o.x + o.width + 4 && px + slot.width > o.x - 4 && py < o.y + o.height + 4 && py + slot.height > o.y - 4) return true;
            }
            return false;
        }
        for (var cx = x, pass = 0; pass < 24; pass++) {
            for (var cy = y; cy + slot.height <= height - 8; cy += pitch) if (!hits(cx, cy)) return Qt.point(cx, cy);
            cx += pitch; if (cx + slot.width > width - 8) cx = 16;
            y = top0 + 4;
        }
        return Qt.point(x, y);
    }
    readonly property real cellW: fixedGrid ? (width - 32 - (fixedCols - 1) * gap) / fixedCols : 300 * ws
    readonly property real gap: 16 * ws
    readonly property int cols: fixedGrid ? fixedCols : Math.max(1, Math.floor((width - 32 + gap) / (cellW + gap)))
    // колонка по номеру: от левого края или, если колонки справа, от правого
    function colX(c) { return right ? width - 16 - (c + 1) * cellW - c * gap : 16 + c * (cellW + gap); }
    function spanOf(it) { return it.size === "L" ? 2 : 1; }
    // раскладка: виджеты по порядку списка, каждый — в свою колонку, под предыдущими (широкий — на две)
    readonly property var gridMap: {
        var h = [], out = {}, i, c;
        for (c = 0; c < cols; c++) h.push(top0);
        for (i = 0; i < items.length; i++) {
            var it = items[i], s = rep.count > i ? rep.itemAt(i) : null;
            if (!s || !s.shown) continue;
            var sp = Math.min(cols, spanOf(it));
            c = Math.max(0, Math.min(cols - sp, it.col === undefined ? 0 : it.col));
            var y = h[c];
            for (var k = 1; k < sp; k++) y = Math.max(y, h[c + k]);
            out[it.type] = { x: right ? colX(c + sp - 1) : colX(c), y: y, w: sp * cellW + (sp - 1) * gap, c: c };
            for (k = 0; k < sp; k++) h[c + k] = y + s.height + 12;
        }
        return out;
    }
    // сетка по двум осям: места всех виджетов разом — по порядку, каждый в ближайший свободный узел к желаемому
    // (сохранённому или следующему в колонке); занятые узлы пропускаются, поэтому виджеты не наслаиваются
    readonly property var grid2Map: {
        if (!grid2) return {};
        var out = {}, taken = [], autoY = top0;
        function hit(x, y, wd, ht) {
            for (var k = 0; k < taken.length; k++) {
                var t = taken[k];
                if (x < t.x + t.w + 4 && x + wd > t.x - 4 && y < t.y + t.h + 4 && y + ht > t.y - 4) return true;
            }
            return false;
        }
        for (var i = 0; i < items.length; i++) {
            var it = items[i], sl = rep.count > i ? rep.itemAt(i) : null;
            if (!sl || !sl.shown) continue;
            var wd = sl.width, ht = sl.height, placedIt = it.x !== undefined && it.y !== undefined;
            var x = snapCell(placedIt ? it.x : (right ? width - wd - 16 : 16), 16, width - wd - 8);
            var y = snapCell(placedIt ? it.y : autoY, top0, height - ht - 8);
            // свободный узел: вниз по колонке, затем следующая колонка
            for (var guard = 0; guard < 400 && hit(x, y, wd, ht); guard++) {
                y += pitch;
                if (y + ht > height - 8) { y = top0; x += pitch; if (x + wd > width - 8) x = 16; }
            }
            out[it.type] = { x: x, y: y };
            taken.push({ x: x, y: y, w: wd, h: ht });
            if (!placedIt) autoY = y + Math.ceil((ht + 4) / pitch) * pitch;
        }
        return out;
    }

    // ---------- свободно: места по долям экрана, без наложений ----------
    readonly property bool freeMode: layoutMode === "free"
    // прямоугольник занят кем-то из списка (с зазором 6)
    function overlaps(x, y, wd, ht, rects) {
        for (var k = 0; k < rects.length; k++) {
            var t = rects[k];
            if (x < t.x + t.w + 6 && x + wd > t.x - 6 && y < t.y + t.h + 6 && y + ht > t.y - 6) return true;
        }
        return false;
    }
    // ближайшее к (x, y) свободное место: кольцами с шагом 12 во все стороны, в пределах экрана и под баром
    function nearestFree(x, y, wd, ht, rects) {
        var minX = 8, maxX = Math.max(8, width - wd - 8), minY = top0, maxY = Math.max(top0, height - ht - 8);
        x = Math.max(minX, Math.min(maxX, x)); y = Math.max(minY, Math.min(maxY, y));
        if (!overlaps(x, y, wd, ht, rects)) return Qt.point(x, y);
        for (var r = 1; r < 90; r++) {
            var best = null, bd = 1e12;
            for (var i = -r; i <= r; i++) for (var j = -r; j <= r; j++) {
                if (Math.abs(i) !== r && Math.abs(j) !== r) continue;          // только кольцо
                var cx = x + i * 12, cy = y + j * 12;
                if (cx < minX || cx > maxX || cy < minY || cy > maxY || overlaps(cx, cy, wd, ht, rects)) continue;
                var d = i * i + j * j;
                if (d < bd) { bd = d; best = Qt.point(cx, cy); }
            }
            if (best) return best;
        }
        return Qt.point(x, y);
    }
    // места всех: сначала поставленные (по долям экрана; старые настройки — по пикселям), затем остальные — в первое свободное
    // место колонкой от своего края
    readonly property var freeMap: {
        if (!freeMode || width <= 0) return {};
        var out = {}, taken = [], rest = [], i, it, sl;
        for (i = 0; i < items.length; i++) {
            it = items[i]; sl = rep.count > i ? rep.itemAt(i) : null;
            if (!sl || !sl.shown) continue;
            if (it.x === undefined && it.rx === undefined) { rest.push(i); continue; }
            var px = it.rx !== undefined ? it.rx * width : it.x, py = it.ry !== undefined ? it.ry * height : it.y;
            var p = nearestFree(px, py, sl.width, sl.height, taken);
            out[it.type] = p; taken.push({ x: p.x, y: p.y, w: sl.width, h: sl.height });
        }
        for (var k = 0; k < rest.length; k++) {
            it = items[rest[k]]; sl = rep.itemAt(rest[k]);
            var q = nearestFree(right ? width - sl.width - 16 : 16, top0, sl.width, sl.height, taken);
            out[it.type] = q; taken.push({ x: q.x, y: q.y, w: sl.width, h: sl.height });
        }
        return out;
    }
    // занятое другими (для отпускания перетаскиваемого)
    function othersRects(slot) {
        var out = [];
        slots().forEach(function (o) { if (o !== slot) out.push({ x: o.baseX, y: o.baseY, w: o.width, h: o.height }); });
        return out;
    }
    property var ghost: null                // куда встанет перетаскиваемый (свободно): рамка-подсказка

    // ---------- по рядам: раскладка под любой экран ----------
    // колонок столько, сколько помещается по ширине (не больше, чем виджетов), ширина колонки растягивается поровну (до 400),
    // весь блок по центру; виджет встаёт в самую короткую колонку — ряды выходят ровными, без пустой полосы с одного края
    // масштаб виджетов: «авто» — по логическому размеру экрана (масштаб монитора уже учтён), за основу — Full HD; или число из настроек
    readonly property var scaleOpt: Config.widgets.scale
    // заданное число колонок или рядов (0 — авто): колонок = заданное или «виджетов ÷ рядов»;
    // ширина колонки — поровну на всю ширину экрана, масштаб виджетов подбирается под неё (колонка = 300 точек виджета)
    readonly property int wantCols: Math.max(0, Math.min(10, Config.widgets.cols || 0))
    readonly property int wantRows: Math.max(0, Math.min(6, Config.widgets.rows || 0))
    readonly property bool fixedGrid: (autoMode || gridMode) && (wantCols > 0 || wantRows > 0)
    // считаются только видимые: пустой виджет (плеер без музыки) колонку не занимает
    readonly property int shownCount: { var n = 0; for (var i = 0; i < rep.count; i++) { var s = rep.itemAt(i); if (s && s.shown) n++; } return Math.max(1, n); }
    readonly property int fixedCols: wantCols > 0 ? wantCols : Math.max(1, Math.ceil(shownCount / Math.max(1, wantRows)))
    readonly property real fixedColW: Math.max(160, (width - 32 - (fixedCols - 1) * 16) / fixedCols)
    readonly property real ws: fixedGrid && width > 0 ? Math.max(0.6, Math.min(2.2, fixedColW / 300))
                               : ((scaleOpt === undefined || scaleOpt === "auto") && width > 0 && height > 0
                                  ? Math.max(0.85, Math.min(1.5, Math.min(width / 1920, height / 1080)))
                                  : Math.max(0.6, Math.min(2, Number(scaleOpt) || 1)))
    // выравнивание рядов: left — прижаты влево, center — по центру, right — вправо, fill — колонки на всю ширину экрана
    readonly property string align: Config.widgets.align || "center"
    readonly property real autoMin: 280 * ws
    // «на всю ширину»: колонок — сколько помещается, независимо от числа виджетов; иначе — не больше, чем виджетов
    readonly property int fitCols: Math.max(1, Math.floor((width - 32 + gap) / (autoMin + gap)))
    readonly property int autoCols: fixedGrid ? fixedCols : (align === "fill" ? fitCols : Math.max(1, Math.min(shownCount, fitCols)))
    // ширина колонки не меньше autoMin: пока окно слоя ещё без размера (ширина 0), формула давала отрицательную ширину,
    // часы считали по ней свою высоту и застревали полоской; кроме «на всю ширину» — не шире 400 (с масштабом)
    readonly property real autoW: fixedGrid ? (width - 32 - (autoCols - 1) * gap) / autoCols
                                  : Math.max(autoMin, Math.min(align === "fill" ? 1e6 : 400 * ws, (width - 32 - (autoCols - 1) * gap) / autoCols))
    readonly property real autoTotal: autoCols * autoW + (autoCols - 1) * gap
    readonly property real autoX0: fixedGrid || align === "left" || align === "fill" ? 16 : (align === "right" ? width - 16 - autoTotal : (width - autoTotal) / 2)
    readonly property var autoMap: {
        if (!autoMode) return {};
        var h = [], out = {}, c, i;
        for (c = 0; c < autoCols; c++) h.push(top0);
        for (i = 0; i < items.length; i++) {
            var it = items[i], s = rep.count > i ? rep.itemAt(i) : null;
            if (!s || !s.shown) continue;
            var sp = Math.min(autoCols, spanOf(it)), best = 0, by = 1e9;
            // самая низкая «крыша» среди подходящих мест (для широкого — по двум колонкам)
            for (c = 0; c + sp <= autoCols; c++) {
                var y = h[c];
                for (var k = 1; k < sp; k++) y = Math.max(y, h[c + k]);
                if (y < by - 0.5) { by = y; best = c; }
            }
            out[it.type] = { x: autoX0 + best * (autoW + gap), y: by };
            for (k = 0; k < sp; k++) h[best + k] = by + s.height + gap;
        }
        return out;
    }
    // перетаскивание по рядам: встать перед виджетом, ближайшим к точке отпускания
    function autoDrop(type, cx, cy) {
        var best = "", bd = 1e12;
        for (var t in autoMap) {
            if (t === type) continue;
            var s = slotOf(t); if (!s) continue;
            var d = Math.pow(autoMap[t].x + s.width / 2 - cx, 2) + Math.pow(autoMap[t].y + s.height / 2 - cy, 2);
            if (d < bd) { bd = d; best = t; }
        }
        return best;
    }

    // куда встанет перетаскиваемый в сетке: колонка под курсором и виджет, перед которым
    property var dropAt: null
    readonly property int grid: 8

    // ---------- фон режима правки и меню стола ----------
    Rectangle { anchors.fill: parent; color: "black"; opacity: w.edit ? 0.35 : 0; Behavior on opacity { NumberAnimation { duration: 200 } } }
    // сетка привязки
    Canvas {
        anchors.fill: parent
        visible: w.edit && !w.gridMode && !w.autoMode
        onVisibleChanged: if (visible) requestPaint()
        readonly property bool g2: w.grid2
        onG2Changed: requestPaint()
        onPaint: {
            var ctx = getContext("2d"); ctx.reset();
            var st = w.grid2 ? w.pitch : w.grid * 4, x0 = w.grid2 ? 16 : 0, y0 = w.grid2 ? w.top0 : 0;
            ctx.fillStyle = Qt.rgba(1, 1, 1, w.grid2 ? 0.22 : 0.08);
            for (var x = x0; x < width; x += st) for (var y = y0; y < height; y += st) ctx.fillRect(x - 1, y - 1, w.grid2 ? 3 : 1.5, w.grid2 ? 3 : 1.5);
        }
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => {
            if (menu.visible) { menu.visible = false; return; }
            if (addDlg.visible) { addDlg.visible = false; return; }
            if (m.button === Qt.RightButton) menu.show(m.x, m.y);
            else if (w.edit) w.done();
        }
    }

    // космос: солнечная система или приложения на орбитах — загружается только нужный
    Loader {
        anchors.fill: parent
        active: w.space
        enabled: !w.edit
        source: Theme.cosmos === "apps" ? "AppSpace.qml" : "Space.qml"
    }

    // ---------- виджеты ----------
    // колонка: позиции виджетов без сохранённого места, одна под другой
    function autoY(index) {
        var y = top0;
        for (var i = 0; i < index; i++) {
            var it = items[i], slot = rep.itemAt(i);
            if (!it.on || it.x !== undefined || !slot || !slot.shown) continue;
            // сетка по двум осям: каждый занимает целое число узлов, иначе после привязки они наложились бы
            y += grid2 ? Math.ceil((slot.height + 4) / pitch) * pitch : slot.height + 12;
        }
        return y;
    }

    Repeater {
        id: rep
        // модель — число пунктов: при изменении настроек виджеты переиспользуются, а не создаются заново
        model: w.items.length
        Item {
            id: slot
            required property int index
            readonly property var it: w.items[index] || ({})
            readonly property bool placed: it.x !== undefined && it.y !== undefined
            readonly property bool shown: w.cardsOn && it.on === true && loader.status === Loader.Ready && loader.item.empty !== true
            visible: shown
            readonly property var cell: w.gridMode ? (w.gridMap[it.type] || null) : null
            // ширина — только из размера: от раскладки её брать нельзя (раскладка зависит от высоты, а та — от ширины)
            readonly property int span: Math.min(w.cols, w.spanOf(it))
            readonly property int aspan: Math.min(w.autoCols, w.spanOf(it))
            width: w.autoMode ? aspan * w.autoW + (aspan - 1) * w.gap : (w.gridMode ? span * w.cellW + (span - 1) * w.gap : (Config.sizes[it.size || "M"] || 300) * w.ws)
            // высота — из виджета, но отложенно (Qt.callLater): ширина в раскладке «по рядам» зависит от числа видимых виджетов,
            // а та — от загрузки соседей; прямая привязка ловила цикл, и Qt оставлял высоту от прежней ширины (часы вылезали за карточку)
            height: 0
            function syncHeight() { height = loader.item ? Math.max(0, loader.item.implicitHeight) * w.ws : 0; }
            Connections { target: loader.item; ignoreUnknownSignals: true; function onImplicitHeightChanged() { Qt.callLater(slot.syncHeight); } }
            // место по настройкам; во время перетаскивания — плюс смещение жеста
            readonly property real freeX: placed ? Math.min(it.x, w.width - width - 8) : (w.right ? w.width - width - 16 : 16)
            readonly property real freeY: placed ? Math.min(it.y, w.height - height - 8) : w.autoY(index)
            readonly property var g2: w.grid2 ? (w.grid2Map[it.type] || null) : null
            readonly property var am: w.autoMode ? (w.autoMap[it.type] || null) : null
            readonly property var fm: w.freeMode ? (w.freeMap[it.type] || null) : null
            readonly property real baseX: am ? am.x : (cell ? cell.x : (g2 ? g2.x : (fm ? fm.x : freeX)))
            readonly property real baseY: am ? am.y : (cell ? cell.y : (g2 ? g2.y : (fm ? fm.y : freeY)))
            // во время перетаскивания — с привязкой к соседям и краям экрана
            // свободно — с привязкой к соседям и краям; в сетке виджет просто следует за курсором
            readonly property var snapped: !drag.active ? null
                : (w.gridMode || w.autoMode ? { x: baseX + drag.activeTranslation.x, y: baseY + drag.activeTranslation.y, gx: -1, gy: -1 }
                : (w.grid2 ? { x: w.snapCell(baseX + drag.activeTranslation.x, 16, w.width - width - 8), y: w.snapCell(baseY + drag.activeTranslation.y, w.top0, w.height - height - 8), gx: -1, gy: -1 }
                : w.snapTo(slot, baseX + drag.activeTranslation.x, baseY + drag.activeTranslation.y)))
            onSnappedChanged: if (snapped) {
                w.guideX = snapped.gx; w.guideY = snapped.gy;
                if (w.gridMode) w.dropAt = w.gridDrop(slot, snapped.x + width / 2, snapped.y);
                if (w.freeMode) { var gp = w.nearestFree(snapped.x, snapped.y, width, height, w.othersRects(slot)); w.ghost = { x: gp.x, y: gp.y, w: width, h: height }; }
            }
            x: snapped ? snapped.x : baseX
            y: snapped ? snapped.y : baseY
            z: drag.active ? 5 : 0
            Behavior on x { enabled: !drag.active; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !drag.active; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            // виджет рисуется в своём размере и увеличивается целиком (масштаб ws): шрифты, отступы и рамки — в одной пропорции
            onWidthChanged: Qt.callLater(slot.syncHeight)
            Connections { target: w; function onWsChanged() { Qt.callLater(slot.syncHeight); } }
            Loader {
                id: loader
                width: slot.width / w.ws
                height: slot.height / w.ws
                scale: w.ws
                transformOrigin: Item.TopLeft
                active: slot.it.on === true && w.cardsOn
                source: w.files[slot.it.type] || ""
                asynchronous: true
                onLoaded: slot.syncHeight()
                onItemChanged: Qt.callLater(slot.syncHeight)
                // при правке кнопки виджета не перехватывают перетаскивание
                enabled: !w.edit
            }
            readonly property bool wantsKeys: loader.item !== null && loader.item.editing === true

            // правка: выбранный — рамка акцента и свечение, остальные — тонкая рамка; при перетаскивании — подъём
            readonly property bool picked: drag.active || w.sel === slot.it.type
            Rectangle {
                visible: w.edit && slot.picked
                anchors.fill: parent
                anchors.margins: -10
                radius: (Theme.ios ? 30 : 24) + 6
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, drag.active ? 0.16 : 0.08)
            }
            Rectangle {
                visible: w.edit
                anchors.fill: parent
                anchors.margins: -4
                radius: Theme.ios ? 30 : 24
                color: "transparent"
                border.width: slot.picked ? 2.5 : 1
                border.color: slot.picked ? Theme.accent : Qt.rgba(1, 1, 1, editHov.hovered ? 0.55 : 0.28)
            }
            scale: drag.active ? 1.03 : 1
            Behavior on scale { NumberAnimation { duration: 140 } }
            HoverHandler { id: editHov; enabled: w.edit; cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
            // правый клик по виджету — его меню (и в обычном режиме); левый в правке — выбрать для стрелок
            TapHandler { acceptedButtons: Qt.RightButton; gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: (ev) => { var p = slot.mapToItem(null, ev.position.x, ev.position.y); menu.showFor(slot.it.type, p.x, p.y); } }
            TapHandler { enabled: w.edit; onTapped: w.sel = slot.it.type }
            DragHandler {
                id: drag
                enabled: w.edit
                target: null
                // смещение запоминается до сброса жеста: после отпускания activeTranslation обнуляется
                property real lx: 0
                property real ly: 0
                onActiveTranslationChanged: if (active) { lx = activeTranslation.x; ly = activeTranslation.y; }
                onActiveChanged: {
                    if (active) { w.sel = slot.it.type; return; }
                    w.guideX = -1; w.guideY = -1;
                    // по рядам: меняется только порядок — встать перед ближайшим к точке отпускания
                    if (w.autoMode) {
                        var before = w.autoDrop(slot.it.type, slot.baseX + lx + slot.width / 2, slot.baseY + ly + slot.height / 2);
                        if (before !== "") Config.gridMove(slot.it.type, slot.it.col || 0, before);
                        return;
                    }
                    if (w.gridMode) {
                        // сетка: в колонку под курсором, перед виджетом ниже точки отпускания
                        var t = w.gridDrop(slot, slot.baseX + lx + slot.width / 2, slot.baseY + ly);
                        w.dropAt = null;
                        Config.gridMove(slot.it.type, t.col, t.before);
                        return;
                    }
                    // сетка по двум осям: ближайший свободный узел
                    if (w.grid2) {
                        var c = w.freeCell(slot, w.snapCell(slot.baseX + lx, 16, w.width - slot.width - 8), w.snapCell(slot.baseY + ly, w.top0, w.height - slot.height - 8));
                        Config.placeWidget(slot.it.type, c.x, c.y);
                        return;
                    }
                    // свободно: привязка, затем свободное место без наложения
                    // свободно: привязка, затем ближайшее свободное место (во все стороны), место — и в долях экрана
                    var r = w.snapTo(slot, slot.baseX + lx, slot.baseY + ly), f = w.nearestFree(r.x, r.y, slot.width, slot.height, w.othersRects(slot));
                    w.ghost = null;
                    Config.placeWidget(slot.it.type, f.x, f.y, f.x / w.width, f.y / w.height);
                }
            }
            // кнопки виджета — плашкой внутри правого верхнего угла, только у наведённого или выбранного:
            // раньше ряд под каждым виджетом наезжал на соседей
            Row {
                visible: w.edit && (editHov.hovered || slot.picked) && !drag.active
                anchors { right: parent.right; top: parent.top; margins: 8 }
                spacing: 3
                z: 3
                Repeater {
                    model: ["S", "M", "L"]
                    Chip {
                        required property string modelData
                        text: modelData
                        on: (slot.it.size || "M") === modelData
                        onClicked: Config.setItem(slot.it.type, "size", modelData)
                    }
                }
                Chip { text: "󰒓"; icon: true; onClicked: if (w.shell) { w.done(); w.shell.openWidgetSettings(slot.it.type); } }
                Chip { text: "󰅖"; icon: true; danger: true; onClicked: Config.setItem(slot.it.type, "on", false) }
            }
            Rectangle {
                visible: w.edit
                anchors { left: parent.left; bottom: parent.top; bottomMargin: 8 }
                z: 3
                width: tag.implicitWidth + 16; height: 22; radius: 11
                color: slot.picked ? Theme.accent : Qt.rgba(0, 0, 0, 0.6)
                Text { id: tag; anchors.centerIn: parent; text: (Config.kinds[slot.it.type] || {}).name || ""; color: "white"; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
            }
        }
    }

    // ---------- панель правки ----------
    Rectangle {
        visible: w.edit
        // внизу по центру: сверху обычно стоят виджеты
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 110 }
        width: bar.implicitWidth + 16; height: 48
        radius: 24
        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.94)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.15)
        Row {
            id: bar
            anchors.centerIn: parent
            spacing: 6
            Text { anchors.verticalCenter: parent.verticalCenter; leftPadding: 8; rightPadding: 6; text: Tr.t("Перетаскивайте · стрелки сдвигают выбранный"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
            GSegment {
                ui: Theme; width: 320
                anchors.verticalCenter: parent.verticalCenter
                options: [{ v: "grid", t: Tr.t("Сетка"), icon: "󰕰" }, { v: "columns", t: Tr.t("Колонки"), icon: "󰕭" }, { v: "free", t: Tr.t("Свободно"), icon: "󰆾" }]
                value: w.layoutMode
                onPicked: (v) => Config.set("widgets.layout", v)
            }
            GButton { ui: Theme; height: 36; icon: "󰐕"; label: Tr.t("Добавить"); onClicked: addDlg.open() }
            GButton { visible: !w.gridMode; ui: Theme; height: 36; icon: "󰕰"; label: Tr.t("Сбросить места"); onClicked: Config.unplaceWidgets() }
            GButton { ui: Theme; height: 36; icon: "󰒓"; label: Tr.t("Настройки"); onClicked: { w.done(); if (w.shell) w.shell.openDesktop(0); } }
            GButton { ui: Theme; height: 36; icon: "󰄬"; label: Tr.t("Готово"); on: true; onClicked: w.done() }
        }
    }
    // правка с клавиатуры: стрелки — сдвиг выбранного виджета на 8 px (с Shift — на 32), Esc — выход
    Item {
        focus: w.edit
        Keys.onEscapePressed: { if (menu.visible) menu.visible = false; else if (addDlg.visible) addDlg.visible = false; else w.done(); }
        Keys.onPressed: (e) => {
            var st = w.grid2 ? w.pitch : ((e.modifiers & Qt.ShiftModifier) ? 32 : 8);
            if (e.key === Qt.Key_Left) w.nudge(-st, 0); else if (e.key === Qt.Key_Right) w.nudge(st, 0);
            else if (e.key === Qt.Key_Up) w.nudge(0, -st); else if (e.key === Qt.Key_Down) w.nudge(0, st);
            else return;
            e.accepted = true;
        }
    }
    // сетка: колонка, куда встанет перетаскиваемый
    Rectangle {
        visible: w.edit && w.gridMode && w.dropAt !== null
        x: w.dropAt ? w.colX(w.dropAt.col) : 0
        y: w.top0 - 6
        width: w.cellW; height: w.height - w.top0 - 100
        radius: 22
        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08)
        border.width: 1.5; border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
    }
    // сетка: контуры колонок при правке
    Repeater {
        model: w.edit && w.gridMode ? w.cols : 0
        Rectangle {
            required property int index
            x: w.colX(index); y: w.top0 - 6
            width: w.cellW; height: w.height - w.top0 - 100
            radius: 22
            color: "transparent"
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
        }
    }
    // направляющие привязки
    Rectangle { visible: w.edit && w.guideX >= 0; x: w.guideX; width: 1; height: w.height; color: Theme.accent; opacity: 0.8; z: 4 }
    // свободно: где встанет перетаскиваемый виджет
    Rectangle {
        visible: w.edit && w.freeMode && w.ghost !== null
        x: w.ghost ? w.ghost.x : 0; y: w.ghost ? w.ghost.y : 0
        width: w.ghost ? w.ghost.w : 0; height: w.ghost ? w.ghost.h : 0
        radius: Theme.ios ? 26 : 20; z: 3
        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
        border.width: 2; border.color: Theme.accent
    }
    Rectangle { visible: w.edit && w.guideY >= 0; y: w.guideY; height: 1; width: w.width; color: Theme.accent; opacity: 0.8; z: 4 }

    // меню закрывается, как только работа ушла с рабочего стола: курсор на баре или в окне (слой стола
    // перестаёт получать курсор), сменилось активное окно или рабочий стол
    HoverHandler {
        id: deskHover
        onHoveredChanged: if (!hovered && menu.visible) leaveT.restart(); else leaveT.stop()
    }
    Timer { id: leaveT; interval: 250; onTriggered: if (!deskHover.hovered) menu.visible = false }
    Connections {
        target: Compositor.hyprland ? Hyprland : null
        function onRawEvent(e) {
            if (["activewindow", "activewindowv2", "workspace", "workspacev2", "openwindow", "focusedmon"].indexOf(e.name) < 0) return;
            menu.visible = false;
            addDlg.visible = false;
        }
    }

    // ---------- меню рабочего стола ----------
    Item {
        id: menu
        visible: false
        z: 10
        width: 250
        height: mcol.implicitHeight + 16
        property string forType: ""
        readonly property var forItem: forType !== "" ? Config.item(forType) : null
        function showFor(type, px, py) { forType = type; place(px, py); }
        function show(px, py) { forType = ""; place(px, py); }
        function place(px, py) {
            x = Math.min(px, w.width - width - 8);
            y = Math.min(py, w.height - height - 8);
            visible = true;
        }
        function run(f) { visible = false; f(); }

        Rectangle {
            anchors.fill: parent
            radius: Theme.r(16)
            color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.97)
            border.width: 1
            border.color: Theme.glass ? Qt.rgba(1, 1, 1, 0.16) : Theme.line(0.22)
        }
        Column {
            id: mcol
            x: 8; y: 8
            width: parent.width - 16
            spacing: 2
            // ----- меню виджета -----
            Text { visible: menu.forType !== ""; width: parent.width; leftPadding: 10; topPadding: 4; bottomPadding: 4; text: (Config.kinds[menu.forType] || {}).name || ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
            MenuRow { visible: menu.forType !== ""; icon: "󰒓"; label: Tr.t("Настроить…"); onClicked: { var t = menu.forType; menu.run(function () { w.done(); if (w.shell) w.shell.openWidgetSettings(t); }); } }
            Row {
                visible: menu.forType !== ""
                x: 8; spacing: 4
                Text { anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Размер"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; rightPadding: 6 }
                Repeater {
                    model: ["S", "M", "L"]
                    Chip {
                        required property string modelData
                        text: modelData
                        on: menu.forItem !== null && (menu.forItem.size || "M") === modelData
                        onClicked: Config.setItem(menu.forType, "size", modelData)
                    }
                }
            }
            MenuRow { visible: menu.forType !== "" && !w.edit; icon: "󰆾"; label: Tr.t("Переместить"); onClicked: { var t = menu.forType; menu.run(function () { w.sel = t; if (w.shell) w.shell.widgetsEdit = true; }); } }
            MenuRow { visible: menu.forType !== "" && menu.forItem !== null && menu.forItem.x !== undefined; icon: "󰕰"; label: Tr.t("Вернуть в колонку"); onClicked: { var t = menu.forType; menu.run(function () { Config.setItem(t, "x", undefined); Config.setItem(t, "y", undefined); }); } }
            MenuRow { visible: menu.forType !== ""; icon: "󰅖"; danger: true; label: Tr.t("Убрать с рабочего стола"); onClicked: { var t = menu.forType; menu.run(function () { Config.setItem(t, "on", false); }); } }
            Rectangle { visible: menu.forType !== ""; width: parent.width; height: 1; color: Theme.fill(0.12) }
            // ----- меню стола -----
            MenuRow { icon: "󰙵"; label: w.edit ? Tr.t("Закончить правку") : Tr.t("Расставить виджеты"); onClicked: menu.run(function () { if (w.shell) w.shell.widgetsEdit = !w.edit; }) }
            MenuRow { icon: "󰒓"; label: Tr.t("Виджеты и док…"); onClicked: menu.run(function () { if (w.shell) { w.done(); w.shell.openDesktop(0); } }) }
            MenuRow { icon: "󰸉"; label: Tr.t("Следующие обои"); onClicked: menu.run(function () { Quickshell.execDetached([Theme.script, "action", "wallpaper-next"]); }) }
            MenuRow { icon: "󰏘"; label: Tr.t("Оформление"); onClicked: menu.run(function () { Quickshell.execDetached([Theme.script, "action", "drawer"]); }) }
            Rectangle { width: parent.width; height: 1; color: Theme.fill(0.12) }
            // список виджетов — не в меню, а во втором окне
            MenuRow { icon: "󰐕"; label: Tr.t("Добавить виджеты…"); onClicked: menu.run(function () { addDlg.open(); }) }
        }
    }

    // ---------- окно «Добавить виджеты» ----------
    // по центру стола: плитки выключенных виджетов (значок, имя, описание); нажатие ставит виджет на стол,
    // окно остаётся открытым — можно добавить несколько подряд. Закрытие: крестик, Esc, клик по столу
    Item {
        id: addDlg
        visible: false
        z: 11
        width: Math.min(640, w.width - 48)
        height: Math.min(dcol.implicitHeight + 32, w.height - 160)
        anchors.centerIn: parent
        readonly property var off: w.items.filter(function (x) { return !x.on; })
        function open() { menu.visible = false; visible = true; forceActiveFocus(); }
        Keys.onEscapePressed: visible = false

        // фон-подложка не нужна: клик мимо окна ловит MouseArea стола и закрывает его
        Rectangle {
            anchors.fill: parent
            radius: Theme.r(22)
            color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.97)
            border.width: 1
            border.color: Theme.glass ? Qt.rgba(1, 1, 1, 0.16) : Theme.line(0.22)
        }
        // поглощает клики внутри окна, чтобы они не закрывали его через стол
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

        Column {
            id: dcol
            x: 16; y: 16
            width: parent.width - 32
            spacing: 12
            Item {
                width: parent.width; height: 32
                Text { anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Добавить виджеты"); color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold }
                Chip { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: "󰅖"; icon: true; onClicked: addDlg.visible = false }
            }
            Text { visible: addDlg.off.length === 0; width: parent.width; padding: 10; text: Tr.t("Все виджеты уже на столе"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 13 }
            Flickable {
                visible: addDlg.off.length > 0
                width: parent.width
                height: Math.min(grid.implicitHeight, w.height - 260)
                contentHeight: grid.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Grid {
                    id: grid
                    width: parent.width
                    columns: width > 460 ? 2 : 1
                    spacing: 8
                    Repeater {
                        model: addDlg.off
                        Rectangle {
                            id: tile
                            required property var modelData
                            readonly property var kind: Config.kinds[modelData.type] || ({ name: modelData.type, icon: "", about: "" })
                            width: (grid.width - (grid.columns - 1) * grid.spacing) / grid.columns
                            height: 64
                            radius: Theme.r(14)
                            color: tma.containsMouse ? Theme.fill(0.14) : Theme.fill(0.06)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text { id: tic; x: 14; width: 24; anchors.verticalCenter: parent.verticalCenter; text: tile.kind.icon; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 22 }
                            Column {
                                anchors { left: tic.right; leftMargin: 10; right: tadd.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                spacing: 2
                                Text { width: parent.width; text: Tr.t(tile.kind.name); elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                                Text { width: parent.width; text: Tr.t(tile.kind.about); elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap; color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                            }
                            Text { id: tadd; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } text: "󰐕"; color: tma.containsMouse ? Theme.accent : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 18 }
                            MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Config.setItem(tile.modelData.type, "on", true) }
                        }
                    }
                }
            }
        }
    }

    // кнопка-ярлык правки
    component Chip: Rectangle {
        id: ch
        property alias text: ct.text
        property bool on: false
        property bool icon: false
        property bool danger: false
        signal clicked
        width: Math.max(28, ct.implicitWidth + 14); height: 28; radius: 14
        color: on ? Theme.accent : (danger ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.85) : Qt.rgba(0, 0, 0, 0.6))
        Text { id: ct; anchors.centerIn: parent; color: "white"; font.family: ch.icon ? Theme.iconFont : Theme.font; font.pixelSize: ch.icon ? 14 : 12; font.weight: Font.DemiBold }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
    }
}
