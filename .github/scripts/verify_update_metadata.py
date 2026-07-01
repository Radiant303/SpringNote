#!/usr/bin/env python3
"""Verify SpringNote update metadata points at the released assets."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET


def read_json(path: Path) -> dict[str, object]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit(f"{path} must contain a JSON object")
    return data


def verify_platform(path: Path, *, version: str, expected_url: str) -> None:
    data = read_json(path)
    actual_version = str(data.get("version", "")).strip()
    actual_url = str(data.get("download_url", "")).strip()
    actual_change_time = str(data.get("change_time", "")).strip()

    if actual_version != version:
        raise SystemExit(f"{path} version {actual_version!r} does not match {version!r}")
    if actual_url != expected_url:
        raise SystemExit(f"{path} download_url {actual_url!r} does not match {expected_url!r}")
    if not actual_change_time:
        raise SystemExit(f"{path} change_time is empty")


def verify_appcast(
    path: Path,
    *,
    version: str,
    expected_macos_url: str,
) -> None:
    namespaces = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
    root = ET.parse(path).getroot()
    items = root.findall("./channel/item")
    if not items:
        raise SystemExit(f"{path} must contain a macOS update item")

    seen = set()
    sparkle_ns = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    for item in items:
        enclosure = item.find("enclosure")
        if enclosure is None:
            raise SystemExit(f"{path} item is missing enclosure")
        os_name = enclosure.attrib.get(f"{sparkle_ns}os", "")
        url = enclosure.attrib.get("url", "")
        length = enclosure.attrib.get("length", "")
        if not length.isdigit() or int(length) <= 0:
            raise SystemExit(f"{path} {os_name or 'unknown'} length must be positive")
        if os_name == "macos":
            seen.add("macos")
            if url != expected_macos_url:
                raise SystemExit(f"{path} macOS url {url!r} does not match {expected_macos_url!r}")
            if not enclosure.attrib.get(f"{sparkle_ns}edSignature", "").strip():
                raise SystemExit(f"{path} macOS edSignature is empty")
            short_version = item.findtext("sparkle:shortVersionString", namespaces=namespaces)
            if short_version != version:
                raise SystemExit(f"{path} macOS shortVersionString does not match {version!r}")

    missing = {"macos"} - seen
    if missing:
        raise SystemExit(f"{path} is missing update items for {', '.join(sorted(missing))}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--macos-asset", required=True)
    parser.add_argument("--windows-asset", required=True)
    parser.add_argument("--metadata-dir", type=Path, required=True)
    args = parser.parse_args()

    release_base = f"https://github.com/{args.repo}/releases/download/{args.version}"
    expected_macos_url = f"{release_base}/{args.macos_asset}"
    expected_windows_url = f"{release_base}/{args.windows_asset}"
    verify_platform(
        args.metadata_dir / "mac.json",
        version=args.version,
        expected_url=expected_macos_url,
    )
    verify_platform(
        args.metadata_dir / "windows.json",
        version=args.version,
        expected_url=expected_windows_url,
    )

    changelog = args.metadata_dir.joinpath("LATESTCHANGELOG.md").read_text(
        encoding="utf-8"
    )
    if not changelog.strip():
        raise SystemExit("LATESTCHANGELOG.md is empty")
    verify_appcast(
        args.metadata_dir / "appcast.xml",
        version=args.version,
        expected_macos_url=expected_macos_url,
    )


if __name__ == "__main__":
    main()
