"""Regression checks for required CI status and changed-file detection."""
import subprocess
import unittest
from unittest.mock import patch

from ci_quality import build_needed, requires_build, revision_range, verify_jobs


class CIQualityTests(unittest.TestCase):
    def test_documentation_does_not_need_a_macos_build(self):
        self.assertFalse(requires_build(['README.md', 'CHANGELOG.md',
                         'docs/images/demo.webp', '.vale/styles/Words.yml', '.vale.ini']))

    def test_code_or_unknown_files_require_a_build(self):
        for path in ('Paguro/App/AppState.swift', 'Core/Package.swift', 'project.yml',
                     '.github/workflows/code-quality.yml', 'scripts/lint_docs.sh',
                     'Configuration/DirectInfo.plist', 'new-file'):
            with self.subTest(path=path):
                self.assertTrue(requires_build(['README.md', path]))

    def test_pull_requests_compare_from_the_merge_base(self):
        event = {'pull_request': {'base': {'sha': 'a' * 40}, 'head': {'sha': 'b' * 40}}}
        self.assertEqual(revision_range('pull_request', event), 'a' * 40 + '...' + 'b' * 40)

    def test_pushes_compare_the_whole_pushed_range(self):
        self.assertEqual(revision_range('push', {'before': 'a' * 40, 'after': 'b' * 40}),
                         'a' * 40 + '..' + 'b' * 40)

    def test_new_branches_require_tests(self):
        self.assertTrue(build_needed('push', {'before': '0' * 40, 'after': 'b' * 40}))

    def test_unknown_events_and_invalid_revisions_fail(self):
        with self.assertRaises(ValueError):
            revision_range('workflow_dispatch', {})
        for revision in ('--output=README.md', '', None, 'abcd'):
            with self.subTest(revision=revision), self.assertRaises(ValueError):
                revision_range('push', {'before': revision, 'after': 'b' * 40})

    @patch('ci_quality.subprocess.run')
    def test_renames_include_the_old_code_path(self, run):
        run.return_value.stdout = b'Paguro/Old.swift\0docs/Old.swift\0'
        self.assertTrue(build_needed('push', {'before': 'a' * 40, 'after': 'b' * 40}))
        self.assertIn('--no-renames', run.call_args.args[0])

    @patch('ci_quality.subprocess.run')
    def test_filenames_with_newlines_are_not_split_into_fake_paths(self, run):
        run.return_value.stdout = b'docs/example\nfile.txt\0'
        self.assertFalse(build_needed('push', {'before': 'a' * 40, 'after': 'b' * 40}))

    @patch('ci_quality.subprocess.run', side_effect=subprocess.CalledProcessError(128, 'git'))
    def test_missing_git_history_fails_instead_of_skipping_tests(self, run):
        with self.assertRaises(subprocess.CalledProcessError):
            build_needed('push', {'before': 'a' * 40, 'after': 'b' * 40})

    def test_required_result_accepts_only_the_expected_job_states(self):
        for detection in ('success', 'failure', 'cancelled', 'skipped'):
            for decision in ('true', 'false', '', None):
                for tests in ('success', 'failure', 'cancelled', 'skipped'):
                    needs = {'changes': {'result': detection, 'outputs': {'build': decision}},
                             'test': {'result': tests}}
                    allowed = (detection == 'success' and
                               ((decision == 'true' and tests == 'success') or
                                (decision == 'false' and tests in ('success', 'skipped'))))
                    with self.subTest(detection=detection, decision=decision, tests=tests):
                        if allowed:
                            verify_jobs(needs)
                        else:
                            with self.assertRaises(ValueError):
                                verify_jobs(needs)

    def test_missing_job_results_fail(self):
        for needs in ({}, {'changes': {'result': 'success', 'outputs': {'build': 'true'}}}):
            with self.subTest(needs=needs), self.assertRaises(KeyError):
                verify_jobs(needs)


if __name__ == '__main__':
    unittest.main()
