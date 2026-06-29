#!/usr/bin/env python3
"""Write SpringNote update metadata files for released installers."""

from __future__ import annotations

import argparse
import json
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo


def write_json(path: Path, *, version: str, change_time: str, download_url: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "version": version,
                "change_time": change_time,
                "download_url": download_url,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--macos-asset", required=True)
    parser.add_argument("--windows-asset", required=True)
    parser.add_argument("--notes", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--change-time", default="")
    args = parser.parse_args()

    change_time = args.change_time.strip()
    if not change_time:
        now = datetime.now(ZoneInfo("Asia/Shanghai"))
        change_time = (
            f"{now.year}年{now.month}月{now.day}日 "
            f"{now.hour:02d}:{now.minute:02d}:{now.second:02d}"
        )

    release_base = f"https://github.com/{args.repo}/releases/download/{args.version}"
    write_json(
        args.output_dir / "mac.json",
        version=args.version,
        change_time=change_time,
        download_url=f"{release_base}/{args.macos_asset}",
    )
    write_json(
        args.output_dir / "windows.json",
        version=args.version,
        change_time=change_time,
        download_url=f"{release_base}/{args.windows_asset}",
    )

    changelog = args.notes.read_text(encoding="utf-8").strip()
    if not changelog:
        raise SystemExit("Release notes are empty")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.output_dir.joinpath("LATESTCHANGELOG.md").write_text(
        "## ✨ 更新日志\n\n" + changelog + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
