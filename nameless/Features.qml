import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Функции и производительность (плитка «Функции» на шторке): какие технологии используются, чего не хватает и сколько это стоит.
//   Режим производительности: авто (экономно от батареи) / обычный / экономный.
//   Каждая функция: готова или не хватает пакетов — кнопка «Установить» открывает терминал с pacman (нужен пароль sudo);
//   у части есть выключатель — выключенное не запускает ничего в фоне.
// Состояние пакетов проверяется при открытии и после установки
PanelWindow {
    id: w
    property var shell: null
    readonly property bool open: shell ? shell.featuresOpen : false
    function close() { if (shell) shell.featuresOpen = false; }
    property real progress: 0
    Component.onCompleted: { progress = Qt.binding(function () { return w.open ? 1 : 0; }); check(); }
    Behavior on progress { NumberAnimation { duration: Theme.dur(w.open); easing.type: Easing.OutCubic } }

    visible: progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-features"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    onOpenChanged: if (open) { check(); statT.restart(); Gpu.refresh(); }

    // ---------- реестр функций ----------
    // deps: [команда, пакет]; toggle — путь настройки (вкл/выкл); seg — выбор режима
    readonly property var feats: [
        { id: "clip", i: "󰅌", t: Tr.t("Буфер обмена"), about: Tr.t("история копирования, закреплённое (SUPER+SHIFT+V); в фоне — два наблюдателя wl-paste"), cost: Tr.t("низкая"),
          deps: [["cliphist", "cliphist"], ["wl-paste", "wl-clipboard"]], toggle: "clipboard.on" },
        { id: "ocr", i: "󰗊", t: Tr.t("Текст с экрана"), about: Tr.t("выделить область — текст в буфер (SUPER+SHIFT+T); работает только по запросу"), cost: Tr.t("нет"),
          deps: [["tesseract", "tesseract"], ["tess-rus", "tesseract-data-rus"], ["tess-eng", "tesseract-data-eng"]] },
        { id: "rec", i: "󰑋", t: Tr.t("Запись экрана"), about: Tr.t("экран и область со звуком (SUPER+ALT+R); работает только во время записи"), cost: Tr.t("нет"),
          deps: [["wf-recorder", "wf-recorder"], ["slurp", "slurp"]] },
        { id: "night", i: "󰖔", t: Tr.t("Ночной свет"), about: Tr.t("тёплый цвет экрана: плитка «Ночь» и профили"), cost: Tr.t("нет"), deps: [["hyprsunset", "hyprsunset"]] },
        { id: "pick", i: "󰈊", t: Tr.t("Пипетка"), about: Tr.t("цвет с экрана в буфер (плитка на шторке)"), cost: Tr.t("нет"), deps: [["hyprpicker", "hyprpicker"]] },
        { id: "mini", i: "󰎆", t: Tr.t("Мини-плеер в баре"), about: Tr.t("обложка, название, управление рядом со временем; раз в секунду опрашивает позицию трека"), cost: Tr.t("низкая"),
          deps: [], toggle: "player.mini" },
        { id: "quota", i: "󰚩", t: Tr.t("Лимиты Claude"), about: Tr.t("окно 5 часов и неделя в мониторе и виджете «Помощники»; раз в 2 минуты запрос с токеном Claude Code (токен не сохраняется)"), cost: Tr.t("низкая"),
          deps: [["curl", "curl"]], toggle: "agents.quota" },
        { id: "codexstats", i: "󰚩", t: Tr.t("Статистика Codex"), about: Tr.t("расход токенов, модели, проекты и последние лимиты из локальных журналов Codex; без сетевых запросов"), cost: Tr.t("низкая"), deps: [], toggle: "agents.codexStats" },
        { id: "quotabar", i: "󰚩", t: Tr.t("Лимит Claude в баре"), about: Tr.t("процент окна 5 часов рядом со временем; цвет — по запасу"), cost: Tr.t("низкая"), deps: [], toggle: "agents.bar" },
        { id: "orbit", i: "󰟀", t: Tr.t("Orbit — связь с устройствами"), about: Tr.t("главный выключатель: телефон и другие компьютеры (файлы, буфер, уведомления, экран). Выключено — Orbit не запускается, док, лента, виджет и уведомления про Claude молчат; включить можно и плиткой в Пункте управления"), cost: Tr.t("низкая"), deps: [], toggle: "orbit.enabled" },
        { id: "orbitbar", i: "󰟀", t: Tr.t("Orbit в баре"), about: Tr.t("значок Orbit справа в баре: нажатие открывает ленту устройств, правый клик включает и выключает Orbit целиком; зелёный — устройство подключено"), cost: Tr.t("низкая"), deps: [], toggle: "orbit.bar" },
        { id: "orbitindock", i: "󰟀", t: Tr.t("Orbit в нижнем доке"), about: Tr.t("верхняя таблетка с устройствами переезжает в док приложений: значок телефона рядом с «Загрузками», зелёная ссылка — устройство подключено; нажатие открывает ленту, правый клик включает и выключает Orbit"), cost: Tr.t("низкая"), deps: [], toggle: "orbit.indock" },
        { id: "orbitdock", i: "󰟀", t: Tr.t("Док Orbit"), about: Tr.t("таблетка под баром с подключёнными устройствами и зарядом; нажатие открывает ленту; раз в 5 секунд опрос Orbit"), cost: Tr.t("низкая"), deps: [], toggle: "orbit.dock" },
        { id: "orbitclaude", i: "󰚩", t: Tr.t("Claude → устройства Orbit"), about: Tr.t("когда Claude Code закончил работу (или ждёт ответа), уведомление приходит на телефон и подключённые устройства; раз в 4 секунды опрос, только пока они на связи"), cost: Tr.t("низкая"), deps: [], toggle: "orbit.claude" },
        { id: "orbitauto", i: "󰐊", t: Tr.t("Orbit в фоне"), about: Tr.t("запускать NameLess Orbit без окна, когда нужны устройства (док или виджет)"), cost: Tr.t("низкая"), deps: [], toggle: "orbit.autostart" },
        { id: "entries", i: "󰀻", t: Tr.t("Окна NameLess в меню приложений"), about: Tr.t("диспетчер задач, программы, обои, буфер, мониторы и другие окна ищутся в rofi и лаунчере как обычные программы"), cost: Tr.t("нет"), deps: [], toggle: "apps.entries" },
        { id: "edge", i: "󰏲", t: Tr.t("Жест от верхнего края"), about: Tr.t("потянуть вниз: шторка и уведомления; тонкая невидимая полоска у края экрана"), cost: Tr.t("низкая"), deps: [],
          seg: { path: "touch.edge", opts: [{ v: "auto", t: Tr.t("Авто") }, { v: "on", t: Tr.t("Вкл") }, { v: "off", t: Tr.t("Выкл") }] } },
        { id: "shots", i: "󰹑", t: Tr.t("Скриншоты"), about: Tr.t("область и экран (Print)"), cost: Tr.t("нет"), deps: [["grim", "grim"], ["slurp", "slurp"]] },
        { id: "sound", i: "󰕾", t: Tr.t("Проверка звука"), about: Tr.t("тест каналов и микрофона в панели «Звук»"), cost: Tr.t("нет"), deps: [["pw-play", "pipewire"], ["pw-record", "pipewire"]] }
    ]
    // состояние: команда → есть ли
    property var have: ({})
    property bool checking: true
    Process {
        id: checkProc
        command: ["sh", "-c", "for c in curl cliphist wl-paste tesseract wf-recorder slurp hyprsunset hyprpicker grim pw-play pw-record; do command -v $c >/dev/null && echo \"$c 1\" || echo \"$c 0\"; done; " +
                  "l=$(tesseract --list-langs 2>/dev/null); echo \"$l\" | grep -qx rus && echo 'tess-rus 1' || echo 'tess-rus 0'; echo \"$l\" | grep -qx eng && echo 'tess-eng 1' || echo 'tess-eng 0'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = {}, l = text.trim().split("\n");
                for (var i = 0; i < l.length; i++) { var f = l[i].split(" "); m[f[0]] = f[1] === "1"; }
                w.have = m; w.checking = false;
            }
        }
    }
    function check() { checking = true; if (!checkProc.running) checkProc.running = true; }
    function missing(f) {
        var out = [];
        for (var i = 0; i < f.deps.length; i++) if (!have[f.deps[i][0]] && out.indexOf(f.deps[i][1]) < 0) out.push(f.deps[i][1]);
        return out;
    }
    readonly property var allMissing: {
        var out = [];
        for (var i = 0; i < feats.length; i++) { var m = missing(feats[i]); for (var k = 0; k < m.length; k++) if (out.indexOf(m[k]) < 0) out.push(m[k]); }
        return checking ? [] : out;
    }

    // ---------- установка: терминал с pacman, потом повторная проверка ----------
    property bool installing: false
    Process {
        id: installProc
        onExited: { w.installing = false; w.check(); }
    }
    function install(pkgs) {
        if (installing || pkgs.length === 0) return;
        installing = true;
        installProc.command = ["kitty", "--class", "glassrice-pkg", "-e", "sh", "-c",
            "echo 'Устанавливаю: " + pkgs.join(" ") + "'; sudo pacman -S --needed " + pkgs.join(" ") + Tr.t("; echo; read -r -n1 -p 'Готово. Нажмите любую клавишу…'")];
        installProc.running = true;
    }

    // ---------- что занимает сам NameLess (при открытом окне, раз в 2 с) ----------
    property real cpu: 0
    property int rss: 0
    property real lastTicks: 0
    property real lastAt: 0
    FileView { id: fStat; path: "/proc/self/stat"; blockLoading: true; printErrors: false }
    FileView { id: fStatus; path: "/proc/self/status"; blockLoading: true; printErrors: false }
    Timer {
        id: statT
        interval: 2000; repeat: true; running: w.open; triggeredOnStart: true
        onTriggered: {
            fStat.reload(); fStatus.reload();
            var f = fStat.text().split(" "), ticks = (Number(f[13]) || 0) + (Number(f[14]) || 0), now = Date.now();
            if (w.lastAt > 0) w.cpu = Math.max(0, (ticks - w.lastTicks) / 100 / ((now - w.lastAt) / 1000) * 100);
            w.lastTicks = ticks; w.lastAt = now;
            var m = /VmRSS:\s+(\d+)/.exec(fStatus.text());
            w.rss = m ? Math.round(Number(m[1]) / 1024) : 0;
        }
    }

    // ---------- окно ----------
    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * w.progress }
    MouseArea { anchors.fill: parent; onClicked: w.close() }

    Surface {
        id: box
        alpha: Theme.overlayAlpha
        width: Math.min(parent.width - 40, 680)
        height: Math.min(parent.height - 60, 760)
        anchors.horizontalCenter: parent.horizontalCenter
        y: (parent.height - height) / 2 - 30 * (1 - w.progress)
        opacity: Math.min(1, w.progress * 2)
        radius: Theme.ios ? 30 : 22
        MouseArea { anchors.fill: parent }
        MoveArea { win: box; anchors { left: parent.left; right: parent.right; top: parent.top } height: 56 }
        focus: w.open
        Keys.onEscapePressed: w.close()

        Item {
            id: head
            x: 18; y: 14
            width: parent.width - 36; height: 40
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text { anchors.verticalCenter: parent.verticalCenter; text: "󰒓"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 22 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: Tr.t("Функции и производительность"); color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
                    Text { text: Tr.t("NameLess сейчас: ") + w.rss + Tr.t(" МБ, процессор ") + w.cpu.toFixed(1).replace(".", ",") + " %" + (Perf.eco ? Tr.t(" · экономный режим") : ""); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                }
            }
            GTile { anchors { right: parent.right; verticalCenter: parent.verticalCenter } ui: Theme; width: 36; height: 36; radius: 18; Text { anchors.centerIn: parent; text: "✕"; color: Theme.text; font.pixelSize: 13 } onClicked: w.close() }
        }

        Flickable {
            anchors { top: head.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 18; rightMargin: 18; bottomMargin: 18 }
            contentHeight: col.implicitHeight + 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: col
                width: parent.width
                spacing: 10

                // режим производительности
                Rectangle {
                    width: parent.width; height: pcol.implicitHeight + 24; radius: Theme.r(18)
                    color: Theme.fill(0.06); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.14)
                    Column {
                        id: pcol
                        x: 14; y: 12; width: parent.width - 28
                        spacing: 8
                        Text { text: Tr.t("Режим производительности"); color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                        GSegment {
                            ui: Theme
                            options: [{ v: "auto", t: Tr.t("Авто"), icon: "󰁹" }, { v: "normal", t: Tr.t("Обычный"), icon: "󰓅" }, { v: "eco", t: Tr.t("Экономный"), icon: "󰌪" }]
                            value: Perf.mode
                            onPicked: (v) => Config.set("perf.mode", v)
                        }
                        Text {
                            width: parent.width; wrapMode: Text.WordWrap
                            text: Tr.t("Экономный: живые фоны (небо, космос) — 30 кадров вместо 60 и без мерцания звёзд и метеоров, стекло без объёмного канта и теней, нагрузка и диспетчер опрашиваются реже. «Авто» включает его, пока ноутбук работает от батареи.")
                            color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
                        }
                    }
                }

                // графика ноутбука: какая видеокарта рисует, спит ли дискретная, кто её держит
                Rectangle {
                    visible: Gpu.hybrid
                    width: parent.width; height: gcol.implicitHeight + 24; radius: Theme.r(18)
                    color: Theme.fill(0.06); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.14)
                    Column {
                        id: gcol
                        x: 14; y: 12; width: parent.width - 28
                        spacing: 8
                        Row {
                            spacing: 8
                            Text { text: Tr.t("Графика"); color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Gpu.st.state === "suspended" ? Tr.t("󰒲 дискретная спит") : Tr.t("󰢮 дискретная работает")
                                color: Gpu.st.state === "suspended" ? Theme.green : Theme.yellow; font.family: Theme.iconFont; font.pixelSize: 11
                            }
                        }
                        GSegment {
                            ui: Theme
                            options: [{ v: "eco", t: Tr.t("Экономия"), icon: "󰌪" }, { v: "hybrid", t: Tr.t("Гибрид"), icon: "󰢮" }, { v: "performance", t: Tr.t("Производительность"), icon: "󰓅" }]
                            value: Gpu.st.mode
                            onPicked: (v) => Gpu.setMode(v)
                        }
                        Text {
                            width: parent.width; wrapMode: Text.WordWrap
                            text: Gpu.st.mode === "eco" ? Tr.t("Рисует встроенная, Hyprland не трогает дискретную — она спит. Мониторы на её портах (часто HDMI) не работают.")
                                  : (Gpu.st.mode === "performance" ? Tr.t("Всё рисует дискретная: быстрее в тяжёлых программах, батарея садится быстрее.")
                                  : Tr.t("Рабочий стол рисует встроенная, дискретная включается сама для игр и prime-run и засыпает без дела."))
                            color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
                        }
                        Text {
                            visible: Gpu.st.relogin === true
                            width: parent.width; wrapMode: Text.WordWrap
                            text: Tr.t("󰍃 Режим сменится после перезахода в сессию")
                            color: Theme.yellow; font.family: Theme.iconFont; font.pixelSize: 11
                        }
                        Row {
                            visible: (Gpu.st.holders || []).length > 0
                            width: parent.width; spacing: 8
                            Text {
                                width: parent.width - 8 - freeBtn.width; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                                text: Tr.t("На видеокарте: ") + (Gpu.st.holders || []).map(function (h) { return h.name; }).join(", ")
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 11
                            }
                            GButton { id: freeBtn; ui: Theme; height: 30; icon: "󰅖"; label: Tr.t("Закрыть их"); onClicked: Gpu.free() }
                        }
                        GSwitch {
                            ui: Theme; width: parent.width
                            label: Tr.t("Спрашивать при отключении зарядки")
                            sub: Tr.t("предложить перейти на встроенную, если дискретная работает от батареи")
                            checked: Gpu.o.ask !== false
                            onToggled: (v) => Config.set("gpu.ask", v)
                        }
                    }
                }

                // какие окна NameLess показывать в rofi и лаунчере
                Rectangle {
                    visible: (Config.store.apps || {}).entries !== false && w.shell !== null
                    width: parent.width; height: entCol.implicitHeight + 24; radius: Theme.r(18)
                    color: Theme.fill(0.06); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.14)
                    Column {
                        id: entCol
                        x: 14; y: 12; width: parent.width - 28
                        spacing: 8
                        Text { text: Tr.t("Окна NameLess в rofi и лаунчере"); color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { width: parent.width; wrapMode: Text.WordWrap; text: Tr.t("Нажмите, чтобы убрать окно из списка приложений или вернуть его. Само окно остаётся доступным с клавиш и шторки."); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                        Flow {
                            width: parent.width; spacing: 6
                            Repeater {
                                model: w.shell ? w.shell.entries.map(function (e) { return [e[0], e[1]]; }).concat([["nameless-themedrawer", "Оформление"]]) : []
                                Rectangle {
                                    id: ech
                                    required property var modelData
                                    readonly property bool on: ((Config.store.apps || {}).hidden || []).indexOf(modelData[0]) < 0
                                    width: echT.implicitWidth + 28; height: 30; radius: 15
                                    color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.85) : Theme.fill(0.08)
                                    Text { id: echT; anchors.centerIn: parent; text: (ech.on ? "󰄬 " : "󰅖 ") + Tr.t(ech.modelData[1]); color: ech.on ? "white" : Theme.sub; font.family: Theme.iconFont; font.pixelSize: 12 }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var h = ((Config.store.apps || {}).hidden || []).slice(), i = h.indexOf(ech.modelData[0]);
                                            if (i >= 0) h.splice(i, 1); else h.push(ech.modelData[0]);
                                            Config.set("apps.hidden", h);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // недостающие пакеты
                Rectangle {
                    visible: w.allMissing.length > 0
                    width: parent.width; height: 52; radius: Theme.r(16)
                    color: Qt.rgba(Theme.yellow.r, Theme.yellow.g, Theme.yellow.b, 0.14); border.width: 1; border.color: Qt.rgba(Theme.yellow.r, Theme.yellow.g, Theme.yellow.b, 0.4)
                    Text { x: 16; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 220; elide: Text.ElideRight; text: Tr.t("Не хватает: ") + w.allMissing.join(", "); color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                    GButton { anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } ui: Theme; height: 34; icon: "󰇚"; label: w.installing ? Tr.t("Устанавливаю…") : Tr.t("Установить всё"); on: true; active: !w.installing; onClicked: w.install(w.allMissing) }
                }

                Repeater {
                    model: w.feats
                    Rectangle {
                        id: fr
                        required property var modelData
                        readonly property var miss: w.checking ? [] : w.missing(modelData)
                        width: col.width; height: 70; radius: Theme.r(16)
                        color: Theme.fill(0.06); border.width: Theme.ios ? 0 : 1; border.color: Theme.line(0.14)
                        Text { id: fi; x: 16; anchors.verticalCenter: parent.verticalCenter; text: fr.modelData.i; color: fr.miss.length ? Theme.sub : Theme.accent; font.family: Theme.iconFont; font.pixelSize: 22 }
                        Column {
                            anchors { left: fi.right; leftMargin: 14; right: ctl.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Text { width: parent.width; elide: Text.ElideRight; text: fr.modelData.t; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { width: parent.width; elide: Text.ElideRight; text: fr.modelData.about; color: Theme.sub; font.family: Theme.font; font.pixelSize: 10 }
                            Text {
                                width: parent.width; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 10
                                text: w.checking ? Tr.t("проверяю…") : (fr.miss.length ? Tr.t("не хватает: ") + fr.miss.join(", ") : Tr.t("готово")) + Tr.t("  ·  нагрузка: ") + fr.modelData.cost
                                color: fr.miss.length ? Theme.yellow : "#34c759"
                            }
                        }
                        Row {
                            id: ctl
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 8
                            GButton { visible: fr.miss.length > 0; ui: Theme; height: 32; icon: "󰇚"; label: Tr.t("Установить"); active: !w.installing; onClicked: w.install(fr.miss) }
                            // выключатель
                            Rectangle {
                                visible: fr.modelData.toggle !== undefined
                                readonly property bool on: Config.get(fr.modelData.toggle || "x") !== false
                                width: 42; height: 24; radius: 12
                                color: on ? Theme.accent : Theme.fill(0.2)
                                Behavior on color { ColorAnimation { duration: 140 } }
                                Rectangle { width: 18; height: 18; radius: 9; y: 3; x: parent.on ? 21 : 3; color: "white"; Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Config.set(fr.modelData.toggle, !parent.on) }
                            }
                            GSegment {
                                visible: fr.modelData.seg !== undefined
                                ui: Theme; width: 180; implicitHeight: 30
                                options: fr.modelData.seg ? fr.modelData.seg.opts : []
                                value: fr.modelData.seg ? String(Config.get(fr.modelData.seg.path) || "auto") : ""
                                onPicked: (v) => Config.set(fr.modelData.seg.path, v)
                            }
                        }
                    }
                }
            }
        }
    }
}
