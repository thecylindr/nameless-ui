#!/usr/bin/env python3
"""Расход токенов Claude Code по журналам сессий (~/.claude/projects/**/*.jsonl): сегодня, неделя, по дням, моделям и проектам.

  claude_stats.py   →  одна строка JSON со сводкой

Журналы большие (сотни мегабайт), поэтому разбор инкрементальный: для каждого файла хранится смещение, и при следующем запуске
читается только дописанное; старше 9 дней и файлы, не менявшиеся 9 дней, не читаются. Сводка — по часам (UTC), дни считаются по местному времени.
Токены: вход (input), выход (output), запись кеша (cache_creation); чтение кеша (cache_read) считается отдельно — оно дёшево и квоту почти не расходует."""
import glob, json, os, re, time
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", HOME + "/.cache"), "glassrice")
SF = os.path.join(CACHE, "claude-stats.json")
KEEP = 9 * 86400


def short(model):
    m = (model or "").lower()
    for k in ("opus", "sonnet", "haiku", "fable"):
        if k in m:
            return k
    return model or "?"


def parse_ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except (ValueError, AttributeError):
        return 0


def main():
    try:
        st = json.load(open(SF))
    except (OSError, ValueError):
        st = {"files": {}, "b": {}}
    files, b = st["files"], st["b"]
    now = time.time()
    for path in glob.glob(HOME + "/.claude/projects/*/*.jsonl"):
        try:
            sz, mt = os.path.getsize(path), os.path.getmtime(path)
        except OSError:
            continue
        if now - mt > KEEP:
            continue
        off = files.get(path, 0)
        if sz < off:
            off = 0
        if sz == off:
            continue
        home = "-" + os.path.expanduser("~").strip("/").replace("/", "-")      # папка проектов Claude Code называется по пути: /home/имя → -home-имя
        proj = os.path.basename(os.path.dirname(path)).replace(home + "-", "").replace(home, "~").lstrip("-") or "~"
        try:
            with open(path, "rb") as f:
                f.seek(off)
                chunk = f.read()
        except OSError:
            continue
        # неполная последняя строка дочитается в следующий раз
        end = chunk.rfind(b"\n")
        if end < 0:
            continue
        for ln in chunk[:end].split(b"\n"):
            if b'"usage"' not in ln or b'"type":"assistant"' not in ln:
                continue
            try:
                d = json.loads(ln)
            except ValueError:
                continue
            u = (d.get("message") or {}).get("usage")
            ts = parse_ts(d.get("timestamp", ""))
            if not u or not ts or now - ts > KEEP:
                continue
            key = "%d|%s|%s" % (int(ts // 3600), short((d.get("message") or {}).get("model")), proj)
            v = b.setdefault(key, [0, 0, 0, 0, 0])
            v[0] += u.get("input_tokens", 0) or 0
            v[1] += u.get("output_tokens", 0) or 0
            v[2] += u.get("cache_creation_input_tokens", 0) or 0
            v[3] += u.get("cache_read_input_tokens", 0) or 0
            v[4] += 1
        files[path] = off + end + 1
    # старые часы и файлы убираем
    for k in [k for k in b if now - int(k.split("|")[0]) * 3600 > KEEP]:
        del b[k]
    for p in [p for p in files if not os.path.exists(p)]:
        del files[p]
    try:
        os.makedirs(CACHE, exist_ok=True)
        json.dump(st, open(SF + ".tmp", "w"))
        os.replace(SF + ".tmp", SF)
    except OSError:
        pass

    # сводка
    tz_off = datetime.now().astimezone().utcoffset().total_seconds()
    today = datetime.fromtimestamp(now).strftime("%Y-%m-%d")
    days, models, projs = {}, {}, {}
    block = [0, 0, 0, 0, 0]
    tot = lambda v: v[0] + v[1] + v[2]
    for k, v in b.items():
        h, model, proj = k.split("|", 2)
        t = int(h) * 3600
        day = datetime.fromtimestamp(t + 1800).strftime("%Y-%m-%d")
        if now - t <= 7 * 86400:
            d = days.setdefault(day, {"date": day, "tokens": 0, "msgs": 0, "models": {}})
            d["tokens"] += tot(v); d["msgs"] += v[4]
            d["models"][model] = d["models"].get(model, 0) + tot(v)
            models[model] = models.get(model, 0) + tot(v)
            projs[proj] = projs.get(proj, 0) + tot(v)
        if now - t <= 5 * 3600:
            for i in range(5):
                block[i] += v[i]
    ordered = []
    for i in range(6, -1, -1):
        dd = datetime.fromtimestamp(now - i * 86400).strftime("%Y-%m-%d")
        ordered.append(days.get(dd, {"date": dd, "tokens": 0, "msgs": 0, "models": {}}))
    td = days.get(today, {"tokens": 0, "msgs": 0})
    print(json.dumps({"today": {"tokens": td["tokens"], "msgs": td["msgs"]}, "week": {"tokens": sum(d["tokens"] for d in ordered), "msgs": sum(d["msgs"] for d in ordered)},
                      "block5h": {"in": block[0], "out": block[1], "cacheNew": block[2], "cacheRead": block[3], "msgs": block[4], "tokens": block[0] + block[1] + block[2]},
                      "days": ordered, "models": sorted(models.items(), key=lambda x: -x[1]), "projects": sorted(projs.items(), key=lambda x: -x[1])[:6], "t": round(now)},
                     ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
