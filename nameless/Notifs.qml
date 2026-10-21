pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Сервер уведомлений NameLess UI: история (центр уведомлений), всплывающие карточки, «не беспокоить».
// Важные (critical) показываются и в режиме «не беспокоить»
Singleton {
    id: n

    // «не беспокоить» переживает перезапуск: хранится в Config (notifs.dnd)
    property bool dnd: false
    // запись — всегда: до чтения файла настроек она встаёт в очередь Config и применяется поверх него
    // (раньше изменение до загрузки терялось, а загрузка возвращала старое значение)
    property bool fromStore: false
    onDndChanged: if (!fromStore && Config.store.notifs.dnd !== dnd) Config.set("notifs.dnd", dnd)
    Connections {
        target: Config
        // значение из файла (в том числе изменённого снаружи) — только если своих изменений в очереди нет
        function onStoreChanged() {
            var v = Config.store.notifs.dnd === true;
            if (Config.ready && Config.pending.length === 0 && v !== n.dnd) { n.fromStore = true; n.dnd = v; n.fromStore = false; }
        }
    }
    property bool centerOpen: false
    // всплывающие: уведомления, ещё не скрытые таймером
    property var popups: []
    readonly property var list: server.trackedNotifications.values
    readonly property int count: list.length

    NotificationServer {
        id: server
        keepOnReload: false
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true
        actionsSupported: true
        persistenceSupported: true
        onNotification: note => {
            // уведомление без заголовка, текста и картинки показывать нечем — молча закрывается (пустая карточка только пугает)
            if ((note.summary || "").trim() === "" && (note.body || "").trim() === "" && !note.image) { note.dismiss(); return; }
            note.tracked = true;
            if (n.dnd && note.urgency !== NotificationUrgency.Critical) return;
            var p = n.popups.slice();
            p.unshift(note);
            n.popups = p.slice(0, 4);
        }
    }

    function hidePopup(note) { n.popups = n.popups.filter(function (x) { return x !== note; }); }
    function dismiss(note) { hidePopup(note); note.dismiss(); }
    function clear() {
        n.popups = [];
        var l = list.slice();
        for (var i = 0; i < l.length; i++) l[i].dismiss();
    }

    IpcHandler {
        target: "notifs"
        function toggle(): void { n.centerOpen = !n.centerOpen; }
        function open(): void { n.centerOpen = true; }
        function close(): void { n.centerOpen = false; }
        function dnd(): void { n.dnd = !n.dnd; }
        function clear(): void { n.clear(); }
    }
}
