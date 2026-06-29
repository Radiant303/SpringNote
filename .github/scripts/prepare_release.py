#!/usr/bin/env python3
"""Prepare SpringNote release metadata from pubspec and CHANGELOG."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")
CHANGELOG_VERSION_HEADING_RE = re.compile(
    r"^##\s+v?(?P<version>\d+\.\d+\.\d+)"
    r"(?:\s*\([^)]+\))?"
    r"(?:\s*[:：-]\s*(?P<title>\S.*))?\s*$"
)


def read_pubspec_version(path: Path) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^version:\s*([^\s]+)", line)
        if match:
            return match.group(1).split("+", 1)[0].strip()
    raise SystemExit(f"Missing version in {path}")


def extract_release_notes(changelog: Path, version: str) -> tuple[str, str | None]:
    lines = changelog.read_text(encoding="utf-8").splitlines()

    start = None
    title = None
    for index, line in enumerate(lines):
        match = CHANGELOG_VERSION_HEADING_RE.match(line.strip())
        if match and match.group("version") == version:
            start = index + 1
            title = match.group("title")
            break

    if start is None:
        raise SystemExit(f"Missing CHANGELOG entry for v{version}")

    end = len(lines)
    for index in range(start, len(lines)):
        if CHANGELOG_VERSION_HEADING_RE.match(lines[index].strip()):
            end = index
            break

    body = "\n".join(lines[start:end]).strip()
    if not body:
        raise SystemExit(f"CHANGELOG entry for v{version} is empty")
    return body + "\n", title.strip() if title else None


def append_output(path: Path, key: str, value: str) -> None:
    with path.open("a", encoding="utf-8") as output:
        output.write(f"{key}={value}\n")


def normalize_title_suffix(value: str, source: str) -> str:
    suffix = value.strip()
    if not suffix:
        return ""
    if "\n" in suffix or "\r" in suffix:
        raise SystemExit(f"Release title suffix from {source} must be one line")
    return suffix


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--pubspec", type=Path, required=True)
    parser.add_argument("--changelog", type=Path, required=True)
    parser.add_argument("--notes-output", type=Path, required=True)
    parser.add_argument("--outputs-file", type=Path, required=True)
    parser.add_argument("--title-suffix", default="")
    args = parser.parse_args()

    pubspec_version = read_pubspec_version(args.pubspec)
    version = args.tag.strip()
    if not VERSION_RE.match(version):
        raise SystemExit(
            f"Release tag must match the existing format, for example 1.0.1: {version}"
        )
    if version != pubspec_version:
        raise SystemExit(
            f"Release tag {version} does not match pubspec version {pubspec_version}"
        )

    notes, changelog_title = extract_release_notes(args.changelog, version)
    args.notes_output.write_text(notes, encoding="utf-8")

    title_suffix = normalize_title_suffix(args.title_suffix, "--title-suffix")
    title_suffix = title_suffix or normalize_title_suffix(
        changelog_title or "",
        "CHANGELOG heading",
    )
    if not title_suffix:
        raise SystemExit(
            "Missing release title suffix. Add it to the CHANGELOG heading "
            "as `## vX.Y.Z (YYYY-MM-DD)：标题`."
        )
    release_name = f"SpringNote v{version}：{title_suffix}"
    macos_asset = f"SpringNote-{version}-macos-arm64.dmg"
    windows_asset = f"SpringNote-{version}-windows-x64-setup.exe"

    append_output(args.outputs_file, "version", version)
    append_output(args.outputs_file, "tag", version)
    append_output(args.outputs_file, "release_name", release_name)
    append_output(args.outputs_file, "macos_asset", macos_asset)
    append_output(args.outputs_file, "windows_asset", windows_asset)


if __name__ == "__main__":
    main()
