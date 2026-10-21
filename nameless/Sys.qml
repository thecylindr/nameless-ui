pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Mpris

// Системные данные: Wi-Fi, Bluetooth, яркость, батарея, плеер.
// Сеть и Bluetooth — редкий опрос (15 с) и сразу после действий; яркость — через scripts/brightness.sh (подсветка или DDC)
Singleton {
    id: s

    readonly property string home: Quickshell.env("HOME")

    // ---------- Wi-Fi ----------
    property bool wifiOn: false
    property string ssid: ""
    property int signal: 0
    readonly property string wifiIcon: !wifiOn ? "󰤭" : (ssid === "" ? "󰤯" : (signal >= 75 ? "󰤨" : signal >= 50 ? "󰤥" : signal >= 25 ? "󰤢" : "󰤟"))
    Process {
        id: netProc
        command: ["sh", "-c", "export LC_ALL=C; nmcli -t -f WIFI general 2>/dev/null; nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi 2>/dev/null | grep '^yes' | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.trim().split("\n");
                s.wifiOn = l[0] === "enabled";
                if (l.length > 1 && l[1] !== "") { var f = l[1].split(":"); s.ssid = f[1] || ""; s.signal = parseInt(f[2]) || 0; }
                else { s.ssid = ""; s.signal = 0; }
            }
        }
    }
    function toggleWifi() { Quickshell.execDetached(["nmcli", "radio", "wifi", wifiOn ? "off" : "on"]); wifiOn = !wifiOn; soon.restart(); }
    function wifiMenu() { Quickshell.execDetached([home + "/.config/rofi/wifi.sh"]); }

    // ---------- Bluetooth ----------
    property bool btOn: false
    property string btDevice: ""
    Process {
        id: btProc
        command: ["sh", "-c", "command -v bluetoothctl >/dev/null || exit 0; bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off; bluetoothctl devices Connected 2>/dev/null | head -n1 | cut -d' ' -f3-"]
        stdout: StdioCollector {
            onStreamFinished: { var l = text.trim().split("\n"); s.btOn = l[0] === "on"; s.btDevice = l.length > 1 ? l[1] : ""; }
        }
    }
    function toggleBt() { Quickshell.execDetached(["bluetoothctl", "power", btOn ? "off" : "on"]); btOn = !btOn; soon.restart(); }

    // ---------- яркость ----------
    property int brightness: -1           // -1 — неизвестно (нет подсветки и DDC)
    readonly property string brightnessScript: home + "/.config/waybar/scripts/brightness.sh"
    Process {
        id: brProc
        command: [s.brightnessScript]
        stdout: StdioCollector { onStreamFinished: { var v = parseInt(text); s.brightness = isNaN(v) ? -1 : v; } }
    }
    // абсолютное значение: разница с текущим уходит в brightness.sh шагом
    function setBrightness(v) {
        v = Math.round(Math.max(1, Math.min(100, v)));
        var d = v - (brightness < 0 ? 50 : brightness);
        if (d === 0) return;
        brightness = v;
        Quickshell.execDetached([brightnessScript, d > 0 ? "up" : "down", String(Math.abs(d))]);
    }

    // ---------- батарея ----------
    readonly property var bat: UPower.displayDevice
    readonly property bool hasBattery: bat !== null && bat !== undefined && bat.isPresent
    readonly property int batPct: hasBattery ? Math.round(bat.percentage <= 1.0 ? bat.percentage * 100 : bat.percentage) : 0
    readonly property bool charging: hasBattery && (bat.state === UPowerDeviceState.Charging || bat.state === UPowerDeviceState.FullyCharged)
    readonly property string batIcon: charging ? "󰂄" : (batPct >= 90 ? "󰁹" : batPct >= 70 ? "󰂀" : batPct >= 50 ? "󰁾" : batPct >= 30 ? "󰁼" : "󰁺")

    // ---------- плеер ----------
    // выбранный вручную (переключатель в карточке плеера), пока он есть; иначе играющий, иначе первый
    readonly property var players: Mpris.players.values
    property var chosen: null
    readonly property var player: {
        var ps = players;
        if (chosen && ps.indexOf(chosen) >= 0) return chosen;
        for (var i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i];
        return ps.length > 0 ? ps[0] : null;
    }
    function nextPlayer() {
        if (players.length < 2) return;
        chosen = players[(players.indexOf(player) + 1) % players.length];
    }
    function fmtTime(sec) {
        sec = Math.max(0, Math.floor(sec || 0));
        var h = Math.floor(sec / 3600), m = Math.floor(sec / 60) % 60, x = sec % 60;
        return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (x < 10 ? "0" : "") + x;
    }

    // ---------- «кофеин»: не гасить экран и не засыпать (hypridle учитывает блокировки systemd) ----------
    readonly property bool caffeine: inhibit.running
    Process { id: inhibit; command: ["systemd-inhibit", "--what=idle:sleep", "--who=NameLess UI", Tr.t("--why=Кофеин"), "sleep", "infinity"] }
    function setCaffeine(on) { if (on !== inhibit.running) toggleCaffeine(); }
    function toggleCaffeine() { if (inhibit.running) inhibit.signal(15); else inhibit.running = true; }

    // ---------- режим полёта: все радио (rfkill) ----------
    property bool airplane: false
    Process {
        id: rfProc
        command: ["sh", "-c", "rfkill -n -o SOFT list | grep -qv '^blocked' && echo off || echo on"]
        stdout: StdioCollector { onStreamFinished: s.airplane = text.trim() === "on" }
    }
    function toggleAirplane() { Quickshell.execDetached(["rfkill", airplane ? "unblock" : "block", "all"]); airplane = !airplane; soon.restart(); }

    // ---------- опрос ----------
    function refresh() {
        if (!netProc.running) netProc.running = true;
        if (!btProc.running) btProc.running = true;
        if (!brProc.running) brProc.running = true;
        if (!rfProc.running) rfProc.running = true;
    }
    Timer { id: soon; interval: 1500; onTriggered: s.refresh() }
    Timer { interval: 15000; running: true; repeat: true; triggeredOnStart: true; onTriggered: s.refresh() }
}
