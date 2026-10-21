pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Настройки рабочего стола NameLess UI: док, набор и порядок виджетов, их параметры.
// Общие для всех тем — ~/.config/glassrice/nameless.json; включение дока и виджетов — в теме (theme.sh set .dock / .widgets).
// При первом запуске закреплённые приложения берутся из прежнего ~/.config/glassrice/dock.txt
Singleton {
    id: cfg

    readonly property string dir: Quickshell.env("HOME") + "/.config/glassrice"
    readonly property string path: dir + "/nameless.json"

    // виды виджетов: подпись, значок и описание для панели «Рабочий стол»
    readonly property var kinds: ({
        clock:    { name: "Часы",        icon: "󰥔", about: "цифры, стрелки, словами или столбиком; второй часовой пояс" },
        system:   { name: "Нагрузка",    icon: "󰍛", about: "процессор, память, температура, диск, сеть, батарея, видеокарта" },
        player:   { name: "Плеер",       icon: "󰝚", about: "обложка, перемотка, повтор и перемешивание" },
        calendar: { name: "Календарь",   icon: "󰃭", about: "месяц, листается колесом; номера недель" },
        notifs:   { name: "Пришло",      icon: "󰂚", about: "приложения с непрочитанными уведомлениями" },
        weather:  { name: "Погода",      icon: "󰖐", about: "Open-Meteo, MET Norway или wttr.in; город — прямо в виджете" },
        notes:    { name: "Заметка",     icon: "󰎞", about: "быстрая заметка, сохраняется сама" },
        timer:    { name: "Помодоро",    icon: "󰔛", about: "таймер работы и перерывов с уведомлением" },
        actions:  { name: "Действия",    icon: "󰀻", about: "плитки: терминал, файлы, скриншот, блокировка…" },
        photo:    { name: "Фоторамка",   icon: "󰋩", about: "слайд-шоу из папки с картинками" },
        updates:  { name: "Обновления",  icon: "󰚰", about: "сколько пакетов ждёт обновления" },
        countdown:{ name: "Отсчёт",      icon: "󰔟", about: "сколько дней осталось до даты" },
        claude:   { name: "Лимиты Claude", icon: "󰚩", about: "окно 5 часов и неделя кольцами, сброс и прогноз исчерпания" },
        tokens:   { name: "Расход токенов", icon: "󰆼", about: "токены за сегодня, неделю и 5 часов, столбики по дням и моделям" },
        orbit:    { name: "Устройства",  icon: "󰟀", about: "NameLess Orbit: подключённые устройства, заряд, «найти», буфер обмена" },
        touch:    { name: "Сенсорная панель", icon: "󰟸", about: "тачпад: точки на месте пальцев и клики своим цветом (левая, правая, средняя), как touchview" },
        agents:   { name: "Помощники",   icon: "󰚩", about: "Claude Code и Codex: кто работает, ждёт, последнее сообщение; быстрый вопрос" }
    })
    // ширина виджета по размеру
    readonly property var sizes: ({ S: 240, M: 300, L: 380 })

    readonly property var defaults: ({
        lang: "",              // язык интерфейса: ru | en; пусто — ещё не выбран (при первом запуске предлагается выбор)
        dock: {
            pinned: ["org.kde.dolphin", "kitty", "brave-browser", "org.telegram.desktop", "discord", "steam"],
            style: "mac",       // mac — стеклянная полка с увеличением, ios — плашка с плитками значков
            size: 54,           // значок, px
            magnify: true,      // увеличение при наведении
            zoom: 1.7,          // во сколько раз увеличивается значок под курсором
            tiles: false,       // значки на одинаковых плитках-«сквирклах», как в iOS
            autohide: false,    // прятать, пока курсор не у нижнего края
            running: true,      // показывать запущенные без закрепления
            labels: true,       // подпись над значком при наведении
            downloads: true,    // папка «Загрузки» справа
            trash: true         // корзина справа
        },
        widgets: {
            layout: "grid",     // grid — сетка по двум осям, columns — колонки списком, free — свободно (с привязкой к соседям)
            side: "left",       // сетка: с какого края колонки; свободно — колонка для неперемещённых
            look: "glass",      // фон карточек: glass | solid | clear
            items: [
                { type: "clock", on: true, size: "M" },
                { type: "system", on: true, size: "M" },
                { type: "player", on: true, size: "M" },
                { type: "calendar", on: false, size: "M" },
                { type: "notifs", on: true, size: "M" },
                { type: "weather", on: false, size: "M" },
                { type: "notes", on: false, size: "M" },
                { type: "timer", on: false, size: "M" },
                { type: "actions", on: false, size: "M" },
                { type: "photo", on: false, size: "M" },
                { type: "updates", on: false, size: "M" },
                { type: "countdown", on: false, size: "M" },
                { type: "agents", on: false, size: "M" },
                { type: "claude", on: false, size: "M" },
                { type: "tokens", on: false, size: "M" },
                { type: "orbit", on: false, size: "M" },
                { type: "touch", on: false, size: "M" }
            ]
        },
        clock: {
            style: "digital",   // digital | analog | words | stack
            h24: true,
            seconds: false,
            date: "long",       // long | short | none
            zone: "",           // второй пояс: подпись
            offset: 0           // его смещение от UTC, ч
        },
        system: {
            view: "bars",       // bars — полосы, rings — кольца, graph — графики за минуту
            interval: 2,        // с
            cpu: true, ram: true, temp: true, disk: true, net: true,
            swap: false, gpu: false, igpu: false, freq: true, battery: false, uptime: true
        },
        weather: { city: "", units: "C", days: 3, provider: "open-meteo" },   // open-meteo | metno | wttr
        calendar: { weeks: false },
        player: { compact: false, mini: true },
        notes: { text: "", size: 13 },
        timer: { work: 25, rest: 5 },                         // мин
        actions: { list: ["terminal", "files", "screenshot", "lock", "drawer", "programs"] },
        photo: { dir: "~/Pictures", interval: 30 },           // с
        updates: { interval: 60 },                            // мин
        countdown: { title: "Новый год", date: "2027-01-01" },
        orbit: { enabled: true, bar: true, dock: true, indock: false, autostart: true, claude: true, claudeMin: 20 },   // claude — сообщать на устройства, что Claude закончил работу; claudeMin — не короче стольких секунд             // верхний док устройств; запуск Orbit в фоне, когда он нужен
        // переход курсора между компьютерами (Orbit): links — [{ device, name, side }], side — край этого экрана (left|right|top|bottom|off);
        // effect — glow | ripple | sparks | line | portal | none; color — accent | accent2 | white | #RRGGBB; delay — задержка на краю, мс
        crossing: { enabled: false, effect: "glow", color: "accent", duration: 700, intensity: 1.0, delay: 120, links: [] },
        touchpad: { left: "", right: "", middle: "", dot: "", dotSize: 9 },        // цвета — имя цвета темы (accent, red, green…) или #RRGGBB; пусто — по умолчанию
        claude: { view: "rings" },                          // rings | bars
        tokens: { view: "chart" },                          // chart | numbers
        agents: { ask: "claude", last: true, quota: true, bar: false },   // кого спрашивать; последнее сообщение; лимиты Claude (запрос с токеном Claude Code); лимит в баре
        lock: {
            style: "theme",     // theme — по комплекту темы | ios | glass | aurora | terminal | minimal
            notifs: true,       // уведомления на экране блокировки
            player: true,
            seconds: false
        },
        notifs: { dnd: false },
        // производительность: auto — экономно от батареи, normal, eco
        perf: { mode: "auto" },
        // жест от верхнего края: auto — только с сенсорным экраном, on, off
        touch: { edge: "auto" },
        // профили: набор настроек одним нажатием; значения "keep" (не менять) | "on" | "off", яркость 0 — не менять
        profiles: {
            active: "normal",
            items: [
                { id: "normal", name: "Обычный", icon: "󰋜", dnd: "off", caffeine: "off", night: "off", animations: "on", blur: "on", rgb: "on", brightness: 0, nightTemp: 4000 },
                { id: "work", name: "Работа", icon: "󰃖", dnd: "on", caffeine: "off", night: "off", animations: "on", blur: "on", rgb: "keep", brightness: 0, nightTemp: 4000 },
                { id: "games", name: "Игры", icon: "󰊗", dnd: "on", caffeine: "on", night: "off", animations: "off", blur: "off", rgb: "keep", brightness: 0, nightTemp: 4000 },
                { id: "night", name: "Ночь", icon: "󰖔", dnd: "on", caffeine: "off", night: "on", animations: "on", blur: "on", rgb: "off", brightness: 30, nightTemp: 3500 }
            ]
        },
        // буфер обмена: история (cliphist) и закреплённые записи
        clipboard: { on: true, pins: [] },
        // запись экрана (Recorder.qml, окно «Запись экрана»): mp4 | gif; звук none | desktop | mic | both; качество medium | high | ultra
        rec: { fmt: "mp4", audio: "desktop", fps: 60, quality: "high", gifFps: 15, gifWidth: 640, cursor: true, delay: 0 },
        // шторка NameLess: крупные и малые плитки по порядку, во весь экран
        control: {
            big: ["wifi", "bt", "dnd", "theme", "desktop", "display"],
            small: ["programs", "mic", "screenshot", "record", "night", "wallpaper", "orbit"],
            orbitSeeded: false,     // станет true после того, как плитка Orbit один раз окажется на шторке (дальше её можно убрать и вернуть самому)
            full: false,
            style: "desktop",       // вид: desktop — окно под баром, как раньше; mobile — шторка от верхнего края, как на планшете
            align: "right",         // где открывается: left | center | right
            wmode: "normal",        // ширина шторки: narrow | normal | wide | full
            height: 0,              // высота, px (ручка внизу шторки); 0 — по содержимому; меньше 300 не действует
            cols: 2,                // крупных плиток в ряд
            scols: 5,               // малых плиток в ряд
            recAudio: "desktop"     // звук записи: none | desktop | mic
        },
        // подсветка: свои цвета и цвета перелива (сам цвет и эффект хранит rgb.sh)
        rgb: { custom: [], gradient: ["ff2d55", "0a84ff", "34c759"] },
        // диспетчер задач: вкладка (1 — производительность, 0 — процессы), группировка по приложениям, сортировка
        tasks: { tab: 1, group: true, sort: "cpu", desc: true },
        // мастер программ: вид списка и сортировка
        programs: { view: "list", sort: "state" },     // list | compact | grid; state | name | size
        // звёздное небо (вид с Земли, режим stars)
        sky: {
            palette: "theme",   // theme — цвета темы | deep — глубокий синий | violet | teal | ember — закат
            stars: 1.0,         // плотность звёзд, 0.3–2
            twinkle: true,      // мерцание
            meteors: true,      // падающие звёзды
            meteorRate: 1.0,    // частота, 0.3–3
            nebula: 1.0,        // яркость туманностей, 0 — нет
            milkyway: true,     // Млечный Путь
            constellations: true,
            moon: true,         // Луна в настоящей фазе
            daytime: true       // сумерки и рассвет по времени суток
        },
        // космос (вид из космоса, режим solar): фон глубокого космоса, солнечная система, спутники, звёздные системы
        space: {
            bgStars: 1.0,       // звёзды фона, 0.3–2
            bgNebula: 1.0,      // туманности, 0–2
            galaxies: true,     // далёкие галактики
            satellites: true,   // искусственные спутники Земли: МКС, Хаббл, связь
            systems: true,      // ближайшие звёздные системы на краю: Альфа Центавра, Сириус…
            speed: 1,           // 0 — пауза, 1, 10, 100
            labels: true,
            orbits: true,
            belt: true,         // пояс астероидов
            kuiper: true,       // пояс Койпера за Нептуном
            moons: true,        // спутники: Луна, Фобос и Деймос, галилеевы, Титан, Тритон
            comet: true,        // комета Галлея с хвостом от Солнца
            details: true,      // поверхности: полосы Юпитера, облака Земли, полярные шапки, кольца Сатурна
            planetScale: 1.0,   // размер планет, 0.6–2
            spread: 1.0,        // расстояния между орбитами, 0.7–1.6
            follow: true,       // камера следует за выбранной планетой
            // что открывает планета: «action:имя» — системная кнопка, иначе — id ярлыка приложения
            planets: { mercury: "action:terminal", venus: "action:drawer", earth: "action:files", mars: "action:monitor",
                       jupiter: "action:programs", saturn: "action:desktop", uranus: "action:display", neptune: "action:control" }
        }
    })

    // не «data»: так называется свойство, куда QML кладёт дочерние объекты (FileView, Process, Timer)
    property var store: defaults
    property bool ready: false
    readonly property var dock: store.dock
    readonly property var widgets: store.widgets
    readonly property var lock: store.lock

    // недостающие ключи — из значений по умолчанию; новые виды виджетов добавляются выключенными
    function merge(def, v) {
        if (v === undefined || v === null) return def;
        if (Array.isArray(def) || typeof def !== "object") return v;
        var out = {};
        for (var k in def) out[k] = merge(def[k], v[k]);
        for (var k2 in v) if (out[k2] === undefined) out[k2] = v[k2];
        return out;
    }
    function normalize(d) {
        var items = (d.widgets.items || []).filter(function (x) { return x && cfg.kinds[x.type] !== undefined; });
        var have = items.map(function (x) { return x.type; });
        for (var k in kinds) if (have.indexOf(k) < 0) items.push({ type: k, on: false });
        d.widgets.items = items.map(function (x) { return Object.assign({ size: "M" }, x); });
        // прежние настройки (до параметров виджетов): ширина колонки → размер
        delete d.widgets.width;
        return d;
    }

    // изменение по пути «dock.size»: копируются только узлы на пути — нетронутые ветки остаются теми же объектами,
    // и их привязки (док, виджеты) не пересчитываются; запись в файл с задержкой (ползунки шлют подряд)
    // значение по пути «clipboard.on»; привязки, читающие его, обновляются вместе с настройками
    function get(keyPath) { var o = store, k = keyPath.split("."); for (var i = 0; i < k.length && o !== undefined && o !== null; i++) o = o[k[i]]; return o; }

    function set(keyPath, value) {
        var keys = keyPath.split(".");
        function put(o, i) {
            var c = Object.assign({}, (typeof o === "object" && o !== null) ? o : {});
            c[keys[i]] = i === keys.length - 1 ? value : put(c[keys[i]], i + 1);
            return c;
        }
        store = put(store, 0);
        // файл ещё не прочитан: изменение повторится поверх него, иначе загрузка его затрёт
        if (!ready) pending.push([keyPath, value]);
        else saveT.restart();
    }
    property var pending: []
    function replay() {
        var l = pending;
        pending = [];
        ready = true;
        for (var i = 0; i < l.length; i++) set(l[i][0], l[i][1]);
    }

    // ---------- док ----------
    function isPinned(id) { return dock.pinned.indexOf(id) >= 0; }
    function pin(id) { if (id && !isPinned(id)) set("dock.pinned", dock.pinned.concat([id])); }
    function unpin(id) { set("dock.pinned", dock.pinned.filter(function (x) { return x !== id; })); }
    function togglePin(id) { if (isPinned(id)) unpin(id); else pin(id); }
    // перетаскивание в доке: поставить на место index
    function movePinTo(id, index) {
        var l = dock.pinned.filter(function (x) { return x !== id; });
        l.splice(Math.max(0, Math.min(l.length, index)), 0, id);
        set("dock.pinned", l);
    }
    function movePin(id, d) {
        var l = dock.pinned.slice(), i = l.indexOf(id), j = i + d;
        if (i < 0 || j < 0 || j >= l.length) return;
        l.splice(i, 1); l.splice(j, 0, id);
        set("dock.pinned", l);
    }

    // ---------- виджеты ----------
    function widgetOn(type) {
        var l = widgets.items;
        for (var i = 0; i < l.length; i++) if (l[i].type === type) return l[i].on;
        return false;
    }
    function item(type) {
        var l = widgets.items;
        for (var i = 0; i < l.length; i++) if (l[i].type === type) return l[i];
        return null;
    }
    // поле пункта виджета: on, size, x, y
    function setItem(type, key, value) {
        set("widgets.items", widgets.items.map(function (x) {
            if (x.type !== type) return x;
            var c = Object.assign({}, x); c[key] = value; return c;
        }));
    }
    function toggleWidget(type) { var it = item(type); if (it) setItem(type, "on", !it.on); }
    // перетаскивание: сразу x и y одной записью
    function placeWidget(type, x, y) {
        set("widgets.items", widgets.items.map(function (w) { return w.type === type ? Object.assign({}, w, { x: Math.round(x), y: Math.round(y) }) : w; }));
    }
    // вернуть все виджеты в колонку
    function unplaceWidgets() {
        set("widgets.items", widgets.items.map(function (w) { var c = Object.assign({}, w); delete c.x; delete c.y; return c; }));
    }
    // сетка: перенести виджет в колонку col и встать перед виджетом before (или в конец)
    function gridMove(type, col, before) {
        var l = widgets.items.slice(), i = -1;
        for (var k = 0; k < l.length; k++) if (l[k].type === type) i = k;
        if (i < 0) return;
        var it = Object.assign({}, l.splice(i, 1)[0], { col: col });
        var j = l.length;
        if (before) for (var m = 0; m < l.length; m++) if (l[m].type === before) { j = m; break; }
        l.splice(j, 0, it);
        set("widgets.items", l);
    }
    function moveWidget(type, d) {
        var l = widgets.items.slice(), i = -1;
        for (var k = 0; k < l.length; k++) if (l[k].type === type) i = k;
        var j = i + d;
        if (i < 0 || j < 0 || j >= l.length) return;
        var x = l.splice(i, 1)[0]; l.splice(j, 0, x);
        set("widgets.items", l);
    }
    function resetWidgets() { set("widgets", JSON.parse(JSON.stringify(defaults.widgets))); }

    // ---------- файл ----------
    property string written: ""
    FileView {
        id: file
        path: cfg.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            var t = text();
            // своя же запись вернулась через слежение: данные уже те же, привязки не трогаем
            if (t === cfg.written) return;
            try { cfg.store = cfg.normalize(cfg.merge(cfg.defaults, JSON.parse(t))); } catch (e) { }
            if (!cfg.ready) cfg.replay();
        }
        onLoadFailed: (err) => { if (err === FileViewError.FileNotFound) migrate.running = true; else cfg.replay(); }
    }
    // первый запуск: папка настроек и закреплённые приложения из dock.txt
    Process {
        id: migrate
        command: ["sh", "-c", "mkdir -p \"$1\"; cat \"$1/dock.txt\" 2>/dev/null", "sh", cfg.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.split("\n").map(function (x) { return x.trim(); }).filter(function (x) { return x !== "" && x.charAt(0) !== "#"; });
                // изменения, сделанные до конца миграции, применяются после списка дока из dock.txt
                cfg.store = cfg.normalize(cfg.merge(cfg.defaults, cfg.store));
                if (l.length > 0) cfg.pending.unshift(["dock.pinned", l]);
                cfg.replay();
                cfg.save();
            }
        }
    }
    function save() {
        written = JSON.stringify(store, null, 2) + "\n";
        file.setText(written);
    }
    Timer { id: saveT; interval: 400; onTriggered: cfg.save() }
}
