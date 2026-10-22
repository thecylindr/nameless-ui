import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest
from datetime import datetime, timezone

spec = importlib.util.spec_from_file_location('codex_stats', Path(__file__).resolve().parents[1] / 'nameless/codex_stats.py')
stats = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stats)


class StatsTests(unittest.TestCase):
    def test_usage_dedup_incremental_partial_and_truncation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            session = root / 'sessions/example.jsonl'
            session.parent.mkdir()
            cache = root / 'cache.json'
            now = time.time()
            ts = datetime.fromtimestamp(now, timezone.utc).isoformat()
            def event(kind, payload):
                return json.dumps({'timestamp': ts, 'type': kind, 'payload': payload}) + '\n'
            usage = {'input_tokens': 100, 'cached_input_tokens': 80, 'output_tokens': 30, 'reasoning_output_tokens': 20, 'total_tokens': 130}
            record = event('token_usage_record', {'response_id': 'r1', 'usage': usage})
            session.write_text(event('session_meta', {'cwd': '/private/project'}) + event('turn_context', {'model': 'example-model'}) + record + record + event('event_msg', {'type': 'token_count', 'info': {'total_token_usage': usage}, 'rate_limits': {'primary': {'used_percent': 17, 'window_minutes': 300, 'resets_at': now + 100}}}))
            summary = stats.collect(root, cache, now)
            self.assertEqual(summary['today'], {'tokens': 130, 'msgs': 1})
            self.assertEqual(summary['block5h']['cacheRead'], 80)
            self.assertEqual(summary['block5h']['reasoning'], 20)
            self.assertEqual(summary['usage']['primary']['util'], 17)
            self.assertEqual(summary['models'], [('example-model', 130)])
            self.assertEqual(stats.collect(root, cache, now)['today']['tokens'], 130)
            # Incomplete JSON stays unread until the following poll.
            second = event('token_usage_record', {'response_id': 'r2', 'usage': usage})
            with session.open('a') as f:
                f.write(second[:-3])
            self.assertEqual(stats.collect(root, cache, now)['today']['tokens'], 130)
            with session.open('a') as f:
                f.write(second[-3:])
            self.assertEqual(stats.collect(root, cache, now)['today']['tokens'], 260)
            # Truncation rebuilds this file, rather than retaining its former contribution.
            session.write_text(record)
            self.assertEqual(stats.collect(root, cache, now)['today']['tokens'], 130)
            session.unlink()
            self.assertEqual(stats.collect(root, cache, now)['today']['tokens'], 0)

    def test_legacy_cumulative_counters_and_empty_install(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache = root / 'cache.json'
            empty = stats.collect(root, cache)
            self.assertFalse(empty['available'])
            self.assertFalse(empty['usage']['ok'])
            session = root / 'sessions/old.jsonl'
            session.parent.mkdir()
            ts = datetime.now(timezone.utc).isoformat()
            rows = []
            for total in (100, 100, 150):
                rows.append(json.dumps({'timestamp': ts, 'type': 'event_msg', 'payload': {'type': 'token_count', 'info': {'total_token_usage': {'input_tokens': total, 'total_tokens': total}}}}))
            session.write_text('\n'.join(rows) + '\n')
            result = stats.collect(root, cache)
            self.assertEqual(result['today'], {'tokens': 150, 'msgs': 2})


if __name__ == '__main__':
    unittest.main()
