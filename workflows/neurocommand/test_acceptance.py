"""Local checks of the real menu builder and acceptance input contract.

These do not substitute for Linux/KVM, Apptainer or CVMFS acceptance.
"""

import configparser
import contextlib
import os
from pathlib import Path
import tempfile
import unittest

import acceptance


class AcceptanceTests(unittest.TestCase):
    def test_candidate_install_preserves_source_and_isolates_generated_paths(self):
        source = Path(__file__).resolve().parents[2] / "neurocommand"
        before = acceptance.tree_hash(source)
        with tempfile.TemporaryDirectory(prefix="sa2-neurocommand-local-") as directory:
            root = Path(directory).resolve()
            # Keep the real builder's long informational log out of test output.
            with (root / "builder.log").open("w") as log, contextlib.redirect_stderr(log):
                candidate, installed, count = acceptance.install(source, root, dict(os.environ))
            self.assertGreater(count, 0)
            self.assertNotEqual(candidate, source)
            config = configparser.ConfigParser()
            config.read(installed / "config.ini")
            self.assertEqual(config["neurodesk"]["edit"], "n")
            for key in ("installdir", "appdir", "deskdir"):
                self.assertTrue(Path(config["neurodesk"][key]).is_relative_to(root))
        self.assertEqual(acceptance.tree_hash(source), before)

    def test_spec_requires_explicit_artifacts_and_expected_scientific_output(self):
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "candidate.simg"
            image.write_bytes(b"validation fixture, not a runnable SIF")
            spec = {"container": "demo_1.0_20260101.simg", "local_sif": str(image),
                    "sif_sha256": acceptance.sha256(image), "stdout_sha256": "0" * 64,
                    "image_files": {"/opt/tool": "1" * 64},
                    "command": ["scientific-check", "argument with spaces"]}
            self.assertEqual(acceptance.validate_spec(spec, "local"), image)
            for patch in ({"stdout_sha256": ""}, {"container": "../../escape.simg"},
                          {"command": "implicit shell"}, {"command": ["/usr/bin/true"]},
                          {"image_files": {}}, {"image_files": {"/../escape": "1" * 64}},
                          {"local_sif": "missing"}, {"cvmfs_sif": str(image)}):
                with self.subTest(patch=patch), self.assertRaises(ValueError):
                    acceptance.validate_spec(dict(spec, **patch), "cvmfs" if "cvmfs_sif" in patch else "local")

    def test_source_identity_includes_content_and_executable_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "candidate.sh"
            script.write_text("original")
            original = acceptance.tree_hash(root)
            script.write_text("changed")
            self.assertNotEqual(original, acceptance.tree_hash(root))
            script.write_text("original")
            script.chmod(script.stat().st_mode ^ 0o100)
            self.assertNotEqual(original, acceptance.tree_hash(root))
            (root / "link").symlink_to(script)
            with self.assertRaises(ValueError):
                acceptance.tree_hash(root)


if __name__ == "__main__":
    unittest.main()
