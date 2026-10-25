#!/bin/bash
# Распознавание текста с экрана: выделить область — текст окажется в буфере обмена (SUPER+SHIFT+T, плитка «Текст с экрана»).
# Нужны tesseract и языковые данные (sudo pacman -S tesseract tesseract-data-rus tesseract-data-eng); slurp, grim, wl-clipboard
set -uo pipefail
say() { notify-send -a "Текст с экрана" "$1" "${2:-}" 2>/dev/null; }

# нет tesseract или языков — предложить установку в терминале (спросит подтверждение и пароль sudo)
offer_install() {
    say "$1" "открываю терминал: установка tesseract и языковых данных"
    command -v kitty >/dev/null && setsid -f kitty --class glassrice-pkg -e sh -c '
        echo "Для распознавания текста нужны: tesseract tesseract-data-rus tesseract-data-eng"
        read -r -p "Установить? [Y/n] " a
        case "$a" in n|N) ;; *) sudo pacman -S --needed tesseract tesseract-data-rus tesseract-data-eng ;; esac
        echo; read -r -n1 -p "Готово. Повторите SUPER+SHIFT+T. Нажмите любую клавишу…"' >/dev/null 2>&1
}
command -v tesseract >/dev/null || { offer_install "Не установлен tesseract"; exit 1; }
langs="$(tesseract --list-langs 2>/dev/null)"
lang=eng
grep -qx rus <<<"$langs" && lang=rus+eng
[[ "$lang" == eng ]] && ! grep -qx eng <<<"$langs" && { offer_install "Нет языковых данных tesseract"; exit 1; }

area="$(slurp -d 2>/dev/null)" || exit 0
[[ -n "$area" ]] || exit 0
img="$(mktemp --suffix=.png)"; trap 'rm -f "$img" "$img.s.png"' EXIT
grim -g "$area" "$img" || exit 1
# мелкий текст распознаётся лучше в двойном размере
src="$img"
if command -v magick >/dev/null; then magick "$img" -resize 200% -colorspace Gray -normalize "$img.s.png" 2>/dev/null && src="$img.s.png"; fi
text="$(tesseract "$src" - -l "$lang" --psm 6 2>/dev/null | sed 's/[[:space:]]*$//' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
if [[ -z "${text//[[:space:]]/}" ]]; then say "Текст не найден" "попробуйте выделить область крупнее"; exit 0; fi
printf '%s' "$text" | wl-copy
say "Текст скопирован ($(wc -m <<<"$text") знаков)" "$(head -c 160 <<<"$text" | tr '\n' ' ')"
