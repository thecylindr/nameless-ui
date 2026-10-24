import QtQuick

// Перекидная карточка часов (WClock, вид «Карточки»): при смене цифр перелистывается
Rectangle {
    id: fc
    property string text
    property real k: 1
    width: 112 * fc.k; height: 104 * fc.k; radius: 14 * fc.k
    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.10)
    // нижняя половина темнее, посередине — щель
    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: parent.height / 2; radius: parent.radius; color: Qt.rgba(0, 0, 0, 0.12) }
    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: Math.max(1, 2 * fc.k); color: Qt.rgba(0, 0, 0, 0.35) }
    Text {
        id: ft
        anchors.centerIn: parent
        text: fc.text
        color: Theme.text; font.family: Theme.font; font.pixelSize: 74 * fc.k; font.weight: Font.Black; font.features: { "tnum": 1 }
        transform: Rotation { id: rot; origin.x: ft.width / 2; origin.y: ft.height / 2; axis { x: 1; y: 0; z: 0 } angle: 0 }
    }
    // смена цифр — карточка «перелистывается» (раз в минуту, 0,3 с)
    onTextChanged: flip.restart()
    SequentialAnimation {
        id: flip
        NumberAnimation { target: rot; property: "angle"; from: -90; to: 0; duration: 300; easing.type: Easing.OutBack }
    }
}
