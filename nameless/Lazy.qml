import QtQuick
import Quickshell

// Ленивая загрузка окна: тяжёлое окно создаётся, когда оно нужно, а не при запуске оболочки.
//   want    — окно нужно сейчас (привязка к флагу «открыто»); после закрытия окно живёт ещё linger мс — доигрывает
//             анимацию — и выгружается, память возвращается
//   keep    — окно хранит своё состояние (мастер программ, справка, лаунчер): после первого обращения не выгружается
//   request(fn) — создать окно, если его нет, и вызвать fn(окно) сразу, как оно появится
// Окно с анимацией выезда начинает с progress = 0 (см. Component.onCompleted окон): при создании в открытом виде оно тоже выезжает
Item {
    id: l
    property bool want: false
    property bool keep: false
    property int linger: 500
    default property alias component: ll.component
    readonly property var item: ll.item

    property bool hold: false
    property bool requested: false
    property var pending: null

    onWantChanged: { if (want) { hold = true; holdT.stop(); } else holdT.restart(); }
    Timer { id: holdT; interval: l.linger; onTriggered: l.hold = false }

    function request(fn) {
        requested = true;
        if (ll.item) fn(ll.item); else pending = fn;
    }
    LazyLoader {
        id: ll
        active: l.want || l.hold || (l.keep && l.requested)
        onItemChanged: if (item && l.pending) { var f = l.pending; l.pending = null; f(item); }
    }
}
