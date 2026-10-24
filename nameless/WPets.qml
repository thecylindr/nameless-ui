import QtQuick

// Питомцы: пиксельные рыжий кот, белая кошка (поменьше), чёрный кот, корги, лиса, Клод — гуляют, сидят, засыпают.
// Сцена — Config.store.pets.scene: none (прямо на рабочем столе) | auto (по дате: праздники и времена года) | park | home | night |
// winter | beach | newyear | halloween | spring | autumn | valentine (карточка-фон, PetScene).
// Взаимодействие:
//   нажатие на питомца — прыжок и сердечко; навести и подержать — садится и мурлычет (сердечки); перетащить — переставить;
//   «Покормить» — миска, все бегут есть; нажатие по пустому месту — мячик, ближайший гоняет его;
//   дома уставшие котики спят в лукошке у печки.
// Экономия: один общий шаг 8 раз в секунду (4 — в экономном режиме), «пиксель за шагом»; стол закрыт окнами — сцена стоит
Item {
    id: w
    readonly property var o: Config.store.pets || ({})
    readonly property var list: o.list || ["ginger", "white"]
    readonly property real unit: o.unit || 4
    readonly property string scene: o.scene || "none"
    readonly property bool card: scene !== "none"
    readonly property var kinds: ({
        ginger: { species: "cat", look: "ginger", opt: { striped: true }, k: 1.0, name: Tr.t("Рыжий кот") },
        white:  { species: "cat", look: "white", opt: { striped: true, darkTail: true }, k: 0.8, name: Tr.t("Белая кошка") },
        black:  { species: "cat", look: "black", opt: {}, k: 0.85, name: Tr.t("Чёрный кот") },
        corgi:  { species: "dog", look: "corgi", opt: { dog: true }, k: 0.9, name: Tr.t("Корги") },
        fox:    { species: "dog", look: "fox", opt: { dog: true, fox: true }, k: 0.9, name: Tr.t("Лиса") },
        clawd:  { species: "clawd", look: "clawd", opt: {}, k: 0.9, name: Tr.t("Клод") }
    })
    implicitHeight: card ? Math.round(18 * unit) + 140 : Math.round(18 * unit) + 28
    // линия, на которой стоят лапы
    readonly property real feet: card ? bg.groundTop + 10 : height - 12

    property int tick: 0
    readonly property bool live: visible && !Compositor.covered
    Timer { interval: Perf.eco ? 250 : 125; repeat: true; running: w.live; onTriggered: w.tick++ }
    readonly property bool night: { var h = new Date().getHours(); return h >= 23 || h < 7; }

    // ---------- игрушки ----------
    property real bowlX: -1                 // миска с едой (-1 — нет)
    property int bowlLeft: 0
    // мячик: физика — катится с трением, отскакивает от стенок, подпрыгивает; считается 30 раз в секунду, только пока он в игре
    property real ballX: -1                 // центр по горизонтали (-1 — нет)
    property real ballH: 0                  // высота над землёй
    property real ballVX: 0
    property real ballVY: 0
    property real ballSpin: 0
    property int ballLeft: 0                // шагов сцены до исчезновения (сбрасывается каждым пинком)
    readonly property real ballR: Math.max(5, unit * 1.6)
    function throwBall(x, vx) { ballX = Math.max(ballR, Math.min(width - ballR, x)); ballH = 30; ballVX = vx; ballVY = 0; ballLeft = 160; ball(ballX); }
    // пинок: от того, кто пнул, вверх и в сторону
    function kick(dir, power) { ballVX = dir * power * (0.8 + Math.random() * 0.5); ballVY = 4 + Math.random() * 3; ballLeft = 160; }
    Timer {
        interval: 33; repeat: true
        running: w.ballX >= 0 && w.live
        onTriggered: {
            w.ballX += w.ballVX;
            w.ballSpin += w.ballVX * 12;
            if (w.ballX < w.ballR) { w.ballX = w.ballR; w.ballVX = -w.ballVX * 0.7; }
            if (w.ballX > w.width - w.ballR) { w.ballX = w.width - w.ballR; w.ballVX = -w.ballVX * 0.7; }
            // подпрыгивание: тяжесть, отскок с потерей
            w.ballVY -= 0.6; w.ballH += w.ballVY;
            if (w.ballH <= 0) { w.ballH = 0; w.ballVY = Math.abs(w.ballVY) > 1.5 ? -w.ballVY * 0.55 : 0; w.ballVX *= 0.94; }
            if (Math.abs(w.ballVX) < 0.05) w.ballVX = 0;
        }
    }
    signal feed()
    signal ball(real at)
    onTickChanged: {
        if (bowlX >= 0 && --bowlLeft <= 0) bowlX = -1;
        if (ballX >= 0 && ballVX === 0 && ballH === 0 && --ballLeft <= 0) ballX = -1;      // лежит без дела — исчезает
    }

    // фон-карточка
    PetScene {
        id: bg
        visible: w.card
        anchors.fill: parent
        scene: w.scene
        tick: w.tick
        p: Math.max(2, Math.round(w.unit * 0.75))
        groundTop: height - 34
        radius: Theme.ios ? 26 : 20
    }
    // без карточки — тонкая земля, чтобы питомцы не «висели»
    Rectangle {
        visible: !w.card && w.o.ground !== false
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 10 }
        height: 2; radius: 1
        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)
    }
    // нажатие по пустому месту — мячик
    MouseArea {
        anchors.fill: parent
        onClicked: (m) => w.throwBall(m.x, (Math.random() - 0.5) * 6)
    }

    // миска и мячик
    Item {
        visible: w.bowlX >= 0
        x: w.bowlX - 12; y: w.feet - 10
        width: 24; height: 10
        Rectangle { anchors.bottom: parent.bottom; width: 24; height: 7; radius: 2; color: "#4aa8ff" }
        Rectangle { x: 4; y: 1; width: 16; height: 4; radius: 2; color: "#b8743c" }
    }
    // мячик: полоска показывает вращение, тень на земле — высоту; нажатие — пинок от курсора
    Rectangle {
        visible: w.ballX >= 0
        x: w.ballX - width / 2; y: w.feet - 3
        width: w.ballR * 2 * Math.max(0.4, 1 - w.ballH / 80); height: 3; radius: 2
        color: Qt.rgba(0, 0, 0, 0.25 * Math.max(0.3, 1 - w.ballH / 60))
    }
    Rectangle {
        id: ballItem
        visible: w.ballX >= 0
        width: w.ballR * 2; height: width; radius: width / 2
        x: w.ballX - w.ballR; y: w.feet - width - w.ballH
        color: "#ff5a5a"; border.width: 1; border.color: "#b8323a"
        rotation: w.ballSpin
        Rectangle { anchors.centerIn: parent; width: parent.width; height: Math.max(2, parent.height * 0.28); color: "#ffd34a" }
        Rectangle { x: parent.width * 0.22; y: parent.height * 0.16; width: parent.width * 0.25; height: width; radius: width / 2; color: Qt.rgba(1, 1, 1, 0.55) }
        MouseArea {
            anchors.fill: parent; anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: (m) => { w.kick(m.x < ballItem.width / 2 ? 1 : -1, 6); w.ball(w.ballX); }
        }
    }

    Repeater {
        id: pets
        model: w.list
        Item {
            id: slot
            required property string modelData
            required property int index
            readonly property var kd: w.kinds[slot.modelData] || w.kinds.ginger
            readonly property bool clawd: kd.species === "clawd"
            readonly property bool cat: kd.species === "cat"
            width: sprite.width; height: sprite.height
            // в лукошке спящий кот чуть «утоплен»
            readonly property bool inBasket: bg.indoor && cat && sprite.pose === "sleep" && Math.abs(x + width / 2 - (bg.basketX + bg.basketW / 2)) < bg.basketW / 2
            y: w.feet - height - jumpY + (inBasket ? 6 : 0)
            property real jumpY: 0
            property real targetX: x
            property int stepsLeft: 8
            property string goal: ""          // "" | food | ball | basket — куда идёт
            property int pet: 0               // поглаживание: сколько шагов держат курсор
            Component.onCompleted: x = Math.max(0, (w.width - width) * (0.2 + 0.6 * index / Math.max(1, w.list.length)))

            PixelPet {
                id: sprite
                species: slot.kd.species
                look: slot.kd.look
                opt: slot.kd.opt
                unit: Math.max(2, Math.round(w.unit * slot.kd.k))
                tick: w.tick
            }

            function goTo(px, why) {
                targetX = Math.max(0, Math.min(w.width - width, px - width / 2));
                sprite.dir = targetX >= x ? 1 : -1;
                sprite.pose = clawd ? "idle" : "walk";
                goal = why; stepsLeft = 400;
            }
            function arrived() {
                if (goal === "ball") return;           // мячик ловится в шаге погони (он движется)
                if (goal === "food") { sprite.pose = clawd ? "work" : "sit"; stepsLeft = 40; heartFade.restart(); }
                else if (goal === "basket") { sprite.pose = "sleep"; stepsLeft = 80 + Math.floor(Math.random() * 80); }
                else { sprite.pose = clawd ? "idle" : "stand"; stepsLeft = 0; }
                goal = "";
            }
            function decide() {
                var r = Math.random(), maxX = Math.max(0, w.width - width);
                goal = "";
                if (clawd) {
                    sprite.pose = r < 0.15 ? "sleep" : (r < 0.55 ? "idle" : (r < 0.8 ? "work" : "wait"));
                    stepsLeft = 12 + Math.floor(Math.random() * 24);
                    return;
                }
                if (sprite.pose === "sleep" && Math.random() < (w.night ? 0.9 : 0.6)) { stepsLeft = 20; return; }
                if (r < (w.night ? 0.35 : 0.12)) {
                    // дома кошки идут спать в лукошко
                    if (bg.indoor && cat) { goTo(bg.basketX + bg.basketW / 2 + (Math.random() - 0.5) * bg.basketW * 0.4, "basket"); return; }
                    sprite.pose = "sleep"; stepsLeft = 40 + Math.floor(Math.random() * 60); return;
                }
                if (r < 0.55) { goTo(Math.random() * maxX + width / 2, "walk"); return; }
                sprite.pose = r < 0.78 ? "sit" : "stand";
                stepsLeft = 12 + Math.floor(Math.random() * 30);
            }
            Connections {
                target: w
                function onTickChanged() {
                    if (drag.active) return;
                    // гладят: сидит и мурлычет
                    if (petHov.hovered) {
                        if (++slot.pet === 4) { sprite.pose = slot.clawd ? "idle" : "sit"; slot.goal = ""; }
                        if (slot.pet >= 4) { if (slot.pet % 8 === 0) heartFade.restart(); slot.stepsLeft = 10; return; }
                    } else slot.pet = 0;
                    // погоня за мячиком: цель — где мяч сейчас; догнал и мяч низко — пинок; устал — бросает игру
                    if (slot.goal === "ball") {
                        if (w.ballX < 0 || --slot.stepsLeft <= 0) { slot.goal = ""; sprite.pose = slot.clawd ? "idle" : "sit"; slot.stepsLeft = 20; return; }
                        var bx = w.ballX - slot.width / 2, d = bx - slot.x;
                        sprite.dir = d >= 0 ? 1 : -1;
                        if (Math.abs(d) < slot.width * 0.45 && w.ballH < slot.height * 0.5) {
                            w.kick(sprite.dir, 4 + Math.random() * 4);
                            sprite.pose = "jump"; hop.restart();
                            if (Math.random() < 0.3) heartFade.restart();
                        } else {
                            sprite.pose = slot.clawd ? "idle" : "walk";
                            slot.x = Math.max(0, Math.min(w.width - slot.width, slot.x + Math.sign(d) * Math.min(Math.abs(d), sprite.unit * 2.5)));
                        }
                        return;
                    }
                    if (slot.goal !== "") {
                        var step = sprite.unit * (slot.goal === "food" ? 2 : 1);
                        if (Math.abs(slot.targetX - slot.x) <= step) { slot.x = slot.targetX; slot.arrived(); }
                        else slot.x += step * sprite.dir;
                        return;
                    }
                    if (--slot.stepsLeft <= 0) slot.decide();
                }
                function onFeed() { slot.goTo(w.bowlX + (slot.index - (w.list.length - 1) / 2) * 18, "food"); }
                function onBall(at) {
                    // за мячиком бежит ближайший
                    var mine = Math.abs(slot.x + slot.width / 2 - at), best = true;
                    for (var i = 0; i < pets.count; i++) { var o = pets.itemAt(i); if (o && o !== slot && Math.abs(o.x + o.width / 2 - at) < mine) best = false; }
                    // играть идёт ближайший; иногда — и второй
                    if (best || Math.random() < 0.35) { slot.goal = "ball"; slot.stepsLeft = 120 + Math.floor(Math.random() * 120); }
                }
            }

            SequentialAnimation {
                id: hop
                NumberAnimation { target: slot; property: "jumpY"; to: sprite.unit * 4; duration: 160; easing.type: Easing.OutQuad }
                NumberAnimation { target: slot; property: "jumpY"; to: 0; duration: 200; easing.type: Easing.InQuad }
                ScriptAction { script: if (slot.goal === "") { sprite.pose = slot.clawd ? "wait" : "sit"; slot.stepsLeft = 16; } else if (slot.goal === "ball") sprite.pose = slot.clawd ? "idle" : "walk"; }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: -14 - (1 - opacity) * 16
                text: slot.pet >= 4 ? Tr.t("мур") + " ♥" : (sprite.pose === "sit" && w.bowlX >= 0 ? Tr.t("ням") + " ♥" : "♥")
                color: "#ff6b8b"; font.pixelSize: slot.pet >= 4 ? 12 : 16; font.family: Theme.font; font.weight: Font.Bold
                opacity: 0
                NumberAnimation on opacity { id: heartFade; running: false; from: 1; to: 0; duration: 900 }
            }
            // новогодняя шапочка — у кошек и собак на голове (голова справа по ходу, у Клода — сверху по центру)
            Item {
                visible: bg.kind === "newyear" && w.card
                x: slot.clawd ? parent.width * 0.38 : (sprite.dir > 0 ? parent.width * 0.62 : parent.width * 0.12)
                y: (slot.clawd ? 0 : (sprite.pose === "sit" ? -2 : (sprite.pose === "sleep" ? parent.height * 0.42 : parent.height * 0.08))) - sprite.unit * 2
                width: sprite.unit * 6; height: sprite.unit * 4
                Rectangle { y: parent.height - sprite.unit; width: parent.width; height: sprite.unit; color: "#ffffff" }
                Rectangle { x: sprite.unit; width: parent.width - sprite.unit * 2; height: parent.height - sprite.unit; color: "#d42a2a" }
                Rectangle { x: sprite.dir > 0 ? parent.width - sprite.unit : -sprite.unit; y: -sprite.unit; width: sprite.unit * 2; height: sprite.unit * 2; radius: sprite.unit; color: "#ffffff" }
            }
            Text {
                visible: sprite.pose === "sleep"
                x: sprite.dir > 0 ? parent.width - 8 : 0
                y: -10 - (w.tick % 8)
                text: "z"; color: w.card ? "#ffffff" : Theme.sub; font.family: Theme.font; font.pixelSize: 11 + (w.tick % 8) / 2
                opacity: 1 - (w.tick % 8) / 10
            }
            HoverHandler { id: petHov; cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor }
            TapHandler { onTapped: { sprite.pose = "jump"; slot.goal = ""; hop.restart(); heartFade.restart(); } }
            DragHandler {
                id: drag
                yAxis.enabled: false
                xAxis.minimum: 0; xAxis.maximum: w.width - slot.width
                onActiveChanged: if (!active) { slot.targetX = slot.x; slot.goal = ""; sprite.pose = slot.clawd ? "idle" : "stand"; slot.stepsLeft = 10; }
            }
        }
    }

    // передняя стенка лукошка — поверх спящих в нём котиков
    Rectangle {
        visible: w.card && bg.indoor
        x: bg.basketX; y: bg.groundTop - 2
        width: bg.basketW; height: 12
        color: "#a8743c"
        Repeater { model: Math.floor(bg.basketW / 9); Rectangle { required property int index; x: index * 9; width: 3; height: 12; color: "#7d5428" } }
    }

    // действия: показываются при наведении на сцену
    HoverHandler { id: sceneHov }
    Row {
        visible: sceneHov.hovered
        anchors { right: parent.right; top: parent.top; margins: 8 }
        spacing: 6
        Repeater {
            model: [{ t: Tr.t("Покормить"), a: "feed" }, { t: Tr.t("Мячик"), a: "ball" }]
            Rectangle {
                required property var modelData
                width: lbl.implicitWidth + 18; height: 24; radius: 12
                color: actMa.containsMouse ? Theme.accent : Qt.rgba(0, 0, 0, 0.45)
                Text { id: lbl; anchors.centerIn: parent; text: parent.modelData.t; color: "white"; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
                MouseArea {
                    id: actMa
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (parent.modelData.a === "feed") { w.bowlX = w.width * (0.3 + Math.random() * 0.4); w.bowlLeft = 160; w.feed(); }
                        else w.throwBall(w.width * (0.2 + Math.random() * 0.6), (Math.random() - 0.5) * 8);
                    }
                }
            }
        }
    }
}
