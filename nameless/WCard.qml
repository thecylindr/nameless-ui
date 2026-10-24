import QtQuick

// Карточка виджета. Оформление общее для всех виджетов (Config.widgets, «Рабочий стол» → «Оформление карточек»):
//   look    — фон: glass (стекло темы) | solid (плотный) | tint (тонированный акцентом) | outline (только контур) | clear (без фона, текст с тенью)
//   corners — углы: auto (по комплекту) | 8 | 16 | 28
//   border  — обводка: none | thin | accent | gradient (акцент 1 → акцент 2)
//   glow    — мягкий акцентный свет сверху карточки
//   density — отступы: compact | normal | roomy
//   opacity — плотность фона (множитель 0,3–1)
// empty — виджету нечего показать (нет плеера, нет уведомлений): место он не занимает.
// cw — ширина содержимого (без отступов): по ней виджеты считают сетки, иначе последний столбец вылезал за край
Item {
    id: c
    readonly property var o: Config.widgets || ({})
    readonly property string look: o.look || "glass"
    readonly property bool clear: look === "clear"
    property real radius: o.corners > 0 ? o.corners : (Theme.ios ? 26 : 20)
    property bool empty: false
    property real pad: o.density === "compact" ? 12 : (o.density === "roomy" ? 22 : 16)
    readonly property real cw: Math.max(0, width - pad * 2)
    default property alias content: inner.data
    readonly property real k: Math.max(0.3, Math.min(1, o.opacity === undefined ? 1 : o.opacity))
    readonly property string border: o.border || "none"

    Surface {
        visible: c.look === "glass" || c.look === "solid"
        anchors.fill: parent
        radius: c.radius
        alpha: (c.look === "solid" ? Math.min(0.96, Theme.panelAlpha + 0.3) : Theme.panelAlpha) * c.k
    }
    // тонированный: фон из акцента темы, книзу — второй акцент
    Rectangle {
        visible: c.look === "tint"
        anchors.fill: parent
        radius: Theme.r(c.radius)
        opacity: c.k
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.32) }
            GradientStop { position: 1; color: Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, 0.22) }
        }
    }
    // свет сверху: мягкое акцентное свечение (без размытия — дёшево)
    Rectangle {
        visible: c.o.glow === true && !c.clear
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: Math.min(parent.height, 90)
        radius: Theme.r(c.radius)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.30) }
            GradientStop { position: 1; color: "transparent" }
        }
    }
    // обводка: контур поверх фона; у «только контур» — всегда
    Rectangle {
        readonly property string mode: c.look === "outline" && c.border === "none" ? "thin" : c.border
        visible: mode !== "none" && mode !== "gradient" && !c.clear
        anchors.fill: parent
        radius: Theme.r(c.radius)
        color: "transparent"
        border.width: mode === "accent" ? 1.5 : 1
        border.color: mode === "accent" ? Theme.accent : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.28)
    }
    // градиентная обводка (акцент 1 → акцент 2 по диагонали): Canvas перерисовывается только при смене размера, углов или цветов
    Item {
        visible: c.border === "gradient" && !c.clear
        anchors.fill: parent
        Canvas {
            id: gb
            anchors.fill: parent
            readonly property color a: Theme.accent
            readonly property color b: Theme.accent2
            readonly property real r: Theme.r(c.radius)
            onAChanged: requestPaint(); onBChanged: requestPaint(); onRChanged: requestPaint()
            onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                var g = ctx.createLinearGradient(0, 0, width, height);
                g.addColorStop(0, a); g.addColorStop(1, b);
                ctx.strokeStyle = g; ctx.lineWidth = 1.5;
                var x = 0.75, y = 0.75, w = width - 1.5, h = height - 1.5, rr = Math.min(r, w / 2, h / 2);
                ctx.beginPath();
                ctx.moveTo(x + rr, y); ctx.arcTo(x + w, y, x + w, y + h, rr); ctx.arcTo(x + w, y + h, x, y + h, rr);
                ctx.arcTo(x, y + h, x, y, rr); ctx.arcTo(x, y, x + w, y, rr); ctx.closePath();
                ctx.stroke();
            }
        }
    }
    Item {
        id: inner
        anchors.fill: parent
        anchors.margins: c.pad
    }
}
