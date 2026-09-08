"""Release launcher tests use disposable local remotes; no GitHub/Apple calls."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('publish', SOURCE / 'scripts/publish-release.py')
publish = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publish)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.repo = base / 'repo'
        self.remote = base / 'remote.git'
        def cmd(*args):
            subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        cmd('git', 'init', '--bare', str(self.remote))
        cmd('git', 'init', '-b', 'main', str(self.repo))
        for key, value in [('user.name', 'Release Test'), ('user.email', 'test@example.invalid'), ('commit.gpgsign', 'false'), ('tag.gpgsign', 'false')]:
            cmd('git', '-C', str(self.repo), 'config', key, value)
        (self.repo / 'Resources').mkdir()
        shutil.copy(SOURCE / 'Resources/Info.plist', self.repo / 'Resources/Info.plist')
        for name in ('test.sh', 'build.sh'):
            path = self.repo / name
            path.write_text('#!/bin/sh\nexit 0\n')
            path.chmod(0o755)
        cmd('git', '-C', str(self.repo), 'add', '.')
        cmd('git', '-C', str(self.repo), 'commit', '-m', 'Initial')
        self.current = plistlib.loads((self.repo / 'Resources/Info.plist').read_bytes())['CFBundleShortVersionString']
        cmd('git', '-C', str(self.repo), 'remote', 'add', 'origin', str(self.remote))
        cmd('git', '-C', str(self.repo), 'push', '-u', 'origin', 'main')
        self.root_patch = patch.object(publish, 'ROOT', self.repo)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.actual_run = publish.run
        self.secrets = publish.SECRETS
        self.fail_build = False
        self.fail_push = False
        def fake_run(*args, **kwargs):
            if args == ('git', 'remote', 'get-url', 'origin'):
                return 'git@github.com:justin-schroeder/liberator.git\n'
            if args[0] == 'gh':
                return json.dumps([{'name': name} for name in self.secrets])
            if (args[0] == './build.sh' and self.fail_build) or (args[:2] == ('git', 'push') and self.fail_push):
                raise subprocess.CalledProcessError(1, args)
            return self.actual_run(*args, **kwargs)
        self.run_patch = patch.object(publish, 'run', fake_run)
        self.run_patch.start()
        self.addCleanup(self.run_patch.stop)

    def tag(self, bump):
        return 'v' + publish.next_version(self.current, bump)

    def launch(self, *args):
        with patch('sys.argv', ['publish-release', *args]):
            publish.main()

    def test_semver(self):
        for bump, expected in [('patch', '1.2.4'), ('minor', '1.3.0'), ('major', '2.0.0'), ('4.5.6', '4.5.6')]:
            self.assertEqual(publish.next_version('1.2.3', bump), expected)
        for bad in ['1.2.3', '0.9.9', '01.2.4', '2.0.0-beta', '2.0.0+build', 'patch;echo bad']:
            with self.assertRaises(ValueError):
                publish.next_version('1.2.3', bad)

    def test_atomic_release(self):
        self.launch('minor', '--yes')
        self.assertEqual(publish.git('status', '--porcelain'), '')
        self.assertEqual(publish.git('rev-parse', 'HEAD'), publish.git('rev-parse', 'origin/main'))
        self.assertEqual(publish.git('cat-file', '-t', self.tag('minor')), 'tag')
        self.assertIn('refs/tags/' + self.tag('minor'), publish.git('ls-remote', 'origin'))

    def test_dirty_refused(self):
        (self.repo / 'untracked').write_text('work')
        with self.assertRaises(ValueError): self.launch('patch', '--yes')
        self.assertEqual(publish.git('tag'), '')

    def test_dry_run_and_missing_secrets(self):
        self.secrets = set()
        head = publish.git('rev-parse', 'HEAD')
        self.launch('patch', '--dry-run')
        with self.assertRaises(ValueError): self.launch('patch', '--yes')
        self.assertEqual(publish.git('rev-parse', 'HEAD'), head)
        self.assertEqual(publish.git('status', '--porcelain'), '')

    def test_build_failure_does_not_mutate(self):
        self.fail_build = True
        with self.assertRaises(subprocess.CalledProcessError): self.launch('patch', '--yes')
        self.assertEqual(publish.git('status', '--porcelain'), '')
        self.assertEqual(publish.git('tag'), '')

    def test_push_failure_keeps_local_release(self):
        self.fail_push = True
        with self.assertRaises(subprocess.CalledProcessError): self.launch('patch', '--yes')
        self.assertEqual(publish.git('tag'), self.tag('patch'))
        self.assertNotIn('refs/tags/' + self.tag('patch'), publish.git('ls-remote', 'origin'))

    def test_noninteractive_requires_explicit_intent(self):
        with patch('sys.stdin.isatty', return_value=False):
            for args in [(), ('--yes',), ('patch',)]:
                with self.assertRaises(SystemExit): self.launch(*args)

    def test_interactive_cancel(self):
        head = publish.git('rev-parse', 'HEAD')
        with patch('sys.stdin.isatty', return_value=True), patch('builtins.input', side_effect=['minor', 'n']):
            self.launch()
        self.assertEqual(publish.git('rev-parse', 'HEAD'), head)
        self.assertEqual(publish.git('tag'), '')

    def test_unsynchronized_main_refused(self):
        publish.git('commit', '--allow-empty', '-m', 'Unpushed')
        with self.assertRaises(ValueError): self.launch('patch', '--yes')

    def test_existing_tag_refused(self):
        publish.git('tag', self.tag('patch'))
        with self.assertRaises(ValueError): self.launch('patch', '--yes')


if __name__ == '__main__':
    unittest.main()
