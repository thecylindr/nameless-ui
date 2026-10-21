#!/bin/bash
# Обои из интернета для мастера «Обои» NameLess UI: бесплатные источники без ключей, один вид ответа.
#
#   wallnet.sh search <источник> "<запрос>" <страница>      → JSON: [{ id, thumb, full, title, res, author, license, source, page, desc, open }]
#   wallnet.sh get <адрес> <папка> [имя] [название] [автор] [лицензия] [страница]   → скачивает, печатает путь; запись об авторе — в CREDITS.tsv
#   источники с открытыми лицензиями (open: true):
#     commons — Wikimedia Commons (избранные фото и поиск; CC и общественное достояние, автор и лицензия у каждого файла)
#     nasa    — NASA Images (космос; общественное достояние)
#     artic   — Чикагский институт искусств (картины в общественном достоянии, CC0)
#     cleveland — музей Кливленда (открытый доступ, CC0)
#   прочие:   wallhaven_anime — Wallhaven, аниме; bingworld — картинки дня Bing других стран; wallhaven — Wallhaven (поиск), bing — картинки дня Bing, picsum — фото Unsplash (свободная лицензия Unsplash)
#
# Запрос и страница нужны Wallhaven; у Bing страница — глубина архива (8 картинок на страницу, до 2 недель),
# у picsum — набор случайных фото. Таймауты короткие: мастер не должен висеть без сети

set -uo pipefail
UA="glassrice-nameless/1.0 (https://github.com/thecylindr)"
RCF="$(mktemp)"; trap 'rm -f "$RCF"' EXIT
# код возврата curl сохраняется: если источник молчит, мастер должен отличить таймаут от «нет сети» и «ошибка сервера»
# -4: через VPN-туннель IPv6 к Wikimedia обрывается уже после соединения (TLS), и curl не переходит на IPv4 — источник выглядел «недоступным», хотя по IPv4 отвечает
get() { curl -4 -sfL --connect-timeout 8 --max-time 18 -A "$UA" "$@"; local rc=$?; echo "$rc" > "$RCF"; return $rc; }
enc() { jq -rn --arg s "$1" '$s | @uri'; }

do_search() {
    case "$src" in
    wallhaven|wallhaven_anime)
        # categories=100 — «general», 010 — «anime» — только «general», purity=100 — только безопасное; широкие экраны от Full HD
        sort="relevance"; [[ -z "$q" ]] && sort="toplist"
        cats=100; [[ "$src" == wallhaven_anime ]] && cats=010
        get "https://wallhaven.cc/api/v1/search?q=$(enc "$q")&categories=$cats&purity=100&sorting=$sort&atleast=1920x1080&ratios=16x9,16x10,21x9&page=$page" \
            | jq -c --arg c "$cats" '[ .data[]? | { id: .id, thumb: .thumbs.large, full: .path, title: ("Обои Wallhaven " + .id), res: .resolution, author: "загрузил пользователь Wallhaven",
                                    license: "лицензия — на странице работы (обычно личное использование)", source: (if $c == "010" then "Wallhaven: аниме" else "Wallhaven" end), page: .url,
                                    desc: ("Просмотров: " + (.views | tostring) + " · в избранном: " + (.favorites | tostring)), open: false } ]'
        ;;
    bing)
        idx=$(( (page - 1) * 8 ))
        get "https://www.bing.com/HPImageArchive.aspx?format=js&idx=$idx&n=8&mkt=ru-RU" \
            | jq -c '[ .images[]? | { id: .hsh, thumb: ("https://www.bing.com" + .urlbase + "_400x240.jpg"), full: ("https://www.bing.com" + .urlbase + "_UHD.jpg"),
                                      title: ((.copyright // .title) | split(" (")[0]), res: "3840×2160",
                                      author: ((.copyright // "") | capture("©\\s*(?<a>[^)]*)")? | .a // "Bing"), license: "© Microsoft Bing, для личного использования",
                                      source: "Bing: картинка дня", page: .copyrightlink, desc: (.title // ""), open: false } ]'
        ;;
    picsum)
        # фото Unsplash через Lorem Picsum: список с авторами
        get "https://picsum.photos/v2/list?page=$page&limit=12" \
            | jq -c '[ .[]? | select(.width >= 1920) | { id: ("picsum-" + .id), thumb: ("https://picsum.photos/id/" + .id + "/400/240"), full: ("https://picsum.photos/id/" + .id + "/2560/1440"),
                                  title: ("Фото " + .id), res: "\(.width)×\(.height)", author: .author, license: "Unsplash License (свободное использование)",
                                  source: "Unsplash через Lorem Picsum", page: .url, desc: "", open: false } ]'
        ;;
    bingworld)
        # картинки дня Bing других стран: страница = страна (8 картинок на страницу, 8 стран)
        mkts=(en-US ja-JP de-DE fr-FR pt-BR en-GB en-AU zh-CN); mkt="${mkts[$(( (page - 1) % 8 ))]}"
        get "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=$mkt" \
            | jq -c --arg m "$mkt" '[ .images[]? | { id: (.hsh + $m), thumb: ("https://www.bing.com" + .urlbase + "_400x240.jpg"), full: ("https://www.bing.com" + .urlbase + "_UHD.jpg"),
                                      title: ((.copyright // .title) | split(" (")[0]), res: "3840×2160",
                                      author: ((.copyright // "") | capture("©\\s*(?<a>[^)]*)")? | .a // "Bing"), license: "© Microsoft Bing, для личного использования",
                                      source: ("Bing: " + $m), page: .copyrightlink, desc: (.title // ""), open: false } ]'
        ;;
    cleveland)
        # музей Кливленда, открытый доступ (CC0): крупные изображения
        get "https://openaccess-api.clevelandart.org/api/artworks/?q=$(enc "${q:-landscape}")&has_image=1&cc0=1&limit=24&skip=$(( (page - 1) * 24 ))" \
            | jq -c '[ .data[]? | select(.images.print.url != null) | { id: (.id | tostring), thumb: .images.web.url, full: .images.print.url,
                    title: .title, res: "до 3400 px", author: ((.creators[0].description // "неизвестен")), license: "CC0 — общественное достояние",
                    source: "Cleveland Museum of Art", page: .url, desc: ((.description // .technique // "") | gsub("<[^>]*>"; "") | .[0:220]), open: true } ]'
        ;;
    commons)
        # без запроса — избранные фото Commons (поиск по категории), с запросом — обычный поиск по изображениям; листаются смещением
        [[ -z "$q" ]] && sq="incategory:Featured_pictures_on_Wikimedia_Commons filemime:image/jpeg" || sq="$q filemime:image/jpeg"
        gen="generator=search&gsrnamespace=6&gsrsearch=$(enc "$sq")&gsrlimit=40&gsroffset=$(( (page - 1) * 40 ))"
        get "https://commons.wikimedia.org/w/api.php?action=query&format=json&$gen&prop=imageinfo&iiprop=url|size|extmetadata&iiurlwidth=400" \
            | jq -c "[ (.query.pages // {}) | to_entries[].value | select(.imageinfo[0].width >= 1920 and .imageinfo[0].width > .imageinfo[0].height)
                | .imageinfo[0] as \$i | (\$i.extmetadata // {}) as \$m
                | { id: (.pageid | tostring), thumb: \$i.thumburl, full: (if \$i.width > 3840 then (\$i.thumburl | sub(\"/[0-9]+px-\"; \"/3840px-\")) else \$i.url end),
                    title: (.title | sub(\"^File:\"; \"\") | sub(\"\\\\.[A-Za-z]+\$\"; \"\")), res: \"\(\$i.width)×\(\$i.height)\",
                    author: ((\$m.Artist.value // \"неизвестен\") | $strip), license: (\$m.LicenseShortName.value // \"см. страницу файла\"),
                    source: \"Wikimedia Commons\", page: \$i.descriptionurl, desc: ((\$m.ImageDescription.value // \"\") | $strip | .[0:220]), open: true } ] | sort_by(.title)"
        ;;
    nasa)
        # космос NASA: без запроса — туманности; оригинал и «large» — по шаблону адреса миниатюры
        [[ -z "$q" ]] && q="nebula galaxy"
        get "https://images-api.nasa.gov/search?q=$(enc "$q")&media_type=image&page=$page&page_size=24" \
            | jq -c '[ .collection.items[]? | select(.links[0].href != null) | .data[0] as $d | .links[0].href as $t
                | { id: $d.nasa_id, thumb: $t, full: ($t | sub("~thumb\\."; "~large.")), title: $d.title, res: "до 2048 px",
                    author: ($d.photographer // $d.secondary_creator // $d.center // "NASA"), license: "Общественное достояние (NASA)",
                    source: "NASA Images", page: ("https://images.nasa.gov/details/" + $d.nasa_id), desc: (($d.description // "") | gsub("<[^>]*>"; "") | .[0:220]), open: true } ]'
        ;;
    artic)
        # картины в общественном достоянии (CC0): полная картинка — через IIIF; только широкие
        get "https://api.artic.edu/api/v1/artworks/search?q=$(enc "${q:-landscape}")&query%5Bterm%5D%5Bis_public_domain%5D=true&fields=id,title,artist_display,image_id,date_display,thumbnail&limit=40&page=$page" \
            | jq -c '[ .data[]? | select(.image_id != null and (.thumbnail.width // 0) > (.thumbnail.height // 1)) | .image_id as $im
                | { id: (.id | tostring), thumb: ("https://www.artic.edu/iiif/2/" + $im + "/full/400,/0/default.jpg"), full: ("https://www.artic.edu/iiif/2/" + $im + "/full/1686,/0/default.jpg"),
                    title: (.title + (if .date_display then ", " + .date_display else "" end)), res: "1686 px", author: ((.artist_display // "неизвестен") | gsub("\\n"; ", ")),
                    license: "CC0 — общественное достояние", source: "Art Institute of Chicago", page: ("https://www.artic.edu/artworks/" + (.id | tostring)),
                    desc: "Произведение из коллекции Чикагского института искусств", open: true } ]'
        ;;
    *) echo "[]"; exit 2 ;;
    esac
}

cmd="${1:-}"
# HTML из полей Wikimedia (имя автора приходит со ссылками) → обычный текст
strip='gsub("<[^>]*>"; "") | gsub("&amp;"; "&") | gsub("&quot;"; "\"") | gsub("\\s+"; " ") | gsub("^ | $"; "")'
case "$cmd" in
search)
    src="${2:-wallhaven}" q="${3:-}" page="${4:-1}"
    [[ "$page" =~ ^[0-9]+$ ]] || page=1
    out="$(do_search)"
    if [[ -z "$out" ]]; then
        case "$(cat "$RCF" 2>/dev/null)" in
            28) echo "{\"error\":\"timeout\",\"src\":\"$src\"}" ;;
            6|7|35|52|56) echo "{\"error\":\"offline\",\"src\":\"$src\"}" ;;
            22) echo "{\"error\":\"server\",\"src\":\"$src\"}" ;;
            0|"") echo "[]" ;;
            *) echo "{\"error\":\"failed\",\"src\":\"$src\"}" ;;
        esac
    else
        echo "$out"
    fi
    ;;
get)
    url="${2:-}" dir="${3:-$HOME/wallpapers/everyday}" name="${4:-}" title="${5:-}" author="${6:-}" lic="${7:-}" page="${8:-}"
    [[ "$url" =~ ^https:// ]] || { echo "нужен адрес https://" >&2; exit 2; }
    dir="${dir/#\~/$HOME}"; mkdir -p "$dir"
    # имя: из адреса, только безопасные знаки; расширение — по содержимому
    [[ -n "$name" ]] || name="$(basename "${url%%\?*}")"
    name="$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_' | sed 's/^_*//' | cut -c1-80)"
    tmp="$(mktemp "$dir/.dl-XXXXXX")" || exit 1
    # NASA: «large» есть не у всех снимков — тогда пробуем оригинал
    if ! curl -4 -sfL --max-time 120 -A "$UA" -o "$tmp" "$url"; then
        if [[ "$url" == *"~large."* ]] && curl -4 -sfL --max-time 120 -A "$UA" -o "$tmp" "${url/~large./~orig.}"; then :; else rm -f "$tmp"; echo "не удалось скачать" >&2; exit 1; fi
    fi
    case "$(file -b --mime-type "$tmp")" in
        image/jpeg) ext=jpg ;;
        image/png)  ext=png ;;
        image/webp) ext=webp ;;
        *) rm -f "$tmp"; echo "это не картинка" >&2; exit 1 ;;
    esac
    name="${name%.*}"; out="$dir/$name.$ext"
    [[ -e "$out" ]] && out="$dir/$name-$(date +%s).$ext"
    mv "$tmp" "$out"
    # кто автор и откуда: запись в ~/wallpapers/CREDITS.tsv (файл, название, автор, лицензия, страница)
    if [[ -n "$title$author$lic$page" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\n' "$(basename "$out")" "$title" "$author" "$lic" "$page" | tr -d '\r' >> "$HOME/wallpapers/CREDITS.tsv"
    fi
    echo "$out"
    ;;
*)
    echo "использование: wallnet.sh search <commons|nasa|artic|wallhaven|bing|picsum> \"запрос\" [страница] | get <адрес> <папка> [имя] [название] [автор] [лицензия] [страница]" >&2
    exit 2 ;;
esac
