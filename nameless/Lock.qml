import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

// Экран блокировки NameLess UI: логика — здесь (PAM по правилам /etc/pam.d/hyprlock, ввод, сведения о системе),
// вид — отдельные файлы LockIos / LockGlass / LockAurora / LockTerminal / LockMinimal.
// Оформление — Config.lock.style; «theme» — по теме: классика → терминал, стекло → стекло, iOS → iOS,
// Аврора → сияние, EchoStar → стекло над звёздным небом.
// Ввод пароля один на все виды (невидимое поле): вид только показывает точки, ошибку и Caps Lock
Scope {
    id: root
    property bool locked: false
    property string pass: ""
    property bool busy: false
    property string error: ""
    property int fails: 0
    property bool unlocking: false
    property bool caps: false
    // iOS: сначала экран «спит» (время, уведомления), ввод открывается нажатием клавиши или клика
    property bool awake: false
    property string layout: ""
    property string avatar: ""
    property string host: ""
    property string kernel: ""
    property string wallpaper: ""
    readonly property string user: Quickshell.env("USER") || ""
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
    property date now: new Date()

    readonly property string style: {
        var s = Config.lock.style || "theme";
        if (s !== "theme") return s;
        if (Theme.st.current === "aurora") return "aurora";
        if (Theme.kit === "ios") return "ios";
        if (Theme.kit === "classic") return "terminal";
        return "glass";
    }
    readonly property string viewFile: ({ ios: "LockIos.qml", glass: "LockGlass.qml", aurora: "LockAurora.qml",
                                          terminal: "LockTerminal.qml", minimal: "LockMinimal.qml", neon: "LockNeon.qml",
                                          analog: "LockAnalog.qml", split: "LockSplit.qml" })[style] || "LockGlass.qml"

    function lock() {
        if (locked) return;
        pass = ""; error = ""; fails = 0; unlocking = false; awake = false; now = new Date();
        infoProc.running = true;
        checkCaps();
        locked = true;
    }
    function submit() {
        if (busy || pass === "" || unlocking) return;
        busy = true; error = "";
        if (!pam.start()) { busy = false; error = Tr.t("Не удалось начать проверку"); }
    }
    function wake() { awake = true; sleepT.restart(); }
    // без ввода 20 с — экран снова «засыпает» (iOS)
    Timer { id: sleepT; interval: 20000; onTriggered: if (root.pass === "") root.awake = false }
    // вход: растворение, затем снять блокировку
    Timer { id: unlockT; interval: 420; onTriggered: { root.locked = false; root.unlocking = false; root.pass = ""; } }
    Timer { interval: 1000; running: root.locked; repeat: true; onTriggered: root.now = new Date() }

    // обои, аватар, раскладка, имя машины, ядро — одним вызовом; поля разделены пустой строкой
    Process {
        id: infoProc
        command: ["sh", "-c",
            "cat \"$1/hypr-theme/wallpaper\" 2>/dev/null; echo; echo; " +
            "for f in \"$HOME/.face\" \"$HOME/.face.icon\" \"/var/lib/AccountsService/icons/$USER\"; do [ -f \"$f\" ] && { echo \"$f\"; break; }; done; echo; echo; " +
            Compositor.layoutQuery + "; echo; echo; " +
            "cat /etc/hostname 2>/dev/null || uname -n; echo; echo; uname -r",
            "sh", root.stateDir]
        stdout: StdioCollector {
            onStreamFinished: {
                var f = text.split("\n\n").map(function (x) { return x.trim(); });
                root.wallpaper = f[0] || "";
                root.avatar = f[1] || "";
                root.layout = f[2] || "";
                root.host = f[3] || "";
                root.kernel = f[4] || "";
            }
        }
    }
    // Caps Lock: светодиод клавиатуры, проверяется при нажатиях
    Process {
        id: capsProc
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null | sort -r | head -n1"]
        stdout: StdioCollector { onStreamFinished: root.caps = text.trim() !== "" && text.trim() !== "0" }
    }
    function checkCaps() { if (!capsProc.running) capsProc.running = true; }
    function nextLayout() {
        Compositor.nextLayout();
        layoutT.restart();
    }
    // раскладка: после нажатий (переключение сочетанием) — с задержкой, одним запросом
    Process {
        id: layoutProc
        command: ["sh", "-c", Compositor.layoutQuery]
        stdout: StdioCollector { onStreamFinished: if (text.trim() !== "") root.layout = text.trim() }
    }
    Timer { id: layoutT; interval: 250; onTriggered: if (!layoutProc.running) layoutProc.running = true }
    function checkLayout() { layoutT.restart(); }
    function power(kind) { Quickshell.execDetached(["systemctl", kind]); }

    PamContext {
        id: pam
        configDirectory: "/etc/pam.d"
        config: "hyprlock"
        onPamMessage: { if (this.responseRequired) this.respond(root.pass); }
        onCompleted: result => {
            root.busy = false;
            if (result === PamResult.Success) { root.unlocking = true; unlockT.restart(); }
            else { root.fails++; root.error = Tr.t("Неверный пароль"); root.pass = ""; }
        }
        onError: err => { root.busy = false; root.error = Tr.t("Ошибка проверки"); }
    }

    WlSessionLock {
        locked: root.locked

        WlSessionLockSurface {
            id: surf
            color: "#05070f"

            // общий ввод: невидимое поле получает все нажатия, виды показывают точки
            TextInput {
                id: input
                width: 1; height: 1
                opacity: 0
                echoMode: TextInput.Password
                focus: root.locked
                enabled: !root.busy && !root.unlocking
                text: root.pass
                onTextChanged: { root.pass = text; if (text !== "") { root.wake(); if (root.error !== "") root.error = ""; } }
                onAccepted: root.submit()
                // нажатие только отмечается и идёт дальше в поле: без accepted = false символы могли не попадать в пароль
                Keys.onPressed: (e) => { root.checkCaps(); root.checkLayout(); root.wake(); e.accepted = false; }
                Keys.onEscapePressed: { root.pass = ""; root.awake = false; }
            }
            // клик в любом месте — открыть ввод и вернуть фокус полю
            MouseArea { anchors.fill: parent; onClicked: { root.wake(); input.forceActiveFocus(); } }

            // вид; при входе — растворение с лёгким приближением
            Loader {
                anchors.fill: parent
                source: root.viewFile
                opacity: root.unlocking ? 0 : 1
                scale: root.unlocking ? 1.05 : 1
                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                onLoaded: item.lk = root
            }
        }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.lock(); }
    }
}
