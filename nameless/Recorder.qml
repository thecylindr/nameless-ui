pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Запись экрана: gpu-screen-recorder (аппаратное кодирование, если установлен), иначе wf-recorder.
//   start("screen" | "area", звук)   звук: none | desktop — звук компьютера | mic — микрофон
//   stop()                           SIGINT: файл корректно закрывается
// Настройки записи — Config.store.rec (окно «Запись экрана», RecorderPanel.qml): формат (видео MP4 или GIF), звук, частота, качество, курсор, отсчёт.
// Файлы — ~/Videos/Записи/запись-ДАТА.mp4 (или .gif); по окончании — уведомление. Готовые записи можно превратить в GIF, убрать звук, удалить.
// Индикатор и таймер — в баре
Singleton {
    id: r
    property bool recording: false
    property bool starting: false
    property string file: ""
    property date since: new Date()
    property int elapsed: 0
    property string audio: "desktop"
    property bool processing: false            // идёт обработка готового файла (GIF, удаление звука)
    property var recent: []                    // последние записи: [{ path, name, size, gif }]
    property bool gsr: false
    readonly property string dir: Quickshell.env("HOME") + Tr.t("/Videos/Записи")
    readonly property var cfg: Config.store.rec || ({})
    function opt(k, d) { var v = cfg[k]; return v === undefined || v === null ? d : v; }

    Process {
        running: true
        command: ["sh", "-c", "command -v gpu-screen-recorder >/dev/null && echo gsr || echo wf"]
        stdout: StdioCollector { onStreamFinished: r.gsr = text.trim() === "gsr" }
    }
    Timer { interval: 1000; repeat: true; running: r.recording; onTriggered: r.elapsed = Math.round((Date.now() - r.since.getTime()) / 1000) }
    function clock() { var s = elapsed; return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60); }

    Process {
        id: proc
        onStarted: { r.starting = false; r.recording = true; r.since = new Date(); r.elapsed = 0; }
        onExited: (code) => {
            var was = r.recording;
            r.recording = false; r.starting = false;
            if (was && r.tmpFile !== r.finalFile) r.toGif(r.tmpFile, r.finalFile, true);
            else if (was) { Quickshell.execDetached(["notify-send", "-a", Tr.t("Запись экрана"), "-i", "media-record", Tr.t("Запись сохранена"), r.file]); r.scan(); }
            else if (code !== 0) Quickshell.execDetached(["notify-send", "-a", Tr.t("Запись экрана"), "-u", "critical", Tr.t("Запись не началась"), Tr.t("код ") + code]);
        }
    }

    property string finalFile: ""              // итоговый файл: для GIF — .gif, а запись идёт во временный .mp4
    property string tmpFile: ""
    function start(mode, snd) {
        if (recording || starting) return;
        var fmt = opt("fmt", "mp4"), gif = fmt === "gif";
        audio = gif ? "none" : (snd || opt("audio", Config.store.control.recAudio || "desktop"));
        var stamp = new Date().toLocaleString(Qt.locale("C"), "yyyy-MM-dd_HH-mm-ss");
        finalFile = dir + Tr.t("/запись-") + stamp + (gif ? ".gif" : ".mp4");
        tmpFile = gif ? dir + Tr.t("/.запись-") + stamp + ".mp4" : finalFile;
        file = finalFile;
        var fps = gif ? Math.max(24, Number(opt("fps", 60))) : Number(opt("fps", 60));
        var q = opt("quality", "high");
        var delay = Number(opt("delay", 0));
        // область — slurp (выбирается до отсчёта); звук компьютера — монитор устройства вывода по умолчанию
        var sh = "mkdir -p \"$1\"; g=''; " + (mode === "area" ? "g=\"$(slurp)\" || exit 3; " : "")
               + "[ \"$3\" -gt 0 ] && sleep \"$3\"; mon=\"$(pactl get-default-sink 2>/dev/null).monitor\"; ";
        if (gsr) {
            var a = audio === "desktop" ? " -a default_output" : (audio === "mic" ? " -a default_input" : (audio === "both" ? " -a 'default_output|default_input'" : ""));
            var gq = { medium: "medium", high: "high", ultra: "very_high" }[q] || "high";
            sh += "set -- -w " + (mode === "area" ? "region -region \"$g\"" : "screen") + " -f " + fps + " -q " + gq
                + (opt("cursor", true) === false ? " -cursor no" : "") + " -o \"$2\"" + a + "; exec gpu-screen-recorder \"$@\"";
        } else {
            var crf = { medium: 28, high: 23, ultra: 18 }[q] || 23;
            sh += "set -- -f \"$2\" -r " + fps + " -p crf=" + crf + (mode === "area" ? " -g \"$g\"" : "")
                + (audio === "desktop" || audio === "both" ? " --audio=\"$mon\"" : (audio === "mic" ? " --audio" : "")) + "; exec wf-recorder -y \"$@\"";
        }
        starting = true;
        proc.command = ["sh", "-c", sh, "sh", dir, tmpFile, String(delay)];
        proc.running = true;
    }
    // ---------- обработка готовых записей ----------
    Process {
        id: work
        property string done: ""
        onExited: (code) => {
            r.processing = false;
            Quickshell.execDetached(["notify-send", "-a", Tr.t("Запись экрана"), code === 0 ? Tr.t("Готово") : Tr.t("Не получилось"), work.done]);
            r.scan();
        }
    }
    // в GIF: палитра по самому кадру — без «каши» в цветах; ширина и частота — из настроек; исходный файл удаляется только у временной записи
    function toGif(src, dst, removeSrc) {
        if (processing) return;
        processing = true;
        var w = Number(opt("gifWidth", 640)), f = Number(opt("gifFps", 15));
        work.done = dst.substring(dst.lastIndexOf("/") + 1);
        work.command = ["sh", "-c", "ffmpeg -y -v error -i \"$1\" -vf \"fps=" + f + ",scale=" + w + ":-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=4\" -loop 0 \"$2\""
                        + (removeSrc ? " && rm -f \"$1\"" : ""), "sh", src, dst];
        work.running = true;
    }
    // без звука: дорожки копируются как есть (без пережатия)
    function mute(src) {
        if (processing || src.slice(-4) !== ".mp4") return;
        processing = true;
        var dst = src.slice(0, -4) + Tr.t("-без-звука.mp4");
        work.done = dst.substring(dst.lastIndexOf("/") + 1);
        work.command = ["ffmpeg", "-y", "-v", "error", "-i", src, "-c", "copy", "-an", dst];
        work.running = true;
    }
    function remove(src) { Quickshell.execDetached(["rm", "-f", src]); removeT.restart(); }
    Timer { id: removeT; interval: 400; onTriggered: r.scan() }
    function open(src) { Quickshell.execDetached(["xdg-open", src]); }

    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [], l = text.trim() === "" ? [] : text.trim().split("\n");
                for (var i = 0; i < l.length; i++) {
                    var f = l[i].split("\t");
                    if (f.length < 3) continue;
                    var p = f[2];
                    out.push({ path: p, name: p.substring(p.lastIndexOf("/") + 1), size: Number(f[1]), gif: p.slice(-4) === ".gif" });
                }
                r.recent = out;
            }
        }
    }
    function scan() {
        if (lister.running) return;
        lister.command = ["sh", "-c", "mkdir -p \"$1\"; find \"$1\" -maxdepth 1 -type f \\( -name '*.mp4' -o -name '*.gif' \\) ! -name '.*' -printf '%T@\\t%s\\t%p\\n' | sort -rn | head -8", "sh", dir];
        lister.running = true;
    }
    function fmtSize(b) { return b >= 1048576 ? (b / 1048576).toFixed(1) + Tr.t(" МБ") : Math.max(1, Math.round(b / 1024)) + Tr.t(" КБ"); }

    function stop() { if (proc.running) proc.signal(2); }
    function toggle(mode) { if (recording) stop(); else start(mode || "screen"); }
    function openFolder() { Quickshell.execDetached(["xdg-open", dir]); }

    IpcHandler {
        target: "record"
        function screen(): void { r.toggle("screen"); }
        function area(): void { r.toggle("area"); }
        function stop(): void { r.stop(); }
        function settings(): void { }
    }
}
