#!/bin/bash
# Запуск программы из rofi: rofi-run.sh <команда…>
# Программы с одним экземпляром (Incy, Telegram…) при повторном запуске лишь просят работающую копию показать окно,
# а Hyprland на её рабочий стол сам не переключается. Поэтому: запуск, через секунду проверка — если новых окон нет,
# а окно этой программы есть, фокус переходит на него (вместе с переходом на его рабочий стол).
# Окно программы — то, у которого процесс или класс/заголовок содержат имя запускаемого файла.
[[ $# -gt 0 ]] || exit 0
name="$(basename "${1,,}")"
name="${name%.sh}"
mine() {
    hyprctl -j clients 2>/dev/null | jq -r --arg n "$name" '
        .[] | select(.mapped) | select(
            ((.class + " " + .initialClass + " " + .title) | ascii_downcase | contains($n))
            or ((.pid | tostring) as $p | false)) | .address'
}
# процессы окон, чьё имя запуска совпадает (Telegram, Java-приложения с чужим классом окна)
mine_pid() {
    hyprctl -j clients 2>/dev/null | jq -r '.[] | select(.mapped) | "\(.pid) \(.address)"' | while read -r pid addr; do
        exe="$(basename "$(readlink "/proc/$pid/exe" 2>/dev/null)")"
        [[ "${exe,,}" == "$name" || "${exe,,}" == "${name//-desktop/}" ]] && echo "$addr"
    done
}
all() { { mine; mine_pid; } | sort -u; }

# без qs-app.sh или jq программа всё равно запускается — просто без проверки окон
launcher="$(dirname "$0")/qs-app.sh"
[[ -x "$launcher" ]] || launcher=""
if [[ -z "$launcher" ]] || ! command -v jq >/dev/null; then exec ${launcher:+"$launcher"} "$@"; fi
before="$(all | wc -l)"
nohup "$launcher" "$@" >/dev/null 2>&1 &
disown
sleep 1.2
after="$(all)"
if [[ -n "$after" && "$(wc -l <<<"$after")" -le "$before" ]]; then
    hyprctl dispatch "hl.dsp.focus({ window = \"address:$(head -n1 <<<"$after")\" })" >/dev/null 2>&1
fi
