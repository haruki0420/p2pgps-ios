#!/usr/bin/env python3
"""Update the AltStore / SideStore source JSON from a GitHub release.

The source format is AltStore's `apps.json` (v2), which SideStore also reads.
This script is run by `.github/workflows/update-source.yml` after the
"Release IPA" workflow succeeds, and can also be run locally:

    python3 scripts/generate_source.py --tag v1.0.4

It requires the GitHub CLI (`gh`) to be authenticated (GH_TOKEN in CI).
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_REPO = "haruki0420/p2pgps-ios"
DEFAULT_OUTPUT = Path("source/apps.json")
ICON_URL = "https://raw.githubusercontent.com/haruki0420/p2pgps-ios/main/Resources/AppIcon.png"
TINT_COLOR = "#2F6B4F"


def gh(*args: str) -> str:
    result = subprocess.run(
        ["gh", *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout


def release_info(repo: str, tag: str) -> dict:
    raw = gh(
        "release",
        "view",
        tag,
        "--repo",
        repo,
        "--json",
        "tagName,name,body,publishedAt,assets,url",
    )
    return json.loads(raw)


def sha256_for_asset(repo: str, tag: str, ipa_name: str) -> str | None:
    """Returns the SHA-256 recorded in the release's `.sha256` asset."""
    with tempfile.TemporaryDirectory() as tmp:
        try:
            gh(
                "release",
                "download",
                tag,
                "--repo",
                repo,
                "--pattern",
                "*.sha256",
                "--dir",
                tmp,
                "--clobber",
            )
        except RuntimeError:
            return None
        for path in Path(tmp).glob("*.sha256"):
            text = path.read_text(encoding="utf-8", errors="replace")
            match = re.search(r"\b([0-9a-fA-F]{64})\b", text)
            if match:
                return match.group(1).lower()
    return None


def first_paragraph(body: str) -> str:
    """Turns a release body into a short one-line description."""
    lines: list[str] = []
    for raw in (body or "").splitlines():
        line = raw.strip()
        if not line:
            if lines:
                break
            continue
        if line.startswith("#"):
            continue
        line = re.sub(r"^[-*]\s+", "", line)
        lines.append(line)
    text = " ".join(lines).strip()
    return text[:280] if text else ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True, help="Release tag, e.g. v1.0.4")
    parser.add_argument("--repo", default=DEFAULT_REPO)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    info = release_info(args.repo, args.tag)
    version = args.tag[1:] if args.tag.startswith("v") else args.tag

    ipa_assets = [a for a in info["assets"] if a["name"].endswith(".ipa")]
    if not ipa_assets:
        print(f"error: no IPA asset on release {args.tag}", file=sys.stderr)
        return 1
    ipa = ipa_assets[0]

    sha256 = None
    digest = ipa.get("digest") or ""
    if digest.startswith("sha256:"):
        sha256 = digest.split(":", 1)[1].lower()
    if not sha256:
        sha256 = sha256_for_asset(args.repo, args.tag, ipa["name"])
    published = info.get("publishedAt") or datetime.now(timezone.utc).isoformat()
    if published.endswith("Z"):
        published = published[:-1] + "+00:00"
    date = datetime.fromisoformat(published).astimezone(timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )

    output = args.output
    if output.exists():
        source = json.loads(output.read_text(encoding="utf-8"))
    else:
        source = {
            "name": "P2P GPS",
            "identifier": "jp.haruki0420.p2pgps.source",
            "subtitle": "iPhone / Android の GPS を iPad に届ける",
            "description": "iPhone または Android で取得した位置情報を Bluetooth で iPad に送り、iPad 自身の位置として反映するアプリです。",
            "iconURL": ICON_URL,
            "website": "https://github.com/haruki0420/p2pgps",
            "tintColor": TINT_COLOR,
            "featuredApps": ["jp.haruki0420.p2pgps"],
            "apps": [],
            "news": [],
        }

    app = next(
        (a for a in source["apps"] if a.get("bundleIdentifier") == "jp.haruki0420.p2pgps"),
        None,
    )
    if app is None:
        app = {
            "name": "P2P GPS",
            "bundleIdentifier": "jp.haruki0420.p2pgps",
            "developerName": "haruki0420",
            "subtitle": "iPhone / Android の GPS を iPad に届ける",
            "localizedDescription": "iPhone または Android で取得した位置情報を Bluetooth で iPad に送り、iPad 自身の位置として反映します。",
            "iconURL": ICON_URL,
            "tintColor": TINT_COLOR,
            "category": "utilities",
            "screenshots": [],
            "versions": [],
            "appPermissions": [
                {
                    "type": "bluetooth",
                    "usageDescription": "近くの iPhone / iPad と位置情報をやり取りするために Bluetooth を使用します。",
                },
                {
                    "type": "location",
                    "usageDescription": "現在地を取得して iPad に送信し、画面を消している間も位置情報の反映を維持するために位置情報を使用します。",
                },
                {
                    "type": "localNetwork",
                    "usageDescription": "Remote Pairing サービスを Bonjour で検出し、LocalDevVPN 経由でこのデバイス自身の位置情報サービスに接続するためにローカルネットワークを使用します。",
                },
            ],
        }
        source["apps"].append(app)

    entry = {
        "version": version,
        "date": date,
        "localizedDescription": first_paragraph(info.get("body", "")),
        "downloadURL": ipa["url"],
        "size": ipa["size"],
        "minOSVersion": "17.0",
    }
    if sha256:
        entry["sha256"] = sha256

    versions = [v for v in app.get("versions", []) if v.get("version") != version]
    versions.insert(0, entry)
    versions.sort(key=lambda v: v.get("date", ""), reverse=True)
    app["versions"] = versions

    news = [n for n in source.get("news", []) if n.get("identifier") != args.tag]
    news.insert(
        0,
        {
            "title": f"{args.tag}: {info.get('name', 'P2P GPS')}",
            "identifier": args.tag,
            "caption": entry["localizedDescription"] or f"{args.tag} をリリースしました。",
            "date": date,
            "tintColor": TINT_COLOR,
            "url": info.get("url", ""),
        },
    )
    source["news"] = news[:10]

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(source, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"updated {output} with {version} ({ipa['name']}, {ipa['size']} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
