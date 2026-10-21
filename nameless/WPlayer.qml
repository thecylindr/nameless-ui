import QtQuick

// Плеер на рабочем столе: карточка PlayerCard, пока что-то играет; compact — без перемотки
Item {
    readonly property bool empty: !card.has
    implicitHeight: Config.store.player.compact ? 150 : 196
    PlayerCard {
        id: card
        anchors.fill: parent
        radius: Theme.ios ? 26 : 20
        compact: Config.store.player.compact === true
    }
}
