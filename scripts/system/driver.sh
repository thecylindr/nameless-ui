#!/bin/bash
# Настройщик драйверов видеокарты для Arch Linux
#
#   ./driver.sh            определить железо, показать план и установить (с подтверждением)
#   ./driver.sh --check    только диагностика: карта, драйвер в работе, ядра и заголовки, переменные Hyprland
#   ./driver.sh --yes      установить без вопросов (так его вызывает install.sh)
#   ./driver.sh --env      только переменные NVIDIA для Hyprland (~/.config/hypr/gpu.lua) по железу
#   ./driver.sh --status   что найдено и чего не хватает — JSON для NameLess UI («Программы» → «Драйверы», вопрос при первом запуске)
#
# NVIDIA выбирается по кодовому имени чипа из lspci:
#   TU / GA / AD / GB / GH  (RTX 20xx–50xx, GTX 16xx)        — nvidia-open из репозитория
#   GM / GP / GV            (GTX 9xx, GTX 10xx, Titan V)      — nvidia-580xx из AUR (основной драйвер их не поддерживает)
#   GK                      (GTX 6xx/7xx)                     — nvidia-470xx из AUR (Wayland на нём слабый: спросит, nouveau или 470)
#   GF                      (GTX 4xx/5xx)                     — nvidia-390xx из AUR (только X11; под Hyprland остаётся nouveau)
#   G8x / G9x / GT2xx       (8xxx–3xx)                        — драйвера под современные ядра нет, остаётся nouveau
# Intel до Broadwell (Sandy/Ivy Bridge, Haswell, Bay Trail) — libva-intel-driver вместо intel-media-driver.
# AMD: GCN 1–2 (HD 7xxx, R7/R9 2xx) — драйвер amdgpu вместо radeon (даёт Vulkan); TeraScale (HD 2xxx–6xxx) — только Mesa.
# Процессор: микрокод intel-ucode / amd-ucode (встраивается в initramfs хуком microcode)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG="$ROOT/packages"
GPU_LUA="$HOME/.config/hypr/gpu.lua"
MODE="install"
YES=0

for a in "$@"; do
    case "$a" in
        --check) MODE="check" ;;
        --env)   MODE="env" ;;
        --status) MODE="status" ;;
        --yes|-y) YES=1 ;;
        *) echo "неизвестный аргумент: $a" >&2; exit 1 ;;
    esac
done

log()  { echo -e "\n\e[1;32m==>\e[0m \e[1m$1\e[0m"; }
info() { echo -e "\e[1;34m  ->\e[0m $1"; }
warn() { echo -e "\e[1;33m  !!\e[0m $1"; }
bad()  { echo -e "\e[1;31m  xx\e[0m $1"; }

read_list() { grep -vE '^\s*(#|$)' "$PKG/$1.txt"; }

confirm() {
    [[ $YES -eq 1 ]] && return 0
    local ans
    read -rp "  $1 [Y/n] " ans
    [[ -z "$ans" || "$ans" =~ ^[YyДд] ]]
}

# ---------- определение железа ----------

GPU_LINES="$(lspci -k 2>/dev/null | grep -EA3 'VGA|3D|Display')"
# только строки самих видеокарт: в подробных есть «compatible», «Subsystem: Intel» и прочее
GPU_ONLY="$(lspci 2>/dev/null | grep -iE 'vga|3d|display')"
NV_LINE="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -i nvidia | head -n1)"
NV_CHIP="$(grep -oE '\b(GF|GK|GM|GP|GV|TU|GA|AD|GB|GH|GT2|G[89])[0-9]+' <<<"$NV_LINE" | head -n1)"
INTEL_LINE="$(grep -i 'intel' <<<"$GPU_ONLY" | head -n1)"
AMD_LINE="$(grep -E 'Advanced Micro Devices|AMD/ATI|Radeon' <<<"$GPU_ONLY" | head -n1)"
CPU_VENDOR="$(grep -m1 vendor_id /proc/cpuinfo | awk '{print $3}')"

nvidia_branch() {
    case "$NV_CHIP" in
        TU*|GA*|AD*|GB*|GH*) echo open ;;
        GM*|GP*|GV*)         echo 580xx ;;
        GK*)                 echo 470xx ;;
        GF*)                 echo 390xx ;;
        "")                  echo none ;;
        *)                   echo legacy ;;
    esac
}

# Intel: old — до Broadwell (драйвер видео i965), new — Broadwell и новее (iHD)
intel_gen() {
    [[ -n "$INTEL_LINE" ]] || { echo none; return; }
    if grep -qiE '2nd Generation|3rd Gen|4th Gen|Sandy Bridge|Ivy Bridge|Haswell|Bay Trail|Atom|GMA|Mobile 4 Series|Core Processor Integrated|HD Graphics (2000|2500|3000|4000|4200|4400|4600|5000|5100)\b' <<<"$INTEL_LINE"; then echo old; else echo new; fi
}
# AMD: terascale — только Mesa; gcn1 — Southern/Sea Islands (amdgpu вместо radeon); new — остальные
amd_family() {
    [[ -n "$AMD_LINE" ]] || { echo none; return; }
    if grep -qiE 'Cedar|Redwood|Juniper|Cypress|Hemlock|Caicos|Turks|Barts|Cayman|Antilles|Wrestler|Sumo|Trinity|Richland|Devastator|Scrapper|Palm|Aruba|\bRV[0-9]{3}|\bR[67][0-9]{2}\b' <<<"$AMD_LINE"; then echo terascale
    elif grep -qiE 'Tahiti|Pitcairn|Cape Verde|Oland|Hainan|Bonaire|Hawaii|Kaveri|Kabini|Mullins|Beema|Temash|Spectre|Spooky|Kalindi|Godavari|Curacao|Saturn|Mars|Venus|Neptune|Opal|Tobago|Grenada' <<<"$AMD_LINE"; then echo gcn1
    else echo new; fi
}
ucode_pkg() { case "$CPU_VENDOR" in GenuineIntel) echo intel-ucode ;; AuthenticAMD) echo amd-ucode ;; esac; }

# заголовки для всех установленных ядер (нужны dkms-модулям 580xx)
kernel_headers() {
    local k
    for k in linux linux-lts linux-zen linux-hardened; do
        pacman -Q "$k" >/dev/null 2>&1 && echo "$k-headers"
    done
}

# модуль читается из /proc/modules: «lsmod | grep -q» при pipefail ложно падает (SIGPIPE)
nvidia_working() { grep -q '^nvidia ' /proc/modules 2>/dev/null && command -v nvidia-smi >/dev/null && nvidia-smi -L >/dev/null 2>&1; }

# ---------- диагностика ----------

check() {
    log "Видеокарты"
    lspci 2>/dev/null | grep -iE 'vga|3d|display' | sed 's/^/     /'
    log "Драйвер в работе"
    grep -E 'Kernel driver in use' <<<"$GPU_LINES" | sed 's/^\s*/     /' || true

    if [[ -n "$NV_LINE" ]]; then
        log "NVIDIA"
        case "$(nvidia_branch)" in
            open)   info "чип $NV_CHIP — Turing и новее: нужен nvidia-open" ;;
            580xx)  info "чип $NV_CHIP — Maxwell / Pascal / Volta: нужен nvidia-580xx из AUR" ;;
            470xx)  info "чип $NV_CHIP — Kepler: nvidia-470xx из AUR (Wayland слабый) или nouveau" ;;
            390xx)  info "чип $NV_CHIP — Fermi: nvidia-390xx из AUR (только X11) или nouveau" ;;
            legacy) warn "чип $NV_CHIP — Tesla и старше: текущих драйверов нет, только nouveau" ;;
        esac
        local p
        for p in nvidia-open nvidia-utils nvidia-580xx-dkms nvidia-580xx-utils; do
            pacman -Q "$p" 2>/dev/null | sed 's/^/     установлен: /'
        done
        if nvidia_working; then
            info "драйвер работает: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null)"
        else
            bad "драйвер NVIDIA не работает (модуль не загружен или nvidia-smi не отвечает)"
            [[ "$(nvidia_branch)" == 580xx ]] && pacman -Q nvidia-open >/dev/null 2>&1 \
                && bad "стоит nvidia-open — он не поддерживает $NV_CHIP, отсюда ошибки OpenGL"
        fi
    fi

    log "Ядра и заголовки"
    local h
    for h in $(kernel_headers); do
        pacman -Q "$h" >/dev/null 2>&1 && info "$h — есть" || warn "$h — нет (нужен для dkms)"
    done

    log "Переменные NVIDIA в Hyprland ($GPU_LUA)"
    if [[ -f "$GPU_LUA" ]] && grep -q 'nvidia' "$GPU_LUA"; then
        if [[ -z "$NV_LINE" ]]; then bad "заданы, но NVIDIA нет — они ломают OpenGL"
        elif ! nvidia_working; then bad "заданы, но драйвер NVIDIA не работает — они ломают OpenGL"
        else info "заданы, драйвер работает"; fi
    else
        info "не заданы"
    fi

    # зависание Intel (i915): сброс чипа уничтожает контекст Hyprland — он падает и встаёт в безопасном режиме
    log "Зависания видеокарты (журнал за 3 загрузки)"
    local hangs=0 b crashes lines first=""
    for b in 0 -1 -2; do
        lines="$(journalctl -k -b "$b" --no-pager 2>/dev/null | grep 'GPU HANG')"
        [[ -n "$lines" ]] || continue
        hangs=$((hangs + $(wc -l <<<"$lines")))
        [[ -n "$first" ]] || first="$(head -n1 <<<"$lines")"
    done
    crashes="$(find "$HOME/.cache/hyprland" -name 'hyprlandCrashReport*' -mtime -3 2>/dev/null | wc -l)"
    if (( hangs > 0 )); then
        bad "зависаний GPU: $hangs, отчётов о падении Hyprland за 3 дня: $crashes"
        echo "     $first"
        info "обновить прошивку: sudo pacman -Syu linux-firmware"
        info "сброс без падения Hyprland — отправка через execlists: параметр ядра i915.enable_guc=2"
        info "  (добавить в GRUB_CMDLINE_LINUX_DEFAULT в /etc/default/grub и выполнить grub-mkconfig -o /boot/grub/grub.cfg)"
    else
        info "не было"
    fi
}

# ---------- установка ----------

aur_install() {
    if ! command -v yay >/dev/null; then
        info "ставлю yay"
        sudo pacman -S --needed --noconfirm base-devel git || return 1
        local tmp; tmp="$(mktemp -d)"
        git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" && (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
        rm -rf "$tmp"
    fi
    yay -S --needed --noconfirm "$@"
}

# переменные NVIDIA для Hyprland: только при работающей (или ставящейся) NVIDIA
write_gpu_lua() {
    [[ -d "$(dirname "$GPU_LUA")" ]] || return 0
    if [[ "$1" == on ]]; then
        cat > "$GPU_LUA" <<'EOF'
-- Переменные NVIDIA для Wayland (настраивает driver.sh)
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
EOF
    else
        echo '-- Переменные NVIDIA не нужны (настраивает driver.sh)' > "$GPU_LUA"
    fi
}

install_nvidia() {
    local branch; branch="$(nvidia_branch)"
    local headers=(); mapfile -t headers < <(kernel_headers)

    case "$branch" in
        open)
            log "NVIDIA $NV_CHIP: открытые модули (nvidia-open)"
            confirm "Установить?" || return 0
            sudo pacman -S --needed --noconfirm "${headers[@]}" $(read_list drivers-nvidia) || return 1
            ;;
        580xx)
            log "NVIDIA $NV_CHIP: драйвер 580xx из AUR"
            local p old=()
            for p in nvidia-open nvidia-open-dkms nvidia nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings; do
                pacman -Q "$p" >/dev/null 2>&1 && old+=("$p")
            done
            [[ ${#old[@]} -gt 0 ]] && info "будут удалены неподходящие пакеты: ${old[*]}"
            confirm "Установить?" || return 0
            sudo pacman -S --needed --noconfirm "${headers[@]}" || return 1
            # основной драйвер конфликтует с 580xx
            [[ ${#old[@]} -gt 0 ]] && { sudo pacman -Rdd --noconfirm "${old[@]}" || return 1; }
            mapfile -t list < <(read_list drivers-nvidia-580xx)
            aur_install "${list[@]}" || return 1
            ;;
        470xx|390xx)
            # старые ветки: Hyprland с ними работает плохо (470 — без GBM, 390 — только X11), поэтому спрашиваем
            log "NVIDIA $NV_CHIP: драйвер $branch из AUR"
            warn "Hyprland на ветке $branch работает плохо или не запускается; nouveau медленнее, но с Wayland дружит"
            if [[ $YES -eq 1 ]] || ! confirm "Поставить $branch (иначе остаётся nouveau)?"; then
                info "остаётся nouveau"; write_gpu_lua off; return 0
            fi
            local p old=()
            for p in nvidia-open nvidia-open-dkms nvidia nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings; do
                pacman -Q "$p" >/dev/null 2>&1 && old+=("$p")
            done
            sudo pacman -S --needed --noconfirm "${headers[@]}" || return 1
            [[ ${#old[@]} -gt 0 ]] && { sudo pacman -Rdd --noconfirm "${old[@]}" || return 1; }
            mapfile -t list < <(read_list "drivers-nvidia-$branch")
            aur_install "${list[@]}" || return 1
            ;;
        legacy)
            warn "NVIDIA $NV_CHIP (Tesla и старше): драйверов под современные ядра нет, остаётся nouveau"
            write_gpu_lua off
            return 0
            ;;
    esac

    sudo pacman -S --needed --noconfirm $(read_list drivers-nvidia-common) || warn "общие пакеты NVIDIA поставились не все"
    # KMS NVIDIA для Wayland
    echo "options nvidia_drm modeset=1 fbdev=1" | sudo tee /etc/modprobe.d/nvidia.conf >/dev/null
    sudo mkinitcpio -P || return 1
    write_gpu_lua on
    info "готово — нужна перезагрузка, после неё проверь: nvidia-smi"
}

install_all() {
    [[ $EUID -eq 0 ]] && { warn "Запускай от обычного пользователя, sudo спросится сам"; exit 1; }
    local rc=0
    local uc; uc="$(ucode_pkg)"
    if [[ -n "$uc" ]] && ! pacman -Q "$uc" >/dev/null 2>&1; then
        log "Микрокод процессора ($uc)"
        sudo pacman -S --needed --noconfirm "$uc" || rc=1
        need_initramfs=1
    fi
    case "$(intel_gen)" in
        new) log "Intel"; sudo pacman -S --needed --noconfirm $(read_list drivers-intel) || rc=1 ;;
        old) log "Intel (до Broadwell): видеоускорение i965"; sudo pacman -S --needed --noconfirm $(read_list drivers-intel-legacy) || rc=1 ;;
    esac
    case "$(amd_family)" in
        new) log "AMD"; sudo pacman -S --needed --noconfirm $(read_list drivers-amd) || rc=1 ;;
        gcn1)
            log "AMD GCN 1–2: драйвер amdgpu вместо radeon (Vulkan)"
            sudo pacman -S --needed --noconfirm $(read_list drivers-amd) || rc=1
            printf 'options amdgpu si_support=1 cik_support=1\noptions radeon si_support=0 cik_support=0\n' | sudo tee /etc/modprobe.d/glassrice-amdgpu.conf >/dev/null
            need_initramfs=1
            ;;
        terascale) log "AMD TeraScale: OpenGL через Mesa (Vulkan на этих картах нет)"; sudo pacman -S --needed --noconfirm $(read_list drivers-amd-legacy) || rc=1 ;;
    esac
    # ПК без подсветки ноутбука: яркость монитора по DDC/CI (ddcutil через шину i2c)
    if ! compgen -G "/sys/class/backlight/*" >/dev/null; then
        log "Яркость монитора по DDC/CI"
        sudo pacman -S --needed --noconfirm ddcutil || rc=1
        echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
        sudo modprobe i2c-dev
    fi
    if [[ -n "$NV_LINE" ]]; then
        install_nvidia || { bad "установка драйвера NVIDIA завершилась с ошибкой"; rc=1; }
    else
        write_gpu_lua off
    fi
    # микрокод и параметры модулей попадают в initramfs (install_nvidia пересобирает его сам)
    if [[ "${need_initramfs:-0}" == 1 && -z "$NV_LINE" ]]; then sudo mkinitcpio -P || rc=1; fi
    return $rc
}


# ---------- состояние для NameLess UI ----------
# { gpus: [{ vendor, name, branch, note, pkgs: [{ name, installed, aur }], ok }], cpu: { vendor, model, ucode, installed },
#   missing: число недостающих пакетов, nvidiaWorking, kernelDriver }
pkg_json() {
    local aur="$1"; shift
    local p
    for p in "$@"; do jq -cn --arg n "$p" --argjson i "$(pacman -Q "$p" >/dev/null 2>&1 && echo true || echo false)" --argjson a "$aur" '{ name: $n, installed: $i, aur: $a }'; done
}
status_json() {
    local gpus=() note list aur
    if [[ -n "$NV_LINE" ]]; then
        local b; b="$(nvidia_branch)"; aur=false; list=""
        case "$b" in
            open)  note="Turing и новее: открытые модули nvidia-open"; list="$(read_list drivers-nvidia) $(read_list drivers-nvidia-common)" ;;
            580xx) note="Maxwell / Pascal / Volta: ветка 580 из AUR"; list="$(read_list drivers-nvidia-580xx)"; aur=true ;;
            470xx) note="Kepler: ветка 470 из AUR (Wayland слабый — можно остаться на nouveau)"; list="$(read_list drivers-nvidia-470xx)"; aur=true ;;
            390xx) note="Fermi: ветка 390 из AUR, только X11 — под Hyprland остаётся nouveau"; list="$(read_list drivers-nvidia-390xx)"; aur=true ;;
            *)     note="очень старая карта: драйвера под современные ядра нет, работает nouveau" ;;
        esac
        gpus+=("$(jq -cn --arg name "$(sed -E 's/^[0-9a-f:.]+ [^:]+: //' <<<"$NV_LINE")" --arg b "$b" --arg note "$note" \
            --argjson pk "$( [[ -n "$list" ]] && pkg_json "$aur" $list | jq -s . || echo '[]')" --argjson w "$(nvidia_working && echo true || echo false)" \
            '{ vendor: "nvidia", name: $name, branch: $b, note: $note, pkgs: $pk, working: $w, ok: ($pk | all(.installed)) }')")
    fi
    if [[ -n "$INTEL_LINE" ]]; then
        local g; g="$(intel_gen)"
        list="$(read_list "$([[ "$g" == old ]] && echo drivers-intel-legacy || echo drivers-intel)")"
        gpus+=("$(jq -cn --arg name "$(sed -E 's/^[0-9a-f:.]+ [^:]+: //' <<<"$INTEL_LINE")" --arg b "$g" \
            --arg note "$([[ "$g" == old ]] && echo 'до Broadwell: видеоускорение i965 (libva-intel-driver)' || echo 'видеоускорение iHD и Vulkan')" \
            --argjson pk "$(pkg_json false $list | jq -s .)" '{ vendor: "intel", name: $name, branch: $b, note: $note, pkgs: $pk, working: true, ok: ($pk | all(.installed)) }')")
    fi
    if [[ -n "$AMD_LINE" ]]; then
        local f; f="$(amd_family)"
        list="$(read_list "$([[ "$f" == terascale ]] && echo drivers-amd-legacy || echo drivers-amd)")"
        note="Mesa: OpenGL, Vulkan (RADV), видеоускорение"
        [[ "$f" == gcn1 ]] && note="GCN 1–2: amdgpu вместо radeon даёт Vulkan — настраивает «Установить всё»"
        [[ "$f" == terascale ]] && note="TeraScale: только OpenGL через Mesa"
        gpus+=("$(jq -cn --arg name "$(sed -E 's/^[0-9a-f:.]+ [^:]+: //' <<<"$AMD_LINE")" --arg b "$f" --arg note "$note" \
            --argjson pk "$(pkg_json false $list | jq -s .)" \
            --argjson tuned "$([[ "$f" != gcn1 || -f /etc/modprobe.d/glassrice-amdgpu.conf ]] && echo true || echo false)" \
            '{ vendor: "amd", name: $name, branch: $b, note: $note, pkgs: $pk, working: true, ok: (($pk | all(.installed)) and $tuned) }')")
    fi
    local uc; uc="$(ucode_pkg)"
    jq -n --argjson gpus "$(printf '%s\n' "${gpus[@]}" | jq -s .)" \
          --arg cv "$CPU_VENDOR" --arg cm "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')" --arg uc "$uc" \
          --argjson ui "$([[ -z "$uc" ]] || pacman -Q "$uc" >/dev/null 2>&1 && echo true || echo false)" \
          --argjson env "$([[ -f "$GPU_LUA" ]] && grep -q nvidia "$GPU_LUA" && echo true || echo false)" '
        { gpus: $gpus, cpu: { vendor: $cv, model: $cm, ucode: $uc, installed: $ui }, nvidiaEnv: $env,
          missing: ([$gpus[] | select(.ok | not)] | length) + (if $ui then 0 else 1 end) }'
}

case "$MODE" in
    check) check ;;
    status) status_json ;;
    # переменные нужны, только если у карты есть текущий драйвер (Maxwell и новее)
    env)   case "$(nvidia_branch)" in open|580xx) write_gpu_lua on ;; *) write_gpu_lua off ;; esac ;;
    *)     install_all ;;
esac
