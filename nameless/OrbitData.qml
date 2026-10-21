pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Состояние NameLess Orbit для виджета «Устройства»: читается по D-Bus (org.glassrice.NamelessOrbit, метод Status → JSON)
// через busctl. Опрос идёт только пока виджет включён и рабочий стол виден; Orbit не запущен — running=false, виджет предлагает запуск.
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
    property var reqs: []                 // запросы на сопряжение: deviceId, name, kind, code, outgoing
    readonly property int requests: reqs.length

    // подключённые первыми, затем остальные из «рядом»
    readonly property var devices: {
        var ids = {}, out = [];
        connected.forEach(function (c) { ids[c.deviceId] = true; out.push(Object.assign({}, c, { online: true })); });
        nearby.forEach(function (n) { if (!ids[n.deviceId]) out.push(Object.assign({}, n, { online: false, battery: -1, charging: false })); });
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
                } catch (e) { d.running = false; d.connected = []; d.nearby = []; d.reqs = []; }
            }
        }
        onExited: code => { if (code !== 0) { d.running = false; d.loaded = true; d.connected = []; d.nearby = []; d.reqs = []; d.autoLaunch(); } }
    }
    function refresh() { if (!sProc.running) sProc.running = true; }
    Timer { interval: 5000; repeat: true; running: d.need && !Compositor.covered; triggeredOnStart: true; onTriggered: d.refresh() }
    onNeedChanged: if (need) refresh()

    // ---------- команды ----------
    function call(method, sig, arg) {
        // «--» завершает параметры busctl: Claude часто начинает ответ с «- …» (список), и такой аргумент иначе читался бы как параметр —
        // уведомление уходило пустым или со сбитыми аргументами
        var cmd = ["busctl", "--user", "--", "call", svc, path, svc, method];
        if (sig !== "") cmd = cmd.concat([sig], arg);       // arg — строка или массив: у busctl каждый аргумент отдельно
        Quickshell.execDetached(cmd);
        later.restart();
    }
    Timer { id: later; interval: 700; onTriggered: { d.refresh(); interval = 700; } }
    function scan() { call("Scan", "", ""); }
    function setDiscovery(on) { call("SetDiscovery", "b", on ? "true" : "false"); }
    function connectTo(id) { call("Connect", "s", id); }
    function ring(id) { call("Ring", "s", id); }
    function sendClipboard(id) { call("SendClipboard", "s", id); }
    function show() { if (running) call("Show", "", ""); else Quickshell.execDetached(["nameless-orbit"]); }
    // Orbit не запущен, а он нужен — поднимаем без окна; пока файла нет (не собран), команда молча ничего не делает
    function autoLaunch() {
        if (launched || !autostart || !need) return;
        launched = true;
        Quickshell.execDetached(["sh", "-c", "command -v nameless-orbit >/dev/null && exec nameless-orbit --background"]);
        later.interval = 2500; later.restart();
    }
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
    function runCommand(deviceId, commandId) { call("RunCommand", "ss", [deviceId, commandId]); }
    // включить или выключить Orbit целиком; при выключении запущенный Orbit завершается (иначе он продолжит держать порт и сеть)
    function setEnabled(on) {
        Config.set("orbit.enabled", on);
        if (!on) { panelOpen = false; if (running) call("Quit", "", ""); running = false; connected = []; nearby = []; reqs = []; launched = false; }
        else { launched = false; refresh(); }
    }
    function toggleEnabled() { setEnabled(!enabled); }
    function accept(id) { call("AcceptPairing", "s", id); }
    function reject(id) { call("RejectPairing", "s", id); }
    function connectAddress(host, port) { call("ConnectAddress", "si", [host, String(port)]); }
    function launch() { Quickshell.execDetached(["nameless-orbit"]); later.interval = 2500; later.restart(); }

    function kindIcon(k) { return ({ phone: "󰏲", tablet: "󰓷", laptop: "󰌢", server: "󰒋" })[k] || "󰟀"; }
}
