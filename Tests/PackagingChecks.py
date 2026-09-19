#!/usr/bin/env python3
"""Exercise packaging in temporary folders; never register a real input source."""
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


def run(args, *, cwd=ROOT, env=None):
    return subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True)


def snapshot(folder):
    if not folder.exists():
        return None
    return {str(p.relative_to(folder)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in folder.rglob('*') if p.is_file()}


def executable(file, contents):
    file.write_text(contents)
    file.chmod(0o755)


class PackagingChecks(unittest.TestCase):
    def test_install_outcomes(self):
        # Exit zero covers both ready and successfully registered but pending.
        # Native LS/TIS calls are replaced at the helper boundary, not invoked.
        for previous in [None, 'Sunarae.app', 'Dukkeobi.app']:
            for outcome in ['ready', 'pending', 'failure']:
                with self.subTest(previous=previous, outcome=outcome), tempfile.TemporaryDirectory(prefix='Sunarae install ') as temp:
                    base = Path(temp)
                    artifacts = base / 'artifacts'
                    (artifacts / 'Support').mkdir(parents=True)
                    shutil.copytree(ROOT / 'dist/Sunarae.app', artifacts / 'Sunarae.app')
                    executable(artifacts / 'Support/input-source', '''#!/bin/bash
case "$1" in
  current) echo com.apple.keylayout.ABC ;;
  register|register-only)
    echo "$1" >> "$SUNARAE_TEST_LOG"
    echo "$SUNARAE_TEST_OUTCOME"
    [[ "$SUNARAE_TEST_OUTCOME" != failure ]] ;;
  *) exit 99 ;;
esac
''')
                    target = base / 'Input Methods'
                    target.mkdir()
                    old = target / previous if previous else None
                    if old:
                        shutil.copytree(artifacts / 'Sunarae.app', old)
                        # Distinguish a previous install from its replacement.
                        (old / 'old-install-marker').write_text('keep on rollback')
                    before = snapshot(target)
                    env = dict(os.environ, SUNARAE_INPUT_METHODS_DIR=str(target),
                               SUNARAE_TEST_OUTCOME=outcome, SUNARAE_TEST_LOG=str(base / 'calls'))
                    result = run(['bash', 'scripts/install.sh', str(artifacts)], env=env)
                    if outcome == 'failure':
                        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertEqual(snapshot(target), before)
                    else:
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertEqual(snapshot(target / 'Sunarae.app'), snapshot(artifacts / 'Sunarae.app'))
                        self.assertFalse((target / 'Dukkeobi.app').exists())
                    self.assertEqual(list(target.glob('.Sunarae-install.*')), [])

    def test_active_source_and_name_collision(self):
        with tempfile.TemporaryDirectory(prefix='Sunarae guards ') as temp:
            base = Path(temp)
            artifacts = base / 'artifacts'
            (artifacts / 'Support').mkdir(parents=True)
            shutil.copytree(ROOT / 'dist/Sunarae.app', artifacts / 'Sunarae.app')
            executable(artifacts / 'Support/input-source', '''#!/bin/bash
[[ "$1" == current ]] || exit 99
echo "$SUNARAE_TEST_CURRENT"
''')
            target = base / 'Input Methods'
            target.mkdir()
            env = dict(os.environ, SUNARAE_INPUT_METHODS_DIR=str(target),
                       SUNARAE_TEST_CURRENT='local.inputmethod.Dukkeobi')
            result = run(['bash', 'scripts/install.sh', str(artifacts)], env=env)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(list(target.iterdir()), [])
            unrelated = target / 'Sunarae.app/Contents'
            unrelated.mkdir(parents=True)
            (unrelated / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'other.app'}))
            before = snapshot(target)
            env['SUNARAE_TEST_CURRENT'] = 'com.apple.keylayout.ABC'
            result = run(['bash', 'scripts/install.sh', str(artifacts)], env=env)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(snapshot(target), before)

    def test_build_preserves_or_replaces_whole_dist(self):
        with tempfile.TemporaryDirectory(prefix='Sunarae build ') as temp:
            project = Path(temp) / 'project with spaces'
            project.mkdir()
            for directory in ['Sources', 'Resources', 'scripts', 'vendor', 'spec', 'docs']:
                shutil.copytree(ROOT / directory, project / directory)
            for filename in ['README.md', 'CONTRIBUTING.md', 'THIRD_PARTY.md']:
                shutil.copy2(ROOT / filename, project / filename)
            dist = project / 'dist'
            (dist / 'Sunarae.app/Contents/Resources').mkdir(parents=True)
            (dist / 'Sunarae.app/Contents/Resources/obsolete').write_text('old resource')
            (dist / 'old-support-file').write_text('last complete build')
            before = snapshot(dist)
            bin_dir = Path(temp) / 'bin'
            bin_dir.mkdir()
            executable(bin_dir / 'xcrun', '''#!/bin/bash
if [[ "$SUNARAE_TEST_FAILURE" == helper ]]; then
    for argument in "$@"; do
        [[ "$argument" != scripts/InputSourceTool.swift ]] || exit 42
    done
fi
exec /usr/bin/xcrun "$@"
''')
            executable(bin_dir / 'mv', '''#!/bin/bash
if [[ "$SUNARAE_TEST_FAILURE" == publish && "$1" == */Ready && "$2" == */dist ]]; then exit 43; fi
exec /bin/mv "$@"
''')
            env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'])
            for failure, status in [('helper', 42), ('publish', 43), ('none', 0)]:
                with self.subTest(failure=failure):
                    env['SUNARAE_TEST_FAILURE'] = failure
                    result = run(['bash', 'scripts/build.sh'], cwd=project, env=env)
                    self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                    if status:
                        self.assertEqual(snapshot(dist), before)
                    else:
                        self.assertFalse((dist / 'old-support-file').exists())
                        self.assertFalse((dist / 'Sunarae.app/Contents/Resources/obsolete').exists())
                        self.assertTrue((dist / 'Support/input-source').is_file())
                        self.assertTrue(os.access(dist / 'Install.command', os.X_OK))
                        verified = run(['codesign', '--verify', '--deep', '--strict', str(dist / 'Sunarae.app')])
                        self.assertEqual(verified.returncode, 0, verified.stderr)
                    self.assertEqual(list(project.glob('.Sunarae-build.*')), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
