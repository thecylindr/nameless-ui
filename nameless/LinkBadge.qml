import QtQuick

// Значок «устройство подключено» — звенья цепочки (link.svg). Чтобы не мозолить глаза, он показывается при подключении и при каждом изменении
// набора устройств (key), через hideAfter мс плавно гаснет и возвращается, пока курсор над владельцем значка (hover)
Item {
    id: b
    property var key: ""            // меняется — значок снова показывается
    property bool hover: false      // курсор над карточкой или значком устройства
    property bool linked: true      // устройство подключено
    property int hideAfter: 7000
    property bool shown: true

    width: 16; height: 16
    opacity: linked && (shown || hover) ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    onKeyChanged: { shown = true; hideT.restart(); }
    Timer { id: hideT; interval: b.hideAfter; running: b.linked && b.shown; onTriggered: b.shown = false }

    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("link.svg")
        sourceSize: Qt.size(48, 48)
        smooth: true
        asynchronous: true
    }
}
