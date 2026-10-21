#!/bin/bash
# Погода для виджета NameLess UI: один вид данных у разных бесплатных сервисов (без ключей).
#
#   weather.sh <источник> <город|""> <C|F> <дней>
#   источники: open-meteo — Open-Meteo (по умолчанию), metno — MET Norway (yr.no), wttr — wttr.in
#   без города — место по IP (ipwho.is)
#
# Ответ — JSON: { place, temp, feels, humidity, wind, icon, desc, days: [{ date, max, min, icon }] }
# icon: clear | partly | cloudy | fog | drizzle | rain | snow | storm

set -uo pipefail
src="${1:-open-meteo}" city="${2:-}" units="${3:-C}" days="${4:-3}"
UA="glassrice-nameless/1.0 (https://github.com/thecylindr)"
RCF="$(mktemp)"; trap 'rm -f "$RCF"' EXIT
# код возврата curl сохраняется: виджет различает «таймаут», «нет соединения» и «ошибка сервера» и подсказывает, что делать
get() { curl -sf --connect-timeout 6 --max-time 12 -A "$UA" "$@"; local rc=$?; echo "$rc" > "$RCF"; return $rc; }

# место: по городу — геокодер Open-Meteo, иначе по IP
locate() {
    if [[ -n "$city" ]]; then
        get "https://geocoding-api.open-meteo.com/v1/search?count=1&language=ru&name=$(jq -rn --arg c "$city" '$c | @uri')" \
            | jq -c '.results[0] | select(. != null) | { lat: .latitude, lon: .longitude, place: .name }'
    else
        get "https://ipwho.is/?lang=ru" | jq -c 'select(.success) | { lat: .latitude, lon: .longitude, place: .city }'
    fi
}

run() {
case "$src" in
    wttr)
        get "https://wttr.in/$(jq -rn --arg c "$city" '$c | @uri')?format=j1&lang=ru" | jq -c --arg u "$units" --argjson n "$days" '
            def ic($c): ($c | tonumber) as $x
                | if $x == 113 then "clear" elif $x == 116 then "partly" elif ($x == 119 or $x == 122) then "cloudy"
                  elif ([143, 248, 260] | index($x)) then "fog" elif ([200, 386, 389, 392, 395] | index($x)) then "storm"
                  elif ([179, 182, 185, 227, 230, 317, 320, 323, 326, 329, 332, 335, 338, 350, 362, 365, 368, 371, 374, 377] | index($x)) then "snow"
                  else "rain" end;
            .current_condition[0] as $c
            | { place: (.nearest_area[0].areaName[0].value // ""),
                temp: ((if $u == "F" then $c.temp_F else $c.temp_C end) | tonumber),
                feels: ((if $u == "F" then $c.FeelsLikeF else $c.FeelsLikeC end) | tonumber),
                humidity: ($c.humidity | tonumber), wind: ($c.windspeedKmph | tonumber), icon: ic($c.weatherCode),
                desc: (($c.lang_ru[0].value) // ($c.weatherDesc[0].value) // ""),
                days: [ .weather[:$n][] | { date, max: ((if $u == "F" then .maxtempF else .maxtempC end) | tonumber),
                        min: ((if $u == "F" then .mintempF else .mintempC end) | tonumber), icon: ic(.hourly[4].weatherCode) } ] }'
        ;;
    metno)
        loc="$(locate)" || exit 1; [[ -n "$loc" ]] || exit 1
        lat="$(jq -r '.lat * 10000 | round / 10000' <<<"$loc")" lon="$(jq -r '.lon * 10000 | round / 10000' <<<"$loc")"
        get "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=$lat&lon=$lon" | jq -c --argjson loc "$loc" --arg u "$units" --argjson n "$days" '
            def t($c): if $u == "F" then ($c * 9 / 5 + 32) else $c end | round;
            def ic($s): ($s // "") | if test("thunder") then "storm" elif test("snow|sleet") then "snow" elif test("rain") then (if test("light") then "drizzle" else "rain" end)
                         elif test("fog") then "fog" elif test("partlycloudy|fair") then "partly" elif test("cloudy") then "cloudy" else "clear" end;
            def ru($s): ({ clear: "Ясно", partly: "Переменная облачность", cloudy: "Облачно", fog: "Туман", drizzle: "Морось", rain: "Дождь", snow: "Снег", storm: "Гроза" })[ic($s)];
            .properties.timeseries as $ts | $ts[0] as $c
            | ($c.data.next_1_hours.summary.symbol_code // $c.data.next_6_hours.summary.symbol_code) as $sym
            | { place: $loc.place, temp: t($c.data.instant.details.air_temperature), feels: t($c.data.instant.details.air_temperature),
                humidity: ($c.data.instant.details.relative_humidity | round), wind: ($c.data.instant.details.wind_speed * 3.6 | round),
                icon: ic($sym), desc: ru($sym),
                days: ( $ts | group_by(.time[:10]) | .[:$n] | map({ date: .[0].time[:10],
                        max: t(map(.data.instant.details.air_temperature) | max), min: t(map(.data.instant.details.air_temperature) | min),
                        icon: ic((map(select(.time[11:13] == "12")) + .)[0].data.next_6_hours.summary.symbol_code) }) ) }'
        ;;
    *)
        loc="$(locate)" || exit 1; [[ -n "$loc" ]] || exit 1
        unit=""; [[ "$units" == F ]] && unit="&temperature_unit=fahrenheit"
        get "https://api.open-meteo.com/v1/forecast?latitude=$(jq -r .lat <<<"$loc")&longitude=$(jq -r .lon <<<"$loc")&timezone=auto&forecast_days=$days$unit&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min" \
        | jq -c --argjson loc "$loc" '
            # коды погоды ВМО
            def ic($c): if $c <= 1 then "clear" elif $c == 2 then "partly" elif $c == 3 then "cloudy" elif ($c == 45 or $c == 48) then "fog"
                        elif ($c >= 51 and $c <= 57) then "drizzle" elif (($c >= 61 and $c <= 67) or ($c >= 80 and $c <= 82)) then "rain"
                        elif (($c >= 71 and $c <= 77) or $c == 85 or $c == 86) then "snow" else "storm" end;
            def ru($c): ({ clear: "Ясно", partly: "Переменная облачность", cloudy: "Облачно", fog: "Туман", drizzle: "Морось", rain: "Дождь", snow: "Снег", storm: "Гроза" })[ic($c)];
            .current as $c
            | { place: $loc.place, temp: ($c.temperature_2m | round), feels: ($c.apparent_temperature | round),
                humidity: $c.relative_humidity_2m, wind: ($c.wind_speed_10m | round), icon: ic($c.weather_code), desc: ru($c.weather_code),
                days: [ range(0; .daily.time | length) as $i | { date: .daily.time[$i], max: (.daily.temperature_2m_max[$i] | round | if . == 0 then 0 else . end),
                        min: (.daily.temperature_2m_min[$i] | round | if . == 0 then 0 else . end), icon: ic(.daily.weather_code[$i]) } ] }'
        ;;
esac
}

out="$(run)"
if [[ -n "$out" ]]; then echo "$out"; exit 0; fi
case "$(cat "$RCF" 2>/dev/null)" in
    28) echo '{"error":"timeout"}' ;;
    6|7|35|52|56) echo '{"error":"offline"}' ;;
    22) echo '{"error":"server"}' ;;
    *) echo '{"error":"failed"}' ;;
esac
