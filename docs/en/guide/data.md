# Cloud Sync

Cloud sync synchronizes notes and images referenced in notes between the local data directory and a WebDAV service. Synchronization is bidirectional: locally added or modified content can be uploaded, and cloud-added or modified content can be downloaded. Cloud sync is not equivalent to independent backup; deletion confirmation and conflict handling are still governed by sync rules.

## Connection Settings

Cloud sync uses a WebDAV service as remote storage. Connection settings include:

- **Enable Cloud Sync**: Controls whether cloud sync is available. When disabled, startup sync, real-time sync, and manual sync will not execute.
- **WebDAV URL**: Enter the full `http` or `https` address.
- **Account**: Enter the account used for the WebDAV service.
- **Password or App Token**: Enter the password or app-specific token required by the service.

Once cloud sync is enabled, connection information can be edited and tested. Testing the connection checks whether the remote service is accessible and attempts to prepare the remote directory used by SpringNote. The test process does not modify local notes or images. If the test fails, the page retains local data and the current configuration.

Connection failures typically manifest as incorrect URL format, account or token without permission, network connection failure, request timeout, or unrecognized content returned by the remote service. A successful connection test only indicates that the current connection and directory preparation can complete; it does not guarantee that all subsequent sync operations will succeed.

## Sync Strategies

The page provides the following sync timings:

- **Auto sync on startup**: Triggers sync on launch when cloud sync is enabled and the setting is on.
- **Real-time sync**: Triggers sync when local data changes, provided cloud sync is enabled and connection info is complete.
- **Manual sync**: Initiates a sync immediately via the manual sync button on the cloud sync page.
- **Last full sync**: Shows the timestamp of the most recent successful full sync, indicating when local and cloud were last fully aligned.

During connection testing and sync execution, related buttons enter a busy state to prevent duplicate operations. After a successful sync, the last full sync time is updated. If sync fails, local edits are preserved, and sync can be triggered again once the connection is restored.

## Sync Scope

Cloud sync includes:

- Daily notes
- Weekly notes
- Monthly notes
- Shared images referenced in Markdown content

Regular files selected from the home page input box currently only have their file names and paths included in the input content; they are not copied as actual attachments to the note data directory and therefore are not treated as cloud sync files.

## File Changes

Sync identifies changes on both sides based on file content, not just file names. Common change handling:

- New notes or images added locally are uploaded to the cloud.
- New notes or images added on the cloud are downloaded locally.
- When only one side has been modified, changes are synced to the other side.
- When both sides have been modified simultaneously, the local version is retained and the cloud version is saved as a conflict copy, with the conflict count recorded in the sync results.

Sync only processes the remote directory used by SpringNote and files within the sync scope; it does not import other directories in the WebDAV account as note content.

## Deletion Confirmation

Deletion requires confirmation in bidirectional sync. To prevent accidental deletion on one side from propagating to the other, the following situations do not execute deletion immediately:

- A local file has been deleted, but it still exists on the cloud.
- A cloud file has been deleted, but it still exists locally.

The sync page lists pending local and cloud file deletions, requiring step-by-step confirmation through a popup. If confirmation is cancelled, the corresponding deletion is not executed; other sync content not involving deletions continues processing.

If after a deletion, the other side modifies the same file, a deletion-modification conflict occurs. In this case, you need to choose: overwrite local, overwrite remote, or skip. If there are continuously pending items, the page processes them in rounds, up to five rounds; items still remaining require a new sync to be initiated.

## Conflict Handling

A conflict occurs when both local and cloud files have changed since the last sync, making it unclear which version should take precedence. For simultaneous modifications, the local version is retained and the cloud version is saved as a conflict copy to prevent direct data loss.

When deletion and modification occur simultaneously, the conflict popup provides three options:

- **Overwrite local**: Use the cloud version to restore or overwrite the local file.
- **Overwrite remote**: Use the local version to restore or overwrite the cloud file.
- **Skip**: Keep both sides as-is; do not process this conflict.

## Status & Errors

The cloud sync page distinguishes between states such as connecting, syncing, sync successful, and sync failed. Failure reasons may include:

- WebDAV URL format is incorrect.
- Account or password/app token is invalid, or no remote directory permission.
- Network is unavailable or request times out.
- Local file read, write, or deletion fails.
- Remote returned content cannot be parsed.
- Cloud sync feature is not enabled.

When the network is unavailable, local notes can still be created and edited normally. Sync does not clear local content due to local operation failures. After the connection and permissions are restored, you can re-run manual sync or wait for the conditions of enabled startup sync or real-time sync to be met again.
