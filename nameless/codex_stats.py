#!/usr/bin/env python3
"""Local Codex usage and quota snapshots; never reads auth.json or sends requests.

Incremental per-file contributions allow truncated/rotated logs to be rebuilt.
Modern response usage records take precedence over legacy cumulative events.
Cached input and reasoning are subsets, never added to the total twice.
"""
import json
import os
from pathlib import Path
import time
from datetime import datetime, timedelta
import tempfile
import fcntl

KEEP = 9 * 86400
FIELDS = ('input_tokens', 'output_tokens', 'cache_write_input_tokens',
          'cached_input_tokens', 'reasoning_output_tokens', 'total_tokens')


def timestamp(value):
    try:
        return datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()
    except (ValueError, TypeError, AttributeError):
        return 0


def numbers(usage):
    values = [max(0, int(usage.get(k, 0) or 0)) for k in FIELDS]
    if not values[-1]:
        values[-1] = values[0] + values[1]
    return values


def scan(path, old, now):
    stat = path.stat()
    identity = [stat.st_dev, stat.st_ino]
    if old.get('identity') != identity or stat.st_size < old.get('offset', 0):
        old = {}
    state = dict(old)
    state.setdefault('offset', 0)
    state.setdefault('buckets', {})
    state.setdefault('legacy', {})
    state.setdefault('seen', {})
    state.setdefault('totals', [0] * 6)
    state['identity'] = identity
    with path.open('rb') as stream:
        stream.seek(state['offset'])
        while True:
            start = stream.tell()
            line = stream.readline()
            if not line or not line.endswith(b'\n'):
                state['offset'] = start
                break
            state['offset'] = stream.tell()
            try:
                event = json.loads(line)
                payload = event.get('payload') or {}
                ts = timestamp(event.get('timestamp'))
                kind = event.get('type')
                if kind == 'session_meta':
                    state['project'] = Path(payload.get('cwd') or '~').name or '~'
                    state['session'] = payload.get('id') or payload.get('session_id')
                if kind == 'turn_context':
                    state['model'] = payload.get('model') or 'Codex'
                values = None
                if kind == 'token_usage_record':
                    state['modern'] = True
                    if state.get('session') and payload.get('thread_id') and state['session'] != payload['thread_id']:
                        continue
                    rid = payload.get('response_id')
                    if not rid or rid not in state['seen']:
                        if rid:
                            state['seen'][rid] = ts
                        values = numbers(payload.get('usage') or {})
                    target = state['buckets']
                elif kind == 'event_msg' and payload.get('type') == 'token_count':
                    rate = payload.get('rate_limits')
                    if rate and ts >= state.get('rateTime', 0):
                        state['rate'], state['rateTime'] = rate, ts
                    total = (payload.get('info') or {}).get('total_token_usage')
                    if total:
                        current = numbers(total)
                        previous = state['totals']
                        values = [max(0, a - b) for a, b in zip(current, previous)] if current[-1] >= previous[-1] else current
                        state['totals'] = current
                    target = state['legacy']
                else:
                    continue
                if not values or values[-1] <= 0 or ts <= 0 or now - ts > KEEP or ts > now + 60:
                    continue
                key = json.dumps([int(ts // 3600), state.get('model', 'Codex'), state.get('project', '~')])
                bucket = target.setdefault(key, [0] * 7)
                for i, value in enumerate(values):
                    bucket[i] += value
                bucket[6] += 1
            except (ValueError, TypeError, AttributeError, OverflowError):
                continue
    for name in ('buckets', 'legacy'):
        state[name] = {k: v for k, v in state[name].items() if now - json.loads(k)[0] * 3600 <= KEEP}
    state['seen'] = {k: v for k, v in state['seen'].items() if now - v <= KEEP}
    return state


def collect(root, cache, now=None):
    now = time.time() if now is None else now
    try:
        saved = json.loads(cache.read_text())
    except (OSError, ValueError):
        saved = {}
    if not isinstance(saved, dict):
        saved = {}
    files = saved.get('files', {}) if saved.get('version') == 2 else {}
    for path in root.glob('sessions/**/*.jsonl'):
        try:
            if now - path.stat().st_mtime <= KEEP:
                files[str(path)] = scan(path, files.get(str(path), {}), now)
        except OSError:
            continue
    current = {}
    for path, state in files.items():
        try:
            if now - Path(path).stat().st_mtime <= KEEP:
                current[path] = state
        except OSError:
            pass
    files = current
    cache.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.codex-stats-', dir=cache.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump({'version': 2, 'files': files}, stream, separators=(',', ':'))
        os.replace(tmp, cache)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    days, models, projects = {}, {}, {}
    block = [0] * 7
    rate, rate_time = None, 0
    for state in files.values():
        if state.get('rateTime', 0) > rate_time:
            rate, rate_time = state.get('rate'), state['rateTime']
        buckets = state.get('buckets' if state.get('modern') else 'legacy', {})
        for key, values in buckets.items():
            hour, model, project = json.loads(key)
            ts = hour * 3600
            if datetime.fromtimestamp(ts).date() >= datetime.fromtimestamp(now).date() - timedelta(days=6):
                day = datetime.fromtimestamp(ts).strftime('%Y-%m-%d')
                item = days.setdefault(day, {'date': day, 'tokens': 0, 'msgs': 0, 'models': {}})
                item['tokens'] += values[5]
                item['msgs'] += values[6]
                item['models'][model] = item['models'].get(model, 0) + values[5]
                models[model] = models.get(model, 0) + values[5]
                projects[project] = projects.get(project, 0) + values[5]
            if now - ts <= 5 * 3600:
                block = [a + b for a, b in zip(block, values)]
    today = datetime.fromtimestamp(now).date()
    ordered = [days.get(str(today - timedelta(days=i)), {'date': str(today - timedelta(days=i)), 'tokens': 0, 'msgs': 0, 'models': {}}) for i in range(6, -1, -1)]
    def window(name):
        value = (rate or {}).get(name) or {}
        util = value.get('used_percent')
        return {'util': util, 'resets': value.get('resets_at', 0), 'minutes': value.get('window_minutes', 0)} if isinstance(util, (int, float)) else None
    primary, secondary = window('primary'), window('secondary')
    usage = {'ok': bool(primary or secondary), 'five': primary, 'seven': secondary,
             'primary': primary, 'secondary': secondary, 'plan': (rate or {}).get('plan_type') or '',
             'age': max(0, round(now - rate_time)) if rate_time else 0, 'stale': now - rate_time > 600, 'eta': None, 'sonnet': None, 'opus': None}
    return {'today': {k: ordered[-1][k] for k in ('tokens', 'msgs')},
            'week': {k: sum(d[k] for d in ordered) for k in ('tokens', 'msgs')},
            'block5h': dict(zip(('in', 'out', 'cacheNew', 'cacheRead', 'reasoning', 'tokens', 'msgs'), block)),
            'days': ordered, 'models': sorted(models.items(), key=lambda x: -x[1]),
            'projects': sorted(projects.items(), key=lambda x: -x[1])[:6],
            'usage': usage, 'available': bool(files), 't': round(now)}


if __name__ == '__main__':
    root = Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex')))
    directory = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'glassrice'
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / 'codex-stats.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        print(json.dumps(collect(root, directory / 'codex-stats.json'), ensure_ascii=False, separators=(',', ':')))
