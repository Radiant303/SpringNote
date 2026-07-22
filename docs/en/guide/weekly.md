# Weekly Notes

Weekly notes organize progress and issues on a weekly basis, stored separately from their source daily notes. Generating or editing a weekly note does not modify the daily notes for that week.

## Content Source

When generating a weekly note, the application reads daily notes with actual content from Monday to Sunday of the target week and combines them by date before sending them to the report model. Daily notes without valid content do not contribute to the weekly note.

The generated Markdown is saved as an independent file and can be further edited in the notebook. Manual edits belong to the weekly note itself and are not written back to the source daily notes; regenerating re-reads the source daily notes for the target week.

## Creation Timing

Weekly notes can be created through the AI report generation flow or by saving for the first time in the notebook. Before generation, the system checks if the target week already has a weekly note with actual content; existing weekly notes are not overwritten by the automatic generation flow on startup.

On startup, the application checks historical weeks that have ended and contain valid daily notes. A missing weekly note is only created if source content exists, the target weekly note has no valid content, and AI report generation succeeds. The current week is not treated as a completed week during startup checks.

If generation fails, no model is available, the source is empty, or empty content is returned, existing weekly notes are not overwritten with empty results.

The Regenerate button in the editor header re-reads the source daily notes for the target week, calls the report model, and overwrites the current weekly note file, regardless of the startup flow's "no overwrite of existing content" rule. During generation, the button shows progress and the editor is temporarily disabled; on failure, the error is shown in the status pill on the left side of the header. Nothing happens if the week has no valid daily note content.

## File Name

Weekly note files use ISO week numbering:

```text
YYYY-Www.md
```

For example, `2026-W29.md` represents ISO year 2026, week 29. Monday is the start of the week, Sunday is the end. Cross-year weeks are named according to the ISO year they belong to, so week numbers at the beginning or end of a calendar year may belong to an adjacent ISO year.

Files are stored in the `notes/weekly` folder within the data directory.

## Editing & Reading

The notebook list displays weekly notes in descending order by file name. When selected, the full Markdown body is loaded. Edits are saved automatically, updating the title, preview, modification time, and search index.
