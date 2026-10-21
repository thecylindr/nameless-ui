import QtQuick

// Стеклянное поле ввода; Enter — подтвердить
Item {
    id: f
    property QtObject ui
    property string value
    property string placeholder
    property string icon: ""
    readonly property alias text: input.text
    signal accepted(string v)

    function clear() { input.text = ""; }
    function focusInput() { input.forceActiveFocus(); }

    width: parent ? parent.width : 300
    height: 40
    onValueChanged: input.text = value

    Rectangle {
        anchors.fill: parent
        radius: f.ui.r(height / 2)
        color: f.ui.fill(0.08)
        border.width: input.activeFocus ? 1.5 : (f.ui.ios ? 0 : 1)
        border.color: input.activeFocus ? f.ui.accent : f.ui.line(0.26)
    }
    Rim { anchors.fill: parent; ui: f.ui; radius: f.ui.r(height / 2); strength: 0.6 }
    Text {
        id: ic
        visible: f.icon !== ""
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        text: f.icon
        color: f.ui.sub
        font.family: f.ui.iconFont
        font.pixelSize: 15
    }
    TextInput {
        id: input
        anchors { fill: parent; leftMargin: f.icon !== "" ? 38 : 16; rightMargin: 16 }
        verticalAlignment: TextInput.AlignVCenter
        text: f.value
        color: f.ui.text
        selectionColor: f.ui.accent
        font.family: f.ui.font
        font.pixelSize: 13
        clip: true
        selectByMouse: true
        onAccepted: f.accepted(text)
    }
    Text {
        anchors.fill: input
        verticalAlignment: Text.AlignVCenter
        visible: input.text === ""
        text: f.placeholder
        color: f.ui.sub
        font.family: f.ui.font
        font.pixelSize: 13
    }
}
