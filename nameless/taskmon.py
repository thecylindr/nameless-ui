#!/usr/bin/env python3
"""Сборщик данных для диспетчера задач NameLess UI (TaskManager.qml).

Резидентный: раз в интервал печатает одну строку JSON и работает, пока его читают (QML запускает его при
открытии окна и останавливает при закрытии). Только стандартная библиотека; всё — из /proc и /sys.

  taskmon.py [интервал_с]

Первая строка — {"hello": {...}} со сведениями о железе, дальше — измерения:
  cpu    загрузка и частота по потокам (P / E-ядра), температура, режим питания
  mem    память и подкачка
  gpus   NVIDIA (nvidia-smi, только пока карта не спит — спящую не будим), Intel и AMD (sysfs, fdinfo)
  disk   чтение и запись, занятость;  net — приём и передача физических интерфейсов, пакеты в секунду, ошибки;  bat — питание
  conns  соединения: процесс, протокол, откуда и куда (с именем узла и службой), скорость каждого, состояние (из ss)
  procs  процессы: загрузка (100 % = одно ядро), память, потоки, видеокарта
Дорогие операции кешируются: имя и владелец процесса читаются один раз, процессы с видеокартой ищутся раз в 10 тактов.
"""
import ipaddress, json, os, pwd, re, socket, subprocess, sys, threading, time

TICK = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0
CLK = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")
UID = os.getuid()
NCPU = os.cpu_count() or 1


def rd(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def rint(path, default=0):
    try:
        return int(rd(path))
    except ValueError:
        return default


# ---------- сведения о железе (один раз) ----------
def lspci_names():
    """PCI-адрес → название видеокарты."""
    out = {}
    try:
        txt = subprocess.run(["lspci", "-mm"], capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return out
    for line in txt.splitlines():
        m = re.match(r'(\S+) "([^"]*(?:VGA|3D|Display)[^"]*)" "([^"]*)" "([^"]*)"', line)
        if m:
            out["0000:" + m.group(1)] = (m.group(3).replace("Corporation", "").strip(), m.group(4))
    return out


def gpu_devices():
    """Видеокарты из /sys/class/drm: [{card, slot, vendor, name}]."""
    names = lspci_names()
    found, seen = [], set()
    for card in sorted(os.listdir("/sys/class/drm")):
        if not re.fullmatch(r"card\d+", card):
            continue
        dev = os.path.realpath(f"/sys/class/drm/{card}/device")
        slot = os.path.basename(dev)
        if slot in seen:
            continue
        seen.add(slot)
        v = rd(f"{dev}/vendor")
        vendor = {"0x10de": "nvidia", "0x8086": "intel", "0x1002": "amd"}.get(v, "other")
        vend, model = names.get(slot, ("", ""))
        found.append({"card": card, "dev": dev, "slot": slot, "vendor": vendor,
                      "name": (model or vend or vendor.upper()), "maker": vend})
    return found


GPUS = gpu_devices()
NVSMI = any(g["vendor"] == "nvidia" for g in GPUS) and subprocess.run(["sh", "-c", "command -v nvidia-smi"], capture_output=True).returncode == 0


def cpu_static():
    model, l3 = "", ""
    for line in rd("/proc/cpuinfo").splitlines():
        if line.startswith("model name") and not model:
            model = line.split(":", 1)[1].strip()
    for idx in range(4, -1, -1):
        if rd(f"/sys/devices/system/cpu/cpu0/cache/index{idx}/level") == "3":
            l3 = rd(f"/sys/devices/system/cpu/cpu0/cache/index{idx}/size")
            break
    sib = set()
    for i in range(NCPU):
        sib.add(rd(f"/sys/devices/system/cpu/cpu{i}/topology/thread_siblings_list"))
    maxf = [rint(f"/sys/devices/system/cpu/cpu{i}/cpufreq/cpuinfo_max_freq") for i in range(NCPU)]
    top = max(maxf) if maxf else 0
    return {"model": re.sub(r"\s+", " ", re.sub(r"\((R|TM)\)", "", model)), "threads": NCPU, "cores": len(sib) or NCPU,
            "maxMhz": top // 1000, "baseMhz": rint("/sys/devices/system/cpu/cpu0/cpufreq/base_frequency") // 1000, "l3": l3,
            "kinds": ["P" if f >= top * 0.9 else "E" for f in maxf]}


STATIC = cpu_static()


def find_hwmon(names):
    base = "/sys/class/hwmon"
    for h in sorted(os.listdir(base)):
        if rd(f"{base}/{h}/name") in names:
            return f"{base}/{h}"
    return ""


CPU_HWMON = find_hwmon(("coretemp", "k10temp", "zenpower"))


def cpu_temp():
    if not CPU_HWMON:
        return None
    best = None
    for f in os.listdir(CPU_HWMON):
        if f.startswith("temp") and f.endswith("_label") and rd(f"{CPU_HWMON}/{f}") in ("Package id 0", "Tctl", "Tdie"):
            best = rint(f"{CPU_HWMON}/{f[:-6]}_input") / 1000
    if best is None:
        vals = [rint(f"{CPU_HWMON}/{f}") for f in os.listdir(CPU_HWMON) if re.fullmatch(r"temp\d+_input", f)]
        best = max(vals) / 1000 if vals else None
    return best


# ---------- процессор ----------
prev_stat = {}


def read_cpu():
    """Загрузка по потокам из /proc/stat: доля занятого времени между двумя чтениями."""
    cores, total = [None] * NCPU, 0.0
    for line in rd("/proc/stat").splitlines():
        if not line.startswith("cpu"):
            continue
        parts = line.split()
        name = parts[0]
        v = list(map(int, parts[1:9]))
        idle, tot = v[3] + v[4], sum(v)
        p = prev_stat.get(name)
        prev_stat[name] = (idle, tot)
        pct = 0.0
        if p and tot > p[1]:
            pct = 100.0 * (1 - (idle - p[0]) / (tot - p[1]))
        if name == "cpu":
            total = pct
        else:
            i = int(name[3:])
            if i < NCPU:
                cores[i] = pct
    out = []
    for i in range(NCPU):
        out.append({"pct": round(cores[i] or 0, 1), "mhz": rint(f"/sys/devices/system/cpu/cpu{i}/cpufreq/scaling_cur_freq") // 1000,
                    "kind": STATIC["kinds"][i]})
    return round(total, 1), out


def read_mem():
    m = {}
    for line in rd("/proc/meminfo").splitlines():
        k, _, v = line.partition(":")
        m[k] = int(v.split()[0]) * 1024 if v.split() else 0
    total, avail = m.get("MemTotal", 0), m.get("MemAvailable", 0)
    return {"total": total, "used": total - avail, "avail": avail, "cached": m.get("Cached", 0) + m.get("SReclaimable", 0),
            "buffers": m.get("Buffers", 0), "swapTotal": m.get("SwapTotal", 0), "swapUsed": m.get("SwapTotal", 0) - m.get("SwapFree", 0)}


# ---------- диск, сеть, батарея ----------
prev_disk, prev_net = {}, {}
DISK_RE = re.compile(r"(nvme\d+n\d+|sd[a-z]+|vd[a-z]+|xvd[a-z]+|mmcblk\d+)")


def read_disk(dt):
    rd_b = wr_b = 0
    busy = 0.0
    for line in rd("/proc/diskstats").splitlines():
        f = line.split()
        if len(f) < 14 or not DISK_RE.fullmatch(f[2]):
            continue
        cur = (int(f[5]), int(f[9]), int(f[12]))
        p = prev_disk.get(f[2])
        prev_disk[f[2]] = cur
        if p and dt > 0:
            rd_b += (cur[0] - p[0]) * 512 / dt
            wr_b += (cur[1] - p[1]) * 512 / dt
            busy = max(busy, min(100.0, (cur[2] - p[2]) / (dt * 10)))
    return {"read": round(rd_b), "write": round(wr_b), "busy": round(busy, 1)}


def read_net(dt):
    rx = tx = 0
    rxp = txp = errs = drops = 0.0
    iface = ""
    for line in rd("/proc/net/dev").splitlines()[2:]:
        name, _, rest = line.partition(":")
        name = name.strip()
        # только физические интерфейсы: у виртуальных (VPN, docker, veth) нет /sys/class/net/<имя>/device
        if name == "lo" or not os.path.exists(f"/sys/class/net/{name}/device"):
            continue
        f = rest.split()
        cur = (int(f[0]), int(f[8]), int(f[1]), int(f[9]), int(f[2]) + int(f[10]), int(f[3]) + int(f[11]))
        p = prev_net.get(name)
        prev_net[name] = cur
        if p and dt > 0:
            rx += (cur[0] - p[0]) / dt
            tx += (cur[1] - p[1]) / dt
            rxp += (cur[2] - p[2]) / dt
            txp += (cur[3] - p[3]) / dt
            errs += (cur[4] - p[4]) / dt
            drops += (cur[5] - p[5]) / dt
        if cur[0] + cur[1] > 0 and not iface:
            iface = name
    return {"rx": round(rx), "tx": round(tx), "iface": iface, "rxp": round(rxp), "txp": round(txp), "errs": round(errs, 1), "drops": round(drops, 1)}


# ---------- соединения ----------
prev_conn = {}
names = {}           # адрес → имя узла ("" — не нашли); обратный DNS идёт в потоках, не задерживая такт
pending = set()


def _resolve(ip):
    try:
        names[ip] = socket.gethostbyaddr(ip)[0]
    except (OSError, UnicodeError):
        names[ip] = ""
    pending.discard(ip)


def host_of(ip):
    if ip in names:
        return names[ip]
    if ip not in pending and len(pending) < 6:
        pending.add(ip)
        threading.Thread(target=_resolve, args=(ip,), daemon=True).start()
    return ""


def split_addr(a):
    """«адрес%интерфейс:порт» → (адрес, порт); IPv6 в скобках."""
    a = re.sub(r"%[^:\]]+", "", a)
    if a.startswith("["):
        h, _, port = a[1:].partition("]:")
        return h, port
    h, _, port = a.rpartition(":")
    return h, port


def ip_class(ip):
    try:
        o = ipaddress.ip_address(ip)
    except ValueError:
        return "wan"
    if o.is_loopback:
        return "lo"
    if o.is_private or o.is_link_local:
        return "lan"
    return "wan"


def service(port, proto):
    try:
        return socket.getservbyport(int(port), "udp" if proto == "udp" else "tcp")
    except (OSError, ValueError, OverflowError):
        return ""


def read_conns(dt):
    """Соединения из ss: у TCP есть счётчики байт (bytes_sent / bytes_received) — по их разности считается скорость каждого.
    Процесс виден только у своих сокетов (без root); остальные — без имени."""
    try:
        out = subprocess.run(["ss", "-H", "-ntup", "-i"], capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    rows, cur = [], None
    for line in out.splitlines():
        if not line.strip():
            continue
        if line[0] not in " \t":
            f = line.split(None, 6)
            if len(f) < 6:
                cur = None
                continue
            lh, lp = split_addr(f[4])
            rh, rp = split_addr(f[5])
            m = re.search(r'\(\("([^"]*)",pid=(\d+)', f[6]) if len(f) > 6 else None
            cur = {"p": f[0], "st": f[1], "l": lh + ":" + lp, "r": rh + ":" + rp, "rh": rh, "rp": rp, "pid": int(m.group(2)) if m else 0,
                   "name": m.group(1) if m else "", "rxb": 0, "txb": 0}
            rows.append(cur)
        elif cur is not None:
            mr = re.search(r"bytes_received:(\d+)", line)
            ms = re.search(r"bytes_sent:(\d+)", line)
            if mr: cur["rxb"] = int(mr.group(1))
            if ms: cur["txb"] = int(ms.group(1))
    seen, res = set(), []
    for c in rows:
        key = (c["p"], c["l"], c["r"])
        seen.add(key)
        prev = prev_conn.get(key)
        prev_conn[key] = (c["rxb"], c["txb"])
        down = up = 0
        if prev and dt > 0:
            down = max(0, (c["rxb"] - prev[0]) / dt)
            up = max(0, (c["txb"] - prev[1]) / dt)
        kind = ip_class(c["rh"])
        host = host_of(c["rh"]) if kind == "wan" else ""
        res.append({"p": c["p"], "st": c["st"], "l": c["l"], "r": c["r"], "host": host, "svc": service(c["rp"], c["p"]), "pid": c["pid"], "name": c["name"],
                    "down": round(down), "up": round(up), "rx": c["rxb"], "tx": c["txb"], "k": kind})
    for key in [k for k in prev_conn if k not in seen]:
        del prev_conn[key]
    res.sort(key=lambda x: -(x["down"] + x["up"]) if (x["down"] + x["up"]) else 0)
    return res[:200]


def read_bat():
    base = "/sys/class/power_supply"
    for n in sorted(os.listdir(base)):
        if rd(f"{base}/{n}/type") != "Battery":
            continue
        p = rint(f"{base}/{n}/power_now")
        if not p:
            p = rint(f"{base}/{n}/current_now") * rint(f"{base}/{n}/voltage_now") // 1000000
        return {"pct": rint(f"{base}/{n}/capacity"), "status": rd(f"{base}/{n}/status"), "watts": round(p / 1e6, 1)}
    return None


# ---------- процессы ----------
prev_ticks = {}      # pid → (старт, тики)
info_cache = {}      # (pid, старт) → {name, cmd, user, uid}
drm_fds = {}         # pid → [номера дескрипторов видеокарты]
prev_drm = {}        # (pid, client) → {engine: нс}
user_names = {}


def uname(uid):
    if uid not in user_names:
        try:
            user_names[uid] = pwd.getpwuid(uid).pw_name
        except KeyError:
            user_names[uid] = str(uid)
    return user_names[uid]


def proc_info(pid, start, comm):
    key = (pid, start)
    c = info_cache.get(key)
    if c:
        return c
    try:
        uid = os.stat(f"/proc/{pid}").st_uid
    except OSError:
        uid = -1
    cmd = rd(f"/proc/{pid}/cmdline").replace("\0", " ").strip()
    name = comm
    # comm обрезан до 15 знаков: полное имя берётся из командной строки
    if len(comm) >= 15 and cmd:
        name = os.path.basename(cmd.split(" ")[0]) or comm
    c = {"name": name, "cmd": cmd[:240], "user": uname(uid), "uid": uid}
    info_cache[key] = c
    return c


def scan_drm(pids_own):
    """Какие дескрипторы процессов — видеокарты (по ссылке на /dev/dri)."""
    drm_fds.clear()
    for pid in pids_own:
        try:
            fds = []
            for fd in os.listdir(f"/proc/{pid}/fd"):
                try:
                    if os.readlink(f"/proc/{pid}/fd/{fd}").startswith("/dev/dri/"):
                        fds.append(fd)
                except OSError:
                    pass
            if fds:
                drm_fds[pid] = fds
        except OSError:
            pass


def read_drm(dt):
    """Занятость движков по fdinfo процессов (i915, xe, amdgpu): {pid: {vendor: {3d, video}}} и сумма по производителю."""
    per, tot = {}, {}
    dt_ns = dt * 1e9
    for pid, fds in list(drm_fds.items()):
        seen = set()
        for fd in fds:
            txt = rd(f"/proc/{pid}/fdinfo/{fd}")
            if "drm-driver" not in txt:
                continue
            d = {}
            for line in txt.splitlines():
                k, _, v = line.partition(":")
                d[k] = v.strip()
            drv, cid = d.get("drm-driver", ""), d.get("drm-client-id", fd)
            if (drv, cid) in seen:
                continue
            seen.add((drv, cid))
            vendor = {"i915": "intel", "xe": "intel", "amdgpu": "amd"}.get(drv, drv)
            eng = {"3d": 0, "video": 0}
            for k, v in d.items():
                if k.startswith("drm-engine-") and v.endswith("ns"):
                    n = k[11:]
                    ns = int(v.split()[0])
                    kind = "3d" if n in ("render", "gfx", "compute") else ("video" if n in ("video", "video-enhance", "dec", "enc", "decode", "encode", "vcn_dec", "vcn_enc") else "")
                    if kind:
                        eng[kind] += ns
            key = (pid, drv, cid)
            p = prev_drm.get(key)
            prev_drm[key] = eng
            if p and dt_ns > 0:
                r = {k: min(100.0, max(0.0, (eng[k] - p[k]) / dt_ns * 100)) for k in eng}
                a = per.setdefault(pid, {}).setdefault(vendor, {"3d": 0.0, "video": 0.0})
                t = tot.setdefault(vendor, {"3d": 0.0, "video": 0.0})
                for k in r:
                    a[k] += r[k]
                    t[k] += r[k]
    for key in [k for k in prev_drm if k[0] not in drm_fds]:
        del prev_drm[key]
    return per, tot


def read_procs(dt, tick):
    now_ticks, rows, threads = {}, [], 0
    own = []
    for pid_s in os.listdir("/proc"):
        if not pid_s.isdigit():
            continue
        pid = int(pid_s)
        try:
            with open(f"/proc/{pid}/stat") as f:
                s = f.read()
        except OSError:
            continue
        i = s.rfind(")")
        comm = s[s.find("(") + 1:i]
        rest = s[i + 2:].split()
        ppid = int(rest[1])
        if ppid == 2 or pid == 2:          # потоки ядра не показываются
            continue
        ticks, start, thr, rss = int(rest[11]) + int(rest[12]), int(rest[19]), int(rest[17]), int(rest[21]) * PAGE
        threads += thr
        now_ticks[pid] = (start, ticks)
        p = prev_ticks.get(pid)
        cpu = 0.0
        if p and p[0] == start and dt > 0:
            cpu = (ticks - p[1]) / CLK / dt * 100
        info = proc_info(pid, start, comm)
        if info["uid"] == UID:
            own.append(pid)
        rows.append({"pid": pid, "name": info["name"], "cmd": info["cmd"], "user": info["user"], "own": info["uid"] == UID,
                     "cpu": round(cpu, 1), "rss": rss, "thr": thr, "state": rest[0]})
    prev_ticks.clear()
    prev_ticks.update(now_ticks)
    for key in [k for k in info_cache if k[0] not in now_ticks]:
        del info_cache[key]
    if tick % 10 == 0:
        scan_drm(own)
    return rows, len(rows), threads


# ---------- видеокарты ----------
conn_t = {"v": time.monotonic(), "list": []}
nv_name = {"v": ""}
nv_last = {"g": None}


def nvidia_read(dev, tick):
    """NVIDIA: пока карта спит (runtime_status ≠ active), её не опрашиваем — nvidia-smi разбудил бы её.
    Опрос — раз в два такта (два запуска nvidia-smi заметно дороже всего остального), между ними — прошлые значения."""
    state = rd(f"{dev['dev']}/power/runtime_status", "active")
    g = {"vendor": "nvidia", "slot": dev["slot"], "name": nv_name["v"] or dev["name"], "state": state, "procs": []}
    if state != "active" or not NVSMI:
        nv_last["g"] = None
        return g
    if tick % 2 and nv_last["g"]:
        return nv_last["g"]
    try:
        q = subprocess.run(["nvidia-smi", "--query-gpu=name,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw,power.limit,clocks.gr,clocks.max.gr,clocks.mem,pstate",
                            "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=2).stdout.strip().splitlines()
        f = [x.strip() for x in q[0].split(",")] if q else []
        num = lambda i: float(f[i]) if len(f) > i and re.fullmatch(r"-?[\d.]+", f[i]) else None
        if f:
            nv_name["v"] = g["name"] = f[0]
            g.update({"util": num(1), "memUtil": num(2), "memUsed": num(3), "memTotal": num(4), "temp": num(5), "power": num(6),
                      "powerMax": num(7), "mhz": num(8), "mhzMax": num(9), "memMhz": num(10), "pstate": f[11] if len(f) > 11 else ""})
        pm = subprocess.run(["nvidia-smi", "pmon", "-c", "1", "-s", "um"], capture_output=True, text=True, timeout=2).stdout
        for line in pm.splitlines():
            if line.startswith("#") or not line.strip():
                continue
            c = line.split()
            if len(c) >= 11 and c[1].isdigit():
                g["procs"].append({"pid": int(c[1]), "type": c[2], "sm": float(c[3]) if c[3] != "-" else 0.0,
                                   "fb": float(c[9]) if c[9] != "-" else 0.0})
    except (OSError, subprocess.SubprocessError, ValueError, IndexError):
        pass
    nv_last["g"] = g
    return g


def amd_read(dev, tot):
    d = dev["dev"]
    hw = ""
    try:
        hw = f"{d}/hwmon/" + os.listdir(f"{d}/hwmon")[0]
    except (OSError, IndexError):
        pass
    mhz = 0
    for line in rd(f"{d}/pp_dpm_sclk").splitlines():
        if line.rstrip().endswith("*"):
            m = re.search(r"(\d+)Mhz", line)
            mhz = int(m.group(1)) if m else 0
    return {"vendor": "amd", "slot": dev["slot"], "name": dev["name"], "state": "active", "util": rint(f"{d}/gpu_busy_percent", -1) if os.path.exists(f"{d}/gpu_busy_percent") else None,
            "memUsed": rint(f"{d}/mem_info_vram_used") / 1048576, "memTotal": rint(f"{d}/mem_info_vram_total") / 1048576,
            "temp": rint(f"{hw}/temp1_input") / 1000 if hw else None, "power": rint(f"{hw}/power1_average") / 1e6 if hw else None,
            "mhz": mhz, "procs": []}


def intel_read(dev, tot):
    d = dev["dev"]
    card = f"/sys/class/drm/{dev['card']}"
    t = tot.get("intel", {"3d": 0.0, "video": 0.0})
    act = rint(f"{card}/gt_act_freq_mhz") or rint(f"{card}/gt/gt0/rps_act_freq_mhz")
    return {"vendor": "intel", "slot": dev["slot"], "name": dev["name"], "state": "active", "util": round(min(100.0, t["3d"]), 1),
            "video": round(min(100.0, t["video"]), 1), "mhz": act, "mhzMax": rint(f"{card}/gt_RP0_freq_mhz") or rint(f"{card}/gt/gt0/rps_RP0_freq_mhz"),
            "shared": True, "procs": []}


def read_gpus(tot, tick):
    out = []
    for dev in GPUS:
        if dev["vendor"] == "nvidia":
            out.append(nvidia_read(dev, tick))
        elif dev["vendor"] == "amd":
            out.append(amd_read(dev, tot))
        elif dev["vendor"] == "intel":
            out.append(intel_read(dev, tot))
    return out


# ---------- основной цикл ----------
def emit(obj):
    try:
        sys.stdout.write(json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()
    except (BrokenPipeError, OSError):
        sys.exit(0)


def main():
    hello = dict(STATIC)
    hello.pop("kinds", None)
    hello.update({"host": rd("/etc/hostname") or os.uname().nodename, "kernel": os.uname().release,
                  "memTotal": read_mem()["total"], "gpus": [{"vendor": g["vendor"], "name": g["name"], "slot": g["slot"]} for g in GPUS]})
    emit({"hello": hello})
    # первое чтение — «нулевая точка» для разностей
    read_cpu()
    read_procs(1, 0)
    read_disk(1)
    read_net(1)
    last = time.monotonic()
    time.sleep(0.25)
    tick = 0
    while True:
        t0 = time.monotonic()
        dt = t0 - last
        last = t0
        tick += 1
        total, cores = read_cpu()
        rows, nproc, nthr = read_procs(dt, tick)
        per, tot = read_drm(dt)
        gpus = read_gpus(tot, tick)
        # видеокарта в строках процессов: NVIDIA — из pmon, Intel/AMD — из fdinfo
        by_pid = {r["pid"]: r for r in rows}
        for g in gpus:
            for p in g["procs"]:
                r = by_pid.get(p["pid"])
                if r:
                    r["gpu"] = max(r.get("gpu", 0), p["sm"])
                    r["gpuMem"] = p["fb"]
                    r["gpuDev"] = "nvidia"
        for pid, vend in per.items():
            r = by_pid.get(pid)
            if r:
                for v, e in vend.items():
                    val = max(e["3d"], e["video"])
                    if val > r.get("gpu", 0):
                        r["gpu"], r["gpuDev"] = round(val, 1), v
        rows.sort(key=lambda r: (-r["cpu"], -r["rss"]))
        # соединения — раз в два такта: ss дороже остального; скорость считается по времени между опросами
        if tick % 2 == 0:
            cdt = t0 - conn_t["v"]; conn_t["v"] = t0
            conn_t["list"] = read_conns(cdt)
        conns = conn_t["list"]
        load = rd("/proc/loadavg").split()
        emit({"t": round(time.time(), 2), "dt": round(dt, 2), "up": float(rd("/proc/uptime", "0 0").split()[0]),
              "load": [float(x) for x in load[:3]] if len(load) >= 3 else [0, 0, 0],
              "cpu": {"total": total, "cores": cores, "temp": cpu_temp(), "gov": rd("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
                      "epp": rd("/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference"), "procs": nproc, "threads": nthr,
                      "mhz": round(sum(c["mhz"] for c in cores) / max(1, len(cores)))},
              "mem": read_mem(), "gpus": [{k: v for k, v in g.items() if k != "procs"} for g in gpus],
              "disk": read_disk(dt), "net": read_net(dt), "conns": conns, "bat": read_bat(), "procs": rows})
        time.sleep(max(0.05, TICK - (time.monotonic() - t0)))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
