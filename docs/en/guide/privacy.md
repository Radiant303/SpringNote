# Privacy & Security

SpringNote handles local records and AI services separately. Notes and images are stored by default in the data directory you choose; files selected from the home page are not copied as local attachments, but file names and paths may be sent to model services per your configuration when using AI features.

## Local Data

The data directory contains daily, weekly, and monthly notes, images, and application configuration. File selection from the home page does not copy the original files into the data directory. Keep the data directory in a location you control and back up important content; do not place it in a temporary directory that may be automatically cleaned.

## AI Requests

Features such as Smart Generation on the home page, real-time completion in the notebook, and Memory Book answers may send relevant text, images, or retrieved records to the selected provider. Before use, review the provider's privacy policy, account permissions, and data retention rules.

When AI features are not invoked, normal input, saving, editing, previewing, and local search do not automatically upload records simply because the application is open.

## API Key Security

Provider API keys should only be entered in the application settings. Do not include them in notes, screenshots, public repositories, or shared documents. If you suspect a key has been compromised, revoke and regenerate it immediately on the provider side.

## Images and File Paths

When adding an image, SpringNote copies it to the current data directory; the original file is not deleted. Regular files currently send only the file name and path information — the application does not read file contents or copy the file. Deleting an image link from a note does not automatically delete the image from the data directory; cleanup must be confirmed in Storage Management.

## Cloud Sync

When cloud sync is enabled, data is sent to the configured service according to the sync strategy. The security, access control, and retention policies of the sync service are determined by that service. Local editing remains available when the network is unreachable.
