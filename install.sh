#!/usr/bin/env bash
# Установка NameLess UI и NameLess Orbit.
#
#   ./install.sh                оболочка: nameless и шторка «Оформление» (ThemeDrawer) → ~/.config/quickshell (прежние — в бэкап)
#   ./install.sh orbit          ТОЛЬКО приложение Orbit (из AUR, из готовой сборки на GitHub или из исходников)
#   ./install.sh all            оболочка и Orbit
#   ./install.sh --deps         то же, что без аргументов, но сначала минимум пакетов из minimal.txt (pacman / AUR через yay)
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

# ---------- NameLess UI: оболочка и шторка ----------
install_shell() {
    head_ "NameLess UI — оболочка и шторка «Оформление»"
    command -v qs >/dev/null || warn "Quickshell (qs) не найден: поставьте пакет quickshell, иначе оболочка не запустится."
    mkdir -p "$DEST"
    local d
    for d in nameless ThemeDrawer; do
        [[ -d "$HERE/$d" ]] || { warn "в $HERE нет папки $d — этот установщик нужно запускать из папки проекта"; FAILED+=("$d"); continue; }
        if [[ -d "$DEST/$d" ]]; then
            mkdir -p "$BACKUP"; mv "$DEST/$d" "$BACKUP/$d"
            say "прежний $d сохранён в $BACKUP"
        fi
        cp -a "$HERE/$d" "$DEST/$d"
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
    # папки — в Dolphin, а не в терминале (xdg-open без этой привязки берёт kitty-open)
    [[ -f /usr/share/applications/org.kde.dolphin.desktop ]] && xdg-mime default org.kde.dolphin.desktop inode/directory 2>/dev/null
}

# распаковка архива Orbit: «самодостаточная» сборка (внутри AppRun и свои библиотеки) — в ~/.local/opt/nameless-orbit со ссылкой в ~/.local/bin;
# обычный архив (usr/bin, usr/share…) — прямо в ~/.local
orbit_unpack() {
    local ar="$1" dst="$HOME/.local/opt/nameless-orbit"
    if tar -tzf "$ar" | grep -q '/AppRun$'; then
        rm -rf "$dst"; mkdir -p "$dst" "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/256x256/apps" || return 1
        tar -xzf "$ar" -C "$dst" --strip-components=1 || return 1
        ln -sf "$dst/nameless-orbit" "$HOME/.local/bin/nameless-orbit"
        cp -f "$dst/share/applications/nameless-orbit.desktop" "$HOME/.local/share/applications/" 2>/dev/null
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
            | jq -r '[.[] | select(.draft == false)][0].assets[]? | select(.name | test("^nameless-orbit-[0-9.]+-linux-x86_64\\.tar\\.gz$")) | .browser_download_url' 2>/dev/null | head -n1)"
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

# ---------- запуск ----------
case "${1:-}" in
    "")          install_shell ;;
    shell)       install_shell ;;
    orbit)       install_orbit ;;
    all)         install_shell; install_orbit ;;
    --deps)      install_deps; install_shell ;;
    --restore)   restore; exit 0 ;;
    -h|--help)   sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           warn "не знаю команды «$1». Доступно: orbit, shell, all, --deps, --restore, --help"; exit 2 ;;
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
