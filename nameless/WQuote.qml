import QtQuick

// Фраза дня: короткая тёплая мысль — новая каждый день, нажатие — следующая. Подборка своя (без сети), на языке интерфейса
WCard {
    id: w
    readonly property var ru: [
        ["Маленькие шаги каждый день складываются в большой путь.", ""],
        ["Отдых — тоже часть работы.", ""],
        ["Лучшее время посадить дерево было двадцать лет назад. Следующее лучшее — сейчас.", "китайская пословица"],
        ["Делай, что можешь, с тем, что имеешь, там, где ты есть.", "Теодор Рузвельт"],
        ["Простота — высшая степень изощрённости.", "Леонардо да Винчи"],
        ["Сначала сделай, чтобы работало, потом — чтобы было красиво.", ""],
        ["Кто никогда не ошибался, тот никогда не пробовал ничего нового.", "Альберт Эйнштейн"],
        ["Тише едешь — дальше будешь.", "пословица"],
        ["Счастье — это когда тебя понимают.", "«Доживём до понедельника»"],
        ["Глаза боятся, а руки делают.", "пословица"],
        ["Всё получится. Не сразу, но получится.", ""],
        ["Чай остывает быстрее, чем кажется.", ""],
        ["Любая большая задача — это несколько маленьких.", ""],
        ["Мы — то, что мы делаем постоянно.", "Аристотель"],
        ["Иногда лучший код — тот, который не пришлось писать.", ""],
        ["Посмотри в окно. Небо сегодня тоже старалось.", ""],
        ["Сделанное лучше идеального.", ""],
        ["Будь добр к себе: ты стараешься.", ""],
        ["Через год ты будешь рад, что начал сегодня.", ""]
    ]
    readonly property var en: [
        ["Small steps every day add up to a long way.", ""],
        ["Rest is part of the work, too.", ""],
        ["The best time to plant a tree was twenty years ago. The second best time is now.", "Chinese proverb"],
        ["Do what you can, with what you have, where you are.", "Theodore Roosevelt"],
        ["Simplicity is the ultimate sophistication.", "Leonardo da Vinci"],
        ["Make it work, then make it beautiful.", ""],
        ["Anyone who has never made a mistake has never tried anything new.", "Albert Einstein"],
        ["Slow and steady wins the race.", "proverb"],
        ["Done is better than perfect.", ""],
        ["Every big task is a few small ones.", ""],
        ["We are what we repeatedly do.", "Aristotle"],
        ["Sometimes the best code is the code you didn't have to write.", ""],
        ["Look out the window. The sky tried hard today, too.", ""],
        ["Be kind to yourself — you're trying.", ""],
        ["A year from now you'll be glad you started today.", ""]
    ]
    readonly property var list: Tr.lang === "en" ? en : ru
    readonly property int day: Math.floor((Date.now() - new Date().getTimezoneOffset() * 60000) / 86400000)
    property int shift: 0
    readonly property var q: list[(day + shift) % list.length]
    implicitHeight: col.implicitHeight + pad * 2

    Column {
        id: col
        width: parent.width
        spacing: 8
        Text { text: "❝"; color: Theme.accent; font.pixelSize: 28; font.family: Theme.font; height: 18 }
        Text {
            width: parent.width; wrapMode: Text.WordWrap
            text: w.q[0]
            color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; lineHeight: 1.1
        }
        Text { visible: w.q[1] !== ""; text: "— " + w.q[1]; color: Theme.sub; font.family: Theme.font; font.pixelSize: 12; font.italic: true }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.shift++ }
}
