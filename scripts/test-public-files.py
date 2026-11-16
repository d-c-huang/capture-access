#!/usr/bin/env python3
import importlib.util
import pathlib
import plistlib
import subprocess
import tempfile
import unittest

path = pathlib.Path(__file__).with_name("check-public-files.py")
spec = importlib.util.spec_from_file_location("public_check", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

version_spec = importlib.util.spec_from_file_location("version_check", path.with_name("check-version.py"))
version_module = importlib.util.module_from_spec(version_spec)
version_spec.loader.exec_module(version_module)


class PublicFilesTests(unittest.TestCase):
    def test_source_and_explicit_demo_svg_are_allowed(self):
        self.assertEqual(module.inspect_file("macos/Sources/Example.swift", b"import Foundation\n"), [])
        svg = '<svg xmlns="http://www.w3.org/2000/svg"><text>虚构示意图</text></svg>'.encode()
        self.assertEqual(module.inspect_file("docs/images/example.svg", svg), [])

    def test_capture_and_local_report_are_rejected(self):
        for path in ["macos/dist/image.png", "docs/images/real.png", "macos/TEST-REPORT.local.txt", ".env.production"]:
            self.assertTrue(module.inspect_file(path, b"example"))

    def test_personal_path_and_credential_are_rejected_without_printing_values(self):
        value = "/" + "Users/" + "PrivatePerson/" + "file.txt"
        self.assertIn("personal Mac path", module.inspect_file("note.txt", value.encode()))
        credential = "gh" + "p_" + "A" * 36
        self.assertIn("GitHub credential", module.inspect_file("note.txt", credential.encode()))

    def test_embedded_or_external_svg_content_is_rejected(self):
        svg = '<svg xmlns="http://www.w3.org/2000/svg"><text>示意</text><image href="https://example.com/image.png"/></svg>'.encode()
        self.assertTrue(module.inspect_file("docs/images/example.svg", svg))

    def test_svg_event_handlers_and_external_css_are_rejected(self):
        elements = [
            '<rect onload="alert(1)"/>',
            '<rect oNcLiCk="alert(1)"/>',
            '<rect style="fill: url(https://example.com/a.svg)"/>',
            '<style>rect { fill: URL(\'https://example.com/a.svg\'); }</style>',
            '<style>@import "https://example.com/a.css";</style>',
            '<style>@im/**/port "https://example.com/a.css";</style>',
            '<style>rect { fill: u\\72l(https://example.com/a.svg); }</style>',
            '<rect fill="url(data:image/svg+xml;base64,AAAA)"/>',
        ]
        for element in elements:
            with self.subTest(element=element):
                svg = '<svg xmlns="http://www.w3.org/2000/svg"><text>示意</text>' + element + '</svg>'
                self.assertTrue(module.inspect_file("docs/images/example.svg", svg.encode()))

    def test_svg_document_types_and_stylesheets_are_rejected(self):
        for prefix in ['<!DOCTYPE svg [<!ENTITY label "示意">]>',
                       '<?xml-stylesheet href="https://example.com/a.css"?>']:
            with self.subTest(prefix=prefix):
                svg = prefix + '<svg xmlns="http://www.w3.org/2000/svg"><text>示意</text></svg>'
                self.assertTrue(module.inspect_file("docs/images/example.svg", svg.encode()))

    def test_svg_local_gradient_references_are_allowed(self):
        svg = '''<svg xmlns="http://www.w3.org/2000/svg"><text>示意</text>
          <defs><linearGradient id="shade"/></defs>
          <rect fill="url(#shade)"/><style>rect { fill: url( '#shade' ); }</style>
        </svg>'''
        self.assertEqual(module.inspect_file("docs/images/example.svg", svg.encode()), [])


class StagedFilesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.git("init", "-q")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, stderr=subprocess.PIPE)

    def test_staged_secret_is_detected_even_when_working_copy_is_clean_or_missing(self):
        path = self.root / "note.txt"
        path.write_text("gh" + "p_" + "A" * 36)
        self.git("add", "note.txt")
        path.write_text("safe replacement")
        self.assertEqual(module.scan_files(self.root)[1], [])
        expected = [("note.txt", "GitHub credential")]
        self.assertEqual(module.scan_files(self.root, staged=True), (1, expected))
        path.unlink()
        self.assertEqual(module.scan_files(self.root, staged=True), (1, expected))

    def test_unstaged_content_does_not_replace_staged_content(self):
        path = self.root / "note.txt"
        path.write_text("safe staged file")
        self.git("add", "note.txt")
        path.write_text("gh" + "p_" + "A" * 36)
        (self.root / "extra.txt").write_text("untracked file")
        self.assertEqual(module.scan_files(self.root, staged=True), (1, []))
        self.assertIn(("note.txt", "GitHub credential"), module.scan_files(self.root)[1])

    def test_staged_symlink_is_detected_after_working_copy_becomes_regular_file(self):
        path = self.root / "link.txt"
        path.symlink_to("missing.txt")
        self.git("add", "link.txt")
        self.assertEqual(module.scan_files(self.root)[1], [("link.txt", "symlinks require explicit review")])
        path.unlink()
        path.write_text("regular working copy")
        self.assertEqual(module.scan_files(self.root)[1], [])
        self.assertEqual(module.scan_files(self.root, staged=True)[1], [("link.txt", "symlinks require explicit review")])


class VersionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        (self.root / "VERSION").write_text("0.8.0\n")
        (self.root / "macos/Resources").mkdir(parents=True)
        (self.root / "macos/Resources/Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "0.8.0"}))
        (self.root / "windows/src").mkdir(parents=True)
        self.updates = self.root / "windows/src/Updates.cs"
        self.app = self.root / "windows/src/App.cs"
        self.updates.write_text('internal const string CurrentVersion = "0.8.0";')
        self.app.write_text('[assembly: AssemblyVersion("0.8.0.0")]\n[assembly: AssemblyFileVersion("0.8.0.0")]')

    def test_matching_product_and_assembly_versions_pass(self):
        self.assertEqual(version_module.check_versions(self.root), "0.8.0")

    def test_unrelated_or_commented_version_cannot_mask_stale_current_version(self):
        self.updates.write_text('internal const string CurrentVersion = "0.7.0";\n'
                                'internal const string OtherVersion = "0.8.0";\n'
                                '// const string CurrentVersion = "0.8.0";')
        with self.assertRaisesRegex(ValueError, "CurrentVersion"):
            version_module.check_versions(self.root)

    def test_both_assembly_versions_must_match(self):
        for name in ("AssemblyVersion", "AssemblyFileVersion"):
            with self.subTest(name=name):
                original = self.app.read_text()
                self.app.write_text(original.replace(name + '("0.8.0.0")', name + '("0.7.0.0")'))
                with self.assertRaisesRegex(ValueError, name):
                    version_module.check_versions(self.root)
                self.app.write_text(original)


if __name__ == "__main__":
    unittest.main()
