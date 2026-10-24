import QtQuick

// Аквариум: пиксельные рыбки (золотая, синяя, клоун) плавают туда-обратно на своей глубине, со дна поднимаются пузырьки,
// водоросли покачиваются. Нажатие — рыбки разбегаются. Число рыбок — Config.store.fish.count.
// Общий шаг 8 раз в секунду (4 в экономном режиме), стол закрыт окнами — аквариум стоит
WCard {
    id: w
    pad: 0
    readonly property var o: Config.store.fish || ({})
    readonly property int count: Math.max(1, Math.min(8, o.count || 4))
    readonly property var looks: ["goldfish", "bluefish", "clownfish"]
    implicitHeight: 170 * Math.max(0.8, width / 300)

    property int tick: 0
    Timer { interval: Perf.eco ? 250 : 125; repeat: true; running: w.visible && !Compositor.covered; onTriggered: w.tick++ }

    // вода: тёмная глубина книзу, по краям — скругление карточки
    Rectangle {
        anchors.fill: parent
        radius: Theme.r(w.radius)
        clip: true
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.20, 0.55, 0.85, 0.35) }
            GradientStop { position: 1.0; color: Qt.rgba(0.04, 0.16, 0.38, 0.55) }
        }
        // песок
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 14; color: Qt.rgba(0.85, 0.74, 0.52, 0.45) }
        // водоросли: столбики квадратиков, качаются через шаг
        Repeater {
            model: 5
            Column {
                required property int index
                x: 18 + index * (w.width - 36) / 4
                anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                spacing: 0
                Repeater {
                    model: 5 + (index * 3) % 4
                    Rectangle {
                        required property int index
                        width: 5; height: 6
                        x: ((w.tick >> 2) + index + parent.parent.index) % 2 ? 2 : 0
                        color: index % 2 ? "#3fae6a" : "#2e8d55"
                    }
                }
            }
        }
        // пузырьки
        Repeater {
            model: 6
            Rectangle {
                required property int index
                readonly property int period: 26 + index * 5
                readonly property real t: ((w.tick + index * 11) % period) / period
                x: 20 + (index * 47) % Math.max(1, w.width - 40) + Math.sin(t * 6.28) * 3
                y: (w.height - 16) * (1 - t)
                width: 4 + index % 3; height: width; radius: width / 2
                color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.55 * (1 - t * 0.6))
            }
        }
        // рыбки
        Repeater {
            model: w.count
            Item {
                id: f
                required property int index
                property real fx: Math.random() * Math.max(1, w.width - 60)
                property int dir: index % 2 ? -1 : 1
                property real speed: 2 + (index % 3)
                property int flee: 0
                readonly property real depth: 18 + (index * 37) % Math.max(1, w.height - 60)
                width: fishSprite.width; height: fishSprite.height
                x: fx
                y: depth + Math.sin((w.tick + index * 9) / 6) * 3
                PixelPet {
                    id: fishSprite
                    species: "fish"
                    look: w.looks[f.index % w.looks.length]
                    unit: 3
                    tick: w.tick
                    dir: f.dir
                }
                Connections {
                    target: w
                    function onTickChanged() {
                        var sp = f.flee > 0 ? f.speed * 4 : f.speed;
                        if (f.flee > 0) f.flee--;
                        f.fx += sp * f.dir;
                        if (f.fx > w.width - f.width - 6) { f.fx = w.width - f.width - 6; f.dir = -1; }
                        if (f.fx < 6) { f.fx = 6; f.dir = 1; }
                        if (Math.random() < 0.01) f.dir = -f.dir;           // иногда разворачивается сама
                    }
                    function onScare(at) { f.dir = f.fx + f.width / 2 < at ? -1 : 1; f.flee = 12; }
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: (m) => w.scare(m.x)          // рыбки разбегаются от места нажатия
        }
    }
    signal scare(real at)
}
