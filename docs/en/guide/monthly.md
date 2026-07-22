# Monthly Notes

Monthly notes record changes, achievements, and ongoing issues on a calendar month basis. They are stored independently from daily and weekly notes; generating or editing a monthly note does not modify source records.

## Content Source

When generating a monthly note, the application reads weekly notes with actual content within the target calendar month and combines them by weekly note file. Monthly notes use weekly notes as their periodic source; weekly notes from other months are not included as default content.

After saving, monthly notes can be manually edited. Manual edits belong to the monthly note itself and do not update daily or weekly notes. Regenerating re-reads the source weekly notes for the target month.

## Creation Timing

Monthly notes can be created through the AI report generation flow or by saving for the first time in the notebook. On startup, the application checks historical months that have ended and contain valid weekly notes.

A missing monthly note is only created if source content exists, the target monthly note has no valid content, and AI report generation succeeds. The current month is not treated as a completed month during startup checks. If generation fails, empty content is returned, or no model is available, existing monthly notes are not overwritten with empty results.

The Regenerate button in the editor header re-reads the source weekly notes for the target month, calls the report model, and overwrites the current monthly note file, regardless of the startup flow's "no overwrite of existing content" rule. During generation, the button shows progress and the editor is temporarily disabled; on failure, the error is shown in the status pill on the left side of the header. Nothing happens if the month has no valid weekly note content.

## File Name

Monthly note files use the following naming format:

```text
YYYY-MM.md
```

For example, `2026-07.md` represents July 2026. The month is determined by the local calendar from the first to the last day. Files are stored in the `notes/monthly` folder within the data directory.

## Month & Week Boundaries

An ISO week may span two calendar months. When the monthly note reads weekly notes, any weekly note whose coverage falls within the target month may become a source for that month. Therefore, the same cross-month weekly note may contribute to two adjacent calendar months' monthly notes.

## Editing & Reading

The notebook list displays monthly notes in descending order by file name. When selected, the full Markdown body is loaded. Edits are saved automatically, updating the title, preview, modification time, and search index.
