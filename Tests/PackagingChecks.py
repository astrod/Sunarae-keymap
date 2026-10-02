#!/usr/bin/env python3
"""Exercise packaging in temporary folders; never register a real input source."""
import hashlib
import json
import sys
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

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
    def test_package_is_user_only(self):
        result = run(['bash', 'scripts/package.sh'])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        info = plistlib.loads((ROOT / 'dist/Sunarae.app/Contents/Info.plist').read_bytes())
        package = ROOT / 'dist' / f"Sunarae-{info['CFBundleShortVersionString']}-{os.uname().machine}.pkg"
        domains = run(['/usr/sbin/installer', '-pkg', str(package), '-dominfo'])
        self.assertEqual(domains.returncode, 0, domains.stdout + domains.stderr)
        self.assertEqual(domains.stdout.strip(), 'CurrentUserHomeDirectory')
        with tempfile.TemporaryDirectory(prefix='Sunarae package ') as temp:
            expanded = Path(temp) / 'Expanded'
            result = run(['pkgutil', '--expand-full', str(package), str(expanded)])
            self.assertEqual(result.returncode, 0, result.stderr)
            distribution = ET.parse(expanded / 'Distribution').getroot()
            self.assertEqual(distribution.find('domains').attrib, dict(
                enable_anywhere='false', enable_currentUserHome='true', enable_localSystem='false'))
            plists = list(expanded.rglob('Sunarae.app/Contents/Info.plist'))
            self.assertEqual(len(plists), 1)
            payload = plistlib.loads(plists[0].read_bytes())
            for key in ['CFBundleIdentifier', 'TISInputSourceID']:
                self.assertEqual(payload[key], 'local.inputmethod.Sunarae')
            self.assertEqual(payload['InputMethodConnectionName'], 'local.inputmethod.Sunarae_Connection')
            verified = run(['codesign', '--verify', '--deep', '--strict', str(plists[0].parent.parent)])
            self.assertEqual(verified.returncode, 0, verified.stderr)
            postinstall = list(expanded.rglob('postinstall'))
            self.assertEqual(len(postinstall), 1)
            self.assertEqual(postinstall[0].read_bytes(), (ROOT / 'scripts/package-postinstall.sh').read_bytes())
            self.assertTrue(os.access(postinstall[0], os.X_OK))

    def test_diagnosis_only_reads_state(self):
        for installed, query_fails in [(False, False), (True, False), (True, True)]:
            with self.subTest(installed=installed, query_fails=query_fails), tempfile.TemporaryDirectory(prefix='Sunarae diagnose ') as temp:
                base = Path(temp)
                artifacts = base / 'artifacts'
                (artifacts / 'Support').mkdir(parents=True)
                shutil.copytree(ROOT / 'dist/Sunarae.app', artifacts / 'Sunarae.app')
                executable(artifacts / 'Support/input-source', '''#!/bin/bash
echo "$1" >> "$SUNARAE_TEST_LOG"
case "$1" in
  current)
    [[ "$SUNARAE_TEST_QUERY_FAILS" != true ]] || exit 42
    echo com.apple.keylayout.ABC ;;
  status) echo registered=false ;;
  *) exit 99 ;;
esac
''')
                target = base / 'Input Methods'
                target.mkdir()
                if installed:
                    shutil.copytree(artifacts / 'Sunarae.app', target / 'Sunarae.app')
                before = snapshot(target)
                artifact_before = snapshot(artifacts)
                log = base / 'calls'
                env = dict(os.environ, SUNARAE_INPUT_METHODS_DIR=str(target),
                           SUNARAE_TEST_LOG=str(log), SUNARAE_TEST_QUERY_FAILS=str(query_fails).lower())
                result = run(['bash', 'scripts/diagnose.sh', str(artifacts)], env=env)
                self.assertEqual(result.returncode, int(query_fails), result.stdout + result.stderr)
                self.assertIn('버전:', result.stdout)
                self.assertIn('서명: 정상', result.stdout)
                self.assertIn('registered=false', result.stdout)
                self.assertEqual(log.read_text().splitlines(), ['current', 'status'])
                self.assertEqual(snapshot(target), before)
                self.assertEqual(snapshot(artifacts), artifact_before)

    def prepare_install(self, base, previous=None, enabled=False, **options):
        artifacts = base / 'artifacts'
        (artifacts / 'Support').mkdir(parents=True)
        shutil.copytree(ROOT / 'dist/Sunarae.app', artifacts / 'Sunarae.app')
        stub = (ROOT / 'Tests/InputSourceStub.py').read_text().split('\n', 1)[1]
        executable(artifacts / 'Support/input-source', '#!' + sys.executable + '\n' + stub)
        target = base / 'Input Methods'
        target.mkdir()
        if previous:
            old = target / 'Sunarae.app'
            shutil.copytree(artifacts / 'Sunarae.app', old)
            info_path = old / 'Contents/Info.plist'
            info = plistlib.loads(info_path.read_bytes())
            info.update(CFBundleIdentifier=previous, TISInputSourceID=previous,
                        InputMethodConnectionName=previous + '_Connection')
            info_path.write_bytes(plistlib.dumps(info))
            (old / 'old-install-marker').write_text('keep on rollback')
        state = dict(current='com.apple.keylayout.ABC', enabled=[previous] if previous and enabled else [])
        state.update(options)
        state_path = base / 'state.json'
        state_path.write_text(json.dumps(state))
        env = dict(os.environ, SUNARAE_INPUT_METHODS_DIR=str(target),
                   SUNARAE_TEST_STATE=str(state_path), SUNARAE_REAL_TOOL=str(ROOT / 'dist/Support/input-source'))
        return artifacts, target, state_path, env

    def test_unknown_current_source_stops_before_installing(self):
        for mode in ['error', 'empty', 'unknown']:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(prefix='Sunarae query ') as temp:
                artifacts, target, state_path, env = self.prepare_install(
                    Path(temp), previous='local.inputmethod.Sunarae', query=mode)
                before = snapshot(target)
                result = run(['bash', 'scripts/install.sh', str(artifacts)], env=env)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(snapshot(target), before)
                self.assertTrue(set(json.loads(state_path.read_text())['calls']) <= {'inspect', 'enabled', 'current'})

    def test_install_outcomes(self):
        # Exercise fresh installs, same-ID updates and a discovered prior ID.
        for previous in [None, 'local.inputmethod.Sunarae', 'local.inputmethod.Previous']:
            for enabled in [False, True]:
                for outcome in ['ready', 'pending', 'failure']:
                    with self.subTest(previous=previous, enabled=enabled, outcome=outcome), tempfile.TemporaryDirectory(prefix='Sunarae install ') as temp:
                        artifacts, target, state_path, env = self.prepare_install(
                            Path(temp), previous=previous, enabled=enabled, outcome=outcome)
                        before = snapshot(target)
                        result = run(['bash', 'scripts/install.sh', str(artifacts)], env=env)
                        state = json.loads(state_path.read_text())
                        if outcome == 'failure':
                            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                            self.assertEqual(snapshot(target), before)
                            self.assertEqual(state['enabled'], [previous] if previous and enabled else [])
                        else:
                            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                            self.assertEqual(snapshot(target / 'Sunarae.app'), snapshot(artifacts / 'Sunarae.app'))
                            if previous and previous != 'local.inputmethod.Sunarae':
                                self.assertNotIn(previous, state['enabled'])
                        self.assertEqual(list(target.glob('.Sunarae-install.*')), [])

    def test_active_source_and_name_collision(self):
        with tempfile.TemporaryDirectory(prefix='Sunarae guards ') as temp:
            artifacts, target, state_path, env = self.prepare_install(Path(temp), current='local.inputmethod.Sunarae')
            result = run(['bash', 'scripts/install.sh', str(artifacts)], env=env)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(list(target.iterdir()), [])
            unrelated = target / 'Sunarae.app/Contents'
            unrelated.mkdir(parents=True)
            (unrelated / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'other.app'}))
            before = snapshot(target)
            state_path.write_text(json.dumps(dict(current='com.apple.keylayout.ABC', enabled=[])))
            result = run(['bash', 'scripts/install.sh', str(artifacts)], env=env)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(snapshot(target), before)

    def test_automatic_switch_and_late_reselection(self):
        for previous in ['local.inputmethod.Sunarae', 'local.inputmethod.Previous']:
            for switch in ['ready', 'failure', 'stuck']:
                with self.subTest(previous=previous, switch=switch), tempfile.TemporaryDirectory(prefix='Sunarae switch ') as temp:
                    artifacts, target, state_path, env = self.prepare_install(
                        Path(temp), previous=previous, enabled=True, current=previous, switch=switch)
                    before = snapshot(target)
                    result = run(['bash', 'scripts/install.sh', str(artifacts), '--switch-to-abc'], env=env)
                    if switch == 'ready':
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertEqual(json.loads(state_path.read_text())['current'], 'com.apple.keylayout.ABC')
                    else:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertEqual(snapshot(target), before)
        with tempfile.TemporaryDirectory(prefix='Sunarae reselect ') as temp:
            artifacts, target, _, env = self.prepare_install(Path(temp), previous='local.inputmethod.Sunarae', reselect=True)
            before = snapshot(target)
            result = run(['bash', 'scripts/install.sh', str(artifacts), '--switch-to-abc'], env=env)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(snapshot(target), before)

    def test_build_preserves_or_replaces_whole_dist(self):
        with tempfile.TemporaryDirectory(prefix='Sunarae build ') as temp:
            project = Path(temp) / 'project with spaces'
            project.mkdir()
            for directory in ['Sources', 'Resources', 'scripts', 'vendor', 'spec', 'docs']:
                shutil.copytree(ROOT / directory, project / directory)
            for filename in ['LICENSE', 'README.md', 'CONTRIBUTING.md', 'THIRD_PARTY.md']:
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
                        self.assertTrue(os.access(dist / 'Diagnose.command', os.X_OK))
                        self.assertTrue((dist / 'docs/IMPLEMENTATION.md').is_file())
                        for license_path in ['LICENSE', 'Sunarae.app/Contents/Resources/LICENSE']:
                            self.assertEqual((dist / license_path).read_bytes(), (project / 'LICENSE').read_bytes())
                        verified = run(['codesign', '--verify', '--deep', '--strict', str(dist / 'Sunarae.app')])
                        self.assertEqual(verified.returncode, 0, verified.stderr)
                    self.assertEqual(list(project.glob('.Sunarae-build.*')), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
