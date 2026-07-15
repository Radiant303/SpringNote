# Updates & Versions

SpringNote is continuously improved with new features, bug fixes, and stability enhancements. Before upgrading, we recommend reviewing the changelog for the target version to understand new features, behavior changes, and any configuration that may need to be rechecked.

## Check Current Version

Open `Settings > About` to view the current version, system information, and project links.

## Install Updates

Download the installer matching your platform and system architecture from the [releases page](https://github.com/Radiant303/SpringNote/releases/latest) or the [QQ group](https://qm.qq.com/q/c6QiowtYSA).

Before updating:

1. Exit the running SpringNote instance.
2. If using the desktop widget, tray, or sync features, wait for related operations to complete.
3. Regularly back up important data according to your storage strategy.

## Post-Update Checks

When first launching a new version, the application may need to verify existing data or initialize new features.

After entering the main interface, we recommend confirming:

1. The data directory is correct.
2. Recent daily notes and images open properly.
3. Provider configurations and default models are still present.
4. Shortcuts, tray, and desktop widget behave as expected.

If some AI features are unavailable after upgrading, check:

- Provider connection status
- Default model configuration
- Network connectivity

Do not delete existing configuration directly.

## v1.0.3 (2026-07-10)

### Dark Mode, Wallpaper & Markdown Editing Enhancements

#### UI Improvements

- Improved switching display between "Saved" status and edit prediction hint in the note editor.
- Improved Markdown rendering for headings, tables, formulas, task lists, and more.
- Refined website styles and configuration tutorials.

#### New Features

- Added dark mode support with Windows/macOS desktop widget adaptation.
- Added wallpaper support for the application and desktop widget:
  - Default background
  - Opacity adjustment
  - Blur effect
  - Mask configuration
- Added Edit, Split, and Preview modes for notes.
- Added syntax highlighting in the Markdown editor (toggleable in Settings, enabled by default).
- Links in Markdown rendering now open in the browser on click.
- Shortcut settings now support direct key combination recording, with reset and clear options for global shortcuts.
- Added Storage Management to scan and clean up images no longer referenced by notes.

#### Bug Fixes

- Fixed object omission in automatic note sync uploads.
- Fixed tool call context format incompatibility in Memory Book local fallback search.
- Fixed Markdown table, nested bracket, and link parsing issues.
- Fixed desktop widget state cycling during rapid dragging, color switching anomalies, and control boundary issues under font scaling.

## v1.0.2 (2026-07-03)

### WebDAV Sync Feature

#### UI Improvements

- Improved shortcut settings page structure; removed duplicate title.
- Refined settings page styles; added confirmation dialog for deleting providers.

#### New Features

- Added home page image parsing for content recognition.
- Added WebDAV sync functionality.
- Added quick submit shortcuts for the home page and Memory Book.
- Images can now be inserted and previewed in notes.
- Added in-app auto-update for Windows/macOS, with manual update support.
- Windows desktop widget now persists position across restarts.
- Added AI capability configuration for the Memory Book.

#### Bug Fixes

- Fixed issue where multiple launches on Windows would not reuse the existing window.
- Fixed note search not matching full content.
- Fixed tool invocation issue with Bailian official DeepSeek.
- Fixed incomplete AI usage statistics writes.
- Fixed crash on startup due to corrupted configuration files.
- Fixed display issue with desktop widget orb mode during fast movement.
- Fixed inconsistent network permission declarations across platforms.

## v1.0.1 (2026-06-26)

### Feature Polish & Cross-Platform Support

#### UI Improvements

- Replaced settings icon with an outline-style gear icon.
- Improved model selection page with provider-grouped model display.
- Added QQ group contact info on the About page.

#### New Features

- Added customizable daily note organization configuration.
- Added OpenAI Responses API support.
- Added customizable configuration file storage directory.
- Added default model configuration.
- Added file path upload for attachments.
- Added widget orb mode with position memory.
- Added configurable maximum character count for Memory Book retrieval results.

#### Bug Fixes

- Fixed date picker button flickering when switching dates.
- Fixed daily note content being cut off at the bottom.
- Fixed request errors when enabling max reasoning intensity.
- Fixed model selection list conflicts.
- Fixed issue where daily notes wouldn't auto-generate when opening the notebook.

#### Platform Support

- Added macOS platform support.

## v1.0.0 (2026-06-21)

### First Stable Release

- Implemented application update functionality.
- Improved default application icon.
- SpringNote officially released.
