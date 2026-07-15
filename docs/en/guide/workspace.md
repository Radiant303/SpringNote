# Workspace Mode

Workspace mode determines how the editing area on the right side of the notebook presents the current Markdown document. It includes three states: Edit, Split, and Preview. All three states share the same selected document and current content.

## Edit

Edit mode displays the Markdown source. The cursor, selection, undo, redo, AI real-time completion, and auto-save all operate within the editing area. Text changes are written to the currently selected file, and list information is updated synchronously.

## Split

Split mode displays both the Markdown editor and the rendered preview side by side. Changes in the editor are reflected in the preview in real time. The preview is for viewing the final display; it does not independently produce another copy of the document content.

## Preview

Preview mode hides the source editor and shows only the rendered result of the current Markdown. The preview supports text selection, scrolling, links, images, code blocks, tables, and mathematical formulas. Returning to Edit mode continues with the same source.

## Switching & Saving

Switching between Edit, Split, and Preview only changes the workspace layout; it does not alter the Markdown content, current document, or save state. The mode selection is written to the configuration file; the application restores the last selected mode on restart.

When switching documents, the workspace mode remains unchanged. After the new document finishes loading, the editor and preview display the new document's content. While a document is being saved or loaded, the page temporarily limits certain operations to prevent old document content from overwriting the new selection.
