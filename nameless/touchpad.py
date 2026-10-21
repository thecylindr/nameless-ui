#!/usr/bin/env python3
"""Сенсорная панель для виджета «Сенсорная панель» (WTouch.qml): положение пальцев и клики тачпада, одна JSON-строка на событие.

Без зависимостей: читает /dev/input/event* напрямую (нужно состоять в группе input). Тачпад ищется в /proc/bus/input/devices —
по имени «touchpad» или по мультитач-осям указателя; можно указать путь вручную: touchpad.py /dev/input/eventN.
Вывод (координаты 0..1 по размеру панели):
  {"f": [[x, y, слот], …], "l": 0|1, "r": 0|1, "m": 0|1}         состояние: пальцы и нажатые кнопки
  {"e": "click", "b": "l|r|m", "x": …, "y": …}                    нажатие физической кнопки
  {"e": "tap", "n": 1|2|3, "x": …, "y": …}                        касание без нажатия (1 палец — левая, 2 — правая, 3 — средняя)
  {"hello": "имя тачпада"} при старте; {"err": "no-touchpad" | "perm"} и выход, если читать нечего
Ничего не меняет в системе и не перехватывает ввод — только читает события."""
import fcntl, glob, json, os, re, select, struct, sys, time

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
ABS_X, ABS_Y = 0x00, 0x01
ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 0x2F, 0x35, 0x36, 0x39
BTN_LEFT, BTN_RIGHT, BTN_MIDDLE = 0x110, 0x111, 0x112
EVENT = struct.Struct("llHHi")           # struct input_event на 64-битных системах


def bit(bitmap, n):
    """Бит n в строке вида «B: ABS=…» (64-битные слова, старшее первым)."""
    words = bitmap.split()
    wi = n // 64
    if wi >= len(words):
        return False
    return (int(words[-1 - wi], 16) >> (n % 64)) & 1 == 1


def find_touchpad():
    try:
        text = open("/proc/bus/input/devices").read()
    except OSError:
        return None, ""
    best = None
    for block in text.strip().split("\n\n"):
        name = re.search(r'N: Name="([^"]*)"', block)
        handler = re.search(r"H: Handlers=.*?\b(event\d+)", block)
        abs_m = re.search(r"B: ABS=(.*)", block)
        prop = re.search(r"B: PROP=(.*)", block)
        if not (name and handler and abs_m):
            continue
        has_mt = bit(abs_m.group(1), ABS_MT_POSITION_X)
        pointer = prop is not None and bit(prop.group(1), 0) and not bit(prop.group(1), 1)     # INPUT_PROP_POINTER, не DIRECT
        is_pad = "touchpad" in name.group(1).lower() or "trackpad" in name.group(1).lower()
        if has_mt and (is_pad or pointer):
            if is_pad or best is None:
                best = ("/dev/input/" + handler.group(1), name.group(1))
                if is_pad:
                    break
    return best if best else (None, "")


def absinfo(fd, axis):
    buf = fcntl.ioctl(fd, 0x80184540 + axis, b"\0" * 24)          # EVIOCGABS
    value, mn, mx, fuzz, flat, res = struct.unpack("6i", buf)
    return mn, max(mx, mn + 1)


def out(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def main():
    path, name = (sys.argv[1], os.path.basename(sys.argv[1])) if len(sys.argv) > 1 else find_touchpad()
    if not path:
        out({"err": "no-touchpad"})
        return 1
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except PermissionError:
        out({"err": "perm"})
        return 1
    except OSError:
        out({"err": "no-touchpad"})
        return 1
    try:
        x0, x1 = absinfo(fd, ABS_MT_POSITION_X)
        y0, y1 = absinfo(fd, ABS_MT_POSITION_Y)
    except OSError:
        x0, x1 = absinfo(fd, ABS_X)
        y0, y1 = absinfo(fd, ABS_Y)
    out({"hello": name})

    slot = 0
    pos = {}                                   # слот → [x, y] (0..1)
    btn = {"l": 0, "r": 0, "m": 0}
    start = {}                                 # слот → (время касания, x, y) для распознавания касаний
    moved = False
    most = 0                                   # сколько пальцев было вместе за жест
    t_down = 0.0
    last_emit = 0.0
    dirty = False
    pressed_during = False

    def state():
        out({"f": [[round(p[0], 4), round(p[1], 4), s] for s, p in sorted(pos.items())], "l": btn["l"], "r": btn["r"], "m": btn["m"]})

    while True:
        r, _, _ = select.select([fd], [], [], 0.25)
        if not r:
            continue
        try:
            data = os.read(fd, EVENT.size * 64)
        except BlockingIOError:
            continue
        except OSError:
            out({"err": "no-touchpad"})
            return 1
        for off in range(0, len(data) - EVENT.size + 1, EVENT.size):
            _, _, etype, code, value = EVENT.unpack_from(data, off)
            if etype == EV_ABS:
                if code == ABS_MT_SLOT:
                    slot = value
                elif code == ABS_MT_TRACKING_ID:
                    if value < 0:
                        pos.pop(slot, None)
                        if not pos:                                  # все пальцы подняты — было ли это касанием
                            if (not moved) and (not pressed_during) and most > 0 and time.time() - t_down < 0.28 and start:
                                _, sx, sy = next(iter(start.values()))
                                out({"e": "tap", "n": min(most, 3), "x": round(sx, 4), "y": round(sy, 4)})
                            start.clear(); most = 0; moved = False; pressed_during = False
                    else:
                        pos[slot] = pos.get(slot, [0.5, 0.5])
                        if not start:
                            t_down = time.time()
                        start[slot] = (time.time(), pos[slot][0], pos[slot][1])
                        most = max(most, len(pos))
                    dirty = True
                elif code == ABS_MT_POSITION_X and slot in pos or (code == ABS_MT_POSITION_X and value >= 0):
                    p = pos.setdefault(slot, [0.5, 0.5]); p[0] = min(1.0, max(0.0, (value - x0) / (x1 - x0)))
                    if slot in start and abs(p[0] - start[slot][1]) > 0.04: moved = True
                    if slot in start and start[slot][1] == 0.5: start[slot] = (start[slot][0], p[0], start[slot][2])
                    dirty = True
                elif code == ABS_MT_POSITION_Y:
                    p = pos.setdefault(slot, [0.5, 0.5]); p[1] = min(1.0, max(0.0, (value - y0) / (y1 - y0)))
                    if slot in start and abs(p[1] - start[slot][2]) > 0.04: moved = True
                    if slot in start and start[slot][2] == 0.5: start[slot] = (start[slot][0], start[slot][1], p[1])
                    dirty = True
            elif etype == EV_KEY and code in (BTN_LEFT, BTN_RIGHT, BTN_MIDDLE):
                k = {BTN_LEFT: "l", BTN_RIGHT: "r", BTN_MIDDLE: "m"}[code]
                btn[k] = 1 if value else 0
                if value:
                    pressed_during = True
                    first = next(iter(pos.values()), [0.5, 0.5])
                    out({"e": "click", "b": k, "x": round(first[0], 4), "y": round(first[1], 4)})
                dirty = True
            elif etype == EV_SYN and dirty:
                now = time.time()
                if now - last_emit >= 0.016 or not pos:      # не чаще ~60 раз в секунду, но подъём пальцев — сразу
                    state(); last_emit = now; dirty = False


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass
