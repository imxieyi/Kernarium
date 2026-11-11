#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Validate the optional, locally supplied MindTheGapps input and its image contract."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

POLICY = Path(__file__).resolve().parents[1] / "overlay/config/gapps.json"
MARKER = "PRODUCT/etc/andarium-gapps.json"
GMS_APEX = "PRODUCT/apex/com.google.android.gmssystem.prodvic.apex"
REQUIRED = frozenset({
    GMS_APEX,
    "PRODUCT/priv-app/Phonesky/Phonesky.apk",
    "SYSTEM_EXT/priv-app/SetupWizard/SetupWizard.apk",
    "SYSTEM_EXT/priv-app/GoogleServicesFramework/GoogleServicesFramework.apk",
})


def fail(message: str) -> None:
    raise SystemExit(f"GApps policy: {message}")


def policy() -> dict:
    return json.loads(POLICY.read_text(encoding="utf-8"))


def git(source: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-c", "core.fsmonitor=false", "-C", str(source), *args],
        check=True, capture_output=True, text=True, timeout=120,
    )
    return result.stdout.strip()


def verify_source(source: Path) -> None:
    if not source.is_dir() or source.is_symlink():
        fail("vendor/gapps must be a regular, complete source checkout")
    if Path(git(source, "rev-parse", "--show-toplevel")).resolve() != source.resolve():
        fail("vendor/gapps must be its own Git checkout")
    if git(source, "rev-parse", "HEAD") != policy()["revision"]:
        fail("vendor/gapps revision does not match the product pin")
    if git(source, "status", "--porcelain", "--untracked-files=all"):
        fail("vendor/gapps must be clean, including untracked files")
    if any(line.startswith("S ") for line in git(source, "ls-files", "-v").splitlines()):
        fail("a sparse vendor/gapps checkout is not a complete build input")
    for name in ("arm64/arm64-vendor.mk", "arm64/Android.bp", "common/common-vendor.mk"):
        if not (source / name).is_file():
            fail(f"vendor/gapps lacks {name}")


def verify_apex(payload: bytes) -> None:
    if hashlib.sha256(payload).hexdigest() != policy()["gms_apex_sha256"]:
        fail("Play services APEX differs from the pinned presigned input")


def verify_target_files(archive: zipfile.ZipFile) -> None:
    names = set(archive.namelist())
    enabled = MARKER in names
    present = names & REQUIRED
    if not enabled:
        if present:
            fail("Google payload is present without the product's GApps provenance")
        return
    try:
        recorded = json.loads(archive.read(MARKER))
    except (ValueError, UnicodeError) as error:
        fail(f"invalid GApps provenance: {error}")
    if recorded != policy():
        fail("GApps provenance differs from the product pin")
    if missing := REQUIRED - names:
        fail("required Google payload missing: " + ", ".join(sorted(missing)))
    # Match all target partitions, not only the current upstream install path.
    for name in names:
        if "/GoogleRestore/" in name or name.endswith("/GoogleRestore.apk"):
            fail("Android Switch is incompatible with the guest's absent USB service")
        if name.endswith("/d2d_cable_migration_feature.xml"):
            fail("cable migration must not be advertised")
        if name.startswith(("SYSTEM/", "SYSTEM_EXT/", "PRODUCT/", "VENDOR/", "ODM/")):
            if "/etc/" in name and name.endswith(".xml"):
                if b"com.google.android.feature.D2D_CABLE_MIGRATION_FEATURE" in archive.read(name):
                    fail("cable migration feature remains in " + name)
    verify_apex(archive.read(GMS_APEX))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    args = parser.parse_args()
    try:
        verify_source(args.source)
    except (OSError, subprocess.SubprocessError) as error:
        fail(f"cannot verify local GApps checkout: {error}")
    print("verified pinned local MindTheGapps source")


if __name__ == "__main__":
    main()
