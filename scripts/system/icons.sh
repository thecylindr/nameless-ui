#!/bin/bash
# Темы иконок и библиотека значков для NameLess UI (окно «Программы» → «Иконки»).
#
#   icons.sh list                       установленные темы и каталог популярных (пакет, есть ли), текущая тема — JSON
#   icons.sh set <тема>                 тема всей системы: GTK (gsettings, settings.ini), Qt/KDE (kdeglobals, qt5ct/qt6ct),
#                                       NameLess UI (QS_ICON_THEME при запуске — тема читается из ~/.config/glassrice/icon-theme)
#   icons.sh search <тема> <запрос> [N] значки темы по имени (и наследуемых тем) — JSON [{ name, path }], до N (120)
#   icons.sh preview <тема>             несколько значков темы для карточки — JSON [путь…]
#   icons.sh store [страница] [запрос]  каталог gnome-look.org (OCS API, «Full Icon Themes»): сборки людей — имя, автор,
#                                       рейтинг, загрузки, превью, ссылка на страницу (источник) — JSON
#   icons.sh store-install <url> <файл> архив сборки с gnome-look → ~/.local/share/icons; печатает найденные темы (JSON)
#
# Установка тем — пакетами через pkg.sh (run install search:<пакет>), окно вызывает его само

set -uo pipefail
STATE="$HOME/.config/glassrice/icon-theme"
DIRS=("$HOME/.local/share/icons" "$HOME/.icons" "/usr/share/icons")

# каталог: «Тема|пакет|описание» — тема ставится пакетом из репозитория или AUR
catalog() {
    cat <<'EOF'
Papirus-Dark|papirus-icon-theme|плоские и цветные, огромный набор приложений
Papirus|papirus-icon-theme|светлый вариант Papirus
Tela-circle-dark|tela-circle-icon-theme-git|круглые значки, много цветов папок
Colloid-dark|colloid-icon-theme-git|мягкие плоские значки в стиле Material
WhiteSur-dark|whitesur-icon-theme|в стиле macOS
Qogir-dark|qogir-icon-theme|аккуратные плоские значки
Fluent-dark|fluent-icon-theme-git|в стиле Windows 11
kora|kora-icon-theme|объёмные с тенью
candy-icons|candy-icons-git|сочные градиенты
BeautyLine|beautyline|неоновые линии с градиентом
Numix-Circle|numix-circle-icon-theme-git|круглые значки Numix
breeze-dark|breeze-icons|значки KDE Plasma
Adwaita|adwaita-icon-theme|значки GNOME
EOF
}

theme_dir() { local d; for d in "${DIRS[@]}"; do [[ -f "$d/$1/index.theme" ]] && { echo "$d/$1"; return 0; }; done; return 1; }
# текущая тема: своя запись → GTK (gsettings, settings.ini) → KDE; без них — первая установленная (раньше пустая строка давала 0 значков)
current() {
    local t=""
    [[ -s "$STATE" ]] && t="$(<"$STATE")"
    [[ -z "$t" ]] && t="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")"
    [[ -z "$t" ]] && t="$(grep -hm1 '^gtk-icon-theme-name=' "$HOME/.config/gtk-3.0/settings.ini" 2>/dev/null | cut -d= -f2)"
    [[ -z "$t" ]] && t="$(sed -n '/^\[Icons\]/,/^\[/s/^Theme=//p' "$HOME/.config/kdeglobals" 2>/dev/null | head -1)"
    [[ -n "$t" ]] && theme_dir "$t" >/dev/null || t="$(installed | head -1)"
    echo "${t:-hicolor}"
}

# установленные темы: есть index.theme и в нём есть каталоги значков (не тема курсора)
installed() {
    local d t
    for d in "${DIRS[@]}"; do
        [[ -d "$d" ]] || continue
        for t in "$d"/*/index.theme; do
            [[ -f "$t" ]] || continue
            grep -q '^Directories=' "$t" || continue
            basename "$(dirname "$t")"
        done
    done | grep -vx hicolor | sort -u
}

# наследуемые темы (Inherits=) — значок ищется и в них
chain() {
    local t="$1" seen="" q=("$1") cur dir inh
    while ((${#q[@]})); do
        cur="${q[0]}"; q=("${q[@]:1}")
        [[ " $seen " == *" $cur "* ]] && continue
        seen="$seen $cur"
        echo "$cur"
        dir="$(theme_dir "$cur")" || continue
        inh="$(grep -m1 '^Inherits=' "$dir/index.theme" | cut -d= -f2 | tr ',' ' ')"
        for t in $inh; do q+=("$t"); done
    done
}

# путь значка: каталоги крупных размеров из index.theme проверяются напрямую (обход всего дерева темы шёл секундами)
icon_path() {
    local name="$1" th dir sub ext
    for th in $(chain "$2") hicolor; do
        dir="$(theme_dir "$th")" || continue
        for sub in $(grep -m1 '^Directories=' "$dir/index.theme" | cut -d= -f2 | tr ',' '\n' | grep -E '(^|/)(48x48|64x64|scalable|48|64)(@2x)?(/|$)' ); do
            for ext in svg png; do [[ -e "$dir/$sub/$name.$ext" ]] && { echo "$dir/$sub/$name.$ext"; return 0; }; done
        done
    done
    return 1
}

cmd_preview() {
    local th="$1" n p out=()
    for n in folder user-home utilities-terminal firefox org.mozilla.firefox system-settings preferences-system org.kde.dolphin telegram org.telegram.desktop \
             text-editor accessories-text-editor steam spotify code visual-studio-code multimedia-video-player vlc gimp applications-games; do
        p="$(icon_path "$n" "$th")" && out+=("$p")
        (( ${#out[@]} >= 8 )) && break
    done
    printf '%s\n' "${out[@]}" | jq -R . | jq -s .
}

cmd_list() {
    local cur inst
    cur="$(current)"
    inst="$(installed)"
    {
        while read -r t; do
            local dir name
            dir="$(theme_dir "$t")"
            name="$(grep -m1 '^Name=' "$dir/index.theme" | cut -d= -f2-)"
            jq -cn --arg id "$t" --arg name "${name:-$t}" --argjson prev "$(cmd_preview "$t")" '{ id: $id, name: $name, installed: true, preview: $prev }'
        done <<<"$inst"
    } | jq -s --arg cur "$cur" --argjson cat "$(catalog | while IFS='|' read -r t p d; do
            jq -cn --arg id "$t" --arg pkg "$p" --arg about "$d" --argjson inst "$(grep -qxF "$t" <<<"$inst" && echo true || echo false)" \
                '{ id: $id, pkg: $pkg, about: $about, installed: $inst }'
        done | jq -s .)" '{ current: $cur, installed: ., catalog: $cat }'
}

cmd_set() {
    local th="$1"
    theme_dir "$th" >/dev/null || { echo "нет темы $th" >&2; exit 1; }
    mkdir -p "$(dirname "$STATE")"
    echo "$th" > "$STATE"
    # GTK 3/4
    gsettings set org.gnome.desktop.interface icon-theme "$th" 2>/dev/null
    local f
    for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
        [[ -f "$f" ]] || continue
        if grep -q '^gtk-icon-theme-name=' "$f"; then sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=$th/" "$f"
        else sed -i "/^\[Settings\]/a gtk-icon-theme-name=$th" "$f"; fi
    done
    # Qt и KDE
    if command -v kwriteconfig6 >/dev/null; then kwriteconfig6 --file kdeglobals --group Icons --key Theme "$th"
    elif [[ -f "$HOME/.config/kdeglobals" ]]; then
        grep -q '^\[Icons\]' "$HOME/.config/kdeglobals" || printf '\n[Icons]\n' >> "$HOME/.config/kdeglobals"
        sed -i "/^\[Icons\]/,/^\[/{s/^Theme=.*/Theme=$th/}" "$HOME/.config/kdeglobals"
        grep -A3 '^\[Icons\]' "$HOME/.config/kdeglobals" | grep -q '^Theme=' || sed -i "/^\[Icons\]/a Theme=$th" "$HOME/.config/kdeglobals"
    fi
    for f in "$HOME/.config/qt5ct/qt5ct.conf" "$HOME/.config/qt6ct/qt6ct.conf"; do
        [[ -f "$f" ]] && sed -i "s/^icon_theme=.*/icon_theme=$th/" "$f"
    done
    echo ok
}

cmd_search() {
    local th="$1" q="${2:-}" n="${3:-120}" t dir
    for t in $(chain "$th") hicolor; do
        dir="$(theme_dir "$t")" || continue
        find -L "$dir" \( -path '*scalable*' -o -path '*48*' \) \( -name '*.svg' -o -name '*.png' \) 2>/dev/null
    done | awk -F/ -v q="${q,,}" '{ f=$NF; sub(/\.(svg|png)$/, "", f); if (q == "" || index(tolower(f), q)) if (!(f in seen)) { seen[f]=1; print f "\t" $0 } }' \
         | head -n "$n" | jq -R 'split("\t") | { name: .[0], path: .[1] }' | jq -s .
}

# каталог gnome-look.org: категория 132 — полные темы иконок; сортировка по скачиваниям, 24 на страницу
cmd_store() {
    local page="${1:-0}" q="${2:-}" raw
    command -v jq >/dev/null || { echo '{"total":0,"items":[],"error":"нет jq — установите пакет jq"}'; return 1; }
    # запрос: сначала как есть, при обрыве — по IPv4 (у части провайдеров IPv6 до gnome-look не доходит, и каталог «не грузился»)
    local args=(-sf -m 20 -G "https://api.gnome-look.org/ocs/v1/content/data"
        --data-urlencode "categories=132" --data-urlencode "sortmode=down" --data-urlencode "pagesize=24"
        --data-urlencode "page=$page" --data-urlencode "search=$q" --data-urlencode "format=json")
    raw="$(curl "${args[@]}" 2>/dev/null)" || raw="$(curl -4 "${args[@]}" 2>/dev/null)" \
        || { echo '{"total":0,"items":[],"error":"нет связи с gnome-look.org"}'; return 0; }
    printf '%s' "$raw" | jq -c '{ total: (.totalitems // 0), items: [ (.data // [])[] | {
            id, name, author: .personid, downloads: (.downloads | tonumber? // 0), score: (.score // 0),
            preview: (.smallpreviewpic1 // .previewpic1 // ""), url: .detailpage, changed: (.changed // "" | .[0:10]),
            summary: (.summary // ""),
            files: [ range(1; 6) as $i | { name: .["downloadname\($i)"], link: .["downloadlink\($i)"], size: .["downloadsize\($i)"] }
                     | select(.link != null and .link != "" and (.name // "" | test("\\.(tar\\.(gz|xz|bz2|zst)|zip|tgz)$"))) ]
        } ] }' 2>/dev/null || echo '{"total":0,"items":[],"error":"нет связи с gnome-look.org"}'
}

# скачать архив сборки и разложить темы (каталоги с index.theme) в ~/.local/share/icons
cmd_store_install() {
    local url="$1" name="${2:-theme.tar.gz}" tmp dest="$HOME/.local/share/icons" found=()
    tmp="$(mktemp -d)"
    trap "rm -rf '$tmp'" EXIT
    # файлы лежат в CDN DigitalOcean: по IPv6 соединение у части провайдеров рвётся — повтор по IPv4
    curl -sL -m 600 -o "$tmp/$name" "$url" || curl -4 -sL -m 600 -o "$tmp/$name" "$url" || { echo '{"ok":false,"error":"не скачалось"}'; return 1; }
    mkdir -p "$tmp/x" "$dest"
    case "$name" in
        *.zip) unzip -q "$tmp/$name" -d "$tmp/x" ;;
        *)     tar -xf "$tmp/$name" -C "$tmp/x" ;;
    esac || { echo '{"ok":false,"error":"архив не распаковался"}'; return 1; }
    local idx d t
    while IFS= read -r idx; do
        d="$(dirname "$idx")"; t="$(basename "$d")"
        grep -q '^Directories=' "$idx" || continue                # тема курсора, а не иконок
        rm -rf "${dest:?}/$t"; cp -a "$d" "$dest/$t" && found+=("$t")
    done < <(find "$tmp/x" -maxdepth 4 -name index.theme)
    # сборка-установщик без готовых тем (install.sh из исходников) — честно говорим
    (( ${#found[@]} )) || { echo '{"ok":false,"error":"в архиве нет готовой темы (только исходники с install.sh)"}'; return 1; }
    printf '%s\n' "${found[@]}" | jq -R . | jq -sc '{ ok: true, themes: . }'
}

case "${1:-}" in
    list)    cmd_list ;;
    store)   cmd_store "${2:-0}" "${3:-}" ;;
    store-install) cmd_store_install "${2:?url}" "${3:-theme.tar.gz}" ;;
    set)     cmd_set "${2:?тема}" ;;
    search)  cmd_search "${2:?тема}" "${3:-}" "${4:-120}" ;;
    preview) cmd_preview "${2:?тема}" ;;
    *)       sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
