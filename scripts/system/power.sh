#!/bin/bash
# Режим питания ноутбука (плитки «Эко-режим» и «Производительный» в Пункте управления NameLess UI):
#   eco      — процессор бережёт заряд (power-saver), видеокарта — «Экономия» (gpu.sh eco: дискретная спит)
#   balanced — как обычно: процессор balanced, видеокарта — «Гибрид»
#   perf     — процессор на максимум (performance), видеокарта — «Производительность» (всё рисует дискретная)
#
#   power.sh status          режим, чем управляется процессор, батарея — JSON
#   power.sh set <режим>     применить (процессор сразу; видеокарта — после перезахода, если менялись переменные сессии)
#   power.sh install         поставить управление процессором без пароля: power-profiles-daemon (в терминале)
#
# Процессор: power-profiles-daemon (powerprofilesctl) — если есть; иначе энергопрофиль intel_pstate/amd-pstate (EPP) в sysfs,
# если правило udev дало на него запись. Режим хранится в ~/.config/glassrice/power-mode

set -uo pipefail
STATE="$HOME/.config/glassrice/power-mode"
HERE="$(cd "$(dirname "$0")" && pwd)"
EPP=/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference

mode() { [[ -s "$STATE" ]] && cat "$STATE" || echo balanced; }
on_battery() { local s; for s in /sys/class/power_supply/*/online; do [[ -f "$s" ]] || continue; grep -q Mains "$(dirname "$s")/type" 2>/dev/null && [[ "$(cat "$s")" == 0 ]] && return 0; done; return 1; }
laptop() { compgen -G '/sys/class/power_supply/BAT*' >/dev/null; }
cpu_tool() {
    if command -v powerprofilesctl >/dev/null && powerprofilesctl get >/dev/null 2>&1; then echo ppd
    elif [[ -w "$EPP" ]]; then echo epp
    else echo none; fi
}
cpu_profile() {
    case "$(cpu_tool)" in
        ppd) powerprofilesctl get 2>/dev/null ;;
        epp) cat "$EPP" ;;
        *)   cat "$EPP" 2>/dev/null || echo "" ;;
    esac
}

set_cpu() {
    case "$(cpu_tool)" in
        ppd)
            local p; p="$(case "$1" in eco) echo power-saver ;; perf) echo performance ;; *) echo balanced ;; esac)"
            # не на всех процессорах есть performance — тогда balanced
            powerprofilesctl set "$p" 2>/dev/null || powerprofilesctl set balanced 2>/dev/null ;;
        epp)
            local e; e="$(case "$1" in eco) echo power ;; perf) echo performance ;; *) echo balance_performance ;; esac)"
            for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do echo "$e" > "$f" 2>/dev/null; done ;;
        *) return 1 ;;
    esac
}

cmd_status() {
    local gpu='{}'
    [[ -x "$HERE/gpu.sh" ]] && gpu="$("$HERE/gpu.sh" status 2>/dev/null || echo '{}')"
    jq -n --arg mode "$(mode)" --arg tool "$(cpu_tool)" --arg prof "$(cpu_profile)" --argjson gpu "$gpu" \
          --argjson bat "$(on_battery && echo true || echo false)" --argjson laptop "$(laptop && echo true || echo false)" \
          --arg pct "$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1)" \
        '{ mode: $mode, cpu: { tool: $tool, profile: $prof }, gpu: $gpu, battery: $bat, laptop: $laptop, percent: ($pct | tonumber? // -1) }'
}

cmd_set() {
    case "$1" in eco|balanced|perf) ;; *) echo "режим: eco | balanced | perf" >&2; exit 1 ;; esac
    mkdir -p "$(dirname "$STATE")"
    echo "$1" > "$STATE"
    local cpu=ok
    set_cpu "$1" || cpu=none
    if [[ -x "$HERE/gpu.sh" ]]; then
        case "$1" in eco) "$HERE/gpu.sh" mode eco ;; perf) "$HERE/gpu.sh" mode performance ;; *) "$HERE/gpu.sh" mode hybrid ;; esac >/dev/null 2>&1
    fi
    echo "$cpu"
}

cmd_install() {
    echo "==> Управление процессором без пароля: power-profiles-daemon"
    if command -v yay >/dev/null; then yay -S --needed power-profiles-daemon; else sudo pacman -S --needed power-profiles-daemon; fi
    # tlp и auto-cpufreq конфликтуют с ним — служба включается, только если их нет
    if systemctl is-enabled tlp >/dev/null 2>&1 || systemctl is-enabled auto-cpufreq >/dev/null 2>&1; then
        echo "  !! включён tlp или auto-cpufreq — они управляют процессором сами; power-profiles-daemon не включаю"
    else
        sudo systemctl enable --now power-profiles-daemon && echo "  -> служба включена"
    fi
    echo
    read -rp "Готово. Enter — закрыть окно " _
}

case "${1:-}" in
    status)  cmd_status ;;
    set)     cmd_set "${2:?режим}" ;;
    install) cmd_install ;;
    *)       sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
