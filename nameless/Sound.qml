pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Звук: громкость и микрофон через PipeWire (без опроса — изменения приходят сами)
Singleton {
    id: a

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [a.sink, a.source] }

    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property bool micMuted: source && source.audio ? source.audio.muted : false

    readonly property string icon: muted || volume <= 0.001 ? "󰝟" : (volume < 0.34 ? "󰕿" : (volume < 0.67 ? "󰖀" : "󰕾"))

    function setVolume(v) {
        if (!sink || !sink.audio) return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1.5, v));
    }
    function step(d) { setVolume(volume + d); }
    function toggleMute() { if (sink && sink.audio) sink.audio.muted = !sink.audio.muted; }
    function toggleMic() { if (source && source.audio) source.audio.muted = !source.audio.muted; }
}
