# Markdown Rendering

The notebook editor saves Markdown source text, and the preview area renders the same source into a readable document. The editor and preview use the same current content; after saving, the content is written to the current daily, weekly, or monthly note file.

## Editor

The editor supports standard text input, undo, redo, clipboard paste, and image insertion. Markdown source is preserved as-is; the editor does not rewrite headings, lists, links, or emphasis symbols due to preview rendering.

Markdown syntax highlighting is an independent display feature. When enabled, it only changes the color of Markdown syntax tokens and symbols — it does not alter characters, font shapes, saved text, or preview results. When disabled, the editor displays plain text.

## Preview Content

The preview supports headings, paragraphs, lists, links, images, tables, code blocks, and mathematical formulas. Code blocks are styled according to their language tag, and mathematical formulas are rendered using LaTeX rules.

The preview area supports text selection and scrolling. Markdown links can be opened, and images are resolved relative to the note's directory and data directory references.

## Image References

Images inserted through the notebook are saved as Markdown image links; during preview, relative paths are resolved based on the current note's path. Deleting a Markdown image link only changes the body reference; it does not automatically delete the image file from the data directory. Image file cleanup is handled by the Storage Management page.

## Empty Content & Errors

When the current Markdown is empty, the preview area shows an empty state hint and does not generate fabricated content. When an image path is invalid, the link in the body is retained, but the preview cannot display the image. Unrecognized Markdown structures are displayed as parseable plain text or basic structures, and the original source is not deleted.
