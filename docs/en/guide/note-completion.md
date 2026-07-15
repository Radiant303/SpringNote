# AI Real-Time Completion

AI real-time completion predicts subsequent text based on the Markdown content before and after the cursor in the editor. The prediction appears as a temporary completion in the editor and is only written to the document body when accepted; unaccepted predictions do not change the file content.

## Trigger Conditions

Completion is only triggered when a document is selected, the editor has finished loading, the cursor is at a single insertion point, and no text is selected. After the user stops typing or the cursor changes, the application waits approximately 300ms before making a request; further input during this wait cancels the old request and restarts the timer.

Before sending a request, the application checks whether the edit completion model is available. No valid completion request is made if no model is selected, the provider is disabled, the API Key is empty, the model does not exist, the model lacks the "completion" type flag, or the provider protocol does not support completion.

## Context

The request uses content before the cursor as the prefix and content after the cursor as the suffix, allowing the model to generate the missing portion within the current document structure. Completion targets Markdown editing content and does not automatically include other daily, weekly, or monthly notes as context.

## Acceptance

When a prediction is available:

- `Tab` accepts the entire prediction;
- `Ctrl+L` accepts the current line of the prediction;
- `Ctrl+K` accepts the current character of the prediction.

Windows uses the Ctrl combinations above; macOS uses the corresponding system modifier keys. When no prediction is available, `Tab` retains the editor's default tab behavior.

## Status & Saving

During a request, the prediction status is displayed; when returned content is empty, "No prediction available" is shown. If the request fails, is cancelled, times out, or the user continues editing, the temporary prediction is cleared and the original text remains unchanged.

After accepting a prediction, the inserted content is treated as a normal edit, enters the undo history, and is saved automatically. Undoing, redoing, switching documents, or switching workspace modes does not write unaccepted predictions to other documents.
