#!/usr/bin/env python3
"""Installer test double. Only inspect reads real bundle metadata; no TIS calls."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

state_path = Path(os.environ['SUNARAE_TEST_STATE'])
state = json.loads(state_path.read_text())
command = sys.argv[1]
state.setdefault('calls', []).append(command)

def save():
    state_path.write_text(json.dumps(state))

def identity():
    return plistlib.loads((Path(sys.argv[2]) / 'Contents/Info.plist').read_bytes())['CFBundleIdentifier']

result = 0
if command == 'inspect':
    save()
    sys.exit(subprocess.call([os.environ['SUNARAE_REAL_TOOL'], 'inspect', sys.argv[2]]))
elif command == 'current':
    mode = state.get('query', '')
    if mode == 'error':
        result = 42
    elif mode != 'empty':
        state['reads'] = state.get('reads', 0) + 1
        print('unknown' if mode == 'unknown' else (
            'local.inputmethod.Sunarae' if state.get('reselect') and state['reads'] > 1 else state['current']))
elif command == 'enabled':
    print(str(identity() in state['enabled']).lower())
elif command == 'select-abc':
    if state.get('switch') == 'failure':
        result = 43
    elif state.get('switch') != 'stuck':
        state['current'] = 'com.apple.keylayout.ABC'
elif command in ['disable', 'disable-bundle']:
    identifier = identity() if command == 'disable-bundle' else 'local.inputmethod.Sunarae'
    state['enabled'] = [item for item in state['enabled'] if item != identifier]
elif command in ['register', 'register-only']:
    identifier = identity()
    if command == 'register' and state.get('outcome') != 'pending' and identifier not in state['enabled']:
        state['enabled'].append(identifier)
    if state.get('outcome') == 'failure' and not state.get('failed_once'):
        state['failed_once'] = True
        result = 44
else:
    result = 99
save()
sys.exit(result)
