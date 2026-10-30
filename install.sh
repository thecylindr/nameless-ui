#!/usr/bin/env bash
# Установка NameLess UI и NameLess Orbit.
#
#   ./install.sh                оболочка: nameless, шторка «Оформление» (ThemeDrawer) и клавиши → ~/.config/quickshell (прежние — в бэкап)
#   ./install.sh orbit          ТОЛЬКО приложение Orbit (из AUR, из готовой сборки на GitHub или из исходников)
#   ./install.sh all            оболочка и Orbit
#   ./install.sh --deps         то же, что без аргументов, но сначала минимум пакетов из minimal.txt (pacman / AUR через yay)
#   ./install.sh keys           только клавиши NameLess UI (Hyprland, driftwm, справка SUPER+F1) — список в hypr/nameless-keys.txt
#   ./install.sh drivers        только драйверы видеокарты и процессора (scripts/system/driver.sh: подбирает ветку и для старых карт)
#   ./install.sh check          проверка: нужные программы, клавиши, скрипты, отвечает ли оболочка (ничего не меняет)
#   ./install.sh --restore      вернуть самые свежие прежние файлы оболочки
#   ./install.sh --help         эта справка
#
# Для Orbit: ORBIT_REPO=<адрес git> — другой репозиторий; ORBIT_FROM=release|source — пропустить AUR / пропустить и готовую сборку;
# ORBIT_INSECURE=1 — поставить готовую сборку без проверки контрольной суммы (не рекомендуется).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.config/quickshell"
STAMP="$(date +%F_%H-%M-%S)"
BACKUP="$HOME/.config/quickshell-backup-$STAMP"
FAILED=()

say()  { echo -e "\e[1;34m  ->\e[0m $1"; }
warn() { echo -e "\e[1;33m  !!\e[0m $1"; }
head_() { echo -e "\n\e[1;32m==>\e[0m \e[1m$1\e[0m"; }

# пакет: репозиторий — pacman, иначе AUR — yay; ошибка одного пакета не обрывает остальное
need_pkgs() {
    local p
    for p in "$@"; do
        pacman -Q "$p" >/dev/null 2>&1 && continue
        if pacman -Si "$p" >/dev/null 2>&1; then sudo pacman -S --needed --noconfirm "$p" || warn "не получилось поставить «$p» — пропускаю"
        elif command -v yay >/dev/null; then yay -S --needed --noconfirm "$p" || warn "не получилось поставить «$p» из AUR — пропускаю"
        else warn "«$p» есть только в AUR, а yay не найден — поставьте вручную"; fi
    done
}

# программы, без которых часть клавиш и окон молчит: [обязательные | необязательные] «команда:пакет»
RUNTIME_REQ=(qs:quickshell jq:jq python3:python grim:grim slurp:slurp wl-copy:wl-clipboard notify-send:libnotify pgrep:procps-ng timeout:coreutils)
RUNTIME_OPT=(tesseract:tesseract cliphist:cliphist playerctl:playerctl brightnessctl:brightnessctl kitty:kitty swappy:swappy busctl:systemd dbus-monitor:dbus)
check_runtime() {
    local e miss=() opt=()
    for e in "${RUNTIME_REQ[@]}"; do command -v "${e%%:*}" >/dev/null || miss+=("${e##*:}"); done
    for e in "${RUNTIME_OPT[@]}"; do command -v "${e%%:*}" >/dev/null || opt+=("${e##*:}"); done
    command -v hyprctl >/dev/null || [[ -f "$HOME/.config/driftwm/config.toml" ]] || warn "не найден ни Hyprland (hyprctl), ни driftwm — клавиши некуда подключать"
    (( ${#miss[@]} )) && warn "не хватает нужного: ${miss[*]} — ./install.sh --deps поставит минимум (Arch)"
    (( ${#opt[@]} )) && say "не обязательно, но пригодится: ${opt[*]} (нужны для отдельных окон и клавиш: OCR, буфер, плеер, яркость, Orbit)"
    return 0
}

# копия папки оболочки без кэша Python; скрипты и Python-сборщики — исполняемые (иначе ярлыки и клавиши молчат)
copy_dir() {
    cp -a "$1" "$2" || return 1
    find "$2" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
    find "$2" -maxdepth 2 \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} + 2>/dev/null
    return 0
}

# ---------- NameLess UI: оболочка и шторка ----------
install_shell() {
    head_ "NameLess UI — оболочка и шторка «Оформление»"
    check_runtime
    mkdir -p "$DEST"
    local d
    for d in nameless ThemeDrawer; do
        [[ -d "$HERE/$d" ]] || { warn "в $HERE нет папки $d — этот установщик нужно запускать из папки проекта"; FAILED+=("$d"); continue; }
        if [[ -d "$DEST/$d" ]]; then
            mkdir -p "$BACKUP"; mv "$DEST/$d" "$BACKUP/$d"
            say "прежний $d сохранён в $BACKUP"
        fi
        copy_dir "$HERE/$d" "$DEST/$d" || { warn "не удалось скопировать $d в $DEST"; FAILED+=("$d"); continue; }
        say "установлен $d"
    done
    # запуск программ: qs-app.sh (окружение сессии) нужен AppRun.qml; rofi-run.sh — фокус на уже открытое окно (Incy, Telegram…) при запуске из rofi
    mkdir -p "$HOME/.config/hypr/Scripts"
    cp -af "$HERE/scripts/qs-app.sh" "$HERE/scripts/rofi-run.sh" "$HOME/.config/hypr/Scripts/"
    chmod +x "$HOME/.config/hypr/Scripts/qs-app.sh" "$HOME/.config/hypr/Scripts/rofi-run.sh"
    if [[ -f "$HOME/.config/rofi/config.rasi" ]] && ! grep -q "rofi-run.sh" "$HOME/.config/rofi/config.rasi"; then
        cp -a "$HOME/.config/rofi/config.rasi" "$HOME/.config/rofi/config.rasi.bak"
        sed -i '0,/^\( *\)terminal:.*$/s||&\n  run-command:         "sh -c '"'"'r=\\"$HOME/.config/hypr/Scripts/rofi-run.sh\\"; if [ -x \\"$r\\" ]; then exec \\"$r\\" \\"$@\\"; else exec \\"$@\\"; fi'"'"' _ {cmd}";|' "$HOME/.config/rofi/config.rasi"
        say "rofi: добавлен запуск через rofi-run.sh (копия прежнего конфига — config.rasi.bak)"
    fi
    # системные скрипты окон NameLess UI (иконки и каталог gnome-look, подсветка, питание, видеокарта, драйверы) — в ~/.local/share/nameless:
    # оттуда их берут «Программы», «Функции» и диспетчер задач; без них вкладка «Иконки» падала с кодом 127
    mkdir -p "$HOME/.local/share/nameless/scripts/system"
    cp -af "$HERE"/scripts/system/*.sh "$HOME/.local/share/nameless/scripts/system/" && chmod +x "$HOME/.local/share/nameless/scripts/system/"*.sh
    say "системные скрипты — в ~/.local/share/nameless/scripts/system"
    # папки — в Dolphin, а не в терминале (xdg-open без этой привязки берёт kitty-open)
    [[ -f /usr/share/applications/org.kde.dolphin.desktop ]] && xdg-mime default org.kde.dolphin.desktop inode/directory 2>/dev/null
}

# распаковка архива Orbit: «самодостаточная» сборка (внутри AppRun и свои библиотеки) — в ~/.local/opt/nameless-orbit со ссылкой в ~/.local/bin;
# обычный архив (usr/bin, usr/share…) — прямо в ~/.local
orbit_unpack() {
    local ar="$1" dst="$HOME/.local/opt/nameless-orbit"
    local list; list="$(tar -tzf "$ar" 2>/dev/null)"      # не конвейером в grep -q: при pipefail он закрывает канал раньше tar и условие ложно
    if grep -q '/AppRun$' <<<"$list"; then
        # остатки прежней неудачной установки (архив был распакован прямо в ~/.local): AppRun, скрипт запуска, qt.conf и библиотеки сборки
        if [[ -e "$HOME/.local/AppRun" ]]; then
            local f; while read -r f; do [[ -n "$f" ]] && rm -f "$HOME/.local/lib/$f"; done < <(grep -oE '/lib/[^/]+$' <<<"$list" | sed 's#^/lib/##')
            rm -rf "$HOME/.local/AppRun" "$HOME/.local/nameless-orbit" "$HOME/.local/bin/qt.conf" "$HOME/.local/lib/qt6" "$HOME/.local/lib/fallback"
        fi
        rm -f "$HOME/.local/bin/nameless-orbit"
        rm -rf "$dst"; mkdir -p "$dst" "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/256x256/apps" || return 1
        tar -xzf "$ar" -C "$dst" --strip-components=1 || return 1
        ln -sf "$dst/nameless-orbit" "$HOME/.local/bin/nameless-orbit"
        # в ярлыке — полный путь: у rofi и оболочки, запущенных из сессии, ~/.local/bin может не быть в PATH
        sed "s|^Exec=.*|Exec=$HOME/.local/bin/nameless-orbit|; s|^TryExec=.*||" "$dst/share/applications/nameless-orbit.desktop" > "$HOME/.local/share/applications/nameless-orbit.desktop" 2>/dev/null
        command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
        cp -f "$dst/share/icons/hicolor/256x256/apps/nameless-orbit.png" "$HOME/.local/share/icons/hicolor/256x256/apps/" 2>/dev/null
        return 0
    fi
    mkdir -p "$HOME/.local" && tar -xzf "$ar" -C "$HOME/.local" --strip-components=1
}

# готовая сборка собрана на свежем Arch (Qt 6.12, ffmpeg 8): на не обновлённой системе не хватает библиотек — тогда нужна сборка из исходников
orbit_bin_ok() {
    [[ -x "$HOME/.local/opt/nameless-orbit/AppRun" ]] && return 0      # самодостаточная сборка: свои библиотеки, система не важна
    local missing; missing="$(ldd "$HOME/.local/bin/nameless-orbit" 2>&1 | grep -E "not found" | sed 's/^[[:space:]]*//' | head -n5)"
    [[ -z "$missing" ]] && return 0
    warn "готовая сборка не подходит этой системе (нет библиотек):"; echo "$missing" | sed 's/^/        /'
    return 1
}

# ---------- NameLess Orbit ----------
# Порядок: пакет из AUR → готовая сборка из релиза GitHub (в ~/.local, без компиляции, с проверкой суммы) → сборка из исходников
install_orbit() {
    head_ "NameLess Orbit — связь телефона и компьютера"
    local repo="${ORBIT_REPO:-https://github.com/thecylindr/nameless-orbit.git}"
    local slug; slug="$(sed -E 's#^https://github.com/##; s#\.git$##' <<<"$repo")"      # thecylindr/nameless-orbit

    # 0. уже стоит пакетом
    if pacman -Q nameless-orbit-bin >/dev/null 2>&1 || pacman -Q nameless-orbit-git >/dev/null 2>&1; then
        say "Orbit уже установлен пакетом — обновляется командой: yay -Syu"
        return
    fi
    # 1. пакет из AUR (если опубликован)
    if [[ "${ORBIT_FROM:-}" != release && "${ORBIT_FROM:-}" != source ]] && command -v yay >/dev/null; then
        local aur
        for aur in nameless-orbit-bin nameless-orbit-git; do
            if yay -Si "$aur" >/dev/null 2>&1; then
                yay -S --needed --noconfirm "$aur" && return
                warn "не получилось поставить $aur — пробую другой способ"
            fi
        done
    fi
    # 2. готовая сборка из релиза GitHub (подходит Arch; нужны только системные библиотеки)
    if [[ "${ORBIT_FROM:-}" != source ]]; then
        need_pkgs qt6-base qt6-declarative qt6-multimedia qt6-svg qt6-wayland ffmpeg wf-recorder libpulse jq curl
        say "ищу последнюю готовую сборку Orbit на GitHub ($slug)"
        local url tmp sums want got
        url="$(curl -fsSL "https://api.github.com/repos/$slug/releases" 2>/dev/null \
            | jq -r '[[.[] | select(.draft == false)][0].assets[]? | select(.name | test("^nameless-orbit-[0-9.]+-(bundle-)?linux-x86_64\\.tar\\.gz$"))] | sort_by(.name | contains("bundle") | not) | .[0].browser_download_url // empty' 2>/dev/null | head -n1)"
        if [[ -n "$url" ]]; then
            tmp="$(mktemp -d)"
            say "скачиваю: ${url##*/}"
            if curl -fL --progress-bar -o "$tmp/orbit.tar.gz" "$url"; then
                # проверка: сумма из SHA256SUMS релиза должна совпасть; подпись — если она есть и в gpg есть ключ автора
                sums="$(curl -fsSL "${url%/*}/SHA256SUMS" 2>/dev/null || true)"
                if [[ -n "$sums" ]]; then
                    if curl -fsSL -o "$tmp/SHA256SUMS" "${url%/*}/SHA256SUMS" && curl -fsSL -o "$tmp/SHA256SUMS.asc" "${url%/*}/SHA256SUMS.asc" 2>/dev/null && command -v gpg >/dev/null; then
                        if gpg --verify "$tmp/SHA256SUMS.asc" "$tmp/SHA256SUMS" >/dev/null 2>&1; then say "подпись SHA256SUMS проверена"
                        else warn "подпись SHA256SUMS не подтверждена (нет ключа автора в gpg?) — проверяется только контрольная сумма"; fi
                    fi
                    want="$(awk -v f="${url##*/}" '$2 == f || $2 == "*"f {print $1; exit}' <<<"$sums")"
                    got="$(sha256sum "$tmp/orbit.tar.gz" | awk '{print $1}')"
                    if [[ -z "$want" || "$want" != "$got" ]]; then
                        warn "контрольная сумма НЕ совпала — файл не установлен (ожидалась ${want:-—}, получена $got)"
                        rm -rf "$tmp"; FAILED+=("orbit"); return
                    fi
                    say "контрольная сумма совпала"
                elif [[ "${ORBIT_INSECURE:-0}" != 1 ]]; then
                    warn "в релизе нет файла SHA256SUMS — проверить скачанное нечем. Чтобы всё же поставить: ORBIT_INSECURE=1 ./install.sh orbit"
                    rm -rf "$tmp"; FAILED+=("orbit"); return
                fi
                if orbit_unpack "$tmp/orbit.tar.gz"; then
                    rm -rf "$tmp"
                    if orbit_bin_ok; then
                        say "Orbit установлен в ~/.local (запуск: nameless-orbit). Если команда не находится — добавьте ~/.local/bin в PATH."
                        say "обновить: запустите ./install.sh orbit ещё раз"
                        return
                    fi
                    rm -f "$HOME/.local/bin/nameless-orbit"
                    warn "собираю Orbit из исходников под вашу систему"
                    tmp=""
                fi
            fi
            rm -rf "$tmp"
            warn "не удалось скачать или распаковать готовую сборку — собираю из исходников"
        else
            warn "готовых сборок на GitHub не нашлось (нет интернета или релиз ещё не выпущен) — собираю из исходников"
        fi
    fi
    # 3. сборка из исходников в ~/.local/src/nameless-orbit
    need_pkgs git cmake ninja qt6-base qt6-declarative qt6-multimedia qt6-svg qt6-wayland qt6-tools ffmpeg wf-recorder libpulse
    local src="$HOME/.local/src/nameless-orbit"
    if [[ -d "$src/.git" ]]; then git -C "$src" pull --ff-only || { warn "не удалось обновить исходники Orbit в $src"; FAILED+=("orbit"); return; }
    else mkdir -p "$(dirname "$src")" && git clone "$repo" "$src" || { warn "не удалось скачать Orbit с $repo"; FAILED+=("orbit"); return; }; fi
    say "собираю Orbit — это займёт несколько минут"
    cmake -S "$src" -B "$src/build/release" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOME/.local" >/dev/null \
        && cmake --build "$src/build/release" && cmake --install "$src/build/release" >/dev/null \
        && say "Orbit собран и установлен в ~/.local (запуск: nameless-orbit)" \
        || { warn "Orbit не собрался — подробности выше; исходники остались в $src"; FAILED+=("orbit"); }
}

install_deps() {
    [[ -f "$HERE/minimal.txt" ]] || { warn "нет $HERE/minimal.txt"; return; }
    local pk=()
    mapfile -t pk < <(grep -vE '^\s*(#|$)' "$HERE/minimal.txt")
    head_ "Минимум пакетов для NameLess UI"
    say "ставлю: ${pk[*]}"
    need_pkgs "${pk[@]}"
}

restore() {
    local last d
    last="$(ls -1d "$HOME"/.config/quickshell-backup-* 2>/dev/null | sort | tail -n1)"
    [[ -n "$last" ]] || { echo "Бэкапов не нашлось — возвращать нечего."; exit 1; }
    for d in nameless ThemeDrawer; do
        [[ -d "$last/$d" ]] || continue
        rm -rf "${DEST:?}/$d"; cp -a "$last/$d" "$DEST/$d"
        say "вернул $d из $last"
    done
}

# ---------- драйверы видеокарты и процессора ----------
# настройщик и списки пакетов кладутся в ~/.local/share/nameless: оттуда их берёт и NameLess UI (вопрос при первом запуске, «Программы» → «Драйверы»)
install_drivers() {
    local share="$HOME/.local/share/nameless"
    mkdir -p "$share/scripts/system" "$share/packages"
    cp -af "$HERE/scripts/system/driver.sh" "$share/scripts/system/" && chmod +x "$share/scripts/system/driver.sh"
    cp -af "$HERE"/packages/drivers*.txt "$share/packages/"
    local st n
    st="$("$share/scripts/system/driver.sh" --status 2>/dev/null)"
    n="$(jq -r '.missing // 0' <<<"$st" 2>/dev/null)"
    head_ "Драйверы видеокарты и процессора"
    if [[ "${n:-0}" == 0 && "${1:-}" != force ]]; then say "всё нужное уже стоит"; return; fi
    jq -r '.gpus[] | "  \(.vendor): \(.name) — \(.note)"' <<<"$st" 2>/dev/null
    local ans=y
    [[ "${1:-}" == force || ! -t 0 ]] || read -rp "  Поставить недостающие драйверы? [Y/n] " ans
    [[ -z "$ans" || "$ans" =~ ^[YyДд] ]] || { say "пропущено — потом: ./install.sh drivers или «Программы» → «Драйверы»"; return; }
    "$share/scripts/system/driver.sh" || FAILED+=("drivers")
}

# ---------- клавиши NameLess UI ----------
# Один список — hypr/nameless-keys.txt; из него собираются привязки под то, что стоит:
#   Hyprland с Lua-конфигом — ~/.config/hypr/nameless-binds.lua, подключается в конце hyprland.lua (сочетание сначала снимается,
#     прежняя привязка не срабатывает вместе с новой);
#   Hyprland с hyprland.conf — ~/.config/hypr/nameless-binds.conf (unbind + bind), подключается строкой source;
#   driftwm — строки в разделе [keybindings]; сочетание со встроенным действием driftwm (навигация, масштаб) не трогается и выводится списком;
#   справка SUPER+F1 — ~/.config/hypr/keybinds.txt, если её ещё нет (у полной сборки она своя).
# Действия — scripts/nameless-action.sh (с полной сборкой уходят в theme.sh, без неё — прямо в NameLess UI). Конфиги — с копией *.nameless-bak
install_keys() {
    head_ "Клавиши NameLess UI"
    local list="$HERE/hypr/nameless-keys.txt" hypr="$HOME/.config/hypr" act="$HOME/.config/hypr/Scripts/nameless-action.sh"
    [[ -f "$list" ]] || { warn "нет $list — клавиши пропущены"; FAILED+=("keys"); return; }
    mkdir -p "$hypr/Scripts"
    cp -af "$HERE/scripts/nameless-action.sh" "$HERE/scripts/ocr.sh" "$hypr/Scripts/" && chmod +x "$hypr/Scripts/nameless-action.sh" "$hypr/Scripts/ocr.sh"
    local rows; rows="$(grep -v '^#' "$list" | grep -v '^[[:space:]]*$')"
    # строка без пяти полей или с неизвестным действием не должна ломать остальные привязки; одно сочетание дважды — берётся первое
    local ok="" mods key action sec what seen="|" line
    while IFS= read -r line; do
        IFS='|' read -r mods key action sec what <<<"$line"
        if [[ -z "$mods" || -z "$key" || -z "$action" || -z "$what" ]]; then warn "клавиши: строка пропущена (нужно 5 полей через |): $line"; continue; fi
        if ! grep -qE "^[[:space:]]+(.*\|)?$action(\)|\|)" "$HERE/scripts/nameless-action.sh"; then warn "клавиши: у $mods+$key нет действия «$action» в nameless-action.sh — пропущено"; continue; fi
        [[ "$seen" == *"|$mods+$key|"* ]] && { warn "клавиши: $mods+$key повторяется — вторая строка пропущена"; continue; }
        seen+="$mods+$key|"; ok+="$line"$'\n'
    done <<<"$rows"
    rows="${ok%$'\n'}"

    # Hyprland
    if [[ -f "$hypr/hyprland.lua" ]]; then
        {
            echo "-- Клавиши NameLess UI: собрано install.sh из hypr/nameless-keys.txt — файл перезаписывается при установке"
            echo "local act = os.getenv(\"HOME\") .. \"/.config/hypr/Scripts/nameless-action.sh \""
            while IFS='|' read -r mods key action _ _; do
                local k="$key"; [[ "$mods" != "-" ]] && k="${mods//+/ + } + $key"
                echo "pcall(hl.unbind, \"$k\"); hl.bind(\"$k\", hl.dsp.exec_cmd(act .. \"$action\"))"
            done <<<"$rows"
        } > "$hypr/nameless-binds.lua"
        local inc='pcall(function() dofile(os.getenv("HOME") .. "/.config/hypr/nameless-binds.lua") end)'
        if ! grep -qF "nameless-binds.lua" "$hypr/hyprland.lua"; then
            cp -a "$hypr/hyprland.lua" "$hypr/hyprland.lua.nameless-bak"
            printf '\n-- клавиши NameLess UI (install.sh); свои привязки — ниже этой строки\n%s\n' "$inc" >> "$hypr/hyprland.lua"
            say "Hyprland: клавиши подключены в конце hyprland.lua (копия — hyprland.lua.nameless-bak)"
        else say "Hyprland: клавиши обновлены (nameless-binds.lua)"; fi
    elif [[ -f "$hypr/hyprland.conf" ]]; then
        {
            echo "# Клавиши NameLess UI: собрано install.sh из hypr/nameless-keys.txt — файл перезаписывается при установке"
            while IFS='|' read -r mods key action _ _; do
                local m=""; [[ "$mods" != "-" ]] && m="${mods//+/ }"
                echo "unbind = $m, $key"
                echo "bind = $m, $key, exec, $act $action"
            done <<<"$rows"
        } > "$hypr/nameless-binds.conf"
        # оболочка стартует вместе с сессией, если конфиг её ещё не запускает (клавиши и без этого поднимают её по требованию)
        if ! grep -qE "(qs|quickshell)[^#]* -c nameless|theme\.sh" "$hypr/hyprland.conf"; then
            echo "exec-once = sh -c 'qs -c nameless ipc show >/dev/null 2>&1 || exec qs -c nameless'" >> "$hypr/nameless-binds.conf"
        fi
        if ! grep -qF "nameless-binds.conf" "$hypr/hyprland.conf"; then
            cp -a "$hypr/hyprland.conf" "$hypr/hyprland.conf.nameless-bak"
            printf '\n# клавиши NameLess UI (install.sh)\nsource = %s\n' "$hypr/nameless-binds.conf" >> "$hypr/hyprland.conf"
            say "Hyprland: клавиши подключены в hyprland.conf (копия — hyprland.conf.nameless-bak)"
        else say "Hyprland: клавиши обновлены (nameless-binds.conf)"; fi
    fi
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && hyprctl reload >/dev/null 2>&1

    # driftwm
    local dw="$HOME/.config/driftwm/config.toml"
    if [[ -f "$dw" ]] && grep -q '^\[keybindings\]' "$dw"; then
        [[ -f "$dw.nameless-bak" ]] || cp -a "$dw" "$dw.nameless-bak"      # копия — только исходного конфига, повторная установка её не затирает
        local busy=() added=0
        while IFS='|' read -r mods key action _ what; do
            local k; k="$(tr '[:upper:]' '[:lower:]' <<<"$key")"
            [[ "$mods" != "-" ]] && k="$(tr '[:upper:]' '[:lower:]' <<<"${mods/SUPER/mod}")+$k"
            local line="\"$k\" = \"exec $act $action\""
            if grep -q "^\"$k\"[[:space:]]*=" "$dw"; then
                # встроенное действие driftwm (навигация, масштаб) не заменяется; запуск программы (exec: swaylock, grim, прежний NameLess) — заменяется
                if grep -q "^\"$k\"[[:space:]]*=[[:space:]]*\"exec " "$dw"; then sed -i "s|^\"$k\"[[:space:]]*=.*|$line|" "$dw"
                else busy+=("$k ($what)"); fi
            else
                sed -i "/^\[keybindings\]/a $line" "$dw"; added=$((added + 1))
            fi
        done <<<"$rows"
        say "driftwm: добавлено клавиш — $added (копия — config.toml.nameless-bak)"
        (( ${#busy[@]} )) && warn "driftwm: заняты своими действиями, не тронуты — ${busy[*]}"
    fi

    # справка SUPER+F1
    if [[ ! -f "$hypr/keybinds.txt" ]]; then
        {
            echo "# Справочник клавиш: «раздел|клавиша|действие». Показывается по SUPER+F1 (NameLess UI)"
            while IFS='|' read -r mods key _ sec what; do
                local k="$key"; [[ "$key" == period ]] && k="."; [[ "$key" == Escape ]] && k="Esc"
                [[ "$mods" != "-" ]] && k="${mods//+/ + } + $k"
                echo "$sec|$k|$what"
            done <<<"$rows"
        } > "$hypr/keybinds.txt"
        say "справка клавиш — ~/.config/hypr/keybinds.txt"
    fi
}

# ---------- проверка без изменений ----------
cmd_check() {
    head_ "Проверка NameLess UI"
    local hypr="$HOME/.config/hypr" f bad=0
    check_runtime
    for f in "$DEST/nameless/shell.qml" "$DEST/nameless/ipc.sh" "$DEST/nameless/taskmon.py" "$hypr/Scripts/nameless-action.sh" "$hypr/Scripts/ocr.sh" "$hypr/Scripts/qs-app.sh"; do
        [[ -e "$f" ]] || { warn "нет файла: $f"; bad=1; continue; }
        [[ "$f" == *.qml ]] || [[ -x "$f" ]] || { warn "не исполняемый: $f (chmod +x)"; bad=1; }
    done
    if [[ -f "$hypr/hyprland.lua" ]]; then
        [[ -f "$hypr/nameless-binds.lua" ]] && grep -qF nameless-binds.lua "$hypr/hyprland.lua" && say "клавиши подключены (hyprland.lua)" || { warn "клавиши не подключены: ./install.sh keys"; bad=1; }
    elif [[ -f "$hypr/hyprland.conf" ]]; then
        [[ -f "$hypr/nameless-binds.conf" ]] && grep -qF nameless-binds.conf "$hypr/hyprland.conf" && say "клавиши подключены (hyprland.conf)" || { warn "клавиши не подключены: ./install.sh keys"; bad=1; }
    fi
    if command -v qs >/dev/null && timeout 3 qs -c nameless ipc show >/dev/null 2>&1; then say "оболочка отвечает"
    else warn "оболочка не отвечает (не запущена? qs -c nameless) — клавиши поднимут её сами"; fi
    (( bad )) && FAILED+=("check")
}

# ---------- запуск ----------
case "${1:-}" in
    "")          install_shell; install_keys; install_drivers ;;
    shell)       install_shell; install_keys ;;
    keys)        install_keys ;;
    orbit)       install_orbit ;;
    all)         install_shell; install_keys; install_orbit; install_drivers ;;
    --deps)      install_deps; install_shell; install_keys; install_drivers ;;
    drivers)     install_drivers force ;;
    check)       cmd_check ;;
    --restore)   restore; exit 0 ;;
    -h|--help)   sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           warn "не знаю команды «$1». Доступно: orbit, shell, keys, all, drivers, check, --deps, --restore, --help"; exit 2 ;;
esac

echo
if [[ ${#FAILED[@]} -gt 0 ]]; then
    warn "не получилось: ${FAILED[*]} (причина — в выводе выше)"
else
    say "готово"
fi
case "${1:-}" in
    ""|shell|all|--deps)
        echo "Запуск: qs -c nameless &   (оболочка)   и   qs -c ThemeDrawer &   (шторка «Оформление»)"
        echo "При первом запуске оболочка предложит выбрать язык (русский / English)." ;;
esac
case "${1:-}" in
    orbit|all) echo "Orbit: запуск командой nameless-orbit; на телефоне — приложение Orbit (APK из Releases)." ;;
esac
