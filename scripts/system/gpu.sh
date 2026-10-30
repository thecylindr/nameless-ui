#!/bin/bash
# Режимы графики ноутбука с двумя видеокартами — мягко, без перезагрузки и сторонних пакетов:
#   hybrid       — рабочий стол рисует встроенная (Intel/AMD); дискретная просыпается по требованию (prime-run, игры) и засыпает сама
#   eco          — то же, но Hyprland открывает только встроенную (AQ_DRM_DEVICES), программы на дискретной закрываются —
#                  она уходит в сон (Runtime D3), батарея живёт дольше; мониторы на портах дискретной не работают; нужен перезаход
#   performance  — переменные NVIDIA для всей сессии (~/.config/hypr/gpu.lua): всё рисует дискретная; нужен перезаход в сессию
#
#   gpu.sh status            режим, состояние дискретной (спит / работает), кто её держит, питание — JSON
#   gpu.sh mode <режим>      сменить режим (gpu.lua меняется для hybrid/eco ↔ performance — вступит после перезахода)
#   gpu.sh free              закрыть программы пользователя, держащие дискретную (Xorg/системные не трогаются)
# Режим хранится в ~/.config/glassrice/gpu-mode

set -uo pipefail
STATE="$HOME/.config/glassrice/gpu-mode"
GPU_LUA="$HOME/.config/hypr/gpu.lua"

# дискретная: NVIDIA (10de) или вторая AMD, не основная (boot_vga = 0)
dgpu() {
    local d
    for d in /sys/bus/pci/devices/*; do
        [[ "$(cat "$d/class" 2>/dev/null)" == 0x03* ]] || continue
        [[ "$(cat "$d/boot_vga" 2>/dev/null)" == 1 ]] && continue
        echo "$d"; return 0
    done
    return 1
}
gpu_count() { local n=0 d; for d in /sys/bus/pci/devices/*; do [[ "$(cat "$d/class" 2>/dev/null)" == 0x03* ]] && n=$((n + 1)); done; echo "$n"; }
mode() { [[ -s "$STATE" ]] && cat "$STATE" || { [[ -f "$GPU_LUA" ]] && grep -q 'GBM_BACKEND' "$GPU_LUA" && echo performance || echo hybrid; }; }
on_battery() { local s; for s in /sys/class/power_supply/*/online; do [[ "$(cat "$s")" == 0 ]] && grep -q Mains "$(dirname "$s")/type" && return 0; done; return 1; }

# программы пользователя, которые рисуют или считают на дискретной: таблица nvidia-smi (G / C), без nvidia-smi — открытые узлы устройства.
# Композитор и X-серверы не трогаются никогда
SAFE='^(Hyprland|Xwayland|Xorg|X|kwin_wayland|kwin_x11|gnome-shell|sddm.*|gdm.*|driftwm|ld-linux.*)$'
holders() {
    local pid name
    if command -v nvidia-smi >/dev/null; then
        nvidia-smi 2>/dev/null | awk '/Processes:/ { p = 1; next } p && $0 ~ /^\|/ && ($6 == "G" || $6 == "C") { print $5 }'
    else
        local dev slot nodes=()
        dev="$(dgpu)" || return 0; slot="$(basename "$dev")"
        [[ -e "/dev/dri/by-path/pci-$slot-render" ]] && nodes+=("$(readlink -f "/dev/dri/by-path/pci-$slot-render")")
        (( ${#nodes[@]} )) && fuser "${nodes[@]}" 2>/dev/null | tr ' ' '\n'
    fi | while read -r pid; do
        pid="${pid//[^0-9]/}"
        [[ -n "$pid" && "$(stat -c %u "/proc/$pid" 2>/dev/null)" == "$(id -u)" ]] || continue
        name="$(cat "/proc/$pid/comm" 2>/dev/null)"
        [[ "$name" =~ $SAFE ]] && continue
        echo "$pid $name"
    done | sort -u -k2
}

# PCI-адрес встроенной (boot_vga = 1) и дискретной видеокарты — для AQ_DRM_DEVICES
igpu_slot() {
    local d
    for d in /sys/bus/pci/devices/*; do
        [[ "$(cat "$d/class" 2>/dev/null)" == 0x03* && "$(cat "$d/boot_vga" 2>/dev/null)" == 1 ]] && { basename "$d"; return 0; }
    done
    return 1
}
dgpu_slot() { local d; d="$(dgpu)" && basename "$d"; }

# Lua, который при каждом старте Hyprland сам находит карты по PCI-адресу: номера card0 / card1 между загрузками могут поменяться местами,
# а записанный при смене режима «/dev/dri/card0» тогда указывал бы на другую видеокарту. Не нашлось — переменная не задаётся
lua_drm() {
    cat <<EOF
local function card(slot)
    local p = io.popen("readlink -f /dev/dri/by-path/pci-" .. slot .. "-card 2>/dev/null")
    local r = p and p:read("*l")
    if p then p:close() end
    return (r and r:match("^/dev/dri/card%d+$")) and r or nil
end
EOF
}

write_lua() {
    local d i
    [[ -d "$(dirname "$GPU_LUA")" ]] || return 0
    if [[ "$1" == on ]]; then
        cat > "$GPU_LUA" <<'EOF'
-- Переменные NVIDIA для Wayland (gpu.sh: режим «Производительность»)
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
EOF
        # без AQ_DRM_DEVICES Hyprland рисует на встроенной (первой считает карту с монитором ноутбука), а дискретная простаивает:
        # первой в списке — карта, на которой рисуется, остальные — для вывода на их порты
        if d="$(dgpu_slot)" && i="$(igpu_slot)"; then
            { lua_drm; printf 'local dg, ig = card("%s"), card("%s")\nif dg and ig then hl.env("AQ_DRM_DEVICES", dg .. ":" .. ig) end\n' "$d" "$i"; } >> "$GPU_LUA"
        fi
    elif [[ "$1" == eco ]] && i="$(igpu_slot)"; then
        # Hyprland открывает только встроенную: иначе он держит дискретную, и она не засыпает.
        # Мониторы, подключённые к портам дискретной (часто HDMI ноутбука), в этом режиме не работают
        { echo '-- Режим «Экономия» (gpu.sh): Hyprland только на встроенной, дискретная спит'; lua_drm
          printf 'local ig = card("%s")\nif ig then hl.env("AQ_DRM_DEVICES", ig) end\n' "$i"; } > "$GPU_LUA"
    else
        echo '-- Переменные NVIDIA не заданы: рисует встроенная, дискретная — по требованию (gpu.sh: гибрид)' > "$GPU_LUA"
    fi
}

cmd_status() {
    local dev="" st="none" name="" hold
    if dev="$(dgpu)"; then
        st="$(cat "$dev/power/runtime_status" 2>/dev/null || echo unknown)"
        name="$(lspci -s "$(basename "$dev")" 2>/dev/null | sed -E 's/^[0-9a-f:.]+ [^:]+: //')"
    fi
    hold="$(holders | jq -R 'split(" ") | { pid: (.[0] | tonumber), name: .[1] }' | jq -s .)"
    # gpu.lua изменён после запуска Hyprland — новые переменные вступят после перезахода в сессию
    local need=false hp
    hp="$(pgrep -x Hyprland | head -n1)"
    [[ -n "$hp" && -f "$GPU_LUA" && "$(stat -c %Y "$GPU_LUA")" -gt "$(stat -c %Y "/proc/$hp")" ]] && need=true
    jq -n --arg mode "$(mode)" --arg st "$st" --arg name "$name" --argjson hold "$hold" --argjson hybrid "$([[ $(gpu_count) -ge 2 && -n "$dev" ]] && echo true || echo false)" \
          --argjson bat "$(on_battery && echo true || echo false)" --argjson relogin "$need" \
        '{ mode: $mode, hybrid: $hybrid, dgpu: $name, state: $st, holders: $hold, battery: $bat, relogin: $relogin }'
}

cmd_mode() {
    case "$1" in hybrid|eco|performance) ;; *) echo "режим: hybrid | eco | performance" >&2; exit 1 ;; esac
    mkdir -p "$(dirname "$STATE")"
    echo "$1" > "$STATE"
    case "$1" in performance) write_lua on ;; eco) write_lua eco ;; *) write_lua off ;; esac
    [[ "$1" == eco ]] && cmd_free >/dev/null
    echo ok
}

cmd_free() {
    local pid name n=0
    while read -r pid name; do
        [[ -n "$pid" ]] || continue
        kill -TERM "$pid" 2>/dev/null && n=$((n + 1))
    done < <(holders)
    echo "$n"
}

case "${1:-}" in
    status) cmd_status ;;
    mode)   cmd_mode "${2:?режим}" ;;
    free)   cmd_free ;;
    *)      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
