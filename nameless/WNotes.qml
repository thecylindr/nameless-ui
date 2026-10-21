import QtQuick

// Заметка: пишется прямо на рабочем столе, сохраняется через 1.5 с после ввода и при уходе фокуса;
// editing сообщает окну виджетов, что нужна клавиатура
WCard {
    id: w
    property bool editing: note.activeFocus
    readonly property int fsize: Config.store.notes.size || 13
    implicitHeight: Math.max(110, note.contentHeight + pad * 2 + 26)

    Text { text: Tr.t("󰎞  Заметка"); color: Theme.yellow; font.family: Theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold }
    TextEdit {
        id: note
        y: 24
        width: parent.width
        text: Config.store.notes.text || ""
        color: Theme.text
        selectionColor: Theme.accent
        wrapMode: TextEdit.Wrap
        font.family: Theme.font
        font.pixelSize: w.fsize
        function save() { saveT.stop(); if (text !== (Config.store.notes.text || "")) Config.set("notes.text", text); }
        onActiveFocusChanged: if (!activeFocus) save()
        onTextChanged: if (activeFocus) saveT.restart()
        Keys.onEscapePressed: note.focus = false
        Timer { id: saveT; interval: 1500; onTriggered: note.save() }
        Text { visible: note.text === "" && !note.activeFocus; text: Tr.t("Нажмите, чтобы написать…"); color: Theme.sub; font: note.font }
    }
    MouseArea {
        anchors.fill: parent
        visible: !note.activeFocus
        cursorShape: Qt.IBeamCursor
        onClicked: { note.forceActiveFocus(); note.cursorPosition = note.length; }
    }
}
