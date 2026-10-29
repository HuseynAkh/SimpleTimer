#!/usr/bin/env python3
"""Exercise publishing guards in disposable local repositories; never push."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

SOURCE = pathlib.Path(__file__).resolve().parent.parent
SAFE = '12345+demo@users.noreply.github.com'
PRIVATE = 'writer' + '@' + 'mail.test'


class PublicGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='simpletimer-guard-')
        self.root = pathlib.Path(self.temp.name)
        (self.root / 'scripts').mkdir()
        shutil.copy2(SOURCE / 'scripts/audit-public.py', self.root / 'scripts/audit-public.py')
        shutil.copytree(SOURCE / '.githooks', self.root / '.githooks')
        self.env = os.environ.copy()
        for key in list(self.env):
            if key.startswith(('GIT_AUTHOR_', 'GIT_COMMITTER_')):
                del self.env[key]
        self.run_git('init', '-q')
        self.run_git('config', 'user.name', 'Example')
        self.run_git('config', 'user.email', SAFE)
        self.run_git('config', 'commit.gpgsign', 'false')
        self.run_git('config', 'core.hooksPath', '.githooks')
        (self.root / 'README.md').write_text('Sample project\n')
        self.run_git('add', '.')
        self.run_git('commit', '-qm', 'Initial version')

    def tearDown(self):
        self.temp.cleanup()

    def command(self, args, *, env=None, input=None):
        return subprocess.run(args, cwd=self.root, env=env or self.env, input=input,
                              text=True, capture_output=True)

    def run_git(self, *args, env=None):
        result = self.command(['git', *args], env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def audit(self, *args):
        return self.command(['python3', 'scripts/audit-public.py', *args])

    def test_clean_history_passes(self):
        self.assertEqual(self.audit('--history', 'HEAD').returncode, 0)

    def test_effective_author_override_is_blocked(self):
        env = dict(self.env, GIT_AUTHOR_EMAIL=PRIVATE)
        result = self.command(['git', 'commit', '--allow-empty', '-qm', 'Example'], env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(PRIVATE, result.stderr)

    def test_effective_committer_override_is_blocked(self):
        env = dict(self.env, GIT_COMMITTER_EMAIL=PRIVATE)
        self.assertNotEqual(self.command(['git', 'commit', '--allow-empty', '-qm', 'Example'], env=env).returncode, 0)

    def test_personal_coauthor_is_blocked(self):
        message = 'Example\n\nCo-authored-by: Example <' + PRIVATE + '>'
        self.assertNotEqual(self.command(['git', 'commit', '--allow-empty', '-qm', message]).returncode, 0)

    def test_staged_content_cannot_be_hidden_by_working_copy(self):
        sample = self.root / 'sample.txt'
        sample.write_text(PRIVATE)
        self.run_git('add', 'sample.txt')
        sample.write_text('Safe working copy\n')
        result = self.command(['git', 'commit', '-qm', 'Example'])
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(PRIVATE, result.stderr)

    def test_private_artifact_is_blocked(self):
        (self.root / 'sample.p8').write_text('Synthetic test only\n')
        self.run_git('add', 'sample.p8')
        self.assertNotEqual(self.audit('--staged').returncode, 0)

    def test_older_commit_blocks_push_even_when_tip_is_clean(self):
        env = dict(self.env, GIT_AUTHOR_EMAIL=PRIVATE, GIT_COMMITTER_EMAIL=PRIVATE)
        self.run_git('commit', '--no-verify', '--allow-empty', '-qm', 'Unsafe test identity', env=env)
        self.run_git('commit', '--allow-empty', '-qm', 'Clean tip')
        sha = self.run_git('rev-parse', 'HEAD')
        line = 'refs/heads/main ' + sha + ' refs/heads/main ' + '0' * 40 + '\n'
        result = self.command(['.githooks/pre-push', 'origin', 'unused'], input=line)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(PRIVATE, result.stderr)

    def test_annotated_tag_identity_is_audited(self):
        env = dict(self.env, GIT_COMMITTER_EMAIL=PRIVATE)
        self.run_git('tag', '-a', 'sample-tag', '-m', 'Test tag', env=env)
        self.assertNotEqual(self.audit('--history', 'sample-tag').returncode, 0)

    def test_nested_tag_identity_is_audited(self):
        env = dict(self.env, GIT_COMMITTER_EMAIL=PRIVATE)
        self.run_git('tag', '-a', 'inner-tag', '-m', 'Test tag', env=env)
        self.run_git('tag', '-a', 'outer-tag', 'inner-tag', '-m', 'Clean outer tag')
        self.assertNotEqual(self.audit('--history', 'outer-tag').returncode, 0)

    def test_invalid_ref_fails_closed(self):
        self.assertNotEqual(self.audit('--history', 'missing-ref').returncode, 0)


if __name__ == '__main__':
    unittest.main()
