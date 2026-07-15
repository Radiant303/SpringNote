# Quick Input

The quick input box is used to save text and images for the current day. On submission, text is written into the day's daily note, images are copied to the current data directory and inserted as Markdown image links; files are not copied to the data directory — currently only the file name and original path are included as path information in the input.

## Images

Images can be added via the file picker or system clipboard. After adding, they appear in the pending submission area and only become part of the daily note upon successful submission. Image preview depends on the saved reference path; original image files are not deleted when copied to the data directory.

Whether Smart Generation can process images depends on whether the selected model supports image input. If the model does not support images, the images are still saved but are not included in the AI input.

## Files

File selection currently only generates file path information in the input. Upon submission, the file name and path are included as text content for daily note organization and AI requests, but the application does not read file contents, copy files, or create attachment references usable for note previews.

Whether the model service can access the file path depends on the service and runtime environment. Sending a path to the model does not mean the model has read the file, nor that the file has been saved to the SpringNote data directory. File content parsing and true attachment management are not yet implemented.

## Smart Generation

Smart Generation reads the current input and returns structured results based on the three home column definitions in Settings. Each result contains content entries for the corresponding column, and the home page displays the title and content according to the column configuration.

Structured results are saved as the day's home overview and participate in daily note generation. The final daily note content depends on whether AI merge succeeds: when merge succeeds, the model's returned Markdown is used; when merge fails or no model is available, the application's local merge result is used. The application does not guarantee that an unprocessed copy of the original input is retained separately when AI merge succeeds.

When generating again, new results are merged with the existing overview; existing column content is not unconditionally cleared due to an empty result. If no model is available, the provider is unreachable, the request fails, or the structured result does not match column definitions, the text and saved images are still preserved.
