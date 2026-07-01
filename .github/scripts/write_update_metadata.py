#!/usr/bin/env python3
"""Write SpringNote update metadata files for released installers."""

from __future__ import annotations

import argparse
import json
from datetime import datetime
from email.utils import format_datetime
from pathlib import Path
from zoneinfo import ZoneInfo
from xml.sax.saxutils import escape


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


def read_signature_file(path: Path) -> dict[str, str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit(f"{path} must contain a JSON object")
    return {str(key): str(value) for key, value in data.items()}


def write_appcast(
    path: Path,
    *,
    version: str,
    pub_date: datetime,
    release_notes_url: str,
    macos_url: str,
    macos_signature: str,
    macos_length: str,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pub_date_text = format_datetime(pub_date)
    title = f"SpringNote v{version}"
    path.write_text(
        "\n".join(
            [
                '<?xml version="1.0" encoding="UTF-8"?>',
                '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">',
                "  <channel>",
                "    <title>SpringNote Updates</title>",
                "    <description>SpringNote desktop app updates</description>",
                "    <language>zh-CN</language>",
                "    <item>",
                f"      <title>{escape(title)}</title>",
                f"      <sparkle:version>{escape(version)}</sparkle:version>",
                f"      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>",
                f"      <sparkle:releaseNotesLink>{escape(release_notes_url)}</sparkle:releaseNotesLink>",
                f"      <pubDate>{escape(pub_date_text)}</pubDate>",
                (
                    f'      <enclosure url="{escape(macos_url)}" '
                    f'sparkle:edSignature="{escape(macos_signature)}" '
                    'sparkle:os="macos" '
                    f'length="{escape(macos_length)}" '
                    'type="application/octet-stream" />'
                ),
                "    </item>",
                "  </channel>",
                "</rss>",
                "",
            ]
        ),
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
    parser.add_argument("--macos-signature-file", type=Path, required=True)
    parser.add_argument("--change-time", default="")
    args = parser.parse_args()

    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    change_time = args.change_time.strip()
    if not change_time:
        change_time = (
            f"{now.year}年{now.month}月{now.day}日 "
            f"{now.hour:02d}:{now.minute:02d}:{now.second:02d}"
        )

    release_base = f"https://github.com/{args.repo}/releases/download/{args.version}"
    macos_url = f"{release_base}/{args.macos_asset}"
    windows_url = f"{release_base}/{args.windows_asset}"
    write_json(
        args.output_dir / "mac.json",
        version=args.version,
        change_time=change_time,
        download_url=macos_url,
    )
    write_json(
        args.output_dir / "windows.json",
        version=args.version,
        change_time=change_time,
        download_url=windows_url,
    )

    changelog = args.notes.read_text(encoding="utf-8").strip()
    if not changelog:
        raise SystemExit("Release notes are empty")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.output_dir.joinpath("LATESTCHANGELOG.md").write_text(
        "## ✨ 更新日志\n\n" + changelog + "\n",
        encoding="utf-8",
    )
    macos_signature = read_signature_file(args.macos_signature_file)
    release_notes_url = f"{release_base}/LATESTCHANGELOG.md"
    write_appcast(
        args.output_dir / "appcast.xml",
        version=args.version,
        pub_date=now,
        release_notes_url=release_notes_url,
        macos_url=macos_url,
        macos_signature=macos_signature.get("edSignature", ""),
        macos_length=macos_signature.get("length", ""),
    )


if __name__ == "__main__":
    main()
