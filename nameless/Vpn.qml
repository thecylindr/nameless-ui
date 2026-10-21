pragma Singleton
import QtQuick
import Quickshell

// Приложение VPN или прокси, если оно установлено: ищется среди ярлыков по названию (Clash, v2ray, WireGuard, Outline…).
// Нужно подсказкам «сервис не отвечает»: кнопка открывает это приложение, чтобы включить обходной путь
Singleton {
    readonly property var entry: {
        var l = DesktopEntries.applications.values, re = /clash|v2ray|v2rayn|vpn|wireguard|outline|nekoray|hiddify|sing-box|amnezia|shadowsocks|openvpn|xray|mihomo/i;
        for (var i = 0; i < l.length; i++) if (re.test(l[i].name || "") || re.test(l[i].id || "")) return l[i];
        return null;
    }
    readonly property bool available: entry !== null
    readonly property string name: entry ? entry.name : ""
    function open() { if (entry) AppRun.run(entry); }
}
