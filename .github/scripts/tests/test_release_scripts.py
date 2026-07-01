import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(os.environ.get("GITHUB_WORKSPACE", Path(__file__).resolve().parents[3]))
PREPARE_RELEASE = ROOT / ".github" / "scripts" / "prepare_release.py"
WRITE_UPDATE_METADATA = ROOT / ".github" / "scripts" / "write_update_metadata.py"
VERIFY_UPDATE_METADATA = ROOT / ".github" / "scripts" / "verify_update_metadata.py"


def run_script(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, *args],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )


def write_valid_appcast(metadata_dir: Path, *, version: str = "1.2.3") -> None:
    release_base = f"https://github.com/Radiant303/SpringNote/releases/download/{version}"
    metadata_dir.joinpath("appcast.xml").write_text(
        "\n".join(
            [
                '<?xml version="1.0" encoding="UTF-8"?>',
                '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">',
                "  <channel>",
                "    <item>",
                f"      <sparkle:version>{version}</sparkle:version>",
                f"      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>",
                (
                    f'      <enclosure url="{release_base}/SpringNote-{version}-macos-arm64.dmg" '
                    'sparkle:edSignature="mac-signature" sparkle:os="macos" '
                    'length="123" type="application/octet-stream" />'
                ),
                "    </item>",
                "  </channel>",
                "</rss>",
                "",
            ]
        ),
        encoding="utf-8",
    )


class ReleaseScriptTests(unittest.TestCase):
    def test_prepare_release_outputs_existing_format(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pubspec = tmp_path / "pubspec.yaml"
            changelog = tmp_path / "CHANGELOG.md"
            notes = tmp_path / "release-notes.md"
            outputs = tmp_path / "outputs.txt"
            pubspec.write_text("version: 1.2.3+4\n", encoding="utf-8")
            changelog.write_text(
                "\n".join(
                    [
                        "# 更新日志",
                        "",
                        "## v1.2.3 (2026-06-29)：稳定发布",
                        "",
                        "### 功能新增",
                        "",
                        "* 自动发布 Release。",
                        "",
                        "## v1.2.2 (2026-06-28)",
                        "",
                        "* 旧版本。",
                    ]
                ),
                encoding="utf-8",
            )

            result = run_script(
                str(PREPARE_RELEASE),
                "--tag",
                "1.2.3",
                "--pubspec",
                str(pubspec),
                "--changelog",
                str(changelog),
                "--notes-output",
                str(notes),
                "--outputs-file",
                str(outputs),
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("### 功能新增", notes.read_text(encoding="utf-8"))
            self.assertEqual(
                outputs.read_text(encoding="utf-8").splitlines(),
                [
                    "version=1.2.3",
                    "tag=1.2.3",
                    "release_name=SpringNote v1.2.3：稳定发布",
                    "macos_asset=SpringNote-1.2.3-macos-arm64.dmg",
                    "windows_asset=SpringNote-1.2.3-windows-x64-setup.exe",
                ],
            )

    def test_prepare_release_rejects_mismatched_tag(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pubspec = tmp_path / "pubspec.yaml"
            changelog = tmp_path / "CHANGELOG.md"
            pubspec.write_text("version: 1.2.3\n", encoding="utf-8")
            changelog.write_text("## v1.2.4：标题\n\n* 内容。\n", encoding="utf-8")

            result = run_script(
                str(PREPARE_RELEASE),
                "--tag",
                "1.2.4",
                "--pubspec",
                str(pubspec),
                "--changelog",
                str(changelog),
                "--notes-output",
                str(tmp_path / "notes.md"),
                "--outputs-file",
                str(tmp_path / "outputs.txt"),
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("does not match pubspec version", result.stderr)

    def test_prepare_release_keeps_non_version_h2_in_notes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pubspec = tmp_path / "pubspec.yaml"
            changelog = tmp_path / "CHANGELOG.md"
            notes = tmp_path / "release-notes.md"
            outputs = tmp_path / "outputs.txt"
            pubspec.write_text("version: 1.2.3\n", encoding="utf-8")
            changelog.write_text(
                "\n".join(
                    [
                        "## v1.2.3：稳定发布",
                        "",
                        "### 功能新增",
                        "",
                        "* 自动发布 Release。",
                        "",
                        "## 迁移说明",
                        "",
                        "* 这个二级标题仍属于 v1.2.3。",
                        "",
                        "## v1.2.2：旧版本",
                        "",
                        "* 旧版本。",
                    ]
                ),
                encoding="utf-8",
            )

            result = run_script(
                str(PREPARE_RELEASE),
                "--tag",
                "1.2.3",
                "--pubspec",
                str(pubspec),
                "--changelog",
                str(changelog),
                "--notes-output",
                str(notes),
                "--outputs-file",
                str(outputs),
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            note_text = notes.read_text(encoding="utf-8")
            self.assertIn("## 迁移说明", note_text)
            self.assertNotIn("旧版本。", note_text)

    def test_update_metadata_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            notes = tmp_path / "notes.md"
            output_dir = tmp_path / "update"
            macos_signature = tmp_path / "macos-signature.json"
            notes.write_text("### 功能新增\n\n* 自动发布 Release。\n", encoding="utf-8")
            macos_signature.write_text(
                json.dumps({"edSignature": "mac-signature", "length": "123"}),
                encoding="utf-8",
            )

            write_result = run_script(
                str(WRITE_UPDATE_METADATA),
                "--version",
                "1.2.3",
                "--repo",
                "Radiant303/SpringNote",
                "--macos-asset",
                "SpringNote-1.2.3-macos-arm64.dmg",
                "--windows-asset",
                "SpringNote-1.2.3-windows-x64-setup.exe",
                "--notes",
                str(notes),
                "--output-dir",
                str(output_dir),
                "--macos-signature-file",
                str(macos_signature),
                "--change-time",
                "2026年6月29日 13:30:00",
            )
            self.assertEqual(write_result.returncode, 0, write_result.stderr)

            verify_result = run_script(
                str(VERIFY_UPDATE_METADATA),
                "--version",
                "1.2.3",
                "--repo",
                "Radiant303/SpringNote",
                "--macos-asset",
                "SpringNote-1.2.3-macos-arm64.dmg",
                "--windows-asset",
                "SpringNote-1.2.3-windows-x64-setup.exe",
                "--metadata-dir",
                str(output_dir),
            )
            self.assertEqual(verify_result.returncode, 0, verify_result.stderr)

            mac = json.loads(output_dir.joinpath("mac.json").read_text(encoding="utf-8"))
            self.assertEqual(mac["version"], "1.2.3")
            self.assertEqual(mac["change_time"], "2026年6月29日 13:30:00")
            self.assertTrue(
                output_dir.joinpath("LATESTCHANGELOG.md")
                .read_text(encoding="utf-8")
                .startswith("## ✨ 更新日志")
            )
            appcast = output_dir.joinpath("appcast.xml").read_text(encoding="utf-8")
            self.assertIn('sparkle:os="macos"', appcast)
            self.assertIn('sparkle:edSignature="mac-signature"', appcast)
            self.assertNotIn('sparkle:os="windows"', appcast)

    def test_verify_update_metadata_rejects_wrong_version(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            metadata_dir = tmp_path / "update"
            metadata_dir.mkdir()
            metadata_dir.joinpath("mac.json").write_text(
                json.dumps(
                    {
                        "version": "9.9.9",
                        "change_time": "2026年6月29日 13:30:00",
                        "download_url": "https://github.com/Radiant303/SpringNote/releases/download/1.2.3/SpringNote-1.2.3-macos-arm64.dmg",
                    }
                ),
                encoding="utf-8",
            )
            metadata_dir.joinpath("windows.json").write_text(
                json.dumps(
                    {
                        "version": "1.2.3",
                        "change_time": "2026年6月29日 13:30:00",
                        "download_url": "https://github.com/Radiant303/SpringNote/releases/download/1.2.3/SpringNote-1.2.3-windows-x64-setup.exe",
                    }
                ),
                encoding="utf-8",
            )
            metadata_dir.joinpath("LATESTCHANGELOG.md").write_text(
                "## ✨ 更新日志\n\n* 内容。\n",
                encoding="utf-8",
            )
            write_valid_appcast(metadata_dir)

            result = run_script(
                str(VERIFY_UPDATE_METADATA),
                "--version",
                "1.2.3",
                "--repo",
                "Radiant303/SpringNote",
                "--macos-asset",
                "SpringNote-1.2.3-macos-arm64.dmg",
                "--windows-asset",
                "SpringNote-1.2.3-windows-x64-setup.exe",
                "--metadata-dir",
                str(metadata_dir),
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("does not match", result.stderr)

    def test_verify_update_metadata_rejects_empty_changelog(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            metadata_dir = tmp_path / "update"
            metadata_dir.mkdir()
            release_base = "https://github.com/Radiant303/SpringNote/releases/download/1.2.3"
            metadata_dir.joinpath("mac.json").write_text(
                json.dumps(
                    {
                        "version": "1.2.3",
                        "change_time": "2026年6月29日 13:30:00",
                        "download_url": f"{release_base}/SpringNote-1.2.3-macos-arm64.dmg",
                    }
                ),
                encoding="utf-8",
            )
            metadata_dir.joinpath("windows.json").write_text(
                json.dumps(
                    {
                        "version": "1.2.3",
                        "change_time": "2026年6月29日 13:30:00",
                        "download_url": f"{release_base}/SpringNote-1.2.3-windows-x64-setup.exe",
                    }
                ),
                encoding="utf-8",
            )
            metadata_dir.joinpath("LATESTCHANGELOG.md").write_text(
                "  \n",
                encoding="utf-8",
            )
            write_valid_appcast(metadata_dir)

            result = run_script(
                str(VERIFY_UPDATE_METADATA),
                "--version",
                "1.2.3",
                "--repo",
                "Radiant303/SpringNote",
                "--macos-asset",
                "SpringNote-1.2.3-macos-arm64.dmg",
                "--windows-asset",
                "SpringNote-1.2.3-windows-x64-setup.exe",
                "--metadata-dir",
                str(metadata_dir),
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("LATESTCHANGELOG.md is empty", result.stderr)

    def test_verify_update_metadata_rejects_non_object_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            metadata_dir = tmp_path / "update"
            metadata_dir.mkdir()
            metadata_dir.joinpath("mac.json").write_text("[]", encoding="utf-8")
            metadata_dir.joinpath("windows.json").write_text("{}", encoding="utf-8")
            metadata_dir.joinpath("LATESTCHANGELOG.md").write_text(
                "## ✨ 更新日志\n\n* 内容。\n",
                encoding="utf-8",
            )
            write_valid_appcast(metadata_dir)

            result = run_script(
                str(VERIFY_UPDATE_METADATA),
                "--version",
                "1.2.3",
                "--repo",
                "Radiant303/SpringNote",
                "--macos-asset",
                "SpringNote-1.2.3-macos-arm64.dmg",
                "--windows-asset",
                "SpringNote-1.2.3-windows-x64-setup.exe",
                "--metadata-dir",
                str(metadata_dir),
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must contain a JSON object", result.stderr)


if __name__ == "__main__":
    unittest.main()
