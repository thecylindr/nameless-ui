// NameLess UI — своя оболочка для Hyprland и driftwm на Quickshell
//
//   qs -c nameless                                 запуск (theme.sh start, когда в теме shell = nameless)
//   qs -c nameless ipc call launcher toggle        лаунчер            (SUPER+R)
//   qs -c nameless ipc call notifs toggle | dnd    центр уведомлений / не беспокоить (SUPER+N / SUPER+SHIFT+N)
//   qs -c nameless ipc call control toggle         Пункт управления
//   qs -c nameless ipc call display toggle         мониторы: разрешение, частота, масштаб, счётчик кадров
//   qs -c nameless ipc call desktop toggle | widgets | dock   рабочий стол: виджеты и док
//   qs -c nameless ipc call programs toggle        мастер программ    (SUPER+I)
//   qs -c nameless ipc call widgets edit           расставить виджеты на рабочем столе
//   qs -c nameless ipc call clipboard toggle               буфер обмена: история, поиск, закреплённое (SUPER+SHIFT+V)
//   qs -c nameless ipc call wallpapers toggle | online    мастер обоев: мои и из интернета (SUPER+B)
//   qs -c nameless ipc call audio toggle           звук: выход, вход, приложения, проверка
//   qs -c nameless ipc call tasks toggle | perf | procs   диспетчер задач (SUPER+CTRL+ESC)
//   qs -c nameless ipc call record screen | area | stop   запись экрана
//   qs -c nameless ipc call lock lock              экран блокировки   (SUPER+L)
//   qs -c nameless ipc call keys toggle            справка: клавиши   (SUPER+F1)
//   qs -c nameless ipc call help toggle | welcome  справка: где что / приветствие
//   qs -c nameless ipc call orbit power | enable | disable   включить / выключить Orbit целиком (плитка в Пункте управления, «Функции»)
//   qs -c nameless ipc call orbit toggle | open | close   лента Orbit: устройства, сопряжение, «найти», буфер (верхний док — OrbitDock)
//   qs -c nameless ipc call theme reload           перечитать оформление (шлёт theme.sh)
//
// Окна-диалоги создаются лениво (Lazy.qml): пока окно не нужно, оно не занимает память. Всегда загружены только бар,
// док, виджеты, небо, уведомления, OSD и блокировка.
//
// Оформление — комплект активной темы theme.sh: классика (мой исходный дизайн), жидкое стекло (как клиент), iOS.

import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    // второй экземпляр (например, запущенный вручную после падения) закрывается сам: два бара и два дока ни к чему.
    // Остаётся старший процесс: $PPID внутри sh — это сам Quickshell
    Process {
        running: true
        command: ["sh", "-c", "for p in $(pgrep -f '^(qs|quickshell) -c nameless$'); do [ \"$p\" -lt \"$PPID\" ] && echo older; done"]
        stdout: StdioCollector { onStreamFinished: if (text.indexOf("older") >= 0) Qt.quit() }
    }

    // ---------- состояние открытых окон ----------
    property bool controlOpen: false
    property bool displayOpen: false
    property bool desktopOpen: false
    property bool widgetsEdit: false
    property bool recorderOpen: false       // окно «Запись экрана»
    property bool audioOpen: false          // окно «Звук» (правый клик по громкости)
    property bool tasksOpen: false          // диспетчер задач
    property bool wallpapersOpen: false     // мастер обоев
    property bool clipboardOpen: false      // буфер обмена
    property bool profilesOpen: false       // профили
    property bool featuresOpen: false       // функции и производительность
    property bool agentsOpen: false         // монитор помощников
    property int desktopTab: 0              // «Рабочий стол»: 0 — виджеты, 1 — док, 2 — космос, 3 — блокировка
    property string desktopExpanded: ""     // раскрытая строка виджета
    property bool welcomeLive: true         // плашка приветствия живёт несколько секунд после запуска
    Timer { interval: 4500; running: true; onTriggered: root.welcomeLive = false }

    // ---------- окна: загружаются при первом обращении ----------
    Lazy { id: controlL; want: root.controlOpen; ControlCenter { shell: root } }
    Lazy { id: displayL; want: root.displayOpen; Display { shell: root } }
    Lazy { id: desktopL; want: root.desktopOpen; Desktop { shell: root } }
    Lazy { id: audioL; want: root.audioOpen; AudioPanel { shell: root } }
    Lazy { id: recL; want: root.recorderOpen; RecorderPanel { shell: root } }
    Lazy { id: tasksL; want: root.tasksOpen; TaskManager { shell: root } }
    Lazy { id: wallsL; want: root.wallpapersOpen; Wallpapers { shell: root } }
    Lazy { id: clipL; want: root.clipboardOpen; Clipboard { shell: root } }
    Lazy { id: profL; want: root.profilesOpen; ProfilesPanel { shell: root } }
    Lazy { id: featL; want: root.featuresOpen; Features { shell: root } }
    Lazy { id: orbitL; want: OrbitData.panelOpen; OrbitRibbon { shell: root } }
    Lazy { id: agL; want: root.agentsOpen; AgentsPanel { shell: root } }
    Lazy { id: notifsL; want: Notifs.centerOpen; NotifCenter {} }
    // хранят своё состояние (поиск, вкладки, список пакетов): созданные раз, остаются
    Lazy { id: launcherL; keep: true; Launcher {} }
    Lazy { id: programsL; keep: true; Programs { shell: root } }
    Lazy { id: helpL; keep: true; Help { shell: root } }
    // первый запуск: выбор языка (после выбора окно уходит, язык — в «Пункт управления» → значок вида)
    Lazy { id: langL; want: Config.ready && Config.store.lang === ""; LangPicker {} }
    Lazy { id: welcomeL; want: root.welcomeLive; Welcome {} }

    // ---------- действия ----------
    function closeLauncher() { if (launcherL.item) launcherL.item.open = false; }
    function closePanels() { OrbitData.panelOpen = false; controlOpen = false; desktopOpen = false; closeLauncher(); Notifs.centerOpen = false; }
    function toggleAudio() { audioOpen = !audioOpen; if (audioOpen) { controlOpen = false; closeLauncher(); Notifs.centerOpen = false; desktopOpen = false; } }
    function toggleRecorder() { if (recorderOpen) recorderOpen = false; else { closePanels(); recorderOpen = true; } }
    function openTasks(tab) { if (tab !== undefined) Config.set("tasks.tab", tab); closePanels(); tasksOpen = true; }
    function openWallpapers(tab) { closePanels(); wallpapersOpen = true; if (tab !== undefined && wallsL.item) wallsL.item.tab = tab; }
    function toggleWallpapers() { if (wallpapersOpen) wallpapersOpen = false; else openWallpapers(); }
    function openOrbit() { if (!OrbitData.enabled) return; closePanels(); OrbitData.panelOpen = true; }
    function openAgents() { closePanels(); agentsOpen = true; }
    function openFeatures() { closePanels(); featuresOpen = true; }
    function openProfiles() { closePanels(); profilesOpen = true; }
    function toggleClipboard() { if (clipboardOpen) clipboardOpen = false; else { closePanels(); clipboardOpen = true; } }
    function toggleTasks() { if (tasksOpen) tasksOpen = false; else openTasks(); }
    function toggleLauncher() {
        controlOpen = false; desktopOpen = false; Notifs.centerOpen = false;
        launcherL.request(function (it) { it.pick = false; it.open = !it.open; });
    }
    // лаунчер в режиме выбора: клик закрепляет приложение в доке
    function pickForDock() {
        controlOpen = false; desktopOpen = false; Notifs.centerOpen = false;
        launcherL.request(function (it) { it.pick = true; it.open = true; });
    }
    function toggleControl() { controlOpen = !controlOpen; closeLauncher(); desktopOpen = false; Notifs.centerOpen = false; }
    function showHelp(tab) { helpL.request(function (it) { it.show(tab); }); }
    function toggleHelp(tab) { var it = helpL.item; if (it && it.open) it.close(); else showHelp(tab); }
    function openHelp() { controlOpen = false; showHelp(1); }
    function openKeys() { controlOpen = false; showHelp(2); }
    function openDisplay() { controlOpen = false; displayOpen = true; }
    // «Рабочий стол»: 0 — виджеты, 1 — док
    function openDesktop(tab) {
        desktopTab = tab; desktopExpanded = "";
        if (desktopL.item) { desktopL.item.tab = tab; desktopL.item.expanded = ""; }
        controlOpen = false; closeLauncher(); Notifs.centerOpen = false; desktopOpen = true;
    }
    // настройки одного виджета: панель «Рабочий стол», строка виджета раскрыта
    function openWidgetSettings(type) {
        openDesktop(0);
        desktopExpanded = type;
        if (desktopL.item) desktopL.item.expanded = type;
    }
    function openPrograms(tab) {
        controlOpen = false; desktopOpen = false; closeLauncher(); Notifs.centerOpen = false;
        programsL.request(function (it) { if (tab !== undefined) it.ptab = tab; it.open = true; });
    }

    // история буфера: наблюдатели wl-paste складывают копируемое в cliphist (если ещё не запущены, например MacShell'ом)
    Process {
        running: Config.store.clipboard.on !== false
        command: ["sh", "-c", "command -v cliphist >/dev/null && command -v wl-paste >/dev/null || exit 0; pgrep -f 'wl-paste --type text --watch cliphist' >/dev/null && exit 0; wl-paste --type text --watch cliphist store & wl-paste --type image --watch cliphist store & wait"]
    }

    // праздничные шаблоны по датам: при запуске темы это делает theme.sh, дальше — раз в 6 часов
    Timer { interval: 21600000; running: true; repeat: true; onTriggered: Quickshell.execDetached([Theme.script, "seasonal", "auto"]) }

    // сервис профилей: подключается, чтобы IPC-цели «profiles» работали сразу после запуска
    Component.onCompleted: { Profiles.active; OrbitNotify.on; }

    // первый запуск: приветствие через пару секунд после загрузки (флаг — файл в ~/.local/state/nameless)
    Process {
        running: true
        command: ["sh", "-c", "test -f \"$1\" && echo seen || echo new", "sh", (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/nameless/welcomed"]
        stdout: StdioCollector { onStreamFinished: if (text.trim() === "new") firstRun.start() }
    }
    Timer { id: firstRun; interval: 2400; onTriggered: root.showHelp(0) }

    // ---------- всегда загруженное ----------
    Sky {}
    Bar { shell: root }
    NotifPopups {}
    Osd {}
    EdgeSwipe { shell: root }
    Widgets { shell: root }
    CrossEdge { id: crossEdge }
    Dock { shell: root }
    OrbitDock { shell: root }
    Lock { id: lock }

    // открыт центр уведомлений — остальные панели закрываются
    Connections {
        target: Notifs
        function onCenterOpenChanged() { if (Notifs.centerOpen) { root.closeLauncher(); root.controlOpen = false; root.desktopOpen = false; } }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggleLauncher(); }
        function open(): void { launcherL.request(function (it) { it.open = true; }); }
        function close(): void { root.closeLauncher(); }
    }
    IpcHandler {
        target: "control"
        function toggle(): void { root.toggleControl(); }
    }
    IpcHandler {
        target: "desktop"
        function toggle(): void { if (root.desktopOpen) root.desktopOpen = false; else root.openDesktop(root.desktopTab); }
        function widgets(): void { root.openDesktop(0); }
        function dock(): void { root.openDesktop(1); }
        function cosmos(): void { root.openDesktop(2); }
        function lock(): void { root.openDesktop(3); }
    }
    IpcHandler {
        target: "tasks"
        function toggle(): void { root.toggleTasks(); }
        function perf(): void { root.openTasks(1); }
        function procs(): void { root.openTasks(0); }
    }
    IpcHandler {
        target: "orbit"
        function toggle(): void { if (OrbitData.panelOpen) OrbitData.panelOpen = false; else root.openOrbit(); }
        function open(): void { root.openOrbit(); }
        function close(): void { OrbitData.panelOpen = false; }
        function power(): void { OrbitData.toggleEnabled(); }      // включить / выключить Orbit целиком
        function enable(): void { OrbitData.setEnabled(true); }
        function disable(): void { OrbitData.setEnabled(false); }
    }
    // настройки перехода курсора — из шторки «Оформление» (вкладка «Курсор»): значение приходит JSON-строкой
    IpcHandler {
        target: "crossing"
        function set(key: string, value: string): void { try { Config.set("crossing." + key, JSON.parse(value)); } catch (e) { } }
        function preview(): void { crossEdge.preview(); }
        function stop(): void { OrbitData.crossStop(); }
    }
    IpcHandler {
        target: "agents"
        function toggle(): void { if (root.agentsOpen) root.agentsOpen = false; else root.openAgents(); }
    }
    IpcHandler {
        target: "features"
        function toggle(): void { if (root.featuresOpen) root.featuresOpen = false; else root.openFeatures(); }
    }
    IpcHandler {
        target: "profilesui"
        function toggle(): void { if (root.profilesOpen) root.profilesOpen = false; else root.openProfiles(); }
    }
    IpcHandler {
        target: "clipboard"
        function toggle(): void { root.toggleClipboard(); }
    }
    IpcHandler {
        target: "wallpapers"
        function toggle(): void { root.toggleWallpapers(); }
        function online(): void { root.openWallpapers(1); }
    }
    IpcHandler {
        target: "recorder"
        function toggle(): void { root.toggleRecorder(); }
    }
    IpcHandler {
        target: "audio"
        function toggle(): void { root.toggleAudio(); }
    }
    IpcHandler {
        target: "widgets"
        function edit(): void { root.desktopOpen = false; root.widgetsEdit = !root.widgetsEdit; }
    }
    IpcHandler {
        target: "programs"
        function toggle(): void { var p = programsL.item; if (p && p.open) p.open = false; else root.openPrograms(); }
    }
    IpcHandler {
        target: "display"
        function toggle(): void { if (root.displayOpen) root.displayOpen = false; else root.openDisplay(); }
    }
    // справка: клавиши (SUPER+F1) и «где что»
    IpcHandler {
        target: "keys"
        function toggle(): void { root.toggleHelp(2); }
    }
    IpcHandler {
        target: "help"
        function toggle(): void { root.toggleHelp(1); }
        function welcome(): void { root.showHelp(0); }
    }
}
