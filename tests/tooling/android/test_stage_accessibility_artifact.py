#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""android/lineage-24/tools/stage-accessibility-artifact.py.

The stager takes only an artifact whose files match its description, writes
the APKs and the filegroups the product imports, removes anything else the
destination held, and leaves an unchanged file's time alone so an unchanged
artifact rebuilds nothing.
"""

from __future__ import annotations

__import__("sys").dont_write_bytecode = True

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
STAGER = ROOT / "android/lineage-24/tools/stage-accessibility-artifact.py"
OVERLAY = ROOT / "android/lineage-24/overlay/accessibility/Android.bp"
PACKAGES = {"TalkBack.apk": "com.android.talkback", "eSpeakNG.apk": "com.reecedunn.espeak"}


def run(*arguments: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-B", str(STAGER), *arguments],
        stdin=subprocess.DEVNULL, capture_output=True, text=True,
    )


def make_artifact(root: Path, **changes) -> Path:
    artifact = root / "artifact"
    artifact.mkdir()
    apks = {}
    for name, package in PACKAGES.items():
        content = f"apk {name}".encode()
        (artifact / name).write_bytes(content)
        apks[name] = {"package": package, "sha256": hashlib.sha256(content).hexdigest()}
    description = {
        "schema": 1,
        "apks": apks,
        "source_trees": {source: "a" * 40 for source in ("talkback", "espeak-ng", "sonic")},
        "archives_sha256": "b" * 64,
    }
    description.update(changes)
    (artifact / "artifact.json").write_text(json.dumps(description), encoding="utf-8")
    return artifact


class StageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.aosp = self.root / "aosp"
        (self.aosp / ".repo").mkdir(parents=True)

    def tearDown(self) -> None:
        self.directory.cleanup()

    def test_a_matching_artifact_is_staged_and_stale_files_go(self) -> None:
        artifact = make_artifact(self.root)
        destination = self.aosp / "vendor/kernarium/accessibility"
        destination.mkdir(parents=True)
        (destination / "Old.apk").write_bytes(b"stale")
        result = run("--artifact", str(artifact), "--aosp-source", str(self.aosp))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(p.name for p in destination.iterdir()),
                         ["Android.bp", "TalkBack.apk", "artifact.json", "eSpeakNG.apk"])
        self.assertEqual((destination / "TalkBack.apk").read_bytes(), b"apk TalkBack.apk")

    def test_the_filegroups_are_those_the_overlay_imports(self) -> None:
        artifact = make_artifact(self.root)
        self.assertEqual(run("--artifact", str(artifact), "--aosp-source", str(self.aosp)).returncode, 0)
        staged = (self.aosp / "vendor/kernarium/accessibility/Android.bp").read_text()
        for line in OVERLAY.read_text().splitlines():
            if "apk:" in line:
                group = line.split('"')[1].lstrip(":")
                self.assertIn(f'name: "{group}"', staged)

    def test_an_unchanged_file_keeps_its_time(self) -> None:
        artifact = make_artifact(self.root)
        self.assertEqual(run("--artifact", str(artifact), "--aosp-source", str(self.aosp)).returncode, 0)
        apk = self.aosp / "vendor/kernarium/accessibility/TalkBack.apk"
        os.utime(apk, (1_000_000, 1_000_000))
        self.assertEqual(run("--artifact", str(artifact), "--aosp-source", str(self.aosp)).returncode, 0)
        self.assertEqual(apk.stat().st_mtime, 1_000_000)

    def test_a_changed_apk_is_refused(self) -> None:
        artifact = make_artifact(self.root)
        (artifact / "eSpeakNG.apk").write_bytes(b"changed")
        result = run("--artifact", str(artifact), "--check")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("eSpeakNG.apk differs from artifact.json", result.stderr)

    def test_another_package_is_refused(self) -> None:
        artifact = make_artifact(self.root)
        description = json.loads((artifact / "artifact.json").read_text())
        description["apks"]["TalkBack.apk"]["package"] = "com.google.android.marvin.talkback"
        (artifact / "artifact.json").write_text(json.dumps(description))
        result = run("--artifact", str(artifact), "--check")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be package com.android.talkback", result.stderr)

    def test_a_description_without_its_sources_is_refused(self) -> None:
        artifact = make_artifact(self.root, source_trees={"talkback": "a" * 40})
        result = run("--artifact", str(artifact), "--check")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must record the trees", result.stderr)

    def test_a_workspace_without_repo_metadata_is_refused(self) -> None:
        artifact = make_artifact(self.root)
        result = run("--artifact", str(artifact), "--aosp-source", str(self.root))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("AOSP Repo workspace", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
