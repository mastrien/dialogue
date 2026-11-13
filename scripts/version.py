#!/usr/bin/env python3
"""Sync or verify the Dialogue app version across Rust, Desktop, and Mobile."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read_versions() -> dict[str, str]:
    core_toml = (ROOT / "core/Cargo.toml").read_text(encoding="utf-8")
    desktop_toml = (ROOT / "desktop/src-tauri/Cargo.toml").read_text(encoding="utf-8")
    desktop_pkg = json.loads((ROOT / "desktop/package.json").read_text(encoding="utf-8"))
    tauri_conf = json.loads(
        (ROOT / "desktop/src-tauri/tauri.conf.json").read_text(encoding="utf-8")
    )
    pubspec = (ROOT / "mobile/pubspec.yaml").read_text(encoding="utf-8")

    return {
        "core/Cargo.toml": re.search(r'^version\s*=\s*"([^"]+)"', core_toml, re.M).group(1),
        "desktop/src-tauri/Cargo.toml": re.search(
            r'^version\s*=\s*"([^"]+)"', desktop_toml, re.M
        ).group(1),
        "desktop/package.json": desktop_pkg["version"],
        "desktop/src-tauri/tauri.conf.json": tauri_conf["version"],
        "mobile/pubspec.yaml": re.search(r"^version:\s*([^\s+]+)", pubspec, re.M).group(1),
    }


def check_version(expected_tag: str) -> int:
    expected = expected_tag.lstrip("v")
    versions = read_versions()
    mismatches = {k: v for k, v in versions.items() if v != expected}
    if mismatches:
        print(f"Expected version {expected}, found mismatches: {mismatches}", file=sys.stderr)
        return 1
    print(f"All files match version {expected}")
    return 0


def set_version(new_version: str) -> int:
    clean = new_version.lstrip("v")
    if not re.match(r"^\d+\.\d+\.\d+$", clean):
        print(f"Invalid semver: {new_version}", file=sys.stderr)
        return 1

    for rel in ("core/Cargo.toml", "desktop/src-tauri/Cargo.toml"):
        path = ROOT / rel
        text = path.read_text(encoding="utf-8")
        path.write_text(
            re.sub(r'^(version\s*=\s*")[^"]+(")', rf"\g<1>{clean}\2", text, count=1, flags=re.M),
            encoding="utf-8",
        )

    for rel in ("desktop/package.json", "desktop/src-tauri/tauri.conf.json"):
        path = ROOT / rel
        data = json.loads(path.read_text(encoding="utf-8"))
        data["version"] = clean
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    pub_path = ROOT / "mobile/pubspec.yaml"
    pub_text = pub_path.read_text(encoding="utf-8")
    m = re.search(r"^version:\s*[^\s+]+\+(\d+)", pub_text, re.M)
    next_build = int(m.group(1)) + 1 if m else 1
    pub_path.write_text(
        re.sub(r"^version:\s*.*$", f"version: {clean}+{next_build}", pub_text, count=1, flags=re.M),
        encoding="utf-8",
    )

    print(f"Updated all files to {clean} (Android build +{next_build})")
    return 0


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        return check_version(sys.argv[2])
    if len(sys.argv) == 2 and sys.argv[1] not in ("-h", "--help"):
        return set_version(sys.argv[1])
    print("Usage: version.py <X.Y.Z> | version.py --check <tag>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
