#!/bin/bash
# Подсветка и её драйверы: клавиатура ноутбука (sysfs, драйверы по платформе) и подсветка ПК (OpenRGB).
#
#   rgb.sh status                 устройство, найденная подсветка, драйверы и рекомендации — JSON для окна «Программы»
#   rgb.sh set RRGGBB [яркость%]  цвет и яркость везде, где можно: клавиатура ноутбука и устройства OpenRGB
#   rgb.sh effect <вид> [скорость] [RRGGBB…]   эффект: rainbow — радуга, wave — волна (быстрая радуга),
#                                 gradient — перелив между цветами, breathe — дыхание одним цветом; скорость 1–10
#   rgb.sh off                    погасить (и остановить эффект)
#   rgb.sh restore                вернуть сохранённый цвет (theme.sh start при входе)
#   rgb.sh follow on|off [RRGGBB] [accent|accent2]  подсветка следует цвету темы (on) или живёт сама по себе (off);
#                                 цвет — акцент 1 или 2 темы (оба меняются вместе с автоцветом от обоев)
#   rgb.sh theme RRGGBB [RRGGBB2] акценты темы сменились (вызывает theme.sh): применяется выбранный, только если включено follow
#   rgb.sh install                поставить драйверы под это устройство и права на подсветку без sudo (в терминале)
#   rgb.sh probe                  есть ли подсветка (быстро, без поиска устройств OpenRGB) — JSON { supported, kbd, openrgb, usb, why }
#   rgb.sh server                 запустить сервер OpenRGB в фоне (устройства ищутся один раз; restore делает это сам)
#
# Ноутбук: подсветка — /sys/class/leds/*kbd_backlight* (RGB, если есть multi_intensity); драйвер — по производителю:
#   Clevo / Machenike / Tuxedo — tuxedo-drivers-dkms; ASUS — asusctl; System76 — system76-driver.
# ПК: OpenRGB находит подсветку материнской платы, памяти, видеокарты, кулеров (нужен модуль i2c-dev и правила udev).
#   Поиск устройств у OpenRGB долгий (на ПК с платой и памятью — секунды), поэтому при входе запускается его сервер, и цвета
#   применяются через него мгновенно. Без сервера — запуском OpenRGB, по очереди: раньше каждый новый цвет (автоцвет от обоев меняет
#   акцент часто) убивал прошлый запуск посреди поиска, и до устройств не доходил ни один — подсветка «не показывала цвета»
# Права: правило udev даёт запись в brightness и multi_intensity без sudo. Цвет сохраняется в ~/.config/glassrice/rgb.json

set -uo pipefail
STATE="$HOME/.config/glassrice/rgb.json"
RUN="${XDG_RUNTIME_DIR:-/tmp}/glassrice-rgb"      # pid эффекта и фонового OpenRGB
mkdir -p "$RUN"
UDEV_RULE=/etc/udev/rules.d/90-glassrice-kbd-backlight.rules
DMI=/sys/class/dmi/id

vendor() { local v; v="$(cat "$DMI/sys_vendor" 2>/dev/null)"; [[ -n "$v" ]] || v="$(cat "$DMI/board_vendor" 2>/dev/null)"; echo "$v"; }
is_laptop() { compgen -G '/sys/class/power_supply/BAT*' >/dev/null; }
leds() { for d in /sys/class/leds/*kbd_backlight*; do [[ -d "$d" ]] && echo "$d"; done; }

# драйверы по платформе: «пакет|зачем»
recommend() {
    local v; v="$(vendor | tr '[:upper:]' '[:lower:]')"
    if is_laptop; then
        if grep -qE 'clevo|machenike|tuxedo|kapok|xmg|schenker|eluktronics' <<<"$v"; then
            echo "tuxedo-drivers-dkms|клавиатура RGB, вентиляторы, режимы питания (платформа Clevo)"
        elif grep -q 'asus' <<<"$v"; then
            echo "asusctl|подсветка Aura, профили, вентиляторы ноутбуков ASUS"
        elif grep -q 'system76' <<<"$v"; then
            echo "system76-driver|подсветка и прошивка System76"
        fi
    fi
    echo "openrgb|подсветка ПК: плата, память, видеокарта, кулеры, периферия"
}

# цвет в sysfs: multi_intensity в порядке multi_index, яркость — доля max_brightness
set_led() {
    local d="$1" hex="$2" pct="$3" r g b order out="" max
    r=$((16#${hex:0:2})); g=$((16#${hex:2:2})); b=$((16#${hex:4:2}))
    max="$(cat "$d/max_brightness" 2>/dev/null || echo 255)"
    if [[ -f "$d/multi_intensity" ]]; then
        read -ra order < "$d/multi_index"
        for c in "${order[@]}"; do case "$c" in red) out+="$r ";; green) out+="$g ";; blue) out+="$b ";; *) out+="0 ";; esac; done
        echo "${out% }" > "$d/multi_intensity" 2>/dev/null || return 3
    fi
    echo $((max * pct / 100)) > "$d/brightness" 2>/dev/null || return 3
}

stop_effect() { [[ -f "$RUN/effect.pid" ]] && kill "$(cat "$RUN/effect.pid")" 2>/dev/null; rm -f "$RUN/effect.pid"; }

# OpenRGB: сервер SDK на 127.0.0.1:6742 — устройства найдены один раз, клиент применяет цвет за доли секунды
server_up() { (exec 3<>/dev/tcp/127.0.0.1/6742) 2>/dev/null; }
cmd_server() {
    command -v openrgb >/dev/null || return 1
    server_up && return 0
    [[ -f "$RUN/server.pid" ]] && kill -0 "$(cat "$RUN/server.pid")" 2>/dev/null && return 0       # уже запускается
    setsid -f sh -c 'echo $$ > "$1/server.pid"; exec openrgb --server --noautoconnect >/dev/null 2>&1' sh "$RUN"
}

# команда OpenRGB в фоне: записывается как «желаемая», один обработчик применяет их по очереди — всегда последнюю.
# Новый вызов не прерывает идущий (раньше прерывал, и при частой смене цвета не применялся ни один)
openrgb_bg() {
    command -v openrgb >/dev/null || return 1
    printf '%s\n' "$@" > "$RUN/want.tmp" && mv "$RUN/want.tmp" "$RUN/want"
    setsid -f bash "$0" _apply >/dev/null 2>&1
    return 0
}
cmd_apply() {
    exec 9>"$RUN/openrgb.lock"
    flock -n 9 || exit 0                       # обработчик уже работает — он возьмёт и этот цвет
    local args n=0
    while [[ -f "$RUN/want" ]] && (( n++ < 20 )); do
        mapfile -t args < "$RUN/want"; rm -f "$RUN/want"
        if server_up; then timeout 20 openrgb --client 127.0.0.1:6742 "${args[@]}" >/dev/null 2>&1
        else timeout 60 openrgb --noautoconnect "${args[@]}" >/dev/null 2>&1; fi
    done
    exec 9>&-
    # цвет пришёл в последний миг, когда обработчик уже выходил
    [[ -f "$RUN/want" ]] && exec bash "$0" _apply
    exit 0
}

# быстрая проверка: есть ли что подсвечивать (по ней окно показывает вкладку «Подсветка»)
#   клавиатура ноутбука в sysfs; устройства из прошлого поиска OpenRGB; USB-контроллеры подсветки известных производителей;
#   ноутбук, для которого есть драйвер подсветки (Clevo, ASUS, System76)
RGB_USB='0b05:18f3|0b05:1867|0b05:1872|0b05:1939|0b05:19af|0b05:1aa6|1b1c:|1532:|1038:|1e71:|2516:|264a:|0cf2:|048d:5702|048d:8297|1462:7c|0951:16|03f0:|1044:7a|26ce:01a2|3633:|2433:|195d:'
CACHE_DEVS="${XDG_CACHE_HOME:-$HOME/.cache}/glassrice/rgb-devices"
cmd_probe() {
    local kbd=false orgb=false usb="" why="" v
    [[ -n "$(leds)" ]] && { kbd=true; why="клавиатура ноутбука"; }
    [[ -s "$CACHE_DEVS" ]] && { orgb=true; why="${why:+$why, }OpenRGB: $(head -3 "$CACHE_DEVS" | paste -sd, -)"; }
    command -v lsusb >/dev/null && usb="$(lsusb 2>/dev/null | grep -Ei " ID ($RGB_USB)" | sed -E 's/.*ID [0-9a-f:]+ //' | head -3 | paste -sd, -)"
    [[ -n "$usb" ]] && why="${why:+$why, }$usb"
    v="$(vendor | tr '[:upper:]' '[:lower:]')"
    if [[ -z "$why" ]] && is_laptop && grep -qE 'clevo|machenike|tuxedo|asus|system76' <<<"$v"; then why="ноутбук $(vendor): подсветка после установки драйвера"; fi
    # scanned: OpenRGB уже искал устройства — без поиска подсветку памяти и платы (шина i2c) не увидеть, окно запускает его один раз само
    jq -cn --argjson kbd "$kbd" --argjson orgb "$orgb" --arg usb "$usb" --arg why "$why" \
        --argjson hasOrgb "$(command -v openrgb >/dev/null && echo true || echo false)" --argjson scanned "$([[ -f "$CACHE_DEVS" ]] && echo true || echo false)" \
        '{ supported: ($why != ""), kbd: $kbd, openrgb: $orgb, usb: $usb, why: $why, hasOpenrgb: $hasOrgb, scanned: $scanned }'
}

# follow (следовать теме) сохраняется между записями: его меняет только rgb.sh follow
save_state() {
    mkdir -p "$(dirname "$STATE")"
    local fw=false src=accent
    [[ -f "$STATE" ]] && { fw="$(jq -r '.follow // false' "$STATE" 2>/dev/null)"; src="$(jq -r '.source // "accent"' "$STATE" 2>/dev/null)"; }
    [[ "$fw" == true ]] || fw=false
    jq -n --arg c "$1" --argjson b "$2" --arg e "${3:-static}" --argjson sp "${4:-5}" --arg cols "${5:-}" --argjson fw "$fw" --arg src "$src" \
        '{ color: $c, brightness: $b, effect: $e, speed: $sp, colors: ($cols | split(" ") | map(select(. != ""))), follow: $fw, source: $src }' > "$STATE"
}

# акцент темы → подсветка. Статичный цвет и «дыхание» берут акцент; радуга, волна и перелив остаются как есть.
# Тот же цвет повторно не применяется (OpenRGB подключается к устройствам ~1 с), выключенная подсветка (яркость 0) не включается
cmd_theme() {
    local hex="${1#\#}" e pct cur sp
    [[ -f "$STATE" ]] || exit 0
    [[ "$(jq -r '.follow // false' "$STATE")" == true ]] || exit 0
    # акцент 2 — если выбран и передан
    [[ "$(jq -r '.source // "accent"' "$STATE")" == accent2 && -n "${2:-}" ]] && hex="${2#\#}"
    hex="${hex:0:6}"; hex="${hex,,}"
    [[ "$hex" =~ ^[0-9a-f]{6}$ ]] || exit 0
    e="$(jq -r '.effect // "static"' "$STATE")"; pct="$(jq -r '.brightness // 100' "$STATE")"
    cur="$(jq -r '.color // ""' "$STATE")"; sp="$(jq -r '.speed // 5' "$STATE")"
    [[ "${cur,,}" == "$hex" ]] && exit 0
    if (( pct == 0 )); then save_state "$hex" 0 "$e" "$sp"; exit 0; fi
    case "$e" in
        static)   cmd_set "$hex" "$pct" >/dev/null ;;
        breathe)  cmd_effect breathe "$sp" "$hex" >/dev/null ;;
        gradient) [[ -n "${2:-}" ]] && cmd_effect gradient "$sp" "${1#\#}" "${2#\#}" >/dev/null ;;      # перелив между акцентами темы
        *)        exit 0 ;;
    esac
}

cmd_follow() {
    local on="$1" hex="${2:-}" src="${3:-}"
    [[ -f "$STATE" ]] || save_state "${hex:-ffffff}" 100 static
    jq --argjson v "$([[ "$on" == on ]] && echo true || echo false)" --arg s "$src" '.follow = $v | if $s != "" then .source = $s else . end' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    [[ "$on" == on && -n "$hex" ]] && cmd_theme "$hex"
    echo ok
}

cmd_set() {
    local hex="${1#\#}" pct="${2:-100}" ok=0 denied=0 d
    [[ "$hex" =~ ^[0-9a-fA-F]{6}$ ]] || { echo "цвет: RRGGBB" >&2; exit 1; }
    stop_effect
    # клавиатура ноутбука — сразу (sysfs)
    for d in $(leds); do
        if set_led "$d" "$hex" "$pct"; then ok=1; else denied=1; fi
    done
    # OpenRGB — в фоне; яркость — затемнением цвета
    local R G B
    R=$(printf '%02x' $((16#${hex:0:2} * pct / 100))); G=$(printf '%02x' $((16#${hex:2:2} * pct / 100))); B=$(printf '%02x' $((16#${hex:4:2} * pct / 100)))
    openrgb_bg --mode static --color "$R$G$B" && ok=1
    save_state "$hex" "$pct" static
    if (( ok )); then echo ok; elif (( denied )); then echo denied; exit 3; else echo none; exit 2; fi
}

# цвет по оттенку 0–359 при полной насыщенности
hue() {
    local h=$(( $1 % 360 )) f r g b
    f=$(( (h % 60) * 255 / 60 ))
    case $(( h / 60 )) in
        0) r=255; g=$f; b=0 ;; 1) r=$((255 - f)); g=255; b=0 ;; 2) r=0; g=255; b=$f ;;
        3) r=0; g=$((255 - f)); b=255 ;; 4) r=$f; g=0; b=255 ;; *) r=255; g=0; b=$((255 - f)) ;;
    esac
    printf '%02x%02x%02x' $r $g $b
}
# смесь двух цветов: доля второго 0–255
mix() {
    local a="$1" b="$2" k="$3" out="" i x y
    for i in 0 2 4; do x=$((16#${a:i:2})); y=$((16#${b:i:2})); out+=$(printf '%02x' $(( x + (y - x) * k / 255 ))); done
    echo "$out"
}

# эффект: цикл в фоне пишет цвет клавиатуры 20 раз в секунду; OpenRGB — встроенным режимом устройства
cmd_effect() {
    local kind="${1:-rainbow}" speed="${2:-5}" cols=("${@:3}") pct
    pct="$( [[ -f "$STATE" ]] && jq -r '.brightness // 100' "$STATE" || echo 100)"
    (( ${#cols[@]} )) || cols=(ff2d55 0a84ff)
    stop_effect
    case "$kind" in
        rainbow|wave) openrgb_bg --mode "Spectrum Cycle" || true ;;
        breathe)      openrgb_bg --mode Breathing --color "${cols[0]}" || true ;;
        gradient)     openrgb_bg --mode "Spectrum Cycle" || true ;;
    esac
    save_state "${cols[0]}" "$pct" "$kind" "$speed" "${cols[*]}"
    [[ -n "$(leds)" ]] || { echo ok; return; }
    setsid -f bash "$0" _loop "$kind" "$speed" "$pct" "${cols[@]}" >/dev/null 2>&1
    echo ok
}

effect_loop() {
    local kind="$1" speed="$2" pct="$3"; shift 3
    local cols=("$@") n=$# t=0 step hex k seg d
    echo $$ > "$RUN/effect.pid"
    step=$(( speed < 1 ? 1 : (speed > 10 ? 10 : speed) ))
    while :; do
        case "$kind" in
            rainbow)  hex="$(hue $(( t * step / 2 )))" ;;
            wave)     hex="$(hue $(( t * step * 2 )))" ;;
            breathe)  k=$(( (t * step * 4) % 510 )); (( k > 255 )) && k=$((510 - k)); hex="$(mix 000000 "${cols[0]}" "$k")" ;;
            gradient) seg=$(( (t * step * 2) % (256 * n) )); k=$(( seg % 256 )); d=$(( seg / 256 )); hex="$(mix "${cols[d]}" "${cols[(d + 1) % n]}" "$k")" ;;
            *)        exit 0 ;;
        esac
        for d in $(leds); do set_led "$d" "$hex" "$pct" || exit 3; done
        t=$((t + 1))
        sleep 0.05
    done
}

cmd_restore() {
    # сервер OpenRGB — только если подсветка ПК есть (по прошлому поиску) или его ещё не искали: на ноутбуке без неё он не нужен
    if command -v openrgb >/dev/null && { [[ -s "$CACHE_DEVS" ]] || [[ ! -f "$CACHE_DEVS" ]]; }; then cmd_server; sleep 4; fi
    [[ -f "$STATE" ]] || exit 0
    local e; e="$(jq -r '.effect // "static"' "$STATE")"
    if [[ "$e" == static ]]; then cmd_set "$(jq -r '.color' "$STATE")" "$(jq -r '.brightness // 100' "$STATE")" >/dev/null 2>&1 || true
    else mapfile -t c < <(jq -r '.colors[]?' "$STATE"); cmd_effect "$e" "$(jq -r '.speed // 5' "$STATE")" "${c[@]}" >/dev/null 2>&1 || true; fi
}

cmd_status() {
    local led_json="[]" d rec openrgb_devs="" saved='{}'
    for d in $(leds); do
        led_json="$(jq -c --arg n "$(basename "$d")" --argjson rgb "$([[ -f "$d/multi_intensity" ]] && echo true || echo false)" \
            --arg cur "$(cat "$d/multi_intensity" 2>/dev/null)" --arg br "$(cat "$d/brightness" 2>/dev/null)" --arg max "$(cat "$d/max_brightness" 2>/dev/null)" \
            --argjson w "$([[ -w "$d/brightness" ]] && echo true || echo false)" \
            '. + [{ name: $n, rgb: $rgb, current: $cur, brightness: ($br | tonumber? // 0), max: ($max | tonumber? // 255), writable: $w }]' <<<"$led_json")"
    done
    rec="$(recommend | while IFS='|' read -r p why; do
        jq -cn --arg p "$p" --arg w "$why" --argjson inst "$(pacman -Q "$p" >/dev/null 2>&1 && echo true || echo false)" '{ pkg: $p, why: $w, installed: $inst }'
    done | jq -s '.')"
    # OpenRGB: список устройств (без сервера; доступ к i2c — через правила udev пакета)
    if command -v openrgb >/dev/null; then
        if server_up; then openrgb_devs="$(timeout 10 openrgb --client 127.0.0.1:6742 --list-devices 2>/dev/null | grep -E '^[0-9]+: ' | sed -E 's/^[0-9]+: //')"
        else openrgb_devs="$(timeout 40 openrgb --noautoconnect --list-devices 2>/dev/null | grep -E '^[0-9]+: ' | sed -E 's/^[0-9]+: //')"; fi
        mkdir -p "$(dirname "$CACHE_DEVS")"; printf '%s\n' "$openrgb_devs" | sed '/^$/d' > "$CACHE_DEVS"
    fi
    [[ -f "$STATE" ]] && saved="$(cat "$STATE")"
    jq -n --arg vendor "$(vendor)" --arg product "$(cat "$DMI/product_name" 2>/dev/null)" --argjson laptop "$(is_laptop && echo true || echo false)" \
          --argjson leds "$led_json" --argjson rec "$rec" --arg devs "$openrgb_devs" --argjson saved "$saved" \
          --argjson i2c "$(lsmod 2>/dev/null | grep -q '^i2c_dev' && echo true || echo false)" \
          --argjson rule "$([[ -f "$UDEV_RULE" ]] && echo true || echo false)" \
          --argjson running "$([[ -f "$RUN/effect.pid" ]] && kill -0 "$(cat "$RUN/effect.pid")" 2>/dev/null && echo true || echo false)" \
          --argjson server "$(server_up && echo true || echo false)" '
        { vendor: ($vendor | rtrimstr(" ")), product: $product, laptop: $laptop, leds: $leds, drivers: $rec,
          openrgb: ($devs | split("\n") | map(select(. != ""))), i2c: $i2c, rule: $rule, saved: $saved, effectRunning: $running, server: $server }'
}

cmd_install() {
    local pkgs=() p
    while IFS='|' read -r p _; do pacman -Q "$p" >/dev/null 2>&1 || pkgs+=("$p"); done < <(recommend)
    echo "==> Драйверы подсветки для: $(vendor)$(is_laptop && echo ' (ноутбук)' || echo ' (ПК)')"
    if (( ${#pkgs[@]} )); then
        if command -v yay >/dev/null; then yay -S --needed "${pkgs[@]}"; else sudo pacman -S --needed "${pkgs[@]}"; fi
    else
        echo "  -> всё уже установлено"
    fi
    # OpenRGB: доступ к SMBus (память, плата) — модуль i2c-dev при загрузке
    if pacman -Q openrgb >/dev/null 2>&1; then
        echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null && sudo modprobe i2c-dev
        echo "  -> модуль i2c-dev включён"
    fi
    # клавиатура ноутбука: цвет и яркость без sudo
    if [[ -n "$(leds)" ]]; then
        sudo tee "$UDEV_RULE" >/dev/null <<'RULE'
# glassrice: подсветка клавиатуры доступна без sudo (rgb.sh, окно «Программы» → «Подсветка»)
ACTION=="add|change", SUBSYSTEM=="leds", KERNEL=="*kbd_backlight*", RUN+="/bin/chmod a+w /sys%p/brightness /sys%p/multi_intensity"
RULE
        sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=leds
        echo "  -> правило udev: $UDEV_RULE"
    fi
    echo
    read -rp "Готово. Enter — закрыть окно " _
}

case "${1:-}" in
    status)  cmd_status ;;
    set)     cmd_set "${2:?RRGGBB}" "${3:-100}" ;;
    off)     stop_effect; cmd_set 000000 0 ;;
    effect)  shift; cmd_effect "$@" ;;
    _loop)   shift; effect_loop "$@" ;;
    restore) cmd_restore ;;
    theme)   cmd_theme "${2:-}" "${3:-}" ;;
    follow)  cmd_follow "${2:-on}" "${3:-}" "${4:-}" ;;
    install) cmd_install ;;
    probe)   cmd_probe ;;
    server)  cmd_server ;;
    _apply)  cmd_apply ;;
    *)       awk 'NR > 1 && !/^#/ { exit } NR > 1' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
