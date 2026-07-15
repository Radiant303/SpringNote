# Search Notes

Note search filters documents containing the query within the currently selected note type (Daily, Weekly, or Monthly). It is responsible for locating documents, not for expanding full matched content; the editor loads the complete file only after selecting a result.

## Search Scope

The search scope is determined by the currently selected note type: searching Daily only searches the daily notes directory, Weekly only the weekly notes directory, and Monthly only the monthly notes directory. Switching between Daily, Weekly, and Monthly clears and re-executes the current search.

## Matching Rules

Query content is trimmed of leading and trailing whitespace and requires at least two characters. Search uses contiguous two-character matching, supports Chinese and English content, and is case-insensitive for English letters.

Matching covers the document body, file name, and document title. The body index stores information for search filtering, not a full copy of the body; when opening a result, the body is read from the original Markdown file.

## Result Rules

Results are capped at 100 entries. Notebook search results are sorted in descending order by document name; document names typically correspond to dates, ISO weeks, or months, so newer records appear first.

Search results display the document title, file name, and preview information. Previews help identify items in the list; longer content is truncated. Clicking a result loads the full body in the editor on the right.

## Search Timing

After entering a query, the application waits briefly before executing the search to avoid scanning on every keystroke. Query changes, note saves, or note type switches invalidate old search results; only results matching the current query and type are displayed.

When the query is fewer than two characters, the page clears search results without initiating valid matching. When no matches are found, an empty result state is shown, and the currently selected Markdown content is not modified.

## Index Updates

When opening the notebook, the available index list is displayed first, and directory changes are checked in the background. After saving a document, the index for the current file is updated immediately. Newly added, deleted, or externally modified files are reflected in the list and search after the index refreshes. If the index encounters an error, the application may fall back to reading files directly.
