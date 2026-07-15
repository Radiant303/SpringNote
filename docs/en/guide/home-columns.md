# Home Columns

The three home columns display the day's organized content. They are a structured representation of the day's information on the home page — not three separate notes, and not a replacement for the daily note. Each column has its own title, description, entry list, and entry count.

## Content Source

The column content comes from structured results produced by the day's home page organization. Organization uses text, image references, existing daily overview, and column settings from the quick input box. Regular files currently only enter as path information and cannot become file attachments in the columns simply by appearing in the input.

The three home columns only show the overview for the current date. When switching dates or reopening the application, the page reads the saved overview for the corresponding date; if no overview exists for that day, all three columns show an empty state and do not use content from other dates.

## Column Display

The three columns are arranged horizontally in wide windows and vertically in narrow windows. Each card displays:

- A fixed English auxiliary label and the user-configured title;
- Up to two content previews;
- The total number of entries in the current column.

Preview text in the cards is for quick scanning only; longer content is truncated. The count displayed is the total number of saved entries for that column, not the number of preview lines. When a column has no entries, the column title is shown as an empty state hint.

## Viewing Full Content

Clicking any column opens a detail popup, defaulting to the clicked column. A column selector within the popup lets you switch between the three columns; switching scrolls the list to the top and shows all entries for the selected column.

Entries in the detail popup are ordered by save time. When content is lengthy, the list scrolls independently. Closing the popup only ends the view; it does not modify the overview or daily note. When a column has no content, the popup shows "No content".

## Generation & Merge Rules

After the first successful organization, the result is saved as the day's three-column overview. When submitting content again on the same day, new results are merged with the existing overview; existing entries are not unconditionally deleted because one organization result is empty. When the application reloads the overview, it fills in empty lists for all three columns, so old formats or incomplete files do not cause column misalignment.

When an AI organization request fails, no model is available, or the returned structure does not match the column definitions, the existing overview and saved input are retained. The page does not treat failed results as valid new column content.

## Column Settings

Column titles and descriptions can be modified in Settings. When a description is left empty, the system uses the corresponding title as the organization description. Changing configuration does not reprocess already-saved historical results.

The title only affects the column name and the corresponding heading in daily notes; the description only affects the AI's content judgment for that column during future organization. Modifying titles or descriptions does not migrate historical entries, clear existing overviews, or change the number or order of the three columns.
