#!/bin/bash
# Действия клавиш NameLess UI (hypr/nameless-binds.lua, привязки driftwm): одна точка для всех сочетаний.
#
#   nameless-action.sh <действие>
#     menu emoji lock keys programs desktop control-center clipboard tasks wallpapers drawer orbit
#     notif-panel notif-dnd notif-close record record-area screenshot ocr
#
# Стоит полная сборка (theme.sh) — действие уходит ей: она знает выбранную оболочку, лаунчер и экран блокировки.
# Без неё — прямо в NameLess UI (qs ipc); оболочка не запущена — запускается и действие повторяется.
set -uo pipefail

THEME="$HOME/.config/hypr/Scripts/theme.sh"
SCRIPTS="$HOME/.config/hypr/Scripts"
act="${1:-}"
[[ -n "$act" ]] || { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

# Orbit и шторка оформления theme.sh не обслуживает — они ниже
if [[ -x "$THEME" && "$act" != orbit ]]; then exec "$THEME" action "$act"; fi

# после перезапуска Quickshell командная строка процесса теряет «-c имя», pgrep его не находит — поэтому ещё и опрос IPC
running() { pgrep -f "(^|/)(qs|quickshell) -c $1\$" >/dev/null || timeout 2 qs -c "$1" ipc show >/dev/null 2>&1; }
# вызов ipc NameLess: оболочка не запущена — запуск (qs-light.sh, если есть) и до 5 с ожидания
nl() {
    if ! running nameless; then
        local ql="$SCRIPTS/qs-light.sh"; [[ -x "$ql" ]] || ql=qs
        setsid -f "$ql" -c nameless >"$HOME/.cache/nameless.log" 2>&1
        for _ in $(seq 50); do qs -c nameless ipc call "$@" 2>/dev/null && return 0; sleep 0.1; done
    fi
    timeout 5 qs -c nameless ipc call "$@"
}

case "$act" in
    menu)           nl launcher toggle ;;
    emoji)          if command -v gnome-characters >/dev/null; then setsid -f gnome-characters; else nl launcher open; fi ;;      # своего выбора эмодзи у NameLess нет
    lock)           nl lock lock || hyprlock ;;
    keys)           nl keys toggle ;;
    programs)       nl programs toggle ;;
    desktop)        nl desktop toggle ;;
    control-center) nl control toggle ;;
    clipboard)      nl clipboard toggle ;;
    tasks)          nl tasks toggle ;;
    wallpapers)     nl wallpapers toggle ;;
    orbit)          nl orbit toggle ;;
    notif-panel)    nl notifs toggle ;;
    notif-dnd)      nl notifs dnd ;;
    notif-close)    nl notifs clear ;;
    record)         nl record screen ;;
    record-area)    nl record area ;;
    drawer)
        if ! running ThemeDrawer; then
            ql="$SCRIPTS/qs-light.sh"; [[ -x "$ql" ]] || ql=qs
            setsid -f "$ql" -c ThemeDrawer >/dev/null 2>&1
            for _ in $(seq 50); do qs -c ThemeDrawer ipc call drawer toggle 2>/dev/null && exit 0; sleep 0.1; done
        fi
        qs -c ThemeDrawer ipc call drawer toggle ;;
    screenshot)
        # область — в буфер обмена и в редактор (swappy, если есть)
        geo="$(slurp)" || exit 0
        f="$HOME/Pictures/Screenshots/скриншот-$(date +%F_%H-%M-%S).png"; mkdir -p "$(dirname "$f")"
        grim -g "$geo" "$f" && wl-copy < "$f" && { command -v swappy >/dev/null && swappy -f "$f" || notify-send -a NameLess "Скриншот" "$f"; } ;;
    ocr)            exec "$SCRIPTS/ocr.sh" ;;
    *)              echo "неизвестное действие: $act" >&2; exit 1 ;;
esac
