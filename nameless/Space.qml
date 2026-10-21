import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Солнечная система (космос темы — solar; параметры — Config.store.space): живёт в слое виджетов над звёздным небом.
//   колесо — масштаб к курсору, перетаскивание — обзор, двойной клик по пустому месту — исходный вид
//   кнопки сверху — перелёт к Солнцу и планетам; клик по планете — перелёт и карточка: факты и системная кнопка планеты
//   двойной клик по планете — сразу выполнить её кнопку (терминал, файлы, оформление… или выбранное приложение)
// Детали: поверхности планет рисуются один раз в 128 px и масштабируются (полосы и Большое красное пятно Юпитера,
// облака и материки Земли, полярные шапки Марса, кратеры Меркурия, кольца Сатурна с щелью Кассини, тёмное пятно
// Нептуна), ночная сторона — от Солнца; спутники, пояс астероидов, пояс Койпера, комета Галлея с хвостом от Солнца.
// Экономия: положения пересчитываются 20 раз в секунду; движение стоит, пока стол закрыт окнами, на паузе
// и при батарее ниже 25 %
Item {
    id: sp
    readonly property var o: Config.store.space
    readonly property real speed: o.speed === undefined ? 1 : o.speed
    readonly property real spread: Math.max(0.7, Math.min(1.6, o.spread || 1))
    readonly property real psize: Math.max(0.6, Math.min(2, o.planetScale || 1))
    readonly property bool details: o.details !== false

    // ---------- планеты ----------
    // r — радиус орбиты (условный), s — размер, p — период обращения, с (при скорости 1), c1 / c2 — цвета
    readonly property var planets: [
        { id: "mercury", name: Tr.t("Меркурий"), sym: "☿", r: 90,  s: 7,  p: 24,  c1: "#c9b9a6", c2: "#6e6258", d: Tr.t("4 879 км"), day: Tr.t("176 земных суток"), year: Tr.t("88 суток"), moons: 0, dist: Tr.t("0,39 а. е."), temp: "−180…+430 °C", g: "0,38 g", about: Tr.t("Самая маленькая и ближайшая к Солнцу планета; поверхность в кратерах, как у Луны") },
        { id: "venus",   name: Tr.t("Венера"),   sym: "♀", r: 128, s: 12, p: 38,  c1: "#f3d9a4", c2: "#b07a3c", d: Tr.t("12 104 км"), day: Tr.t("243 земных суток"), year: Tr.t("225 суток"), moons: 0, dist: Tr.t("0,72 а. е."), temp: "+465 °C", g: "0,9 g", about: Tr.t("Самая горячая: плотная атмосфера из углекислого газа и облака серной кислоты") },
        { id: "earth",   name: Tr.t("Земля"),    sym: "⊕", r: 172, s: 13, p: 60,  c1: "#6fb6ff", c2: "#1d5c3a", d: Tr.t("12 742 км"), day: Tr.t("24 часа"), year: Tr.t("365 суток"), moons: 1, dist: Tr.t("1 а. е."), temp: "−89…+57 °C", g: "1 g", about: Tr.t("Наш дом и единственная известная обитаемая планета; 71 % поверхности — океан") },
        { id: "mars",    name: Tr.t("Марс"),     sym: "♂", r: 214, s: 9,  p: 82,  c1: "#ff8a5c", c2: "#8c2f1b", d: Tr.t("6 779 км"), day: Tr.t("24 ч 37 мин"), year: Tr.t("687 суток"), moons: 2, dist: Tr.t("1,52 а. е."), temp: "−125…+20 °C", g: "0,38 g", about: Tr.t("Красная планета: самый высокий вулкан — Олимп, полярные шапки изо льда") },
        { id: "jupiter", name: Tr.t("Юпитер"),   sym: "♃", r: 300, s: 30, p: 130, c1: "#f0c9a0", c2: "#9a6a44", d: Tr.t("139 820 км"), day: Tr.t("9 ч 56 мин"), year: Tr.t("11,9 года"), moons: 95, dist: Tr.t("5,2 а. е."), temp: "−110 °C", g: "2,5 g", about: Tr.t("Газовый гигант; Большое красное пятно — вихрь больше Земли, бушует веками") },
        { id: "saturn",  name: Tr.t("Сатурн"),   sym: "♄", r: 380, s: 25, p: 180, c1: "#f3e1b2", c2: "#a88a55", d: Tr.t("116 460 км"), day: Tr.t("10 ч 34 мин"), year: Tr.t("29,4 года"), moons: 146, dist: Tr.t("9,5 а. е."), temp: "−140 °C", g: "1,07 g", about: Tr.t("Кольца изо льда и камня шириной в сотни тысяч километров, толщиной — меньше километра") },
        { id: "uranus",  name: Tr.t("Уран"),     sym: "⛢", r: 450, s: 17, p: 240, c1: "#b8f0f2", c2: "#4a9fb0", d: Tr.t("50 724 км"), day: Tr.t("17 ч 14 мин"), year: Tr.t("84 года"), moons: 28, dist: Tr.t("19,2 а. е."), temp: "−195 °C", g: "0,9 g", about: Tr.t("Вращается «лёжа на боку»: ось наклонена на 98°, кольца стоят почти вертикально") },
        { id: "neptune", name: Tr.t("Нептун"),   sym: "♆", r: 512, s: 16, p: 300, c1: "#7aa0ff", c2: "#22348f", d: Tr.t("49 244 км"), day: Tr.t("16 ч 6 мин"), year: Tr.t("165 лет"), moons: 16, dist: Tr.t("30 а. е."), temp: "−200 °C", g: "1,14 g", about: Tr.t("Самые быстрые ветры в Солнечной системе — до 2 100 км/ч; спутник Тритон летит в обратную сторону") }
    ]
    // спутники: планета, имя, орбита в радиусах планеты, период, с, размер, px при масштабе 1
    readonly property var moonsList: [
        { pl: "earth", name: Tr.t("Луна"), k: 2.2, p: 9, s: 3.6, c: "#d9d9d9" },
        { pl: "mars", name: Tr.t("Фобос"), k: 1.9, p: 2.5, s: 1.8, c: "#b59a86" },
        { pl: "mars", name: Tr.t("Деймос"), k: 2.8, p: 5, s: 1.5, c: "#c9b29e" },
        { pl: "jupiter", name: Tr.t("Ио"), k: 1.35, p: 3, s: 2.6, c: "#f2e27a" },
        { pl: "jupiter", name: Tr.t("Европа"), k: 1.7, p: 5, s: 2.3, c: "#e8dcc6" },
        { pl: "jupiter", name: Tr.t("Ганимед"), k: 2.15, p: 8, s: 3.2, c: "#b8ab99" },
        { pl: "jupiter", name: Tr.t("Каллисто"), k: 2.7, p: 13, s: 3, c: "#8f8577" },
        { pl: "saturn", name: Tr.t("Титан"), k: 2.6, p: 10, s: 3.2, c: "#e3b663" },
        { pl: "neptune", name: Tr.t("Тритон"), k: 2.2, p: -7, s: 2.2, c: "#d6e4ee" }
    ]
    // искусственные спутники Земли: орбита в радиусах Земли, период, с; geo — кольцо геостационарных
    readonly property var satellites: [
        { name: Tr.t("МКС"), k: 1.22, p: 1.6, cross: true },
        { name: Tr.t("Хаббл"), k: 1.3, p: 1.8 },
        { name: Tr.t("ГЛОНАСС"), k: 1.65, p: 4.5 },
        { name: "GPS", k: 1.72, p: 4.8 },
        { name: Tr.t("геостационарные"), k: 1.95, p: 60, geo: 6 }
    ]
    // ближайшие звёздные системы — метки за поясом Койпера (направление и расстояние условные)
    readonly property var systems: [
        { id: "alpha", name: Tr.t("Альфа Центавра"), ang: 0.6, r: 760, c: "#ffe8a8", ly: Tr.t("4,37 св. года"), kind: Tr.t("Тройная: две звезды как Солнце и красный карлик Проксима"), planets: Tr.t("Проксима b — в зоне обитаемости") },
        { id: "barnard", name: Tr.t("Звезда Барнарда"), ang: 1.9, r: 800, c: "#ff9a7a", ly: Tr.t("5,96 св. года"), kind: Tr.t("Красный карлик, самая быстрая по небу звезда"), planets: Tr.t("4 маленькие планеты") },
        { id: "sirius", name: Tr.t("Сириус"), ang: 3.2, r: 860, c: "#cfe3ff", ly: Tr.t("8,6 св. года"), kind: Tr.t("Ярчайшая звезда ночного неба: белая звезда и белый карлик"), planets: Tr.t("не найдены") },
        { id: "eridani", name: Tr.t("Эпсилон Эридана"), ang: 4.1, r: 820, c: "#ffd2a0", ly: Tr.t("10,5 св. года"), kind: Tr.t("Молодая звезда с пылевыми поясами"), planets: Tr.t("Эгир — газовый гигант") },
        { id: "procyon", name: Tr.t("Процион"), ang: 5.0, r: 880, c: "#f6f3e0", ly: Tr.t("11,4 св. года"), kind: Tr.t("Двойная: жёлто-белая звезда и белый карлик"), planets: Tr.t("не найдены") },
        { id: "tauceti", name: Tr.t("Тау Кита"), ang: 5.8, r: 790, c: "#fff0c0", ly: Tr.t("11,9 св. года"), kind: Tr.t("Одиночная, очень похожа на Солнце"), planets: Tr.t("кандидаты в землеподобные") }
    ]
    function sysPos(sy) { var r = sy.r * spread; return Qt.point(Math.cos(sy.ang) * r, Math.sin(sy.ang) * r * 0.92); }

    // системные кнопки, которые можно назначить планете
    readonly property var actions: ({
        terminal:   { t: Tr.t("Терминал"), i: "󰆍", c: ["kitty"] },
        files:      { t: Tr.t("Файлы"), i: "󰉋", c: ["dolphin"] },
        drawer:     { t: Tr.t("Оформление"), i: "󰏘", c: [Theme.script, "action", "drawer"] },
        monitor:    { t: Tr.t("Диспетчер задач"), i: "󰍛", c: ["qs", "-c", "nameless", "ipc", "call", "tasks", "toggle"] },
        programs:   { t: Tr.t("Программы"), i: "󰏖", c: ["qs", "-c", "nameless", "ipc", "call", "programs", "toggle"] },
        desktop:    { t: Tr.t("Рабочий стол"), i: "󰕰", c: ["qs", "-c", "nameless", "ipc", "call", "desktop", "toggle"] },
        display:    { t: Tr.t("Экран"), i: "󰍹", c: ["qs", "-c", "nameless", "ipc", "call", "display", "toggle"] },
        control:    { t: Tr.t("Пункт управления"), i: "󰕮", c: ["qs", "-c", "nameless", "ipc", "call", "control", "toggle"] },
        keys:       { t: Tr.t("Справка и клавиши"), i: "󰌌", c: ["qs", "-c", "nameless", "ipc", "call", "keys", "toggle"] },
        lock:       { t: Tr.t("Блокировка"), i: "󰌾", c: ["qs", "-c", "nameless", "ipc", "call", "lock", "lock"] },
        wallpaper:  { t: Tr.t("Следующие обои"), i: "󰸉", c: [Theme.script, "action", "wallpaper-next"] },
        screenshot: { t: Tr.t("Скриншот"), i: "󰹑", c: [Theme.script, "action", "screenshot"] }
    })

    // ---------- время и движение ----------
    property real t: Date.now() / 1000
    readonly property bool covered: Compositor.covered
    readonly property bool lowBattery: Sys.hasBattery && !Sys.charging && Sys.batPct < 25
    readonly property bool live: visible && !covered && !lowBattery && speed > 0
    // один шаг на кадр, но не чаще 60 раз в секунду: движение планет и камеры плавное (раньше — 20 раз в секунду,
    // и это выглядело как торможение), а на 165 Гц сцена не перерисовывается без нужды
    property real acc: 0
    FrameAnimation {
        running: sp.visible && (sp.live || sp.camMoving)
        onTriggered: {
            sp.acc += frameTime;
            if (sp.acc < 1 / Perf.fps) return;
            var dt = Math.min(0.1, sp.acc);
            sp.acc = 0;
            if (sp.live) sp.t += dt * sp.speed;
            sp.stepCamera(dt);
        }
    }
    function angle(pl) { return (sp.t / pl.p * 2 * Math.PI) % (2 * Math.PI) + pl.r * 0.013; }
    function pos(pl) { var a = angle(pl), r = pl.r * spread; return Qt.point(Math.cos(a) * r, Math.sin(a) * r * 0.92); }
    function size(pl) { return pl.s * psize; }

    // комета Галлея: эллипс с Солнцем в фокусе, уравнение Кеплера — несколько итераций
    readonly property real cometA: 430 * spread
    readonly property real cometE: 0.86
    readonly property point comet: {
        var M = (sp.t / 420 * 2 * Math.PI) % (2 * Math.PI), E = M;
        for (var i = 0; i < 6; i++) E = M + cometE * Math.sin(E);
        var x = cometA * (Math.cos(E) - cometE), y = cometA * Math.sqrt(1 - cometE * cometE) * Math.sin(E);
        var rot = -0.6;   // наклон орбиты
        return Qt.point(x * Math.cos(rot) - y * Math.sin(rot), (x * Math.sin(rot) + y * Math.cos(rot)) * 0.92);
    }

    // закрыт ли стол окнами — Compositor.covered (модель Hyprland, без вызовов hyprctl)

    // ---------- камера ----------
    // камера: цель (zoomT, panX / panY или выбранный объект) и текущее положение, которое плавно её догоняет
    readonly property real baseZoom: Math.min(width, height) / (1150 * spread)
    property real zoom: baseZoom
    property real zoomT: baseZoom
    property real panX: 0
    property real panY: 0
    property real cx: 0
    property real cy: 0
    property bool dragging: false
    property bool camMoving: false
    function stepCamera(dt) {
        var k = 1 - Math.exp(-dt * 9);
        zoom += (zoomT - zoom) * k;
        if (Math.abs(zoomT - zoom) < zoomT * 0.0005) zoom = zoomT;
        var tx = following ? -camTarget.x * zoom : panX, ty = following ? -camTarget.y * zoom : panY;
        if (dragging) { cx = tx; cy = ty; }
        else { cx += (tx - cx) * k; cy += (ty - cy) * k; }
        camMoving = zoom !== zoomT || Math.abs(tx - cx) > 0.3 || Math.abs(ty - cy) > 0.3;
    }
    // любое изменение цели — запустить догон
    onZoomTChanged: camMoving = true
    onPanXChanged: camMoving = true
    onPanYChanged: camMoving = true
    onFocusIdChanged: camMoving = true
    property string focusId: ""
    readonly property var focused: { for (var i = 0; i < planets.length; i++) if (planets[i].id === focusId) return planets[i]; return null; }
    readonly property var focusedSys: { for (var i = 0; i < systems.length; i++) if ("sys:" + systems[i].id === focusId) return systems[i]; return null; }
    // следование: центр камеры — на выбранной планете (если включено) или на звёздной системе
    readonly property bool following: (focused !== null && o.follow !== false) || focusedSys !== null
    readonly property point camTarget: focused ? pos(focused) : (focusedSys ? sysPos(focusedSys) : Qt.point(0, 0))
    function selectSys(sy) { focusId = "sys:" + sy.id; zoomT = Math.max(zoomT, Math.min(width, height) / 700); }
    function resetView() { focusId = ""; panX = 0; panY = 0; zoomT = baseZoom; }
    function select(pl) {
        focusId = pl.id;
        zoomT = Math.max(zoomT, Math.min(width, height) / (pl.s > 20 ? 260 : 420));
        // без следования — один раз навести камеру
        if (o.follow === false) { var p = pos(pl); panX = -p.x * zoomT; panY = -p.y * zoomT; }
    }
    function toSun() { focusId = ""; panX = 0; panY = 0; zoomT = Math.min(width, height) / 300; }
    function zoomBy(f) { zoomT = Math.max(0.2, Math.min(6, zoomT * f)); }

    // ---------- кнопка планеты ----------
    readonly property var apps: DesktopEntries.applications.values
    function bindingOf(pl) { return ((o.planets || {})[pl.id]) || ""; }
    function entryOf(id) { return id !== "" && apps.length >= 0 ? (DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id)) : null; }
    function labelOf(pl) {
        var b = bindingOf(pl);
        if (b.indexOf("action:") === 0) { var a = actions[b.substring(7)]; return a ? a.t : ""; }
        var e = entryOf(b); return e ? e.name : "";
    }
    function run(pl) {
        var b = bindingOf(pl);
        if (b.indexOf("action:") === 0) { var a = actions[b.substring(7)]; if (a) Quickshell.execDetached(a.c); return; }
        var e = entryOf(b); if (e) AppRun.run(e);
    }
    function bind(plId, value) { var m = Object.assign({}, o.planets || {}); m[plId] = value; Config.set("space.planets", m); }

    // ---------- ввод на пустом месте ----------
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        property real sx: 0
        property real sy: 0
        property bool moved: false
        onPressed: (m) => { sx = m.x; sy = m.y; moved = false; }
        onPositionChanged: (m) => {
            if (!pressed) return;
            if (!moved && Math.abs(m.x - sx) + Math.abs(m.y - sy) < 4) return;
            if (!moved) { moved = true; sp.dragging = true; sp.panX = sp.cx; sp.panY = sp.cy; sp.focusId = ""; }
            sp.panX += m.x - sx; sp.panY += m.y - sy; sx = m.x; sy = m.y;
        }
        onReleased: sp.dragging = false
        onClicked: if (!moved) { sp.focusId = ""; card.picking = false; }
        onDoubleClicked: sp.resetView()
        onWheel: (wh) => {
            var f = wh.angleDelta.y > 0 ? 1.15 : 1 / 1.15, nz = Math.max(0.2, Math.min(6, sp.zoomT * f));
            // к курсору: точка под курсором остаётся на месте (считается по цели, камера плавно догоняет)
            if (!sp.following) {
                var mx = wh.x - sp.width / 2, my = wh.y - sp.height / 2, k = nz / sp.zoomT;
                sp.panX = mx - (mx - sp.panX) * k; sp.panY = my - (my - sp.panY) * k;
            }
            sp.zoomT = nz;
        }
        cursorShape: pressed && moved ? Qt.ClosedHandCursor : Qt.ArrowCursor
    }

    // ---------- сцена ----------
    Item {
        id: scene
        x: sp.width / 2 + sp.cx
        y: sp.height / 2 + sp.cy

        // ближайшие звёздные системы: свечение, подпись и расстояние
        Repeater {
            model: sp.o.systems === false ? [] : sp.systems
            Item {
                id: sy
                required property var modelData
                readonly property point p: sp.sysPos(modelData)
                readonly property bool sel: sp.focusId === "sys:" + modelData.id
                x: p.x * sp.zoom; y: p.y * sp.zoom
                Rectangle { width: 26; height: 26; radius: 13; x: -13; y: -13; color: Qt.rgba(Qt.color(sy.modelData.c).r, Qt.color(sy.modelData.c).g, Qt.color(sy.modelData.c).b, 0.14) }
                Rectangle { width: 10; height: 10; radius: 5; x: -5; y: -5; color: Qt.rgba(Qt.color(sy.modelData.c).r, Qt.color(sy.modelData.c).g, Qt.color(sy.modelData.c).b, 0.4) }
                Rectangle { width: 4; height: 4; radius: 2; x: -2; y: -2; color: "white" }
                Rectangle { visible: sy.sel; width: 34; height: 34; radius: 17; x: -17; y: -17; color: "transparent"; border.width: 1.5; border.color: Theme.accent }
                Column {
                    x: 14; y: -14
                    visible: sp.o.labels !== false || syHov.hovered || sy.sel
                    Text { text: sy.modelData.name; color: sy.sel ? Theme.accent : Qt.rgba(1, 1, 1, 0.75); font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
                    Text { text: sy.modelData.ly; color: Qt.rgba(1, 1, 1, 0.45); font.family: Theme.font; font.pixelSize: 9 }
                }
                Item {
                    width: 36; height: 36; x: -18; y: -18
                    HoverHandler { id: syHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: sp.selectSys(sy.modelData) }
                }
            }
        }

        // орбиты
        Repeater {
            model: sp.o.orbits === false ? [] : sp.planets
            Rectangle {
                required property var modelData
                readonly property bool sel: sp.focusId === modelData.id
                width: modelData.r * sp.spread * 2 * sp.zoom; height: width * 0.92
                x: -width / 2; y: -height / 2
                radius: width / 2
                color: "transparent"
                border.width: sel ? 1.5 : 1
                border.color: sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.65) : Qt.rgba(1, 1, 1, 0.08)
            }
        }
        Belt { visible: sp.o.belt !== false; r0: 244; r1: 270; count: 520; tone: "#d9ccb8"; seed: 0; rotation: sp.t * 0.6 }
        Belt { visible: sp.o.kuiper !== false; r0: 560; r1: 640; count: 700; tone: "#a9c4e8"; seed: 900; rotation: sp.t * 0.12 }

        // Солнце: корона (рисуется один раз), диск с грануляцией, медленная пульсация
        Item {
            id: sun
            readonly property real d: 46 * Math.max(0.8, sp.psize) * sp.zoom
            Canvas {
                width: 512; height: 512
                x: -256; y: -256
                scale: sun.d * 3.6 / 512
                onPaint: {
                    var ctx = getContext("2d"), c = 256;
                    ctx.reset();
                    var g = ctx.createRadialGradient(c, c, 0, c, c, c);
                    g.addColorStop(0.0, Qt.rgba(1, 0.92, 0.6, 0.9));
                    g.addColorStop(0.16, Qt.rgba(1, 0.75, 0.3, 0.55));
                    g.addColorStop(0.32, Qt.rgba(1, 0.6, 0.2, 0.18));
                    g.addColorStop(0.6, Qt.rgba(1, 0.5, 0.15, 0.05));
                    g.addColorStop(1.0, Qt.rgba(1, 0.5, 0.1, 0));
                    ctx.fillStyle = g; ctx.fillRect(0, 0, 512, 512);
                    // лучи короны
                    for (var i = 0; i < 48; i++) {
                        var a = i / 48 * Math.PI * 2 + Math.sin(i * 7.1) * 0.05, len = 120 + Math.abs(Math.sin(i * 3.7)) * 110;
                        var lg = ctx.createLinearGradient(c, c, c + Math.cos(a) * len, c + Math.sin(a) * len);
                        lg.addColorStop(0, Qt.rgba(1, 0.85, 0.5, 0.12)); lg.addColorStop(1, Qt.rgba(1, 0.7, 0.3, 0));
                        ctx.strokeStyle = lg; ctx.lineWidth = 3;
                        ctx.beginPath(); ctx.moveTo(c, c); ctx.lineTo(c + Math.cos(a) * len, c + Math.sin(a) * len); ctx.stroke();
                    }
                }
                SequentialAnimation on opacity {
                    running: sp.live; loops: Animation.Infinite
                    NumberAnimation { to: 0.8; duration: 3000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 3000; easing.type: Easing.InOutSine }
                }
            }
            Canvas {
                width: 128; height: 128
                x: -64; y: -64
                scale: sun.d / 128
                onPaint: {
                    var ctx = getContext("2d"); ctx.reset();
                    ctx.beginPath(); ctx.arc(64, 64, 63, 0, Math.PI * 2); ctx.clip();
                    var g = ctx.createRadialGradient(54, 54, 0, 64, 64, 64);
                    g.addColorStop(0, "#fffbe0"); g.addColorStop(0.7, "#ffcc55"); g.addColorStop(1, "#ff9a2e");
                    ctx.fillStyle = g; ctx.fillRect(0, 0, 128, 128);
                    // грануляция
                    for (var i = 0; i < 160; i++) {
                        var x = Math.abs(Math.sin(i * 12.99) * 43758.5) % 128, y = Math.abs(Math.sin(i * 78.23) * 43758.5) % 128;
                        ctx.fillStyle = Qt.rgba(1, 0.8, 0.4, 0.18);
                        ctx.beginPath(); ctx.arc(x, y, 2 + (i % 4), 0, Math.PI * 2); ctx.fill();
                    }
                }
            }
            Item {
                width: Math.max(30, sun.d); height: width; x: -width / 2; y: -height / 2
                HoverHandler { id: sunHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: sp.toSun() }
            }
            Text {
                visible: sp.o.labels !== false || sunHov.hovered
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: sun.d / 2 + 8 }
                text: Tr.t("Солнце"); color: Qt.rgba(1, 0.85, 0.55, 0.8); font.family: Theme.font; font.pixelSize: 11
            }
        }

        // комета: ядро и хвост — всегда от Солнца, длиннее вблизи него
        Item {
            visible: sp.o.comet !== false
            x: sp.comet.x * sp.zoom
            y: sp.comet.y * sp.zoom
            readonly property real dist: Math.max(20, Math.hypot(sp.comet.x, sp.comet.y))
            Rectangle {
                width: Math.min(260, 9000 / parent.dist) * sp.zoom; height: Math.max(2, 4 * sp.zoom)
                y: -height / 2
                transformOrigin: Item.Left
                rotation: Math.atan2(sp.comet.y, sp.comet.x) * 180 / Math.PI
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(0.8, 0.9, 1, 0.55) }
                    GradientStop { position: 1; color: Qt.rgba(0.6, 0.8, 1, 0) }
                }
            }
            Rectangle { width: Math.max(3, 4 * sp.zoom); height: width; radius: width / 2; x: -width / 2; y: -height / 2; color: "#eaf6ff" }
            Text {
                visible: sp.o.labels !== false && sp.zoom > 0.7
                x: 8; y: 6
                text: Tr.t("комета Галлея"); color: Qt.rgba(0.8, 0.9, 1, 0.55); font.family: Theme.font; font.pixelSize: 10
            }
        }

        // планеты
        Repeater {
            model: sp.planets
            Item {
                id: pl
                required property var modelData
                readonly property point p: sp.pos(modelData)
                readonly property real d: Math.max(5, sp.size(modelData) * sp.zoom)
                readonly property bool sel: sp.focusId === modelData.id
                readonly property real sunAngle: Math.atan2(p.y, p.x) * 180 / Math.PI
                readonly property bool ringed: modelData.id === "saturn" || (modelData.id === "uranus" && sp.details)
                x: p.x * sp.zoom
                y: p.y * sp.zoom

                // кольца (задняя половина)
                PlanetRings { visible: pl.ringed; planet: pl.modelData.id; d: pl.d; back: true }

                // поверхность: 128 px, рисуется один раз
                Canvas {
                    width: 128; height: 128
                    x: -64; y: -64
                    scale: pl.d / 128
                    readonly property bool det: sp.details
                    onDetChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d"), id = pl.modelData.id, c1 = pl.modelData.c1, c2 = pl.modelData.c2;
                        function rnd(i, k) { var v = Math.sin(i * 12.9898 + k * 78.233) * 43758.5453; return v - Math.floor(v); }
                        ctx.reset();
                        ctx.beginPath(); ctx.arc(64, 64, 63, 0, Math.PI * 2); ctx.clip();
                        var g = ctx.createLinearGradient(0, 0, 0, 128);
                        g.addColorStop(0, c1); g.addColorStop(1, c2);
                        ctx.fillStyle = g; ctx.fillRect(0, 0, 128, 128);
                        if (!det) return;
                        var i;
                        if (id === "jupiter" || id === "saturn") {
                            // полосы облаков
                            var bands = id === "jupiter" ? 11 : 9;
                            for (i = 0; i < bands; i++) {
                                ctx.fillStyle = i % 2 === 0 ? Qt.rgba(0.55, 0.35, 0.2, id === "jupiter" ? 0.35 : 0.16) : Qt.rgba(1, 0.95, 0.85, 0.18);
                                var y0 = i * 128 / bands, hh = 128 / bands * (0.6 + rnd(i, 3) * 0.6);
                                ctx.beginPath(); ctx.moveTo(0, y0);
                                for (var x = 0; x <= 128; x += 8) ctx.lineTo(x, y0 + Math.sin(x * 0.12 + i) * 1.6);
                                ctx.lineTo(128, y0 + hh); ctx.lineTo(0, y0 + hh); ctx.closePath(); ctx.fill();
                            }
                            if (id === "jupiter") {
                                // Большое красное пятно
                                ctx.fillStyle = Qt.rgba(0.75, 0.32, 0.18, 0.8);
                                ctx.beginPath(); ctx.ellipse(46, 63, 48, 26, 0, 0, Math.PI * 2); ctx.fill();
                                ctx.strokeStyle = Qt.rgba(1, 0.9, 0.8, 0.35); ctx.lineWidth = 1.5;
                                ctx.beginPath(); ctx.ellipse(40, 58, 56, 32, 0, 0, Math.PI * 2); ctx.stroke();
                            }
                        } else if (id === "earth") {
                            // материки, пустыни, полярные шапки, облака
                            ctx.fillStyle = Qt.rgba(0.2, 0.5, 0.25, 0.9);
                            var land = [[8, 24, 46, 32], [42, 48, 22, 46], [66, 32, 40, 24], [76, 72, 32, 22], [32, 90, 18, 14]];
                            for (i = 0; i < land.length; i++) { ctx.beginPath(); ctx.ellipse(land[i][0], land[i][1], land[i][2], land[i][3], 0, 0, Math.PI * 2); ctx.fill(); }
                            ctx.fillStyle = Qt.rgba(0.78, 0.66, 0.42, 0.55);
                            ctx.beginPath(); ctx.ellipse(76, 40, 20, 12, 0, 0, Math.PI * 2); ctx.fill();
                            ctx.fillStyle = "rgba(255,255,255,0.9)";
                            ctx.fillRect(0, 0, 128, 9); ctx.fillRect(0, 120, 128, 8);
                            ctx.strokeStyle = "rgba(255,255,255,0.55)"; ctx.lineWidth = 4; ctx.lineCap = "round";
                            for (i = 0; i < 9; i++) {
                                var cy = 18 + rnd(i, 5) * 92, cx = rnd(i, 6) * 128;
                                ctx.beginPath(); ctx.moveTo(cx, cy); ctx.bezierCurveTo(cx + 12, cy - 6, cx + 26, cy + 6, cx + 40, cy); ctx.stroke();
                            }
                        } else if (id === "mars") {
                            ctx.fillStyle = Qt.rgba(0.45, 0.15, 0.08, 0.45);
                            for (i = 0; i < 9; i++) { ctx.beginPath(); ctx.ellipse(rnd(i, 7) * 128, 20 + rnd(i, 8) * 88, 16 + rnd(i, 9) * 32, 10 + rnd(i, 10) * 16, 0, 0, Math.PI * 2); ctx.fill(); }
                            // долина Маринера
                            ctx.strokeStyle = Qt.rgba(0.35, 0.1, 0.05, 0.6); ctx.lineWidth = 3;
                            ctx.beginPath(); ctx.moveTo(30, 66); ctx.bezierCurveTo(50, 60, 70, 70, 96, 62); ctx.stroke();
                            ctx.fillStyle = "rgba(255,255,255,0.92)";
                            ctx.beginPath(); ctx.ellipse(34, -6, 60, 20, 0, 0, Math.PI * 2); ctx.fill();
                            ctx.beginPath(); ctx.ellipse(42, 117, 44, 16, 0, 0, Math.PI * 2); ctx.fill();
                        } else if (id === "mercury") {
                            for (i = 0; i < 40; i++) {
                                var r = 2 + rnd(i, 11) * 7, mx = rnd(i, 12) * 128, my = rnd(i, 13) * 128;
                                ctx.fillStyle = Qt.rgba(0.3, 0.27, 0.24, 0.35);
                                ctx.beginPath(); ctx.arc(mx, my, r, 0, Math.PI * 2); ctx.fill();
                                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.18); ctx.lineWidth = 1;
                                ctx.beginPath(); ctx.arc(mx - 1, my - 1, r, Math.PI, Math.PI * 1.7); ctx.stroke();
                            }
                        } else if (id === "venus") {
                            // завихрения облаков
                            ctx.strokeStyle = Qt.rgba(1, 0.95, 0.85, 0.25); ctx.lineWidth = 5;
                            for (i = 0; i < 8; i++) {
                                var vy = 10 + i * 15;
                                ctx.beginPath(); ctx.moveTo(0, vy); ctx.bezierCurveTo(40, vy - 10, 80, vy + 12, 128, vy - 4); ctx.stroke();
                            }
                        } else if (id === "uranus") {
                            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.08);
                            for (i = 0; i < 5; i++) ctx.fillRect(14 + i * 22, 0, 8, 128);
                        } else if (id === "neptune") {
                            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.1);
                            for (i = 0; i < 6; i++) ctx.fillRect(0, 10 + i * 20, 128, 5);
                            // Большое тёмное пятно и белые облака
                            ctx.fillStyle = Qt.rgba(0.05, 0.1, 0.35, 0.7);
                            ctx.beginPath(); ctx.ellipse(32, 61, 40, 22, 0, 0, Math.PI * 2); ctx.fill();
                            ctx.fillStyle = "rgba(255,255,255,0.6)";
                            ctx.beginPath(); ctx.ellipse(48, 55, 24, 6, 0, 0, Math.PI * 2); ctx.fill();
                        }
                    }
                }
                // ночная сторона — от Солнца; у планет с атмосферой — тонкий светящийся край
                Rectangle {
                    width: 128; height: 128; x: -64; y: -64
                    scale: pl.d / 128
                    radius: 64
                    rotation: pl.sunAngle - 90
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                        GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.12) }
                        GradientStop { position: 0.62; color: Qt.rgba(0, 0, 0, 0.72) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.88) }
                    }
                    border.width: ["earth", "venus", "uranus", "neptune"].indexOf(pl.modelData.id) >= 0 ? 3 : 0
                    border.color: Qt.rgba(Qt.color(pl.modelData.c1).r, Qt.color(pl.modelData.c1).g, Qt.color(pl.modelData.c1).b, 0.35)
                }
                Rectangle {
                    visible: pl.sel
                    width: pl.d + 10; height: width; radius: width / 2
                    x: -width / 2; y: -height / 2
                    color: "transparent"; border.width: 1.5; border.color: Theme.accent
                }

                // кольца (передняя половина)
                PlanetRings { visible: pl.ringed; planet: pl.modelData.id; d: pl.d; back: false }

                // спутники
                Repeater {
                    model: sp.o.moons === false || pl.d < 8 ? [] : sp.moonsList.filter(function (m) { return m.pl === pl.modelData.id; })
                    Rectangle {
                        required property var modelData
                        readonly property real a: sp.t / modelData.p * 2 * Math.PI
                        readonly property real orb: pl.d / 2 * modelData.k
                        width: Math.max(2.5, modelData.s * sp.zoom * sp.psize * 0.7); height: width; radius: width / 2
                        x: Math.cos(a) * orb - width / 2
                        y: Math.sin(a) * orb * 0.92 - height / 2
                        color: modelData.c
                        Text {
                            visible: pl.sel && sp.o.labels !== false && pl.d > 40
                            anchors { left: parent.right; leftMargin: 3; verticalCenter: parent.verticalCenter }
                            text: parent.modelData.name; color: Qt.rgba(1, 1, 1, 0.6); font.family: Theme.font; font.pixelSize: 9
                        }
                    }
                }

                // искусственные спутники Земли: видны, когда Земля достаточно крупная
                Repeater {
                    model: pl.modelData.id === "earth" && sp.o.satellites !== false && pl.d > 18 ? sp.satellites : []
                    Item {
                        id: sat
                        required property var modelData
                        readonly property real orb: pl.d / 2 * modelData.k
                        // геостационарные — кольцо из нескольких, остальные — по одному
                        Repeater {
                            model: sat.modelData.geo || 1
                            Item {
                                required property int index
                                readonly property real a: sp.t / sat.modelData.p * 2 * Math.PI + index * Math.PI * 2 / (sat.modelData.geo || 1) + sat.modelData.k * 3
                                x: Math.cos(a) * sat.orb
                                y: Math.sin(a) * sat.orb * 0.92
                                // МКС — крестик солнечных панелей, остальные — светящаяся точка
                                Rectangle { visible: sat.modelData.cross === true; width: 9; height: 2; x: -4.5; y: -1; color: "#ffd479" }
                                Rectangle { width: sat.modelData.cross ? 3 : 2.5; height: width; x: -width / 2; y: -height / 2; color: "white" }
                                Text {
                                    visible: pl.sel && sp.o.labels !== false && index === 0 && pl.d > 60
                                    x: 5; y: -6
                                    text: sat.modelData.name; color: Qt.rgba(1, 0.9, 0.6, 0.7); font.family: Theme.font; font.pixelSize: 9
                                }
                            }
                        }
                    }
                }

                // подпись
                Text {
                    visible: (sp.o.labels !== false || hov.hovered || pl.sel)
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: pl.d / 2 + (pl.modelData.id === "saturn" ? pl.d * 0.35 : 0) + 6 }
                    text: pl.modelData.name
                    color: pl.sel ? Theme.accent : Qt.rgba(1, 1, 1, hov.hovered ? 0.95 : 0.6)
                    font.family: Theme.font; font.pixelSize: 11; font.weight: pl.sel ? Font.DemiBold : Font.Normal
                }
                // область нажатия больше диска: мелкие планеты легко попасть
                Item {
                    width: Math.max(28, pl.d + 14); height: width
                    x: -width / 2; y: -height / 2
                    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: sp.select(pl.modelData); onDoubleTapped: sp.run(pl.modelData) }
                }
            }
        }
    }

    // пояс: точки рисуются один раз, пояс медленно поворачивается целиком
    component Belt: Canvas {
        id: bc
        property real r0
        property real r1
        property int count
        property color tone
        property int seed
        // холст фиксированного размера, рисуется один раз и масштабируется: раньше он рос с масштабом
        // (до ~7000 px на приближении) и перерисовывался на каждом кадре — главная причина лагов
        readonly property int px: 1024
        width: px; height: px * 0.92
        x: -width / 2; y: -height / 2
        scale: (r1 * 2 * sp.spread * sp.zoom + 4) / px
        onPaint: {
            var ctx = getContext("2d"); ctx.reset();
            var f = (px / 2 - 2) / r1;
            for (var i = 0; i < count; i++) {
                var rnd = function (k) { var v = Math.sin((i + bc.seed) * 12.9898 + k * 78.233) * 43758.5453; return v - Math.floor(v); };
                var a = rnd(1) * Math.PI * 2, r = (r0 + rnd(2) * (r1 - r0)) * f;
                ctx.fillStyle = Qt.rgba(tone.r, tone.g, tone.b, 0.2 + rnd(3) * 0.45);
                var s = rnd(4) > 0.92 ? 2 : 1.3;
                ctx.fillRect(width / 2 + Math.cos(a) * r, height / 2 + Math.sin(a) * r * 0.92, s, s);
            }
        }
    }

    // кольца: задняя или передняя половина, рисуются один раз
    component PlanetRings: Canvas {
        property string planet
        property real d
        property bool back
        readonly property bool uranus: planet === "uranus"
        width: 320; height: 320
        x: -160; y: -160
        scale: d / 128
        rotation: uranus ? 80 : -16
        onPaint: {
            var ctx = getContext("2d"); ctx.reset();
            // половина: задняя — верх эллипса (за диском), передняя — низ
            ctx.beginPath();
            if (back) ctx.rect(0, 0, 320, 160); else ctx.rect(0, 160, 320, 160);
            ctx.clip();
            var rings = uranus ? [[150, 0.25, 1.2]] : [[92, 0.35, 8], [104, 0.75, 12], [118, 0.0, 4], [128, 0.6, 12], [142, 0.3, 6]];
            for (var i = 0; i < rings.length; i++) {
                if (rings[i][1] <= 0) continue;          // щель Кассини
                ctx.strokeStyle = uranus ? Qt.rgba(0.8, 0.95, 1, rings[i][1]) : Qt.rgba(0.93, 0.85, 0.66, rings[i][1]);
                ctx.lineWidth = rings[i][2];
                ctx.beginPath(); ctx.ellipse(160 - rings[i][0], 160 - rings[i][0] * 0.32, rings[i][0] * 2, rings[i][0] * 0.64, 0, 0, Math.PI * 2); ctx.stroke();
            }
        }
    }

    // ---------- перелёт: Солнце и планеты ----------
    Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 56 }
        width: nav.implicitWidth + 12; height: 40; radius: 20
        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.62)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
        Row {
            id: nav
            anchors.centerIn: parent
            spacing: 2
            NavBtn { t: "☉"; hint: Tr.t("Солнце"); on: sp.focusId === "" && sp.zoom > sp.baseZoom * 2; onClicked: sp.toSun() }
            Repeater {
                model: sp.planets
                NavBtn {
                    required property var modelData
                    t: modelData.sym; hint: modelData.name
                    on: sp.focusId === modelData.id
                    onClicked: sp.select(modelData)
                }
            }
            NavBtn { t: "󰑓"; icon: true; hint: Tr.t("Вся система"); onClicked: sp.resetView() }
        }
    }
    component NavBtn: Rectangle {
        id: nb
        property string t
        property string hint
        property bool on: false
        property bool icon: false
        signal clicked
        width: 32; height: 32; radius: 16
        color: on ? Theme.accent : (nma.containsMouse ? Theme.fill(0.16) : "transparent")
        Text { anchors.centerIn: parent; text: nb.t; color: nb.on ? "white" : Theme.text; font.family: nb.icon ? Theme.iconFont : Theme.font; font.pixelSize: 16 }
        Rectangle {
            visible: nma.containsMouse
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 8 }
            width: ht.implicitWidth + 14; height: 22; radius: 11
            color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.92)
            Text { id: ht; anchors.centerIn: parent; text: nb.hint; color: Theme.text; font.family: Theme.font; font.pixelSize: 11 }
        }
        MouseArea { id: nma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: nb.clicked() }
    }

    // ---------- карточка планеты ----------
    Item {
        id: card
        visible: sp.focused !== null || sp.focusedSys !== null
        width: 340
        height: cardCol.implicitHeight + 32
        anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
        Surface { anchors.fill: parent; radius: 26; alpha: Theme.panelAlpha }
        MouseArea { anchors.fill: parent }
        property bool picking: false
        Column {
            id: cardCol
            x: 18; y: 16
            width: parent.width - 36
            spacing: 10
            readonly property var pl: sp.focused || ({})
            readonly property var sy: sp.focusedSys
            // звёздная система: название, расстояние, состав, планеты
            Column {
                visible: cardCol.sy !== null
                width: parent.width
                spacing: 8
                Row {
                    spacing: 12
                    Rectangle {
                        width: 46; height: 46; radius: 23
                        color: cardCol.sy ? cardCol.sy.c : "white"
                        Rectangle { anchors.centerIn: parent; width: 60; height: 60; radius: 30; color: "transparent"; border.width: 6; border.color: Qt.rgba(1, 1, 1, 0.08) }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: cardCol.sy ? cardCol.sy.name : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 21; font.weight: Font.Bold }
                        Text { text: cardCol.sy ? Tr.t("от Солнца ") + cardCol.sy.ly : ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
                    }
                }
                Text { width: parent.width; wrapMode: Text.WordWrap; text: cardCol.sy ? cardCol.sy.kind : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                Text { width: parent.width; wrapMode: Text.WordWrap; text: cardCol.sy ? Tr.t("Планеты: ") + cardCol.sy.planets : ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
                Text { width: parent.width; wrapMode: Text.WordWrap; text: Tr.t("Свет от неё идёт до нас столько лет, сколько указано выше: мы видим её прошлое."); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
            }
            Row {
                visible: cardCol.sy === null
                spacing: 12
                Rectangle {
                    width: 46; height: 46; radius: 23
                    gradient: Gradient { GradientStop { position: 0; color: cardCol.pl.c1 || "white" } GradientStop { position: 1; color: cardCol.pl.c2 || "gray" } }
                    Text { anchors.centerIn: parent; text: cardCol.pl.sym || ""; color: "white"; font.pixelSize: 20 }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: cardCol.pl.name || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold }
                    Text { text: cardCol.pl.dist ? Tr.t("от Солнца ") + cardCol.pl.dist : ""; color: Theme.sub; font.family: Theme.font; font.pixelSize: 12 }
                }
            }
            Text { visible: cardCol.sy === null; width: parent.width; wrapMode: Text.WordWrap; text: cardCol.pl.about || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
            Grid {
                visible: cardCol.sy === null
                columns: 2; columnSpacing: 14; rowSpacing: 4
                Repeater {
                    model: [[Tr.t("Диаметр"), cardCol.pl.d], [Tr.t("Сутки"), cardCol.pl.day], [Tr.t("Год"), cardCol.pl.year], [Tr.t("Спутники"), String(cardCol.pl.moons)],
                            [Tr.t("Температура"), cardCol.pl.temp], [Tr.t("Притяжение"), cardCol.pl.g]]
                    Text {
                        required property var modelData
                        text: modelData[0] + ": " + (modelData[1] || "")
                        color: Theme.sub; font.family: Theme.font; font.pixelSize: 12
                    }
                }
            }
            Rectangle { width: parent.width; height: 1; color: Theme.fill(0.14) }
            // кнопка планеты
            Text { visible: cardCol.sy === null; text: Tr.t("Кнопка планеты"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
            Row {
                visible: cardCol.sy === null
                spacing: 8
                readonly property string label: sp.focused ? sp.labelOf(sp.focused) : ""
                GButton {
                    ui: Theme; height: 36
                    enabled: parent.label !== ""
                    icon: "󰐊"; on: true
                    label: parent.label !== "" ? parent.label : Tr.t("Не назначено")
                    onClicked: sp.run(sp.focused)
                }
                GButton { ui: Theme; height: 36; icon: "󰏫"; label: Tr.t("Сменить"); onClicked: { card.picking = !card.picking; pickQ.text = ""; } }
            }
            // выбор: системные кнопки, ниже — поиск приложения
            Column {
                visible: cardCol.sy === null && card.picking
                width: parent.width
                spacing: 6
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: Object.keys(sp.actions)
                        Rectangle {
                            required property string modelData
                            readonly property var a: sp.actions[modelData]
                            readonly property bool on: sp.focused !== null && sp.bindingOf(sp.focused) === "action:" + modelData
                            width: at.implicitWidth + 20; height: 30; radius: 15
                            color: on ? Theme.accent : (ama.containsMouse ? Theme.fill(0.16) : Theme.fill(0.08))
                            Text { id: at; anchors.centerIn: parent; text: parent.a.i + "  " + parent.a.t; color: parent.on ? "white" : Theme.text; font.family: Theme.iconFont; font.pixelSize: 12 }
                            MouseArea { id: ama; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { sp.bind(sp.focusId, "action:" + parent.modelData); card.picking = false; } }
                        }
                    }
                }
                Rectangle {
                    width: parent.width; height: 34; radius: Theme.r(12)
                    color: Theme.fill(0.08); border.width: 1; border.color: pickQ.activeFocus ? Theme.accent : Theme.line(0.2)
                    TextInput {
                        id: pickQ
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13; clip: true
                        Keys.onEscapePressed: card.picking = false
                        Text { visible: pickQ.text === ""; anchors.verticalCenter: parent.verticalCenter; text: Tr.t("или найти приложение…"); color: Theme.sub; font: pickQ.font }
                    }
                }
                Repeater {
                    model: {
                        var q = pickQ.text.trim().toLowerCase();
                        if (q === "") return [];
                        return sp.apps.filter(function (e) { return !e.noDisplay && (e.name || "").toLowerCase().indexOf(q) >= 0; }).slice(0, 5);
                    }
                    MenuRow {
                        required property var modelData
                        icon: "󰀻"; label: modelData.name
                        onClicked: { sp.bind(sp.focusId, modelData.id); card.picking = false; }
                    }
                }
            }
            Text { visible: cardCol.sy === null; text: Tr.t("Двойной клик по планете — сразу выполнить"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
        }
        GTile {
            anchors { right: parent.right; top: parent.top; margins: 10 }
            ui: Theme; width: 28; height: 28; radius: 14
            Text { anchors.centerIn: parent; text: "✕"; color: Theme.text; font.pixelSize: 11 }
            onClicked: { sp.focusId = ""; card.picking = false; }
        }
    }

    // ---------- управление ----------
    Rectangle {
        anchors { left: parent.left; leftMargin: 24; bottom: parent.bottom; bottomMargin: 28 }
        width: ctl.implicitWidth + 16; height: 44; radius: 22
        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.7)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
        Row {
            id: ctl
            anchors.centerIn: parent
            spacing: 4
            Btn { t: "󰍴"; onClicked: sp.zoomBy(1 / 1.3) }
            Btn { t: "󰐕"; onClicked: sp.zoomBy(1.3) }
            Btn { t: "󰏤"; on: sp.speed === 0; onClicked: Config.set("space.speed", 0) }
            Btn { t: "×0.5"; on: sp.speed === 0.5; onClicked: Config.set("space.speed", 0.5) }
            Btn { t: "×1"; on: sp.speed === 1; onClicked: Config.set("space.speed", 1) }
            Btn { t: "×5"; on: sp.speed === 5; onClicked: Config.set("space.speed", 5) }
            Btn { t: "×10"; on: sp.speed === 10; onClicked: Config.set("space.speed", 10) }
            Btn { t: "×100"; on: sp.speed === 100; onClicked: Config.set("space.speed", 100) }
            Btn { t: "󰗊"; on: sp.o.labels !== false; onClicked: Config.set("space.labels", sp.o.labels === false) }
            Btn { t: "󰒓"; onClicked: Quickshell.execDetached(["qs", "-c", "nameless", "ipc", "call", "desktop", "cosmos"]) }
        }
    }
    component Btn: Rectangle {
        property string t
        property bool on: false
        signal clicked
        width: Math.max(32, bt.implicitWidth + 16); height: 32; radius: 16
        color: on ? Theme.accent : (bma.containsMouse ? Theme.fill(0.16) : "transparent")
        Text { id: bt; anchors.centerIn: parent; text: parent.t; color: parent.on ? "white" : Theme.text; font.family: Theme.iconFont; font.pixelSize: 13 }
        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }
}
