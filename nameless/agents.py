#!/usr/bin/env python3
"""Состояние ИИ-помощников для виджета «Помощники» (WAgents.qml): одна строка JSON за запуск.

  agents.py            →  {"agents": [...], "t": секунды}
Claude Code пишет о каждой живой сессии ~/.claude/sessions/<pid>.json (статус busy / idle…, папка, имя, время смены статуса);
последнее сообщение берётся из журнала сессии ~/.claude/projects/<папка>/<сессия>.jsonl (читается только хвост файла).
Codex: процессы codex и codex-desktop; «работает», если процесс заметно грузит процессор между опросами (разность хранится в кэше).
Ничего не меняет и не требует хуков в настройках помощников."""
import glob, json, os, re, subprocess, sys, time

HOME = os.path.expanduser("~")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", HOME + "/.cache"), "glassrice")
STATE = os.path.join(CACHE, "agents-state.json")
CLK = os.sysconf("SC_CLK_TCK")


def alive(pid, name=None):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmd = f.read().decode(errors="replace")
    except OSError:
        return False
    return name is None or name in cmd


def ppid_of(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            s = f.read()
        return int(s[s.rfind(")") + 2:].split()[1])
    except (OSError, ValueError, IndexError):
        return 0


def clients():
    """pid окна → адрес окна Hyprland (чтобы по клику перейти в терминал помощника)."""
    try:
        out = subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True, timeout=2).stdout
        return {c["pid"]: c["address"] for c in json.loads(out)}
    except (OSError, subprocess.SubprocessError, ValueError):
        return {}


def window_of(pid, cl):
    """Поднимаемся по родителям процесса до окна Hyprland (терминал, в котором запущен помощник)."""
    for _ in range(12):
        if pid in cl:
            return cl[pid]
        pid = ppid_of(pid)
        if pid <= 1:
            break
    return ""


def tail_text(path, size=96 * 1024):
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            n = f.tell()
            f.seek(max(0, n - size))
            return f.read().decode(errors="replace").splitlines()
    except OSError:
        return []


def last_messages(cwd, sid, memo):
    """Последние: что спросил пользователь и что ответил помощник. Читается хвост журнала сессии, при необходимости всё глубже
    (длинные результаты инструментов занимают сотни килобайт); результат запоминается, пока файл не вырос."""
    proj = re.sub(r"[/.]", "-", cwd)
    path = f"{HOME}/.claude/projects/{proj}/{sid}.jsonl"
    try:
        size = os.path.getsize(path)
    except OSError:
        return "", ""
    m = memo.get(sid)
    if m and m.get("size") == size:
        return m["last"], m["prompt"]
    ans = prompt = ""
    for depth in (96 * 1024, 768 * 1024, 4 * 1024 * 1024):
        for ln in reversed(tail_text(path, depth)):
            try:
                d = json.loads(ln)
            except ValueError:
                continue
            msg = d.get("message") or {}
            c = msg.get("content")
            if not ans and d.get("type") == "assistant" and isinstance(c, list):
                t = " ".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text").strip()
                if t:
                    ans = t
            if not prompt and d.get("type") == "user" and not d.get("isMeta"):
                t = c if isinstance(c, str) else " ".join(b.get("text", "") for b in (c or []) if isinstance(b, dict) and b.get("type") == "text")
                t = (t or "").strip()
                if t and not t.startswith("<"):
                    prompt = t
            if ans and prompt:
                break
        if ans and prompt:
            break
    one = lambda s, n: re.sub(r"\s+", " ", s)[:n]
    memo[sid] = {"size": size, "last": one(ans, 220), "prompt": one(prompt, 120)}
    return memo[sid]["last"], memo[sid]["prompt"]


def main():
    cl = clients()
    now = time.time()
    agents = []
    try:
        memo = json.load(open(STATE)).get("_msgs", {})
    except (OSError, ValueError):
        memo = {}
    for f in glob.glob(HOME + "/.claude/sessions/*.json"):
        try:
            d = json.load(open(f))
        except (OSError, ValueError):
            continue
        pid = d.get("pid")
        if not pid or not alive(pid, "claude"):
            continue
        cwd = d.get("cwd", HOME)
        last, prompt = last_messages(cwd, d.get("sessionId", ""), memo)
        agents.append({"id": f"claude-{pid}", "kind": "claude", "pid": pid, "name": d.get("name") or "Claude Code", "cwd": cwd,
                       "project": os.path.basename(cwd.rstrip("/")) or "~", "status": d.get("status", "idle"),
                       "since": round((d.get("statusUpdatedAt") or d.get("startedAt") or now * 1000) / 1000), "started": round((d.get("startedAt") or 0) / 1000),
                       "version": d.get("version", ""), "last": last, "prompt": prompt, "addr": window_of(pid, cl)})

    # Codex: процессы; активность — по приросту процессорного времени с прошлого запуска
    try:
        prev = json.load(open(STATE))
    except (OSError, ValueError):
        prev = {}
    cur = {}
    for p in glob.glob("/proc/[0-9]*"):
        pid = int(os.path.basename(p))
        try:
            comm = open(p + "/comm").read().strip()
        except OSError:
            continue
        if comm not in ("codex", "codex-desktop", "Codex"):
            continue
        # дочерние процессы Electron не нужны: берём только главный (родитель не codex-desktop)
        if comm != "codex" and ppid_of(pid) and open(f"/proc/{ppid_of(pid)}/comm").read().strip() == comm:
            continue
        try:
            st = open(p + "/stat").read()
            f = st[st.rfind(")") + 2:].split()
            ticks = int(f[11]) + int(f[12])
            started = int(f[19]) / CLK
            cwd = os.readlink(p + "/cwd")
        except (OSError, ValueError, IndexError):
            continue
        pv = prev.get(str(pid)) if str(pid) != "_msgs" else None
        cur[str(pid)] = {"t": now, "ticks": ticks, "busyAt": (pv or {}).get("busyAt", 0), "idleAt": (pv or {}).get("idleAt", now)}
        busy = False
        if pv and now > pv["t"]:
            busy = (ticks - pv["ticks"]) / CLK / (now - pv["t"]) > 0.06     # заметно грузит процессор — отвечает или работает
        if busy:
            cur[str(pid)]["busyAt"] = now
        elif pv and pv.get("busyAt", 0) and now - pv["busyAt"] < 6:          # короткие паузы внутри работы не считаются простоем
            busy = True
        if busy != bool(pv and pv.get("busy")):
            cur[str(pid)]["changed"] = now
        else:
            cur[str(pid)]["changed"] = (pv or {}).get("changed", now)
        cur[str(pid)]["busy"] = busy
        boot = float(open("/proc/uptime").read().split()[0])
        agents.append({"id": f"codex-{pid}", "kind": "codex", "pid": pid, "name": "Codex" if comm != "codex" else "Codex CLI", "cwd": cwd,
                       "project": os.path.basename(cwd.rstrip("/")) or "~", "status": "busy" if busy else "idle", "since": round(cur[str(pid)]["changed"]),
                       "started": round(now - (boot - started)), "version": "", "last": "", "prompt": "", "addr": window_of(pid, cl)})
    try:
        os.makedirs(CACHE, exist_ok=True)
        cur["_msgs"] = memo
        json.dump(cur, open(STATE, "w"))
    except OSError:
        pass
    agents.sort(key=lambda a: (a["kind"], a["project"]))
    print(json.dumps({"agents": agents, "t": round(now)}, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
