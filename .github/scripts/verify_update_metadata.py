#!/usr/bin/env python3
"""Verify SpringNote update metadata points at the released assets."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--macos-asset", required=True)
    parser.add_argument("--windows-asset", required=True)
    parser.add_argument("--metadata-dir", type=Path, required=True)
    args = parser.parse_args()

    release_base = f"https://github.com/{args.repo}/releases/download/{args.version}"
    verify_platform(
        args.metadata_dir / "mac.json",
        version=args.version,
        expected_url=f"{release_base}/{args.macos_asset}",
    )
    verify_platform(
        args.metadata_dir / "windows.json",
        version=args.version,
        expected_url=f"{release_base}/{args.windows_asset}",
    )

    changelog = args.metadata_dir.joinpath("LATESTCHANGELOG.md").read_text(
        encoding="utf-8"
    )
    if not changelog.strip():
        raise SystemExit("LATESTCHANGELOG.md is empty")


if __name__ == "__main__":
    main()
