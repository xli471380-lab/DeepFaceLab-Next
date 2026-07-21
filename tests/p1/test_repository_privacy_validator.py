from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = (
    Path(__file__).resolve().parents[2]
    / "scripts"
    / "p1"
    / "repository_privacy_validator.py"
)
SPEC = importlib.util.spec_from_file_location("repository_privacy_validator", MODULE_PATH)
if SPEC is None or SPEC.loader is None:  # pragma: no cover
    raise RuntimeError(f"Unable to load validator module: {MODULE_PATH}")
validator = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = validator
SPEC.loader.exec_module(validator)


class RepositoryPrivacyValidatorTests(unittest.TestCase):
    def test_clean_text_files_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "README.md").write_text("safe\n", encoding="utf-8")
            findings = validator.scan_tracked_paths(
                root,
                ["README.md", "scripts/example.py"],
            )
            self.assertEqual([], findings)

    def test_windows_separators_are_normalized(self) -> None:
        self.assertEqual(
            "config/local/profile.psd1",
            validator.normalize_repo_path(r".\config\local\profile.psd1"),
        )

    def test_local_profile_root_is_blocked(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            findings = validator.scan_tracked_paths(
                Path(temporary),
                [r"config\local\machine.psd1"],
            )
        self.assertEqual(1, len(findings))
        self.assertEqual("P1_PRIVACY_PROHIBITED_ROOT", findings[0].code)

    def test_dfm_file_is_blocked(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            findings = validator.scan_tracked_paths(
                Path(temporary),
                ["fixtures/p0gate_model.dfm"],
            )
        self.assertEqual(1, len(findings))
        self.assertEqual("P1_PRIVACY_PROHIBITED_EXTENSION", findings[0].code)

    def test_secret_filename_is_blocked(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            findings = validator.scan_tracked_paths(
                Path(temporary),
                ["config/credentials.json"],
            )
        self.assertEqual(1, len(findings))
        self.assertEqual("P1_PRIVACY_SECRET_FILENAME", findings[0].code)
        self.assertFalse(findings[0].retry_safe)

    def test_oversized_nontext_file_is_blocked(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "fixtures" / "payload.bin"
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b"1234567890")
            findings = validator.scan_tracked_paths(
                root,
                ["fixtures/payload.bin"],
                max_nontext_bytes=4,
            )
        self.assertEqual(1, len(findings))
        self.assertEqual("P1_PRIVACY_OVERSIZED_NON_TEXT", findings[0].code)

    def test_report_has_stable_safety_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            findings = validator.scan_tracked_paths(root, ["README.md"])
            report = validator.build_report(
                repo_root=root,
                tracked_paths=["README.md"],
                findings=findings,
            )
        self.assertEqual("passed", report["status"])
        self.assertFalse(report["safety"]["media_contents_read"])
        self.assertFalse(report["safety"]["checkpoint_contents_read"])
        self.assertFalse(report["safety"]["dfm_contents_read"])
        json.dumps(report)

    def test_atomic_json_writer_removes_partial_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "report.json"
            validator.write_json_atomic(output, {"status": "passed"})
            self.assertTrue(output.is_file())
            self.assertFalse((Path(str(output) + ".partial")).exists())
            self.assertEqual(
                "passed",
                json.loads(output.read_text(encoding="utf-8"))["status"],
            )


if __name__ == "__main__":
    unittest.main()
