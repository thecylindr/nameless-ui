#!/usr/bin/env bash
# Установка NameLess UI: оболочка (nameless) и шторка «Оформление» (ThemeDrawer) копируются в ~/.config/quickshell.
# Прежние файлы не пропадают: они уходят в ~/.config/quickshell-backup-<дата>/.
#   ./install.sh            поставить
#   ./install.sh --deps     поставить минимум пакетов из minimal.txt (pacman / AUR через yay) и затем саму оболочку
#   ./install.sh --restore  вернуть самые свежие прежние файлы
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.config/quickshell"
STAMP="$(date +%F_%H-%M-%S)"
BACKUP="$HOME/.config/quickshell-backup-$STAMP"

say() { echo -e "\e[1;34m  ->\e[0m $1"; }

if [[ "${1:-}" == "--restore" ]]; then
    last="$(ls -1d "$HOME"/.config/quickshell-backup-* 2>/dev/null | sort | tail -n1)"
    [[ -n "$last" ]] || { echo "Бэкапов не нашлось — возвращать нечего."; exit 1; }
    for d in nameless ThemeDrawer; do
        [[ -d "$last/$d" ]] || continue
        rm -rf "${DEST:?}/$d"; cp -a "$last/$d" "$DEST/$d"
        say "вернул $d из $last"
    done
    exit 0
fi

if [[ "${1:-}" == "--deps" ]]; then
    mapfile -t pk < <(grep -vE '^\s*(#|$)' "$HERE/minimal.txt")
    say "ставлю минимум пакетов: ${pk[*]}"
    for p in "${pk[@]}"; do
        if pacman -Si "$p" >/dev/null 2>&1; then sudo pacman -S --needed --noconfirm "$p" || echo "  !! не поставился: $p"
        elif command -v yay >/dev/null; then yay -S --needed --noconfirm "$p" || echo "  !! не поставился: $p"
        else echo "  !! $p только в AUR, а yay не найден — поставьте вручную"; fi
    done
fi
command -v qs >/dev/null || echo "  !! Quickshell (qs) не найден: поставьте пакет quickshell, иначе оболочка не запустится."
mkdir -p "$DEST"
for d in nameless ThemeDrawer; do
    if [[ -d "$DEST/$d" ]]; then
        mkdir -p "$BACKUP"; mv "$DEST/$d" "$BACKUP/$d"
        say "прежний $d сохранён в $BACKUP"
    fi
    cp -a "$HERE/$d" "$DEST/$d"
    say "установлен $d"
done

echo
echo "Готово. Запуск:"
echo "  qs -c nameless &        # оболочка"
echo "  qs -c ThemeDrawer &     # шторка «Оформление»"
echo "При первом запуске оболочка предложит выбрать язык (русский / English)."
