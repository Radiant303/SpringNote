# Storage Management

Storage Management handles images that are no longer referenced by notes. It follows a "scan, confirm, clean up" process to avoid accidentally deleting files just because a Markdown image link was removed.

## Image Scan

Clicking "Scan Images" checks the images in the data directory and finds files still referenced by daily, weekly, or monthly notes. The scanning phase only reads and compiles results; it does not modify or delete files.

Scanning captures the data state at the start of the scan. Note saves that occur during scanning may not be reflected in the current results; a subsequent scan is needed to obtain the new reference status.

## Image Preview

The preview list is used to confirm what the candidate images actually contain. After selecting an image, you can view the thumbnail, file info, and reference status. If you are unsure about an image's purpose, do not delete it directly; first return to the relevant note to confirm.

## Clean Up Unused Images

1. After scanning, review the candidate list.
2. Preview images and confirm they are no longer needed.
3. Select the images to clean up.
4. Click "Clean Up" and confirm deletion.

Cleanup only targets images within the application data directory that are determined to be unused; it does not scan or delete files in other user directories. Deleted files cannot be recovered through SpringNote, so important images should be backed up first.
