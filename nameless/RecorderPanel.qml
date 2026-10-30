import QtQuick
import Quickshell
import Quickshell.Wayland

// Запись экрана: настройки и готовые записи.
//   Настройки   — что снимать (экран или область), формат (видео MP4 или GIF), звук, частота кадров, качество, курсор, отсчёт
//   Записи      — последние файлы: открыть, превратить в GIF, убрать звук, удалить
// Значения лежат в Config.store.rec; саму запись делает Recorder.qml (gpu-screen-recorder или wf-recorder, GIF — через ffmpeg)
PanelWindow {
    id: w
    screen: Compositor.panelScreen
    property var shell: null
    readonly property bool open: shell ? shell.recorderOpen : false
    function close() { if (shell) shell.recorderOpen = false; }
    property real progress: 0
    property string mode: "screen"
    readonly property bool gif: Recorder.opt("fmt", "mp4") === "gif"
    Component.onCompleted: {
        progress = Qt.binding(function () { return w.open ? 1 : 0; });
        Recorder.scan();
    }
    onOpenChanged: if (open) Recorder.scan()
    Behavior on progress { NumberAnimation { duration: Theme.dur(w.open); easing.type: Easing.OutCubic } }

    visible: progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nameless-recorder"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dimAlpha * 0.6 * w.progress }
    MouseArea { anchors.fill: parent; onClicked: w.close() }

    // заголовок группы настроек
    component Cap: Text {
        color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6
    }

    Surface {
        id: box
        alpha: Theme.overlayAlpha
        width: Math.min(480, parent.width - 20)
        height: Math.min(parent.height - 70, col.implicitHeight + 32)
        x: parent.width - width - 10
        y: 48 + (1 - w.progress) * -20
        opacity: w.progress
        radius: Theme.ios ? 30 : 22
        MouseArea { anchors.fill: parent }
        MoveArea { win: box; anchors { left: parent.left; right: parent.right; top: parent.top } height: 56 }
        focus: w.open
        Keys.onEscapePressed: w.close()

        Flickable {
            anchors { fill: parent; margins: 16 }
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: col
                width: parent.width
                spacing: 10

                Item {
                    width: parent.width; height: 32
                    Text { anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Запись экрана"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.ios ? 22 : 19; font.weight: Font.Bold }
                    GTile {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        ui: Theme; width: 30; height: 30; radius: 15
                        Text { anchors.centerIn: parent; text: "✕"; color: Theme.text; font.pixelSize: 12 }
                        onClicked: w.close()
                    }
                }

                // ---------- старт ----------
                Row {
                    spacing: 8
                    GButton {
                        ui: Theme; height: 40; width: 218
                        icon: Recorder.recording ? "󰻃" : "󰑋"
                        label: Recorder.recording ? Tr.t("Остановить ") + Recorder.clock() : (Recorder.starting ? Tr.t("Запускаю…") : Tr.t("Начать запись"))
                        on: Recorder.recording
                        onClicked: { if (Recorder.recording) Recorder.stop(); else { w.close(); startT.restart(); } }
                    }
                    GButton { ui: Theme; height: 40; width: 218; icon: "󰉋"; label: Tr.t("Папка с записями"); onClicked: Recorder.openFolder() }
                }

                Cap { text: Tr.t("Что снимать") }
                GSegment {
                    ui: Theme
                    options: [{ v: "screen", t: Tr.t("Весь экран"), icon: "󰍹" }, { v: "area", t: Tr.t("Область"), icon: "󰩭" }]
                    value: w.mode
                    onPicked: (v) => w.mode = v
                }

                Cap { text: Tr.t("Формат") }
                GSegment {
                    ui: Theme
                    options: [{ v: "mp4", t: Tr.t("Видео MP4"), icon: "󰕧" }, { v: "gif", t: Tr.t("GIF (без звука)"), icon: "󰵸" }]
                    value: Recorder.opt("fmt", "mp4")
                    onPicked: (v) => Config.set("rec.fmt", v)
                }

                Cap { visible: !w.gif; text: Tr.t("Звук") }
                GSegment {
                    visible: !w.gif
                    ui: Theme
                    options: [{ v: "none", t: Tr.t("Без звука"), icon: "󰝟" }, { v: "desktop", t: Tr.t("Система"), icon: "󰓃" }, { v: "mic", t: Tr.t("Микрофон"), icon: "󰍬" }, { v: "both", t: Tr.t("Оба"), icon: "󰎈" }]
                    value: Recorder.opt("audio", "desktop")
                    onPicked: (v) => { Config.set("rec.audio", v); Config.set("control.recAudio", v === "both" ? "desktop" : v); }
                }
                Text {
                    visible: !w.gif && Recorder.opt("audio", "desktop") === "both" && !Recorder.gsr
                    width: parent.width; wrapMode: Text.WordWrap
                    text: Tr.t("«Оба» работает с gpu-screen-recorder; с wf-recorder пишется звук системы.")
                    color: Theme.sub; font.family: Theme.font; font.pixelSize: 11
                }

                Cap { text: w.gif ? Tr.t("Частота кадров GIF") : Tr.t("Частота кадров") }
                GSegment {
                    ui: Theme
                    options: w.gif ? [{ v: "10", t: "10" }, { v: "15", t: "15" }, { v: "20", t: "20" }] : [{ v: "30", t: "30" }, { v: "60", t: "60" }, { v: "120", t: "120" }]
                    value: String(w.gif ? Recorder.opt("gifFps", 15) : Recorder.opt("fps", 60))
                    onPicked: (v) => Config.set(w.gif ? "rec.gifFps" : "rec.fps", Number(v))
                }

                Cap { visible: w.gif; text: Tr.t("Ширина GIF, px") }
                GSegment {
                    visible: w.gif
                    ui: Theme
                    options: [{ v: "480", t: "480" }, { v: "640", t: "640" }, { v: "800", t: "800" }, { v: "1024", t: "1024" }]
                    value: String(Recorder.opt("gifWidth", 640))
                    onPicked: (v) => Config.set("rec.gifWidth", Number(v))
                }

                Cap { text: Tr.t("Качество записи") }
                GSegment {
                    ui: Theme
                    options: [{ v: "medium", t: Tr.t("Среднее") }, { v: "high", t: Tr.t("Высокое") }, { v: "ultra", t: Tr.t("Максимум") }]
                    value: Recorder.opt("quality", "high")
                    onPicked: (v) => Config.set("rec.quality", v)
                }

                Cap { text: Tr.t("Отсчёт перед стартом") }
                GSegment {
                    ui: Theme
                    options: [{ v: "0", t: Tr.t("Сразу") }, { v: "3", t: Tr.t("3 с") }, { v: "5", t: Tr.t("5 с") }, { v: "10", t: Tr.t("10 с") }]
                    value: String(Recorder.opt("delay", 0))
                    onPicked: (v) => Config.set("rec.delay", Number(v))
                }

                Cap { visible: Recorder.gsr; text: Tr.t("Курсор мыши") }
                GSegment {
                    visible: Recorder.gsr
                    ui: Theme
                    options: [{ v: "yes", t: Tr.t("Показывать") }, { v: "no", t: Tr.t("Скрыть") }]
                    value: Recorder.opt("cursor", true) === false ? "no" : "yes"
                    onPicked: (v) => Config.set("rec.cursor", v === "yes")
                }

                // ---------- готовые записи ----------
                Cap { text: Tr.t("Последние записи") + (Recorder.processing ? Tr.t(" · обработка…") : "") }
                Text {
                    visible: Recorder.recent.length === 0
                    text: Tr.t("Пока пусто — записи появятся здесь")
                    color: Theme.sub; font.family: Theme.font; font.pixelSize: 12
                }
                Repeater {
                    model: Recorder.recent
                    Item {
                        id: row
                        required property var modelData
                        property bool armed: false
                        width: col.width; height: 54
                        Rectangle { anchors.fill: parent; radius: Theme.r(16); color: Theme.fill(0.07) }
                        Text { x: 14; y: 9; width: parent.width - 190; elide: Text.ElideMiddle; text: row.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text { x: 14; y: 30; text: (row.modelData.gif ? "GIF" : Tr.t("Видео")) + " · " + Recorder.fmtSize(row.modelData.size); color: Theme.sub; font.family: Theme.font; font.pixelSize: 11 }
                        Row {
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            spacing: 4
                            GTile { ui: Theme; width: 30; height: 30; radius: 15; Text { anchors.centerIn: parent; text: "󰐊"; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 13 } onClicked: Recorder.open(row.modelData.path) }
                            // в GIF: из видео; исходное остаётся
                            GTile {
                                visible: !row.modelData.gif; ui: Theme; width: 30; height: 30; radius: 15; enabled: !Recorder.processing
                                Text { anchors.centerIn: parent; text: "󰵸"; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 13 }
                                onClicked: Recorder.toGif(row.modelData.path, row.modelData.path.slice(0, -4) + ".gif", false)
                            }
                            // без звука: копия видео без дорожки звука
                            GTile {
                                visible: !row.modelData.gif; ui: Theme; width: 30; height: 30; radius: 15; enabled: !Recorder.processing
                                Text { anchors.centerIn: parent; text: "󰝟"; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 13 }
                                onClicked: Recorder.mute(row.modelData.path)
                            }
                            // удаление: первое нажатие — «точно?», второе — удалить
                            GTile {
                                ui: Theme; width: row.armed ? 72 : 30; height: 30; radius: 15
                                on: row.armed; onColor: Theme.red
                                Text { anchors.centerIn: parent; text: row.armed ? Tr.t("Удалить") : "󰆴"; color: row.armed ? "white" : Theme.red; font.family: row.armed ? Theme.font : Theme.iconFont; font.pixelSize: row.armed ? 11 : 13 }
                                onClicked: { if (row.armed) Recorder.remove(row.modelData.path); else { row.armed = true; disarm.restart(); } }
                                Timer { id: disarm; interval: 3000; onTriggered: row.armed = false }
                            }
                        }
                    }
                }
            }
        }
    }

    // окно успевает закрыться, и только потом начинается запись (и выбор области)
    Timer { id: startT; interval: 400; onTriggered: Recorder.start(w.mode) }
}
