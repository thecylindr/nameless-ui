#!/usr/bin/env python3
"""Лимиты Claude Code для мониторов (AgentsData.qml): окно 5 часов и неделя, в процентах, со временем сброса и прогнозом.

  usage.py [--force]    →  одна строка JSON: {"ok", "five": {"util", "resets"}, "seven": {...}, "sonnet", "opus", "plan", "eta", "age", "err"}

Данные — тот же запрос, что выполняет команда /usage: GET api.anthropic.com/api/oauth/usage с токеном самого Claude Code
(~/.claude/.credentials.json; токен только читается, нигде не сохраняется и не печатается, в аргументы процесса не попадает).
Токен НЕ обновляется (обновление могло бы разлогинить Claude Code): истёк — «откройте Claude Code». Ответ кешируется на 100 секунд,
чтобы несколько мониторов не делали лишних запросов; история замеров — для прогноза «лимит исчерпается через…»."""
import json, os, subprocess, sys, time
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", HOME + "/.cache"), "glassrice")
CF, HF = os.path.join(CACHE, "claude-usage.json"), os.path.join(CACHE, "claude-usage-hist.json")
TTL = 100


def load(p, d):
    try:
        return json.load(open(p))
    except (OSError, ValueError):
        return d


def save(p, v):
    try:
        os.makedirs(CACHE, exist_ok=True)
        tmp = p + ".tmp"
        json.dump(v, open(tmp, "w"))
        os.replace(tmp, p)
    except OSError:
        pass


def iso_to_ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except (ValueError, AttributeError):
        return 0


def fetch():
    cred = load(HOME + "/.claude/.credentials.json", {}).get("claudeAiOauth") or {}
    tok = cred.get("accessToken")
    if not tok:
        return None, "no_credentials", cred
    if (cred.get("expiresAt") or 0) / 1000 < time.time() + 5:
        return None, "expired", cred
    # токен — через stdin (curl -K -): не виден в списке процессов. Только IPv4: до Anthropic IPv6 из некоторых сетей не доходит
    conf = f'url = "https://api.anthropic.com/api/oauth/usage"\nheader = "Authorization: Bearer {tok}"\nheader = "anthropic-beta: oauth-2025-04-20"\nheader = "User-Agent: glassrice-nameless/1.0"\n'
    for _ in range(2):
        try:
            r = subprocess.run(["curl", "-4", "-sS", "-m", "12", "-K", "-", "-w", "\n%{http_code}"], input=conf, capture_output=True, text=True, timeout=16)
        except (OSError, subprocess.SubprocessError):
            return None, "offline", cred
        body, _, code = r.stdout.rpartition("\n")
        if code == "200":
            try:
                return json.loads(body), "", cred
            except ValueError:
                return None, "failed", cred
        if code in ("401", "403"):
            return None, "auth", cred
        if code == "429":
            return None, "rate", cred
        if r.returncode == 28:
            err = "timeout"
        else:
            err = "offline" if r.returncode else "failed"
    return None, err, cred


def forecast(hist, util, resets):
    """Через сколько секунд окно 5 часов исчерпается при темпе последних 40 минут (None — не успеет до сброса или не растёт)."""
    now = time.time()
    pts = [(t, a) for t, a, _ in hist if now - t < 2400 and t < resets]
    if len(pts) < 2 or util >= 100:
        return None
    t0, a0 = pts[0]
    dt = now - t0
    rate = (util - a0) / dt if dt > 120 else 0
    if rate <= 0:
        return None
    eta = (100 - util) / rate
    return int(eta) if now + eta < resets else None


def main():
    force = "--force" in sys.argv
    c = load(CF, {})
    age = time.time() - c.get("ts", 0)
    data, err = c.get("data"), ""
    if force or age > TTL or not data:
        d, err, cred = fetch()
        if d:
            data = d
            c = {"ts": time.time(), "data": d, "plan": cred.get("subscriptionType", "")}
            save(CF, c)
            hist = load(HF, [])
            f, s = (d.get("five_hour") or {}), (d.get("seven_day") or {})
            if not hist or time.time() - hist[-1][0] > 60:
                hist.append([round(time.time()), f.get("utilization") or 0, s.get("utilization") or 0])
                save(HF, hist[-240:])
            age = 0
        elif not data:
            print(json.dumps({"ok": False, "err": err}))
            return
        else:
            age = time.time() - c.get("ts", 0)        # старые данные остаются, ошибка — рядом
    f, s = data.get("five_hour") or {}, data.get("seven_day") or {}
    util5, res5 = f.get("utilization") or 0, iso_to_ts(f.get("resets_at"))
    hist = load(HF, [])
    sub = lambda k: ({"util": (data.get(k) or {}).get("utilization"), "resets": iso_to_ts((data.get(k) or {}).get("resets_at"))} if data.get(k) else None)
    print(json.dumps({"ok": True, "err": err, "age": round(age), "plan": c.get("plan", ""),
                      "five": {"util": util5, "resets": res5}, "seven": {"util": s.get("utilization") or 0, "resets": iso_to_ts(s.get("resets_at"))},
                      "sonnet": sub("seven_day_sonnet"), "opus": sub("seven_day_opus"), "eta": forecast(hist, util5, res5),
                      "hist": [[t, a] for t, a, _ in hist[-60:]]}, separators=(",", ":")))


if __name__ == "__main__":
    main()
