#!/usr/bin/env python3
"""Gate macOS builds, report a required CI result, and check source-only rules.

A source-only rule is one that a text scan can decide, so it runs on every pull
request without a macOS build.
"""
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


# --- The readable-text floor -------------------------------------------------
#
# Text that a person reads is never smaller than 12 points. The system styles
# below are all smaller than that on macOS, so a font that uses one of them, or
# an explicit size under the floor, is a finding.
#
# A symbol is a picture and not text, so `Image` keeps its own glyph sizes. The
# scan finds the subject by reading upwards to the nearest view constructor,
# which is how these chains are written. A font whose subject it cannot name is
# a finding, so an unusual shape asks for a decision instead of passing quietly.
READABLE_TEXT_FLOOR = 12.0
SMALL_TEXT_STYLES = ('caption2', 'caption', 'footnote', 'subheadline')
# Put this on the font line, or the line above it, with the reason. Use it for
# text in a fixed geometry that the readable size would break.
SMALL_TEXT_MARKER = 'small-text-ok:'
# Each anchor ends on its own opening parenthesis, so the reader below can take
# the complete font expression from there.
FONT_ANCHORS = re.compile(
    r'\.font\(|\bFont\.system\(|\bNSFont\.\w*[fF]ont\((?=ofSize:)'
)
# `Font.caption` and a bare `.caption` are styles. `PaguroTypeSize.caption` is
# the app's own token and names a number, so the type name excludes it.
SMALL_TEXT_STYLE_PATTERN = re.compile(
    r'(?:\bFont|(?<![A-Za-z0-9_]))\.(' + '|'.join(SMALL_TEXT_STYLES) + r')\b'
)
FONT_SIZE_ARGUMENT = re.compile(r'\b(?:size|ofSize):([^,)]*)')
# Only a size that is a plain number carries a fixed size. A size such as
# `tileSize * 0.44` follows the picture it sits in, so the number in it is a
# proportion and not a point value.
NUMERIC_SIZE = re.compile(r'^\d+(?:\.\d+)?$')
# The app keeps its text sizes in the `PaguroTypeSize` ramp, so a font can carry
# a size without writing the number. The scan reads the ramp and resolves a
# reference to one of its names. Without this step a new token would hide a size
# under the floor from the check.
TYPE_SIZE_RAMP = 'PaguroTypeSize'
TYPE_SIZE_ENUM = re.compile(
    r'\benum\s+' + TYPE_SIZE_RAMP + r'\b[^{]*\{(.*?)\n\}', re.DOTALL
)
TYPE_SIZE_TOKEN = re.compile(r'\bstatic let (\w+)\s*:\s*CGFloat\s*=\s*([\w.]+)')
TYPE_SIZE_REFERENCE = re.compile(r'^' + TYPE_SIZE_RAMP + r'\.(\w+)$')
VIEW_CONSTRUCTORS = (
    'Image(', 'Text(', 'Label(', 'TextField(', 'TextEditor(', 'SecureField(',
    'Toggle(', 'Picker(', 'Button(', 'Link(', 'Stepper(', 'Slider(',
)
# How far above a font the subject may sit. Every chain in the app puts its
# view within this distance, and a longer reach would start guessing.
SUBJECT_LOOKBACK = 8


def _balanced_expression(text, start):
    """Returns the text from `start` to the paren that closes the one there."""
    depth = 0
    index = start
    in_string = False
    while index < len(text):
        character = text[index]
        if in_string:
            if character == '\\':
                index += 2
                continue
            if character == '"':
                in_string = False
        elif character == '"':
            in_string = True
        elif character == '(':
            depth += 1
        elif character == ')':
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
        index += 1
    return text[start:]


def _font_subject(lines, line_number):
    """Names the view that a font on `line_number` applies to, or None."""
    first = max(0, line_number - SUBJECT_LOOKBACK)
    for index in range(line_number, first - 1, -1):
        stripped = lines[index].lstrip()
        for constructor in VIEW_CONSTRUCTORS:
            if stripped.startswith(constructor):
                return constructor.rstrip('(')
    return None


def type_size_values(source):
    """Reads the point value of each size in the `PaguroTypeSize` ramp."""
    written = {}
    for block in TYPE_SIZE_ENUM.findall(source):
        written.update(TYPE_SIZE_TOKEN.findall(block))
    values = {}
    for name in written:
        # A size in the ramp can name another size in it, such as the Settings
        # caption that shares the readable floor. Follow that chain to a number.
        value, seen = written[name], set()
        while value in written and value not in seen:
            seen.add(value)
            value = written[value]
        if NUMERIC_SIZE.match(value):
            values[name] = float(value)
    return values


def _point_size(expression, type_sizes):
    """Returns the fixed point size that `expression` asks for, or None."""
    if NUMERIC_SIZE.match(expression):
        return float(expression)
    reference = TYPE_SIZE_REFERENCE.match(expression)
    if reference:
        return type_sizes.get(reference.group(1))
    return None


def small_text_findings(source, path, type_sizes=None):
    """Reports every font in `source` that breaks the readable-text floor."""
    type_sizes = type_sizes if type_sizes is not None else type_size_values(source)
    lines = source.splitlines()
    findings = []
    for anchor in FONT_ANCHORS.finditer(source):
        expression = _balanced_expression(source, anchor.end() - 1)
        reasons = [
            f'the system {name} style'
            for name in {match.group(1)
                         for match in SMALL_TEXT_STYLE_PATTERN.finditer(expression)}
        ]
        for argument in FONT_SIZE_ARGUMENT.finditer(expression):
            # A ternary picks one size for each case, so each branch counts.
            for branch in re.split(r'[?:]', argument.group(1)):
                branch = branch.strip()
                size = _point_size(branch, type_sizes)
                if size is None or size >= READABLE_TEXT_FLOOR:
                    continue
                # A token names the size, so the report also prints the number.
                written = f'{branch} ({size:g})' if branch != f'{size:g}' else branch
                reasons.append(f'size {written}')
        if not reasons:
            continue
        line_number = source.count('\n', 0, anchor.start())
        context = lines[max(0, line_number - 1):line_number + 1]
        if any(SMALL_TEXT_MARKER in line for line in context):
            continue
        subject = _font_subject(lines, line_number)
        if subject == 'Image':
            continue
        named = subject or 'an unnamed view'
        findings.append(
            f'{path}:{line_number + 1}: {named} uses '
            f'{", ".join(sorted(reasons))}'
        )
    return findings


def check_small_text(root):
    """Reports the readable-text floor over every Swift file in the app."""
    sources = {
        path: path.read_text(encoding='utf-8')
        for path in sorted(Path(root).rglob('*.swift'))
    }
    # The ramp sits in one file, and the fonts that use it sit in others, so
    # read every size first and then scan with the complete ramp.
    type_sizes = {}
    for source in sources.values():
        type_sizes.update(type_size_values(source))
    findings = []
    for path, source in sources.items():
        findings += small_text_findings(source, path.as_posix(), type_sizes)
    return findings


def main():
    mode = sys.argv[1]
    if mode == 'text-size':
        findings = check_small_text('Paguro')
        for finding in findings:
            print(finding, file=sys.stderr)
        if findings:
            raise SystemExit(
                f'{len(findings)} font(s) below the {READABLE_TEXT_FLOOR:g} '
                'point readable-text floor. Use the shared caption token, or '
                f'add "// {SMALL_TEXT_MARKER} <reason>" where a fixed geometry '
                'cannot take the readable size.'
            )
        print('Every readable text is at least 12 points')
    elif mode == 'changes':
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
