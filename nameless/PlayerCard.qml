import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris

// Карточка плеера (виджет и Пункт управления): размытая обложка фоном, обложка, трек, перемотка со временем,
// перемешивание, назад / пауза / вперёд, повтор; несколько плееров — переключатель в шапке.
// Позиция опрашивается раз в секунду и только пока карточка видна и трек играет
Item {
    id: c
    property real radius: 22
    property bool compact: false          // без перемотки — ниже
    readonly property var p: Sys.player
    readonly property bool has: p !== null && (p.trackTitle || "") !== ""
    readonly property string art: p ? (p.trackArtUrl || "") : ""
    readonly property real len: p && p.lengthSupported ? p.length : 0
    property real pos: 0
    property bool seeking: false

    implicitHeight: 196

    // позиция MPRIS сама не обновляется: сигнал раз в секунду
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: c.visible && c.p !== null && c.p.isPlaying
        onTriggered: { c.p.positionChanged(); if (!c.seeking) c.pos = c.p.position; }
    }
    onPChanged: pos = p ? p.position : 0

    ClippingRectangle {
        anchors.fill: parent
        radius: Theme.r(c.radius)
        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, Theme.panelAlpha)

        // фон: обложка, сильно размытая и затемнённая (картинка маленькая — размытие дешёвое и считается раз)
        Image {
            id: bgArt
            anchors.fill: parent
            source: c.art
            sourceSize: Qt.size(96, 96)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: bgArt
            visible: bgArt.status === Image.Ready
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 48
            blur: 1.0
            saturation: 0.35
            brightness: Theme.dark ? -0.25 : 0.1
            opacity: 0.85
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.10 : 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.35 : 0.12) }
            }
        }
    }
    Rim { anchors.fill: parent; ui: Theme; radius: Theme.r(c.radius); strength: 0.7 }

    // ---------- ничего не играет ----------
    Column {
        visible: !c.has
        anchors.centerIn: parent
        spacing: 6
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰝛"; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 30 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Tr.t("Ничего не играет"); color: Theme.sub; font.family: Theme.font; font.pixelSize: 13 }
    }

    Item {
        visible: c.has
        anchors.fill: parent
        anchors.margins: 14

        // шапка: обложка, трек, плеер
        Item {
            id: top
            width: parent.width
            height: 76

            Item {
                id: cover
                width: 76; height: 76
                RectangularShadow {
                    anchors.fill: parent
                    radius: Theme.r(16)
                    blur: 18
                    offset: Qt.vector2d(0, 6)
                    color: Qt.rgba(0, 0, 0, 0.4)
                }
                ClippingRectangle {
                    anchors.fill: parent
                    radius: Theme.r(16)
                    color: Theme.fill(0.14)
                    Image {
                        id: coverImg
                        anchors.fill: parent
                        source: c.art
                        sourceSize: Qt.size(160, 160)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Text { anchors.centerIn: parent; visible: coverImg.status !== Image.Ready; text: "󰝚"; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 30 }
                }
                // смена трека: обложка чуть «вдыхает»
                scale: c.p && c.p.isPlaying ? 1 : 0.94
                Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
            }

            Column {
                anchors { left: cover.right; leftMargin: 14; right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 3
                // плеер: название и переключатель, если их несколько
                Row {
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (c.p ? (c.p.identity || Tr.t("Плеер")) : "").toUpperCase()
                        color: Theme.sub
                        font.family: Theme.font
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.6
                    }
                    Rectangle {
                        visible: Sys.players.length > 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: swTxt.implicitWidth + 12; height: 16; radius: 8
                        color: swMa.containsMouse ? Theme.fill(0.22) : Theme.fill(0.12)
                        Text { id: swTxt; anchors.centerIn: parent; text: "󰒭 " + Sys.players.length; color: Theme.sub; font.family: Theme.iconFont; font.pixelSize: 9 }
                        MouseArea { id: swMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Sys.nextPlayer() }
                    }
                }
                Text {
                    width: parent.width
                    text: c.p ? (c.p.trackTitle || "") : ""
                    color: Theme.text
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    text: c.p ? [c.p.trackArtist || "", c.p.trackAlbum || ""].filter(function (x) { return x !== ""; }).join(" — ") : ""
                    color: Theme.sub
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
            // клик по шапке — окно плеера
            MouseArea {
                anchors.fill: parent
                enabled: c.p !== null && c.p.canRaise
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: c.p.raise()
                z: -1
            }
        }

        // перемотка
        Item {
            id: bar
            anchors { top: top.bottom; topMargin: 14 }
            width: parent.width
            height: 26
            visible: c.len > 0 && !c.compact
            readonly property real ratio: c.len > 0 ? Math.max(0, Math.min(1, c.pos / c.len)) : 0

            Rectangle {
                id: track
                width: parent.width
                height: seekMa.containsMouse || c.seeking ? 7 : 5
                radius: height / 2
                color: Theme.fill(0.18)
                Behavior on height { NumberAnimation { duration: 120 } }
                Rectangle {
                    width: Math.max(parent.height, parent.width * bar.ratio)
                    height: parent.height
                    radius: parent.radius
                    color: Theme.text
                    opacity: 0.9
                }
            }
            Text { anchors { left: parent.left; bottom: parent.bottom } text: Sys.fmtTime(c.pos / 1); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10; font.features: { "tnum": 1 } }
            Text { anchors { right: parent.right; bottom: parent.bottom } text: "-" + Sys.fmtTime(c.len - c.pos); color: Theme.sub; font.family: Theme.font; font.pixelSize: 10; font.features: { "tnum": 1 } }
            MouseArea {
                id: seekMa
                width: parent.width
                height: 16
                y: -5
                enabled: c.p !== null && c.p.canSeek
                hoverEnabled: true
                preventStealing: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                function at(x) { return Math.max(0, Math.min(1, x / width)) * c.len; }
                onPressed: (m) => { c.seeking = true; c.pos = at(m.x); }
                onPositionChanged: (m) => { if (pressed) c.pos = at(m.x); }
                onReleased: { c.p.position = c.pos; c.seeking = false; }
            }
        }

        // управление
        Row {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            spacing: 10
            PlayerBtn {
                icon: "󰒝"; small: true
                visible: c.p !== null && c.p.shuffleSupported
                lit: c.p !== null && c.p.shuffle
                onClicked: c.p.shuffle = !c.p.shuffle
            }
            PlayerBtn { icon: "󰒮"; enabled: c.p !== null && c.p.canGoPrevious; onClicked: c.p.previous() }
            PlayerBtn {
                icon: c.p && c.p.isPlaying ? "󰏤" : "󰐊"
                big: true
                enabled: c.p !== null && c.p.canTogglePlaying
                onClicked: c.p.togglePlaying()
            }
            PlayerBtn { icon: "󰒭"; enabled: c.p !== null && c.p.canGoNext; onClicked: c.p.next() }
            PlayerBtn {
                small: true
                visible: c.p !== null && c.p.loopSupported
                icon: c.p && c.p.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                lit: c.p !== null && c.p.loopState !== MprisLoopState.None
                onClicked: c.p.loopState = c.p.loopState === MprisLoopState.None ? MprisLoopState.Playlist
                                         : (c.p.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None)
            }
        }
    }

    // колесо — громкость плеера
    WheelHandler {
        enabled: c.p !== null && c.p.volumeSupported
        onWheel: (e) => c.p.volume = Math.max(0, Math.min(1, c.p.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05)))
    }

    // кнопка управления: круглая, большая — заливка цветом текста
    component PlayerBtn: Item {
        id: btn
        property string icon
        property bool big: false
        property bool small: false
        property bool lit: false
        signal clicked
        width: big ? 48 : (small ? 32 : 40)
        height: width
        opacity: enabled ? 1 : 0.35
        scale: bma.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: btn.big ? Theme.text : (bma.containsMouse ? Theme.fill(0.16) : "transparent")
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Text {
            anchors.centerIn: parent
            text: btn.icon
            color: btn.big ? Theme.base : (btn.lit ? Theme.accent : (btn.small ? Theme.sub : Theme.text))
            font.family: Theme.iconFont
            font.pixelSize: btn.big ? 24 : (btn.small ? 15 : 20)
        }
        MouseArea {
            id: bma
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
