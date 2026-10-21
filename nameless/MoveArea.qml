import QtQuick

// Ручка переноса окна: тянуть за шапку — окно идёт за курсором, но не уходит за экран целиком; двойное нажатие — вернуть на место.
// win — Surface окна (у него dx и dy)
Item {
    id: m
    property Item win
    DragHandler {
        target: null
        property real sx: 0
        property real sy: 0
        onActiveChanged: if (active && m.win) { sx = m.win.dx; sy = m.win.dy; }
        onTranslationChanged: if (active && m.win) {
            var par = m.win.parent, W = par ? par.width : 2000, H = par ? par.height : 1200;
            m.win.dx = Math.max(-(m.win.x + m.win.width - 120), Math.min(W - m.win.x - 120, sx + translation.x));
            m.win.dy = Math.max(-m.win.y, Math.min(H - m.win.y - 60, sy + translation.y));
        }
        cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    }
    TapHandler { onDoubleTapped: if (m.win) { m.win.dx = 0; m.win.dy = 0; } }
}
