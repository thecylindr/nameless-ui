pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Состояние NameLess Orbit для виджета «Устройства»: читается по D-Bus (org.glassrice.NamelessOrbit, метод Status → JSON)
// через busctl. Обновление — по сигналу Changed (dbus-monitor) и редким опросом на всякий случай; пока идёт сопряжение — опрос чаще.
// Опрос идёт только пока виджет включён и рабочий стол виден; Orbit не запущен — running=false, виджет предлагает запуск.
// Команды (поиск, подключение, сопряжение, «найти», буфер) — вызовы тех же методов D-Bus.
// Нужен Orbit в фоне — запускается сам (`nameless-orbit --background`, без окна), если не запущен и autostart не выключен
Singleton {
    id: d
    readonly property string svc: "org.glassrice.NamelessOrbit"
    readonly property string path: "/org/glassrice/NamelessOrbit"
    readonly property bool widgetOn: (Config.widgets.items || []).some(function (i) { return i.type === "orbit" && i.on; })
    // главный выключатель: «Функции» → «Orbit», плитка в Пункте управления, `ipc call orbit power`. Выключено — опроса нет, Orbit не запускается
    // и не нужен (останавливается), док, лента, виджет и уведомления про Claude молчат
    readonly property bool enabled: Config.store.orbit.enabled !== false
    readonly property bool dockOn: enabled && Config.store.orbit.dock !== false
    readonly property bool autostart: Config.store.orbit.autostart !== false
    property bool panelOpen: false        // выезжающая лента открыта
    readonly property bool need: enabled && (widgetOn || dockOn || panelOpen)
    property bool launched: false         // фоновый запуск пробовали — повторять не нужно

    property bool running: false          // Orbit отвечает на шине
    property bool loaded: false           // был хотя бы один ответ
    property bool discovery: false
    property string name: ""
    property var connected: []            // подключённые: deviceId, name, kind, address, battery (-1 нет), charging
    property var nearby: []               // найденные и сопряжённые, в том числе не на связи
    property var reqs: []                 // запросы на сопряжение: deviceId, name, kind, code, outgoing, localAccepted, remoteAccepted, secondsLeft
    readonly property int requests: reqs.length
    property double reqsAt: 0             // когда пришёл список запросов: от него отсчитывается secondsLeft
    property double now: Date.now()       // тикает раз в секунду, пока есть запросы (обратный отсчёт)
    Timer { interval: 1000; repeat: true; running: d.reqs.length > 0; onTriggered: d.now = Date.now() }
    function secondsLeft(r) { return Math.max(0, Math.round((r.secondsLeft || 0) - (d.now - d.reqsAt) / 1000)); }
    function reqFor(id) { for (var i = 0; i < reqs.length; i++) if (reqs[i].deviceId === id) return reqs[i]; return null; }

    // подключённые первыми, затем остальные из «рядом»; устройство, с которым идёт сопряжение, помечено pairing
    readonly property var devices: {
        var ids = {}, out = [], pend = {};
        reqs.forEach(function (r) { pend[r.deviceId] = true; });
        connected.forEach(function (c) { ids[c.deviceId] = true; out.push(Object.assign({}, c, { online: true, pairing: false })); });
        nearby.forEach(function (n) { if (!ids[n.deviceId]) out.push(Object.assign({}, n, { online: false, battery: -1, charging: false, pairing: pend[n.deviceId] === true })); });
        return out;
    }

    Process {
        id: sProc
        command: ["busctl", "--user", "--json=short", "--", "call", d.svc, d.path, d.svc, "Status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var r = JSON.parse(JSON.parse(text).data[0]);
                    d.running = true; d.loaded = true;
                    d.discovery = r.discoveryActive === true;
                    d.name = r.deviceName || "";
                    d.connected = r.connected || [];
                    d.nearby = r.nearby || [];
                    d.reqs = r.pairingRequests || [];
                    d.reqsAt = Date.now(); d.now = d.reqsAt;
                } catch (e) { d.running = false; d.connected = []; d.nearby = []; d.reqs = []; }
            }
        }
        onExited: code => { if (code !== 0) { d.running = false; d.loaded = true; d.connected = []; d.nearby = []; d.reqs = []; d.autoLaunch(); } }
    }
    // ответ пришёл, пока шёл прошлый запрос, — перечитать сразу после него, а не ждать следующего опроса
    property bool again: false
    function refresh() { if (!sProc.running) sProc.running = true; else again = true; }
    Connections { target: sProc; function onRunningChanged() { if (!sProc.running && d.again) { d.again = false; d.refresh(); } } }
    // страховочный опрос: сигнал Changed может потеряться (Orbit перезапущен); во время сопряжения — раз в секунду
    Timer { interval: d.reqs.length > 0 || d.panelOpen ? 1500 : 5000; repeat: true; running: d.need && !Compositor.covered; triggeredOnStart: true; onTriggered: d.refresh() }
    onNeedChanged: if (need) refresh()

    // сигнал Changed от Orbit: состояние перечитывается сразу (сопряжение, подключение, заряд) — без него ответ ждал до 5 секунд
    Process {
        id: watch
        running: d.need && d.running
        command: ["dbus-monitor", "--session", "type='signal',interface='" + d.svc + "',member='Changed'"]
        stdout: SplitParser { onRead: line => { if (line.indexOf("member=Changed") >= 0) soon.restart(); } }
    }
    Timer { id: soon; interval: 60; onTriggered: d.refresh() }

    // ---------- команды ----------
    function call(method, sig, arg) {
        // «--» завершает параметры busctl: Claude часто начинает ответ с «- …» (список), и такой аргумент иначе читался бы как параметр —
        // уведомление уходило пустым или со сбитыми аргументами
        var cmd = ["busctl", "--user", "--", "call", svc, path, svc, method];
        if (sig !== "") cmd = cmd.concat([sig], arg);       // arg — строка или массив: у busctl каждый аргумент отдельно
        Quickshell.execDetached(cmd);
        later.restart();
    }
    Timer { id: later; interval: 300; onTriggered: { d.refresh(); interval = 300; } }
    function scan() { call("Scan", "", ""); }
    function setDiscovery(on) { call("SetDiscovery", "b", on ? "true" : "false"); }
    // ---------- второй экран Orbit на этом компьютере ----------
    // сигнал VirtualScreen: open — монитор создан (чей он), closing — сейчас будет удалён: окна NameLess с него убираются заранее
    property var virtualScreens: ({})       // { HEADLESS-ORBIT-N: { peer, kind } }
    property var closingScreens: []
    Process {
        running: d.enabled
        command: ["dbus-monitor", "--session", "type='signal',interface='" + d.svc + "',member='VirtualScreen'"]
        stdout: SplitParser {
            onRead: line => {
                var i = line.indexOf("string \"");
                if (i < 0) return;
                try {
                    var o = JSON.parse(line.slice(i + 8, line.lastIndexOf("\"")));
                    var m = Object.assign({}, d.virtualScreens);
                    if (o.state === "open") { m[o.output] = { peer: o.peer, kind: o.kind }; d.closingScreens = d.closingScreens.filter(function (n) { return n !== o.output; }); }
                    else { delete m[o.output]; d.closingScreens = d.closingScreens.concat([o.output]); }
                    d.virtualScreens = m;
                } catch (e) { }
            }
        }
    }

    function connectTo(id) { call("Connect", "s", id); }
    function disconnectFrom(id) { call("Disconnect", "s", id); }
    function mediaCommand(id, action) { call("MediaCommand", "ss", [id, action]); }      // плеер устройства: playpause | next | previous
    function ring(id) { call("Ring", "s", id); }
    function sendClipboard(id) { call("SendClipboard", "s", id); }
    function show() { if (running) call("Show", "", ""); else spawnOrbit(""); }
    // Orbit не запущен, а он нужен — поднимаем без окна
    function autoLaunch() {
        if (launched || !autostart || !need) return;
        launched = true;
        start(false);
    }
    // quickshell стартует из Hyprland, где в PATH нет ~/.local/bin (туда install.sh кладёт ссылку на nameless-orbit): без этого «не найден исполняемый файл»
    readonly property string orbitPath: "export PATH=\"$HOME/.local/bin:$HOME/.local/opt/nameless-orbit:/usr/local/bin:/opt/nameless-orbit:/opt/nameless-orbit/bin:$PATH\"; "
    function spawnOrbit(args) { Quickshell.execDetached(["sh", "-c", orbitPath + "command -v nameless-orbit >/dev/null 2>&1 && exec nameless-orbit " + args]); }
    // ---------- запуск с понятным итогом (кнопка «Запустить») ----------
    // launchState: "" — нет запуска, starting — ждём ответа на шине, failed — не вышло (launchError — почему, launchFix — что можно сделать)
    property string launchState: ""
    property string launchError: ""
    property string launchFix: ""          // restart — Orbit работает, но не отвечает; window — открыть окно Orbit
    property int launchWaited: 0
    // 127 — программы нет; 3 — уже работает, но не на шине (раньше «Запустить» молча натыкалась на этот экземпляр); 0 — запущен
    // [/]bin — шаблон pgrep не совпадает с командной строкой самого sh
    Process {
        id: starter
        property bool restart: false
        command: ["sh", "-c", d.orbitPath + (restart ? "pkill -f '[/]bin/nameless-orbit'; for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -f '[/]bin/nameless-orbit' >/dev/null || break; sleep 0.3; done; "
                                       : "pgrep -f '[/]bin/nameless-orbit' >/dev/null && exit 3; ")
                             + "command -v nameless-orbit >/dev/null 2>&1 || exit 127; setsid -f nameless-orbit --background >/dev/null 2>&1; exit 0"]
        onExited: code => {
            if (code === 127) { d.launchState = "failed"; d.launchError = Tr.t("nameless-orbit не найден: Orbit не установлен (~/.local/bin/nameless-orbit)"); d.launchFix = ""; return; }
            if (code === 3) { d.launchState = "failed"; d.launchError = Tr.t("Orbit работает, но не отвечает NameLess UI (шина D-Bus)"); d.launchFix = "restart"; return; }
            d.launchWaited = 0; waitT.restart();
        }
    }
    function start(restart) {
        if (starter.running) return;
        launchState = "starting"; launchError = ""; launchFix = "";
        starter.restart = restart === true;
        starter.running = true;
    }
    // ждём регистрации на шине до 10 секунд, спрашивая раз в секунду
    Timer {
        id: waitT
        interval: 1000; repeat: true
        onTriggered: {
            if (d.running) { stop(); d.launchState = ""; return; }
            d.refresh();
            if (++d.launchWaited >= 10) {
                stop();
                d.launchState = "failed";
                d.launchError = Tr.t("Orbit не ответил за 10 секунд: откройте окно — в нём будет видна ошибка");
                d.launchFix = "window";
            }
        }
    }
    onRunningChanged: if (running) { launchState = ""; waitT.stop(); }
    // уведомление на подключённые устройства (пустой deviceId — на все)
    // сообщение об ответе Claude: Orbit сам решает, отправлять ли его (настройка «Сообщения об ответе Claude»)
    function notifyReply(title, body) { call("NotifyReply", "ss", [title, body]); }
    function notify(title, body, deviceId) { call("Notify", "sss", [title, body, deviceId || ""]); }
    // отправка файла: выбор файла штатным диалогом (kdialog, иначе zenity), затем SendFile по D-Bus
    property string pickFor: ""
    function sendFile(deviceId) {
        pickFor = deviceId;
        picker.running = false;
        picker.running = true;
    }
    Process {
        id: picker
        command: ["sh", "-c", "kdialog --getopenfilename \"$HOME\" 2>/dev/null || zenity --file-selection 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { var p = text.trim(); if (p !== "" && d.pickFor !== "") d.call("SendFile", "ss", [d.pickFor, p]); } }
    }
    function viewScreen(deviceId) { call("ViewScreen", "s", deviceId); }       // посмотреть экран устройства (откроется окно Orbit)
    function shareScreen(deviceId) { call("ShareScreen", "s", deviceId); }     // показать этому устройству свой экран
    function secondScreen(deviceId) { call("SecondScreen", "s", deviceId); }  // этот компьютер становится вторым монитором того устройства (где Hyprland или driftwm)
    // переход курсора на соседний компьютер (край экрана side, место pos 0..1, монитор screen); вернуть — CrossStop или Scroll Lock
    function crossTo(deviceId, side, pos, screen) { call("CrossTo", "ssds", [deviceId, side, String(pos), screen || ""]); }
    function crossStop() { call("CrossStop", "", ""); }
    function runCommand(deviceId, commandId) { call("RunCommand", "ss", [deviceId, commandId]); }
    // включить или выключить Orbit целиком; при выключении запущенный Orbit завершается (иначе он продолжит держать порт и сеть)
    function setEnabled(on) {
        Config.set("orbit.enabled", on);
        if (!on) { panelOpen = false; if (running) call("Quit", "", ""); running = false; connected = []; nearby = []; reqs = []; launched = false; }
        else { launched = false; refresh(); }
    }
    function toggleEnabled() { setEnabled(!enabled); }
    // ответ на сопряжение: карточка сразу показывает «ждём второе устройство», не дожидаясь ответа Orbit
    function patchReq(id, fields) { reqs = reqs.map(function (r) { return r.deviceId === id ? Object.assign({}, r, fields) : r; }); }
    function accept(id) { patchReq(id, { localAccepted: true }); call("AcceptPairing", "s", id); }
    function reject(id) { reqs = reqs.filter(function (r) { return r.deviceId !== id; }); call("RejectPairing", "s", id); }
    function connectAddress(host, port) { call("ConnectAddress", "si", [host, String(port)]); }
    function launch() { spawnOrbit(""); later.interval = 2500; later.restart(); }     // с окном

    function kindIcon(k) { return ({ phone: "󰏲", tablet: "󰓷", laptop: "󰌢", server: "󰒋" })[k] || "󰟀"; }
}
