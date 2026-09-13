#!/usr/bin/env python3
"""Summarize opt-in Record timings; never read speech or composer logs."""
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(os.environ.get('TMPDIR', '/tmp')) / 'Bosun-latency.jsonl'
traces = {}
if not path.exists():
    print('No Record timing samples yet.')
    sys.exit(0)
for line in path.read_text().splitlines():
    try:
        row = json.loads(line)
        traces.setdefault(row['id'], {})[row['stage']] = row['elapsed_ms']
    except (ValueError, KeyError):
        continue
intervals = [
    ('recognition_estimate', 'speech_end_estimate', 'recognition_callback'),
    ('callback_to_candidate', 'recognition_callback', 'candidate'),
    ('settling', 'candidate', 'settled'),
    ('dispatch', 'settled', 'queue_enter'),
    ('initial_lookup', 'queue_enter', 'composer_found'),
    ('refresh_lookup', 'composer_found', 'composer_refreshed'),
    ('focus_and_checks', 'composer_refreshed', 'key_post_start'),
    ('key_delivery', 'key_post_start', 'key_post_end'),
    ('state_confirmation', 'key_post_end', 'recording_confirmed'),
    ('callback_to_key', 'recognition_callback', 'key_post_start'),
    ('callback_to_confirmed', 'recognition_callback', 'recording_confirmed'),
]
for key, stages in list(traces.items())[-12:]:
    print(key, 'confirmed' if 'recording_confirmed' in stages else 'incomplete')
    for label, start, end in intervals:
        if start in stages and end in stages:
            print(f'  {label}: {stages[end] - stages[start]:.1f} ms')
print('recognition_estimate uses recognizer segment timing; not a measured acoustic endpoint.')
print('state_confirmation includes polling and AX lookup; not the exact visual onset.')
