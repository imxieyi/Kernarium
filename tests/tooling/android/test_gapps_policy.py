#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Reject incomplete Google images and USB migration without hardware support."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import unittest
import tempfile
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("gapps_policy", ROOT / "android/lineage-24/tools/gapps_policy.py")
gapps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gapps)


class GappsPolicyTests(unittest.TestCase):
    def setUp(self):
        self.pin = {**gapps.policy(), "gms_apex_sha256": hashlib.sha256(b"signed apex").hexdigest()}
        self.files = {name: b"apk" for name in gapps.REQUIRED}
        self.files[gapps.GMS_APEX] = b"signed apex"
        self.files[gapps.MARKER] = json.dumps(self.pin).encode()

    def verify(self, files):
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive:
            for name, payload in files.items():
                archive.writestr(name, payload)
        with patch.object(gapps, "policy", return_value=self.pin), zipfile.ZipFile(data) as archive:
            gapps.verify_target_files(archive)

    def test_default_image(self):
        self.verify({})

    def test_complete_gapps_image(self):
        self.verify(self.files)

    def test_missing_package(self):
        for name in gapps.REQUIRED:
            with self.subTest(name=name), self.assertRaisesRegex(SystemExit, "missing"):
                self.verify({k: v for k, v in self.files.items() if k != name})

    def test_unmarked_payload(self):
        with self.assertRaisesRegex(SystemExit, "without.*provenance"):
            self.verify({k: v for k, v in self.files.items() if k != gapps.MARKER})

    def test_wrong_provenance(self):
        self.files[gapps.MARKER] = b'{}'
        with self.assertRaisesRegex(SystemExit, "provenance differs"):
            self.verify(self.files)

    def test_modified_apex(self):
        self.files[gapps.GMS_APEX] += b"modified"
        with self.assertRaisesRegex(SystemExit, "presigned"):
            self.verify(self.files)

    def test_switch_in_any_partition(self):
        for partition in ("SYSTEM", "SYSTEM_EXT", "PRODUCT", "VENDOR"):
            with self.subTest(partition=partition), self.assertRaisesRegex(SystemExit, "Android Switch"):
                self.verify({**self.files, f"{partition}/priv-app/GoogleRestore/GoogleRestore.apk": b"apk"})

    def test_cable_feature_in_renamed_xml(self):
        with self.assertRaisesRegex(SystemExit, "cable migration feature"):
            self.verify({**self.files, "PRODUCT/etc/sysconfig/renamed.xml":
                         b'<config><feature name="com.google.android.feature.D2D_CABLE_MIGRATION_FEATURE"/></config>'})

    def test_cable_feature_filename(self):
        with self.assertRaisesRegex(SystemExit, "cable migration must"):
            self.verify({**self.files, "PRODUCT/etc/sysconfig/d2d_cable_migration_feature.xml": b"xml"})


    def test_source_checkout_validation(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            for name in ("arm64/arm64-vendor.mk", "arm64/Android.bp", "common/common-vendor.mk"):
                file = source / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.touch()
            replies = {
                ("rev-parse", "--show-toplevel"): str(source),
                ("rev-parse", "HEAD"): self.pin["revision"],
                ("status", "--porcelain", "--untracked-files=all"): "",
                ("ls-files", "-v"): "H arm64/Android.bp",
            }
            def run_git(root, *args):
                self.assertEqual(root, source)
                return replies[args]
            with patch.object(gapps, "git", side_effect=run_git):
                gapps.verify_source(source)
                for key, value, error in (
                    (("rev-parse", "HEAD"), "0" * 40, "revision"),
                    (("status", "--porcelain", "--untracked-files=all"), " M arm64/Android.bp", "clean"),
                    (("ls-files", "-v"), "S arm64/Android.bp", "sparse"),
                ):
                    with self.subTest(error=error):
                        old = replies[key]
                        replies[key] = value
                        with self.assertRaisesRegex(SystemExit, error):
                            gapps.verify_source(source)
                        replies[key] = old


if __name__ == "__main__":
    unittest.main()
