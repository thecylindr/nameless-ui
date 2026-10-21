import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

// Карточка уведомления в материале комплекта: значок / картинка, приложение, заголовок, текст, действия, закрыть
Item {
    id: card
    property var note: null
    property bool popup: false
    readonly property bool critical: note && note.urgency === NotificationUrgency.Critical
    readonly property bool hovered: hover.hovered
    signal closed

    // Кнопки только с названием. Многие программы присылают действие «default» с пустым текстом — это «нажатие на само уведомление»,
    // а не кнопка (раньше рисовалась кнопка без подписи). Такое действие вызывается касанием карточки
    readonly property var shownActions: note ? note.actions.filter(function (a) { return (a.text || "").trim() !== "" && a.identifier !== "default"; }) : []
    readonly property var defaultAction: {
        if (!note) return null;
        for (var i = 0; i < note.actions.length; i++) if (note.actions[i].identifier === "default") return note.actions[i];
        return null;
    }

    // картинка уведомления, значок-файл (путь или file://) или имя значка из темы
    readonly property string iconSource: {
        if (!note) return "";
        if (note.image) return note.image;
        var ic = note.appIcon || "";
        if (ic.indexOf("/") === 0) return "file://" + ic;
        if (ic.indexOf("file://") === 0) return ic;
        return Quickshell.iconPath(ic || (note.appName || "").toLowerCase(), true) || Quickshell.iconPath("dialog-information");
    }

    width: parent ? parent.width : 360
    implicitHeight: col.implicitHeight + 24

    Surface {
        anchors.fill: parent
        radius: Theme.ios ? 22 : 16
        shadow: card.popup
        alpha: card.popup ? Theme.panelAlpha + 0.04 : Math.max(0.0, Theme.panelAlpha - 0.25)
    }
    // важное — полоса цвета ошибки слева
    Rectangle {
        visible: card.critical
        width: 3; radius: 1.5
        anchors { left: parent.left; leftMargin: 6; top: parent.top; topMargin: 12; bottom: parent.bottom; bottomMargin: 12 }
        color: Theme.red
    }
    HoverHandler { id: hover }
    // правый клик: уведомление прочитано — закрывается и исчезает отовсюду (и из шторки, и из списка)
    // MouseArea поверх всей карточки, но только на правую кнопку: левые клики и кнопки действий проходят как раньше, а правый клик в любом месте
    // карточки (текст, значок, пустое поле) закрывает её — и в окне уведомлений, и в списке-истории
    MouseArea { anchors.fill: parent; z: 20; acceptedButtons: Qt.RightButton; onClicked: card.closed() }
    TapHandler { enabled: card.defaultAction !== null; onTapped: { card.defaultAction.invoke(); card.closed(); } }

    Row {
        x: 14; y: 12
        width: parent.width - 28
        spacing: 12

        // значок приложения или картинка из уведомления
        Item {
            width: 38; height: 38
            ClippingRectangle {
                anchors.fill: parent
                radius: Theme.r(10)
                color: Theme.fill(0.10)
                IconImage {
                    anchors.fill: parent
                    anchors.margins: card.note && card.note.image ? 0 : 6
                    source: card.iconSource
                }
            }
        }

        Column {
            id: col
            width: parent.width - 50
            spacing: 3
            Row {
                width: parent.width
                Text {
                    width: parent.width - closeBtn.width
                    text: card.note ? (card.note.appName || Tr.t("Уведомление")) : ""
                    color: Theme.sub
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.capitalization: Theme.ios ? Font.AllUppercase : Font.MixedCase
                    elide: Text.ElideRight
                }
                Text {
                    id: closeBtn
                    text: "✕"
                    color: closeMa.containsMouse ? Theme.text : Theme.sub
                    font.pixelSize: 12
                    opacity: card.hovered || card.popup ? 1 : 0.0
                    MouseArea { id: closeMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: card.closed() }
                }
            }
            Text {
                width: parent.width
                text: card.note ? card.note.summary : ""
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: card.note ? card.note.body : ""
                color: Theme.text
                opacity: 0.85
                font.family: Theme.font
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                maximumLineCount: card.popup ? 3 : 5
                elide: Text.ElideRight
            }
            // действия
            Flow {
                width: parent.width
                spacing: 6
                topPadding: 4
                visible: card.shownActions.length > 0
                Repeater {
                    model: card.shownActions
                    GButton {
                        required property var modelData
                        ui: Theme
                        label: modelData.text
                        implicitHeight: 30
                        onClicked: modelData.invoke()
                    }
                }
            }
        }
    }
}
