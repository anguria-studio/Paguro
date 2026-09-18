"""Regression checks for required CI status and changed-file detection."""
import subprocess
import unittest
from unittest.mock import patch

from ci_quality import (build_needed, check_small_text, requires_build,
                        revision_range, small_text_findings, verify_jobs)


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


class ReadableTextFloorTests(unittest.TestCase):
    """Text a person reads is never smaller than 12 points."""

    def findings(self, source):
        return small_text_findings(source, 'Sample.swift')

    def test_a_small_system_style_on_text_is_reported(self):
        for style in ('.caption', '.caption2', '.footnote', '.subheadline'):
            with self.subTest(style=style):
                findings = self.findings(
                    f'Text("Saved")\n    .font({style})\n'
                )
                self.assertEqual(len(findings), 1)
                self.assertIn('Text', findings[0])

    def test_a_small_style_with_a_weight_is_reported(self):
        self.assertEqual(
            len(self.findings('Text(total)\n    .font(.caption.weight(.semibold))\n')),
            1
        )

    def test_an_explicit_size_under_the_floor_on_text_is_reported(self):
        findings = self.findings('Text(count)\n    .font(.system(size: 9, weight: .bold))\n')
        self.assertEqual(len(findings), 1)
        self.assertIn('size 9', findings[0])

    def test_a_symbol_keeps_its_own_glyph_size(self):
        self.assertEqual(self.findings(
            'Image(systemName: "bell.slash.fill")\n'
            '    .foregroundStyle(.secondary)\n'
            '    .font(.system(size: 9))\n'
        ), [])
        self.assertEqual(self.findings(
            'Image(systemName: "return")\n    .font(.caption2.weight(.medium))\n'
        ), [])

    def test_a_symbol_size_inside_a_multiline_font_is_allowed(self):
        self.assertEqual(self.findings(
            'Image(systemName: "bell.slash.fill")\n'
            '    .font(\n'
            '        isCompact\n'
            '            ? .system(size: 7, weight: .bold)\n'
            '            : .paguroRowAccessoryGlyph\n'
            '    )\n'
        ), [])

    def test_the_readable_size_passes(self):
        self.assertEqual(self.findings(
            'Text("Saved")\n    .font(.paguroCaption)\n'
            'Text(total)\n    .font(.paguroCaption.weight(.semibold).monospacedDigit())\n'
            'Text("Body")\n    .font(.system(size: 12))\n'
        ), [])

    def test_the_app_type_token_is_not_a_system_style(self):
        self.assertEqual(self.findings(
            'static let paguroCaption = Font.system(size: PaguroTypeSize.caption)\n'
        ), [])

    def test_a_size_that_follows_a_picture_is_a_proportion(self):
        self.assertEqual(self.findings(
            'Text(initial)\n    .font(.system(size: size * 0.44, weight: .semibold))\n'
        ), [])

    def test_every_branch_of_a_chosen_size_counts(self):
        findings = self.findings(
            'Text(emoji)\n    .font(.system(size: isCompact ? 11 : 15))\n'
        )
        self.assertEqual(len(findings), 1)
        self.assertIn('size 11', findings[0])
        self.assertEqual(self.findings(
            'Text(emoji)\n    .font(.system(size: isCompact ? 12 : 15))\n'
        ), [])

    def test_an_appkit_font_under_the_floor_is_reported(self):
        self.assertEqual(len(self.findings(
            '.font: NSFont.systemFont(ofSize: 11),\n'
        )), 1)

    def test_a_font_with_no_named_subject_is_reported(self):
        findings = self.findings('.font(.caption)\n')
        self.assertEqual(len(findings), 1)
        self.assertIn('unnamed view', findings[0])

    def test_the_marker_allows_a_fixed_geometry(self):
        self.assertEqual(self.findings(
            'Text(count)\n'
            '    // small-text-ok: the capsule cannot hold the readable size\n'
            '    .font(.system(size: 9))\n'
        ), [])
        self.assertEqual(self.findings(
            'Text(count)\n'
            '    .font(.system(size: 9))  // small-text-ok: a fixed capsule\n'
        ), [])

    def test_the_app_sources_hold_the_floor(self):
        self.assertEqual(check_small_text('Paguro'), [])


if __name__ == '__main__':
    unittest.main()
