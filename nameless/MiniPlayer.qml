import QtQuick

// Мини-плеер в баре, рядом со временем. Свёрнутый: обложка, «название — исполнитель», пауза/пуск и полоска хода трека.
// Нажатие на название раскрывает: назад, пауза/пуск, вперёд, время «1:23 / 3:45» и перемотка. Колесо мыши — трек, правый клик — карточка плеера.
// Появляется только когда что-то играет или стоит на паузе
Item {
    id: mp
    property var p: Sys.player
    readonly property bool has: p !== null && (p.trackTitle || "") !== ""
    readonly property real len: p && p.lengthSupported ? p.length : 0
    property bool open: false
    property real pos: 0
    property bool seeking: false

    property bool compactHide: false          // узкий экран (телефон как второй монитор): плеер в баре прячется
    visible: has && Config.store.player.mini !== false && !compactHide
    implicitHeight: parent ? parent.height : 30
    implicitWidth: row.implicitWidth + 16

    // позиция у Mpris не сообщается сама — раз в секунду, и только пока что-то играет
    Timer {
        interval: 1000; repeat: true
        running: mp.has && mp.visible && mp.p !== null && mp.p.isPlaying
        triggeredOnStart: true
        onTriggered: if (!mp.seeking) { mp.p.positionChanged(); mp.pos = mp.p.position; }
    }
    onPChanged: pos = p ? p.position : 0
    onHasChanged: if (!has) open = false

    function fmt(t) { return Sys.fmtTime(t); }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8

        // обложка
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; radius: 12
            color: Theme.fill(0.14); clip: true
            Text { anchors.centerIn: parent; visible: art.status !== Image.Ready; text: "󰎆"; color: Theme.accent2; font.family: Theme.iconFont; font.pixelSize: 13 }
            Image {
                id: art
                anchors.fill: parent
                source: mp.p ? (mp.p.trackArtUrl || "") : ""
                sourceSize: Qt.size(48, 48); fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: false
            }
        }

        // название; нажатие — раскрыть или свернуть
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(titleT.implicitWidth, mp.open ? 170 : 200); height: parent.height
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Text {
                id: titleT
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; elide: Text.ElideRight
                text: {
                    if (!mp.p) return "";
                    var t = mp.p.trackTitle || "", a = mp.p.trackArtist || "";
                    return a !== "" ? t + " — " + a : t;
                }
                color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSize; font.weight: Theme.ios ? Font.Medium : Font.DemiBold
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (m) => { if (m.button === Qt.RightButton) Notifs.centerOpen = true; else mp.open = !mp.open; }
                onWheel: (w) => { if (mp.p) { if (w.angleDelta.y > 0) mp.p.previous(); else mp.p.next(); } }
            }
        }

        // раскрытая часть: назад / пуск / вперёд, время, перемотка
        Row {
            id: more
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            visible: width > 1
            clip: true
            width: mp.open ? implicitWidth : 0
            opacity: mp.open ? 1 : 0
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Btn { glyph: "󰒮"; enabled: mp.p !== null && mp.p.canGoPrevious; onTap: mp.p.previous() }
            Btn { glyph: mp.p && mp.p.isPlaying ? "󰏤" : "󰐊"; strong: true; onTap: mp.p.togglePlaying() }
            Btn { glyph: "󰒭"; enabled: mp.p !== null && mp.p.canGoNext; onTap: mp.p.next() }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 6; rightPadding: 4
                text: mp.fmt(mp.pos) + (mp.len > 0 ? " / " + mp.fmt(mp.len) : "")
                color: Theme.sub; font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 }
            }
            // перемотка: клик или перетаскивание
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 76; height: 18
                visible: mp.len > 0
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Theme.fill(0.18) }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * Math.min(1, mp.pos / Math.max(1, mp.len)); height: 4; radius: 2; color: Theme.accent2 }
                MouseArea {
                    anchors.fill: parent; enabled: mp.p !== null && mp.p.canSeek; cursorShape: Qt.PointingHandCursor; preventStealing: true
                    function at(x) { mp.pos = Math.max(0, Math.min(1, x / width)) * mp.len; }
                    onPressed: (m) => { mp.seeking = true; at(m.x); }
                    onPositionChanged: (m) => { if (pressed) at(m.x); }
                    onReleased: { mp.p.position = mp.pos; mp.seeking = false; }
                }
            }
        }

        // свёрнутый: одна кнопка пуск / пауза
        Btn { visible: !mp.open; anchors.verticalCenter: parent.verticalCenter; glyph: mp.p && mp.p.isPlaying ? "󰏤" : "󰐊"; strong: true; onTap: mp.p.togglePlaying() }
    }

    // ход трека — тонкая полоска по нижнему краю острова
    Rectangle {
        anchors { left: parent.left; leftMargin: 8; bottom: parent.bottom; bottomMargin: 6 }
        width: Math.max(0, (parent.width - 16) * Math.min(1, mp.pos / Math.max(1, mp.len)))
        height: 2; radius: 1
        color: Theme.accent2; opacity: 0.8
        visible: mp.len > 0 && !mp.open
    }

    // кнопка плеера: значок, подсветка при наведении
    component Btn: Item {
        id: bt
        property string glyph
        property bool strong: false
        signal tap
        width: 26; height: 26
        opacity: enabled ? 1 : 0.35
        Rectangle { anchors.fill: parent; radius: 13; color: bma.containsMouse && bt.enabled ? Theme.fill(0.16) : "transparent" }
        Text { anchors.centerIn: parent; text: bt.glyph; color: bt.strong ? Theme.accent2 : Theme.text; font.family: Theme.iconFont; font.pixelSize: bt.strong ? 16 : 14 }
        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (bt.enabled) bt.tap() }
    }
}
