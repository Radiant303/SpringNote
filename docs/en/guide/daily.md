# Daily Notes

Daily notes store work records by calendar day. They are the most basic note type in the notebook and serve as the source for weekly notes, the Memory Book, and some statistics. Daily notes can be created through the home page input flow or edited and saved directly in the notebook.

## Content Source

The daily note body may contain:

- Text submitted from the home page;
- Images saved to the data directory and their Markdown references;
- Column organization content from Smart Generation;
- Manual edits in the notebook;
- Markdown returned by AI merge.

Regular files selected from the home page currently only include the file name and path in the input; files are not copied, read, or created as attachments. Images and regular files are handled differently: images can be saved as note references, while regular files remain as path information in the input.

If AI merge succeeds, the body uses the model's returned Markdown; if no model is available, the request fails, or the returned content is unusable, the application's local merge result is used. The application does not guarantee keeping an unprocessed copy of the original input separately.

## Creation Timing

When the first home page input is submitted for the day, the application creates or updates the day's daily note. Simply opening the home page, notebook, selecting a date, or viewing the list does not create a blank daily note.

When content is submitted again for an existing daily note, the application reads the current body and merges new content with it. Manual edits in the notebook are saved directly to the current file and become the existing body for subsequent processing.

When opening the Daily note type in the notebook, if the file for the current day does not exist, the page ensures the file is created and selected. Daily notes for other dates are not automatically created by browsing the list.

## File Name

Daily note files use the following naming format:

```text
YYYY-MM-DD.md
```

The date in the file name uses the local date. For example, `2026-07-15.md` represents the daily note for July 15, 2026. Files are stored in the `notes/daily` folder within the data directory; changing the data directory uses the new directory.

## Editing & Saving

After selecting a daily note, the editor loads the full Markdown body. Text changes are saved automatically, and the page shows the save status during the process. After a successful save, the list title, preview, modification time, and search index are updated synchronously.

If reading or saving fails, the failed content is not treated as a successful result. The editor retains the text currently displayed, and the specific error state is shown on the page.

## Date Boundaries

Daily notes are archived by local date. After midnight, new submissions are attributed to the new date's file; the previous day's daily note is not automatically renamed or migrated due to the date change.
