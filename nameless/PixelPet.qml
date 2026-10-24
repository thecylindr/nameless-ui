import QtQuick
import "PixelSprites.js" as Sprites

// Пиксельный питомец: все кадры всех поз рисуются по одному разу (Canvas на кадр, крупными «пикселями» без сглаживания),
// дальше анимация только показывает нужный кадр — перерисовки нет. Кадр выбирает tick (общий шаг сцены), поза — pose.
//   species: cat | dog | clawd | fish;  look: окрас (PixelSprites.palettes);  opt: { striped, dog };  dir: 1 — вправо, -1 — влево
Item {
    id: pet
    property string species: "cat"
    property string look: "ginger"
    property var opt: ({})
    property string pose: species === "fish" ? "swim" : (species === "clawd" ? "idle" : "stand")
    property int tick: 0
    property real unit: 4
    property int dir: 1

    readonly property var poses: species === "fish" ? ["swim"] : (species === "clawd" ? ["idle", "work", "wait", "sleep", "jump"] : ["stand", "walk", "sit", "sleep", "jump"])
    // все кадры: [{ pose, i, n, g }]
    readonly property var sheet: {
        var out = [];
        for (var p = 0; p < poses.length; p++) {
            var fr = Sprites.frames(species, poses[p], opt);
            for (var i = 0; i < fr.length; i++) out.push({ pose: poses[p], i: i, n: fr.length, g: fr[i] });
        }
        return out;
    }
    readonly property var pal: Sprites.palettes[look] || Sprites.palettes.ginger
    readonly property int cols: sheet.length > 0 ? sheet[0].g[0].length : 1
    readonly property int rows: sheet.length > 0 ? sheet[0].g.length : 1
    width: cols * unit
    height: rows * unit
    transform: Scale { origin.x: pet.width / 2; xScale: pet.dir < 0 ? -1 : 1 }

    Repeater {
        model: pet.sheet
        Canvas {
            required property var modelData
            anchors.fill: parent
            visible: modelData.pose === pet.pose && modelData.i === pet.tick % modelData.n
            onPaint: {
                var ctx = getContext("2d"), g = modelData.g, u = pet.unit, pal = pet.pal;
                ctx.reset();
                for (var y = 0; y < g.length; y++) for (var x = 0; x < g[y].length; x++) {
                    var c = g[y][x];
                    if (c === "") continue;
                    ctx.fillStyle = pal[c] || pal.b;
                    ctx.fillRect(x * u, y * u, u, u);
                }
            }
            // окрас или размер поменялись — кадр перерисовывается (один раз)
            property var colors: pet.pal
            onColorsChanged: requestPaint()
            onWidthChanged: requestPaint()
            Component.onCompleted: requestPaint()
        }
    }
}
