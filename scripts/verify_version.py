#!/usr/bin/env python3
"""Verify that a released IPA matches its release tag.

Checks:
  * Payload/*.app/Info.plist exists and parses
  * CFBundleShortVersionString == tag (without leading "v")
  * CFBundleVersion is numeric
  * CFBundleIdentifier == jp.haruki0420.p2pgps
  * no Xcode debug dylib (`*.debug.dylib` / `__preview.dylib`) is bundled

Usage:
  python3 scripts/verify_version.py --ipa p2pgps-ios-v1.0.5-unsigned.ipa --tag v1.0.5
"""

from __future__ import annotations

import argparse
import plistlib
import sys
import zipfile
from pathlib import Path

EXPECTED_BUNDLE_ID = "jp.haruki0420.p2pgps"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ipa", type=Path, required=True)
    parser.add_argument("--tag", required=True, help="Release tag, e.g. v1.0.5")
    args = parser.parse_args()

    if not args.ipa.exists():
        print(f"error: IPA not found: {args.ipa}", file=sys.stderr)
        return 1

    expected_version = args.tag[1:] if args.tag.startswith("v") else args.tag
    errors: list[str] = []

    with zipfile.ZipFile(args.ipa) as archive:
        names = archive.namelist()

        info_entries = [n for n in names if n.endswith(".app/Info.plist")]
        if len(info_entries) != 1:
            print(f"error: expected exactly one app Info.plist, found {info_entries}", file=sys.stderr)
            return 1

        info = plistlib.loads(archive.read(info_entries[0]))

        version = info.get("CFBundleShortVersionString")
        build = info.get("CFBundleVersion")
        bundle_id = info.get("CFBundleIdentifier")

        if version != expected_version:
            errors.append(f"CFBundleShortVersionString is {version!r}, expected {expected_version!r}")
        if not isinstance(build, str) or not build.isdigit():
            errors.append(f"CFBundleVersion is {build!r}, expected a numeric string")
        if bundle_id != EXPECTED_BUNDLE_ID:
            errors.append(f"CFBundleIdentifier is {bundle_id!r}, expected {EXPECTED_BUNDLE_ID!r}")

        debug_dylibs = [
            n for n in names if n.endswith(".debug.dylib") or n.endswith("/__preview.dylib")
        ]
        if debug_dylibs:
            errors.append(f"debug dylib(s) bundled: {debug_dylibs}")

        print(f"IPA: {args.ipa}")
        print(f"  version: {version} (build {build})")
        print(f"  bundle id: {bundle_id}")
        print(f"  entries: {len(names)}")

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"OK: {args.ipa.name} matches {args.tag}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
