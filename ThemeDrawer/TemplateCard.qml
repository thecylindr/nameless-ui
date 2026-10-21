import QtQuick

// Карточка шаблона с живым превью в его цветах: classic — сплошные таблетки, liquid — стеклянные, ios — бар и док
GTile {
    id: c
    property string kind: "classic"
    property string title
    property string sub
    property var scheme: null            // палитра шаблона { colors, dark }
    property color tAccent: "#0a84ff"
    property bool current: false
    property bool busy: false

    radius: 22
    readonly property var pc: scheme ? scheme.colors : null
    readonly property bool glassy: kind !== "classic"

    // кольцо активного шаблона
    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: c.ui.r(c.radius) + 4
        color: "transparent"
        border.width: 2.5
        border.color: c.ui.accent
        opacity: c.current ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // превью рабочего стола
    Rectangle {
        id: pv
        x: 8; y: 8
        width: parent.width - 16
        height: parent.height - 52
        radius: 15
        clip: true
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: c.pc ? c.pc.mauve : "#6c5ce7" }
            GradientStop { position: 0.55; color: c.pc ? c.pc.blue : "#0984e3" }
            GradientStop { position: 1.0; color: c.pc ? c.pc.teal : "#00cec9" }
        }

        // панель: таблетки (classic/liquid) или бар во всю ширину (ios)
        Row {
            visible: c.kind !== "ios"
            x: 5; y: 5
            spacing: 3
            Repeater {
                model: [14, 22, 10]
                Rectangle {
                    required property int modelData
                    width: modelData; height: 7; radius: c.glassy ? 3.5 : 2
                    color: c.glassy ? Qt.rgba(1, 1, 1, 0.32) : (c.pc ? c.pc.base : "#222")
                    border.width: c.glassy ? 1 : 0
                    border.color: Qt.rgba(1, 1, 1, 0.55)
                }
            }
        }
        Rectangle {
            visible: c.kind === "ios"
            width: parent.width; height: 8
            color: Qt.rgba(1, 1, 1, 0.30)
        }
        // EchoStar: ночное небо — звёзды, падающая звезда, луна
        Rectangle {
            visible: c.kind === "echostar"
            anchors.fill: parent
            radius: pv.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#03050c" }
                GradientStop { position: 0.6; color: "#0d1438" }
                GradientStop { position: 1.0; color: "#2a1b4a" }
            }
            Repeater {
                model: 28
                Rectangle {
                    required property int index
                    readonly property real rx: { var v = Math.sin(index * 78.233) * 43758.5453; return v - Math.floor(v); }
                    readonly property real ry: { var v = Math.sin(index * 12.9898) * 43758.5453; return v - Math.floor(v); }
                    x: rx * (pv.width - 4)
                    y: ry * pv.height * 0.85
                    width: index % 7 === 0 ? 2.5 : 1.5
                    height: width
                    radius: width / 2
                    color: "white"
                    opacity: 0.4 + ry * 0.6
                }
            }
            // падающая звезда
            Rectangle {
                x: pv.width * 0.3; y: pv.height * 0.3
                width: pv.width * 0.32; height: 1.5
                rotation: 155
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: "white" }
                }
            }
            // луна
            Rectangle { x: pv.width * 0.78; y: pv.height * 0.12; width: 12; height: 12; radius: 6; color: "#eef1ff" }
        }
        // «Аврора»: градиентная рамка активного окна
        Rectangle {
            visible: c.kind === "aurora"
            x: 4; y: 14
            width: pv.width * 0.54 + 4; height: pv.height - 18
            radius: 8
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: c.tAccent }
                GradientStop { position: 1.0; color: c.pc ? c.pc.mauve : "#bf5af2" }
            }
        }
        // окна
        Rectangle {
            x: 6; y: 16
            width: pv.width * 0.54; height: pv.height - (c.kind === "ios" ? 34 : 22)
            radius: c.glassy ? 6 : 3
            color: c.glassy ? Qt.rgba(1, 1, 1, 0.22) : (c.pc ? c.pc.mantle : "#111")
            border.width: c.glassy ? 1 : 1.5
            border.color: c.glassy ? Qt.rgba(1, 1, 1, 0.6) : c.tAccent
        }
        Rectangle {
            x: pv.width * 0.54 + 10; y: 16
            width: pv.width * 0.46 - 16; height: pv.height - (c.kind === "ios" ? 34 : 22)
            radius: c.glassy ? 6 : 3
            color: c.glassy ? Qt.rgba(1, 1, 1, 0.16) : (c.pc ? c.pc.surface0 : "#333")
            border.width: c.glassy ? 1 : 0
            border.color: Qt.rgba(1, 1, 1, 0.45)
        }
        // док iOS
        Rectangle {
            visible: c.kind === "ios"
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 4 }
            width: dockRow.width + 8; height: 12; radius: 5
            color: Qt.rgba(1, 1, 1, 0.32)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.6)
            Row {
                id: dockRow
                anchors.centerIn: parent
                spacing: 3
                Repeater {
                    model: ["#ff453a", "#ffd60a", "#30d158", "#0a84ff", "#bf5af2"]
                    Rectangle { required property string modelData; width: 7; height: 7; radius: 2; color: modelData }
                }
            }
        }
    }

    Column {
        anchors { left: parent.left; leftMargin: 12; bottom: parent.bottom; bottomMargin: 9 }
        width: parent.width - 20
        Text {
            width: parent.width
            text: c.title
            color: c.ui.text
            elide: Text.ElideRight
            font.family: c.ui.font
            font.pixelSize: 13
            font.weight: Font.Bold
        }
        Text {
            width: parent.width
            text: c.sub
            color: c.ui.sub
            elide: Text.ElideRight
            font.family: c.ui.font
            font.pixelSize: 11
        }
    }

    // применение шаблона: затемнение превью и вращающийся значок (RotationAnimator — в потоке отрисовки)
    Rectangle {
        x: pv.x; y: pv.y
        width: pv.width; height: pv.height
        radius: pv.radius
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: c.busy ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Column {
            anchors.centerIn: parent
            spacing: 4
            ProgressRing {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 28; height: 28
                thickness: 3
                progress: 0.3
                color: "white"
                track: Qt.rgba(1, 1, 1, 0.2)
                spinning: c.busy
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Tr.t("Применяю…")
                color: "white"
                font.family: c.ui.font
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }
    }
}
