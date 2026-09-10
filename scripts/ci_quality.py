#!/usr/bin/env python3
"""Skip unnecessary macOS builds while always reporting a required CI result."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def requires_build(paths):
    return any(not (path.endswith('.md') or path.startswith(('docs/', '.vale/'))
                   or path == '.vale.ini') for path in paths)


def revision_range(event_name, event):
    if event_name == 'pull_request':
        base = event['pull_request']['base']['sha']
        head = event['pull_request']['head']['sha']
        separator = '...'
    elif event_name == 'push':
        base, head = event['before'], event['after']
        separator = '..'
    else:
        raise ValueError(f'Unsupported event: {event_name}')
    for revision in (base, head):
        if not isinstance(revision, str) or not re.fullmatch('[0-9a-f]{40}', revision):
            raise ValueError('Expected a full commit SHA')
    # A new branch has no previous commit. Run the tests rather than guess.
    if base == '0' * 40:
        return None
    return f'{base}{separator}{head}'


def build_needed(event_name, event):
    revisions = revision_range(event_name, event)
    if revisions is None:
        return True
    # Disabling rename detection checks both paths when code moves into docs.
    result = subprocess.run(['git', 'diff', '--name-only', '--no-renames', '-z',
                             revisions, '--'], check=True, stdout=subprocess.PIPE)
    paths = result.stdout.decode('utf-8', errors='surrogateescape').split('\0')
    return requires_build(path for path in paths if path)


def verify_jobs(needs):
    changes = needs['changes']
    if changes['result'] != 'success':
        raise ValueError('Change detection did not pass')
    build = changes.get('outputs', {}).get('build')
    if build not in ('true', 'false'):
        raise ValueError('Change detection did not report a build decision')
    result = needs['test']['result']
    allowed = ('success',) if build == 'true' else ('success', 'skipped')
    if result not in allowed:
        raise ValueError(f'Required macOS tests did not pass: {result}')


def main():
    mode = sys.argv[1]
    if mode == 'changes':
        event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
        needed = build_needed(os.environ['GITHUB_EVENT_NAME'], event)
        with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
            output.write(f'build={str(needed).lower()}\n')
        print('macOS tests required' if needed else 'Documentation-only change')
    elif mode == 'verify':
        verify_jobs(json.loads(os.environ['CI_NEEDS']))
        print('Code quality passed')
    else:
        raise ValueError(f'Unsupported mode: {mode}')


if __name__ == '__main__':
    main()
