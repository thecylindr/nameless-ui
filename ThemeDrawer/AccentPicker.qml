import QtQuick

// Выбор акцента: стеклянные кружки, «A» — цвет палитры, спектр — свой цвет по тону и насыщенности
Column {
    id: a
    property QtObject ui
    property string value                 // "" — из палитры
    property color autoColor
    property var colors: ["#0a84ff", "#5e5ce6", "#bf5af2", "#ff375f", "#ff9f0a", "#ffd60a", "#30d158", "#64d2ff"]
    signal picked(string v)

    width: parent ? parent.width : 400
    spacing: 14

    property bool custom: false
    readonly property bool isPreset: value === "" || colors.indexOf(value.toLowerCase()) >= 0
    // свой цвет: тон 0..1 и оттенок 0 (пастель) .. 0.5 (сочный) .. 1 (глубокий)
    property real hue: 0.6
    property real shade: 0.5
    function shadeColor(h, t) {
        var sat = 0.35 + 0.65 * Math.min(1, t * 2);
        var val = 1 - Math.max(0, t - 0.5) * 0.9;
        return Qt.hsva(h, sat, val, 1);
    }
    readonly property color customColor: shadeColor(hue, shade)

    readonly property int orbCount: colors.length + 2
    readonly property real orb: 34
    readonly property real gap: (width - orbCount * orb) / (orbCount - 1)

    Row {
        spacing: a.gap
        // цвет палитры
        Orb {
            ui: a.ui
            size: a.orb
            fillColor: a.autoColor
            selected: a.value === "" && !a.custom
            Text { anchors.centerIn: parent; text: "A"; color: "white"; font.family: a.ui.font; font.pixelSize: 13; font.weight: Font.Bold }
            onClicked: { a.custom = false; a.picked(""); }
        }
        Repeater {
            model: a.colors
            Orb {
            ui: a.ui
            size: a.orb
                required property string modelData
                fillColor: modelData
                selected: a.value.toLowerCase() === modelData && !a.custom
                onClicked: { a.custom = false; a.picked(modelData); }
            }
        }
        // свой цвет
        Orb {
            ui: a.ui
            size: a.orb
            spectrum: true
            selected: a.custom || !a.isPreset
            onClicked: a.custom = !a.custom
        }
    }

    // полосы тона и насыщенности для своего цвета
    Column {
        width: parent.width
        spacing: 10
        visible: a.custom
        opacity: a.custom ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Bar {
            ui: a.ui
            width: a.width
            pos: a.hue
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0;  color: "#ff3b30" }
                GradientStop { position: 0.17; color: "#ffcc00" }
                GradientStop { position: 0.33; color: "#34c759" }
                GradientStop { position: 0.5;  color: "#00c7be" }
                GradientStop { position: 0.67; color: "#007aff" }
                GradientStop { position: 0.83; color: "#af52de" }
                GradientStop { position: 1.0;  color: "#ff2d55" }
            }
            onMoved: (p) => a.hue = Math.min(0.999, p)
            onReleased: a.picked(a.customColor.toString())
        }
        Bar {
            ui: a.ui
            width: a.width
            pos: a.shade
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: a.shadeColor(a.hue, 0) }
                GradientStop { position: 0.5; color: a.shadeColor(a.hue, 0.5) }
                GradientStop { position: 1.0; color: a.shadeColor(a.hue, 1) }
            }
            onMoved: (p) => a.shade = p
            onReleased: a.picked(a.customColor.toString())
        }
        Row {
            spacing: 10
            Rectangle { width: 22; height: 22; radius: 11; color: a.customColor; anchors.verticalCenter: parent.verticalCenter }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: a.customColor.toString().toUpperCase()
                color: a.ui.sub
                font.family: a.ui.font
                font.pixelSize: 13
                font.features: { "tnum": 1 }
            }
        }
    }

    // кружок цвета
    component Orb: Item {
        id: o
        property QtObject ui
        property real size: 34
        property color fillColor: "white"
        property bool selected: false
        property bool spectrum: false
        default property alias content: oc.data
        signal clicked
        width: o.size; height: o.size
        scale: oma.pressed ? 0.88 : (oma.containsMouse ? 1.08 : 1)
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 8; height: width; radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: o.ui.text
            opacity: o.selected ? 0.9 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: o.fillColor
            gradient: o.spectrum ? spectrumGrad : null
        }
        Gradient {
            id: spectrumGrad
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#ff3b30" }
            GradientStop { position: 0.33; color: "#34c759" }
            GradientStop { position: 0.66; color: "#007aff" }
            GradientStop { position: 1.0; color: "#af52de" }
        }
        Rim { anchors.fill: parent; ui: o.ui; radius: width / 2 }
        Item { id: oc; anchors.fill: parent }
        MouseArea { id: oma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: o.clicked() }
    }

    // полоса выбора с бегунком
    component Bar: Item {
        id: b
        property QtObject ui
        property real pos: 0
        property alias gradient: barRect.gradient
        signal moved(real p)
        signal released
        height: 30
        Rectangle { id: barRect; anchors.fill: parent; radius: height / 2 }
        Rim { anchors.fill: parent; ui: b.ui; radius: height / 2 }
        Rectangle {
            width: 24; height: 24; radius: 12
            y: 3
            x: 3 + b.pos * (b.width - 30)
            color: "transparent"
            border.width: 3
            border.color: "white"
        }
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            function at(mx) { return Math.max(0, Math.min(1, (mx - 15) / (b.width - 30))); }
            onPressed: (m) => b.moved(at(m.x))
            onPositionChanged: (m) => { if (pressed) b.moved(at(m.x)); }
            onReleased: b.released()
        }
    }
}
