use chrono::{DateTime, Local};
use reqwest::{Client, Method, StatusCode, Url};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeSet, HashMap};
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, UNIX_EPOCH};

const REMOTE_ROOT_DIRECTORY: &str = "SpringNote";
const REMOTE_NOTES_DIRECTORY: &str = "notes";
const IMAGES_DIRECTORY_NAME: &str = "images";
const MANIFEST_FILE_NAME: &str = ".springnote-sync.json";
const MANIFEST_VERSION: &str = "2";
const HTTP_TIMEOUT_SECS: u64 = 15;

#[derive(Clone, Debug)]
pub struct CloudSyncConfig {
    pub enabled: bool,
    pub server_url: String,
    pub username: String,
    pub password: String,
}

#[derive(Clone, Debug)]
pub struct CloudSyncRequest {
    pub config: CloudSyncConfig,
    pub data_directory: String,
    pub daily_notes_directory: String,
    pub weekly_notes_directory: String,
    pub monthly_notes_directory: String,
    pub trigger: String,
    pub confirmed_delete_local: Vec<String>,
    pub confirmed_delete_remote: Vec<String>,
    pub confirmed_overwrite_local: Vec<String>,
    pub confirmed_overwrite_remote: Vec<String>,
    pub skipped_delete_modify_conflicts: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct CloudSyncNoteUploadRequest {
    pub config: CloudSyncConfig,
    pub data_directory: String,
    pub daily_notes_directory: String,
    pub weekly_notes_directory: String,
    pub monthly_notes_directory: String,
    pub note_path: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CloudSyncResult {
    pub ok: bool,
    pub message: String,
    pub uploaded: i32,
    pub downloaded: i32,
    pub conflicts: i32,
    pub synced_at: String,
    pub error_code: String,
    pub needs_delete_confirmation: bool,
    pub pending_delete_local: Vec<String>,
    pub pending_delete_remote: Vec<String>,
    pub needs_delete_modify_confirmation: bool,
    pub pending_delete_modify_conflicts: Vec<DeleteModifyConflict>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DeleteModifyConflict {
    pub relative_path: String,
    pub direction: String,
}

#[derive(Clone, Debug)]
pub struct WebDavFile {
    pub name: String,
    pub url: String,
    pub is_directory: bool,
    pub modified: String,
    pub modified_ms: i64,
    pub size: i64,
    pub etag: String,
}

#[derive(Debug)]
pub enum CloudSyncError {
    Validation(String),
    WebDav { action: String, status: u16 },
    NotFound(String),
    Network(String),
    Io(String),
    Url(String),
    Parse(String),
}

impl fmt::Display for CloudSyncError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CloudSyncError::Validation(message) => write!(formatter, "{message}"),
            CloudSyncError::WebDav { action, status } => {
                if *status == 401 || *status == 403 {
                    write!(formatter, "{action}: 账号或令牌无权限")
                } else {
                    write!(formatter, "{action}: HTTP {status}")
                }
            }
            CloudSyncError::NotFound(url) => write!(formatter, "远端文件不存在: {url}"),
            CloudSyncError::Network(message) => {
                write!(formatter, "无法连接 WebDAV 服务: {message}")
            }
            CloudSyncError::Io(message) => write!(formatter, "本地文件读写失败: {message}"),
            CloudSyncError::Url(message) => write!(formatter, "WebDAV 地址格式不正确: {message}"),
            CloudSyncError::Parse(message) => {
                write!(formatter, "WebDAV 返回内容无法解析: {message}")
            }
        }
    }
}

impl std::error::Error for CloudSyncError {}

impl From<std::io::Error> for CloudSyncError {
    fn from(error: std::io::Error) -> Self {
        CloudSyncError::Io(error.to_string())
    }
}

impl From<reqwest::Error> for CloudSyncError {
    fn from(error: reqwest::Error) -> Self {
        if error.is_timeout() {
            return CloudSyncError::Network("连接 WebDAV 超时".to_string());
        }
        CloudSyncError::Network(error.to_string())
    }
}

trait WebDavClient {
    async fn ensure_directory(
        &self,
        url: &str,
        config: &CloudSyncConfig,
    ) -> Result<(), CloudSyncError>;

    async fn list_files(
        &self,
        url: &str,
        config: &CloudSyncConfig,
    ) -> Result<Vec<WebDavFile>, CloudSyncError>;

    async fn read_bytes(
        &self,
        url: &str,
        config: &CloudSyncConfig,
    ) -> Result<Vec<u8>, CloudSyncError>;

    async fn write_bytes(
        &self,
        url: &str,
        config: &CloudSyncConfig,
        bytes: &[u8],
    ) -> Result<(), CloudSyncError>;

    async fn delete_file(&self, url: &str, config: &CloudSyncConfig) -> Result<(), CloudSyncError>;
}

pub async fn test_connection(config: CloudSyncConfig) -> CloudSyncResult {
    match test_connection_with_client(&HttpWebDavClient::new(), &config).await {
        Ok(()) => CloudSyncResult::success("连接成功", 0, 0, 0),
        Err(error) => CloudSyncResult::error(error),
    }
}

pub async fn sync(request: CloudSyncRequest) -> CloudSyncResult {
    match sync_with_client(&HttpWebDavClient::new(), request).await {
        Ok(result) => result,
        Err(error) => CloudSyncResult::error(error),
    }
}

pub async fn upload_note(request: CloudSyncNoteUploadRequest) -> CloudSyncResult {
    match upload_note_with_client(&HttpWebDavClient::new(), request).await {
        Ok(result) => result,
        Err(error) => CloudSyncResult::error(error),
    }
}

async fn test_connection_with_client<C: WebDavClient + Sync>(
    client: &C,
    config: &CloudSyncConfig,
) -> Result<(), CloudSyncError> {
    validate_config(config)?;
    let context = CloudSyncContext::new(config)?;
    client
        .ensure_directory(&context.remote_root_url, config)
        .await?;
    client
        .ensure_directory(&context.remote_notes_url, config)
        .await?;
    Ok(())
}

async fn sync_with_client<C: WebDavClient + Sync>(
    client: &C,
    request: CloudSyncRequest,
) -> Result<CloudSyncResult, CloudSyncError> {
    if !request.config.enabled {
        return Ok(CloudSyncResult::failure("云同步未启用", "disabled"));
    }
    validate_config(&request.config)?;

    let context = CloudSyncContext::new(&request.config)?;
    ensure_remote_note_directories(client, &context, &request.config).await?;

    let local_manifest = read_local_manifest(&request)?;
    let remote_manifest = read_remote_manifest(client, &context, &request.config).await?;
    let previous_entries = local_manifest.entries;

    let local_files = scan_local_notes(&request, &previous_entries)?;
    let remote_files =
        scan_remote_notes(client, &context, &request.config, &previous_entries).await?;
    let mut all_paths = BTreeSet::new();
    all_paths.extend(local_files.keys().cloned());
    all_paths.extend(remote_files.keys().cloned());
    all_paths.extend(previous_entries.keys().cloned());
    all_paths.extend(remote_manifest.entries.keys().cloned());

    let mut uploaded = 0;
    let mut downloaded = 0;
    let mut conflicts = 0;
    let mut deleted = 0;
    let mut pending_delete_local = Vec::new();
    let mut pending_delete_remote = Vec::new();
    let confirmed_delete_local = request
        .confirmed_delete_local
        .iter()
        .cloned()
        .collect::<BTreeSet<_>>();
    let confirmed_delete_remote = request
        .confirmed_delete_remote
        .iter()
        .cloned()
        .collect::<BTreeSet<_>>();
    let confirmed_overwrite_local = request
        .confirmed_overwrite_local
        .iter()
        .cloned()
        .collect::<BTreeSet<_>>();
    let confirmed_overwrite_remote = request
        .confirmed_overwrite_remote
        .iter()
        .cloned()
        .collect::<BTreeSet<_>>();
    let skipped_delete_modify_conflicts = request
        .skipped_delete_modify_conflicts
        .iter()
        .cloned()
        .collect::<BTreeSet<_>>();
    let mut next_entries = remote_manifest.entries;
    let synced_at = Local::now().to_rfc3339();
    let mut pending_delete_modify_conflicts = Vec::new();

    for relative_path in all_paths {
        let previous = previous_entries
            .get(&relative_path)
            .filter(|entry| !entry.deleted && !entry.sha256.is_empty());
        let local = local_files.get(&relative_path);
        let remote = remote_files.get(&relative_path);

        if local.is_none() && remote.is_none() {
            if let Some(entry) = previous_entries.get(&relative_path) {
                if entry.deleted {
                    next_entries.insert(relative_path, entry.clone());
                }
            }
            continue;
        }

        let local_changed = local
            .zip(previous)
            .map(|(file, entry)| file.sha256 != entry.sha256)
            .unwrap_or(false);
        let remote_changed = remote
            .zip(previous)
            .map(|(file, entry)| file.sha256 != entry.sha256)
            .unwrap_or(false);

        match (local, remote) {
            (Some(local_file), None) => {
                if previous.is_some() && !local_changed {
                    if confirmed_delete_local.contains(&relative_path) {
                        delete_local_file(&request, local_file)?;
                        deleted += 1;
                        next_entries.insert(
                            relative_path,
                            SyncManifestEntry::deleted(local_file, &synced_at),
                        );
                    } else {
                        pending_delete_local.push(relative_path.clone());
                        next_entries.insert(
                            relative_path,
                            SyncManifestEntry::from_local(local_file, &synced_at),
                        );
                    }
                    continue;
                }

                if previous.is_some() && local_changed {
                    if confirmed_overwrite_remote.contains(&relative_path) {
                        upload_local_file(client, &context, &request.config, local_file).await?;
                        uploaded += 1;
                        next_entries.insert(
                            relative_path,
                            SyncManifestEntry::from_uploaded(local_file, &synced_at),
                        );
                    } else if confirmed_overwrite_local.contains(&relative_path) {
                        delete_local_file(&request, local_file)?;
                        deleted += 1;
                        next_entries.insert(
                            relative_path,
                            SyncManifestEntry::deleted(local_file, &synced_at),
                        );
                    } else if let Some(entry) = previous {
                        let pending_path = relative_path.clone();
                        next_entries.insert(relative_path, entry.clone());
                        if !skipped_delete_modify_conflicts.contains(&pending_path) {
                            pending_delete_modify_conflicts.push(DeleteModifyConflict {
                                relative_path: pending_path,
                                direction: "local_modified_remote_deleted".to_string(),
                            });
                        }
                    }
                    continue;
                }

                upload_local_file(client, &context, &request.config, local_file).await?;
                uploaded += 1;
                next_entries.insert(
                    relative_path,
                    SyncManifestEntry::from_uploaded(local_file, &synced_at),
                );
            }
            (None, Some(remote_file)) => {
                if previous.is_some() && !remote_changed {
                    if confirmed_delete_remote.contains(&relative_path) {
                        delete_remote_file(client, &request.config, remote_file).await?;
                        deleted += 1;
                        next_entries.insert(
                            relative_path,
                            SyncManifestEntry::deleted_remote(remote_file, &synced_at),
                        );
                    } else {
                        pending_delete_remote.push(relative_path.clone());
                        next_entries.insert(
                            relative_path,
                            SyncManifestEntry::from_remote(remote_file, &synced_at),
                        );
                    }
                    continue;
                }

                if previous.is_some() && remote_changed {
                    if confirmed_overwrite_local.contains(&relative_path) {
                        let downloaded_file = download_remote_file(&request, remote_file)?;
                        downloaded += 1;
                        next_entries.insert(
                            relative_path,
                            SyncManifestEntry::from_synced(
                                &downloaded_file,
                                remote_file,
                                &synced_at,
                            ),
                        );
                    } else if confirmed_overwrite_remote.contains(&relative_path) {
                        delete_remote_file(client, &request.config, remote_file).await?;
                        deleted += 1;
                        next_entries.insert(
                            relative_path,
                            SyncManifestEntry::deleted_remote(remote_file, &synced_at),
                        );
                    } else if let Some(entry) = previous {
                        let pending_path = relative_path.clone();
                        next_entries.insert(relative_path, entry.clone());
                        if !skipped_delete_modify_conflicts.contains(&pending_path) {
                            pending_delete_modify_conflicts.push(DeleteModifyConflict {
                                relative_path: pending_path,
                                direction: "local_deleted_remote_modified".to_string(),
                            });
                        }
                    }
                    continue;
                }

                let downloaded_file = download_remote_file(&request, remote_file)?;
                downloaded += 1;
                next_entries.insert(
                    relative_path,
                    SyncManifestEntry::from_synced(&downloaded_file, remote_file, &synced_at),
                );
            }
            (Some(local_file), Some(remote_file)) if local_file.sha256 == remote_file.sha256 => {
                next_entries.insert(
                    relative_path,
                    SyncManifestEntry::from_synced(local_file, remote_file, &synced_at),
                );
            }
            (Some(local_file), Some(_remote_file)) if local_changed && !remote_changed => {
                upload_local_file(client, &context, &request.config, local_file).await?;
                uploaded += 1;
                next_entries.insert(
                    relative_path,
                    SyncManifestEntry::from_uploaded(local_file, &synced_at),
                );
            }
            (Some(_local_file), Some(remote_file)) if !local_changed && remote_changed => {
                let downloaded_file = download_remote_file(&request, remote_file)?;
                downloaded += 1;
                next_entries.insert(
                    relative_path,
                    SyncManifestEntry::from_synced(&downloaded_file, remote_file, &synced_at),
                );
            }
            (Some(local_file), Some(remote_file)) => {
                let conflict =
                    write_conflict_copy(client, &request, &context, &request.config, remote_file)
                        .await?;
                upload_local_file(client, &context, &request.config, local_file).await?;
                conflicts += 1;
                uploaded += 1;
                downloaded += 1;
                next_entries.insert(
                    local_file.relative_path.clone(),
                    SyncManifestEntry::from_uploaded(local_file, &synced_at),
                );
                next_entries.insert(
                    conflict.relative_path.clone(),
                    SyncManifestEntry::from_local(&conflict, &synced_at),
                );
            }
            (None, None) => {}
        }
    }

    if !pending_delete_local.is_empty()
        || !pending_delete_remote.is_empty()
        || !pending_delete_modify_conflicts.is_empty()
    {
        let next_manifest = SyncManifest {
            version: MANIFEST_VERSION.to_string(),
            entries: next_entries,
        };
        write_local_manifest(&request, &next_manifest)?;
        write_remote_manifest(client, &context, &request.config, &next_manifest).await?;
        let message = if !pending_delete_modify_conflicts.is_empty()
            && (pending_delete_local.is_empty() && pending_delete_remote.is_empty())
        {
            "检测到删除修改冲突，请选择处理方式"
        } else if !pending_delete_modify_conflicts.is_empty() {
            "检测到删除项和删除修改冲突，请确认后继续同步"
        } else {
            "检测到删除项，请确认后继续同步"
        };
        return Ok(CloudSyncResult {
            ok: true,
            message: message.to_string(),
            uploaded,
            downloaded,
            conflicts,
            synced_at: String::new(),
            error_code: String::new(),
            needs_delete_confirmation: !pending_delete_local.is_empty()
                || !pending_delete_remote.is_empty(),
            pending_delete_local,
            pending_delete_remote,
            needs_delete_modify_confirmation: !pending_delete_modify_conflicts.is_empty(),
            pending_delete_modify_conflicts,
        });
    }

    let next_manifest = SyncManifest {
        version: MANIFEST_VERSION.to_string(),
        entries: next_entries,
    };
    write_local_manifest(&request, &next_manifest)?;
    write_remote_manifest(client, &context, &request.config, &next_manifest).await?;

    Ok(CloudSyncResult {
        ok: true,
        message: success_message(&request.trigger, uploaded, downloaded, conflicts, deleted),
        uploaded,
        downloaded,
        conflicts,
        synced_at,
        error_code: String::new(),
        needs_delete_confirmation: false,
        pending_delete_local: Vec::new(),
        pending_delete_remote: Vec::new(),
        needs_delete_modify_confirmation: false,
        pending_delete_modify_conflicts: Vec::new(),
    })
}

async fn upload_note_with_client<C: WebDavClient + Sync>(
    client: &C,
    request: CloudSyncNoteUploadRequest,
) -> Result<CloudSyncResult, CloudSyncError> {
    if !request.config.enabled {
        return Ok(CloudSyncResult::failure("云同步未启用", "disabled"));
    }

    let sync_request = sync_request_from_note_upload_request(&request);
    let mut local_manifest = read_local_manifest(&sync_request)?;
    let note_metadata = local_note_metadata_for_upload_request(&request)?;
    let previous = local_manifest
        .entries
        .get(&note_metadata.relative_path)
        .filter(|entry| !entry.deleted && !entry.sha256.is_empty());
    if previous
        .map(|entry| !local_metadata_changed(note_metadata.size, note_metadata.modified_ms, entry))
        .unwrap_or(false)
    {
        return Ok(CloudSyncResult::success("笔记未变化", 0, 0, 0));
    }

    let note = local_sync_file_from_metadata(&note_metadata)?;
    if let Some(previous) = previous {
        if note.sha256 == previous.sha256 {
            let synced_at = Local::now().to_rfc3339();
            let mut next_entry = previous.clone();
            next_entry.size = note.size;
            next_entry.local_modified_ms = note.modified_ms;
            next_entry.synced_at = synced_at;
            local_manifest
                .entries
                .insert(note.relative_path.clone(), next_entry);
            write_local_manifest(&sync_request, &local_manifest)?;
            return Ok(CloudSyncResult::success("笔记未变化", 0, 0, 0));
        }
    }

    validate_config(&request.config)?;

    let context = CloudSyncContext::new(&request.config)?;
    ensure_remote_note_directories(client, &context, &request.config).await?;

    let mut files = vec![note.clone()];
    files.extend(collect_referenced_local_images(&request, &note)?);

    for file in &files {
        upload_local_file(client, &context, &request.config, file).await?;
    }

    let synced_at = Local::now().to_rfc3339();
    update_manifests_after_note_upload(client, &context, &request, &files, &synced_at).await?;

    Ok(CloudSyncResult {
        ok: true,
        message: format!("笔记自动同步完成: 上传 {}", files.len()),
        uploaded: files.len() as i32,
        downloaded: 0,
        conflicts: 0,
        synced_at,
        error_code: String::new(),
        needs_delete_confirmation: false,
        pending_delete_local: Vec::new(),
        pending_delete_remote: Vec::new(),
        needs_delete_modify_confirmation: false,
        pending_delete_modify_conflicts: Vec::new(),
    })
}

async fn ensure_remote_note_directories<C: WebDavClient + Sync>(
    client: &C,
    context: &CloudSyncContext,
    config: &CloudSyncConfig,
) -> Result<(), CloudSyncError> {
    client
        .ensure_directory(&context.remote_root_url, config)
        .await?;
    client
        .ensure_directory(&context.remote_notes_url, config)
        .await?;
    for kind in NoteKind::all() {
        client
            .ensure_directory(&context.remote_note_directory_url(kind), config)
            .await?;
    }
    Ok(())
}

fn validate_config(config: &CloudSyncConfig) -> Result<(), CloudSyncError> {
    if config.server_url.trim().is_empty() {
        return Err(CloudSyncError::Validation(
            "请输入 WebDAV 服务器地址".to_string(),
        ));
    }
    let url = Url::parse(config.server_url.trim())
        .map_err(|_| CloudSyncError::Validation("WebDAV 地址格式不正确".to_string()))?;
    if url.host_str().is_none() {
        return Err(CloudSyncError::Validation(
            "WebDAV 地址格式不正确".to_string(),
        ));
    }
    if url.scheme() != "http" && url.scheme() != "https" {
        return Err(CloudSyncError::Validation(
            "WebDAV 地址仅支持 http 或 https".to_string(),
        ));
    }
    if config.username.trim().is_empty() {
        return Err(CloudSyncError::Validation("请输入 WebDAV 账号".to_string()));
    }
    if config.password.is_empty() {
        return Err(CloudSyncError::Validation(
            "请输入 WebDAV 密码或应用令牌".to_string(),
        ));
    }
    Ok(())
}

fn scan_local_notes(
    request: &CloudSyncRequest,
    previous_entries: &HashMap<String, SyncManifestEntry>,
) -> Result<HashMap<String, LocalSyncFile>, CloudSyncError> {
    let mut result = HashMap::new();
    for kind in NoteKind::all() {
        let directory = local_directory_for(request, kind);
        if !directory.exists() {
            continue;
        }
        scan_local_directory(kind, &directory, &directory, previous_entries, &mut result)?;
    }
    Ok(result)
}

fn scan_local_directory(
    kind: NoteKind,
    root: &Path,
    directory: &Path,
    previous_entries: &HashMap<String, SyncManifestEntry>,
    result: &mut HashMap<String, LocalSyncFile>,
) -> Result<(), CloudSyncError> {
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        let path = entry.path();
        if file_type.is_dir() {
            if should_descend_local_directory(kind, root, &path) {
                scan_local_directory(kind, root, &path, previous_entries, result)?;
            }
            continue;
        }
        if !file_type.is_file() || !should_sync_local_file(kind, root, &path) {
            continue;
        }
        let Some(name) = local_relative_name(root, &path) else {
            continue;
        };
        let metadata = fs::metadata(&path)?;
        let size = metadata.len();
        let modified_ms = modified_ms(&metadata);
        let relative_path = relative_note_path(kind, &name);
        let previous = previous_entries
            .get(&relative_path)
            .filter(|entry| !entry.deleted && !entry.sha256.is_empty());
        let needs_hash = previous
            .map(|entry| local_metadata_changed(size, modified_ms, entry))
            .unwrap_or(true);
        let (bytes, sha256) = if needs_hash {
            let bytes = fs::read(&path)?;
            let sha256 = sha256_hex(&bytes);
            (Some(bytes), sha256)
        } else {
            (
                None,
                previous
                    .map(|entry| entry.sha256.clone())
                    .unwrap_or_default(),
            )
        };
        result.insert(
            relative_path.clone(),
            LocalSyncFile {
                kind,
                name,
                relative_path,
                size,
                modified_ms,
                bytes,
                sha256,
            },
        );
    }
    Ok(())
}

fn local_metadata_changed(size: u64, modified_ms: i64, previous: &SyncManifestEntry) -> bool {
    size != previous.size || modified_ms != previous.local_modified_ms
}

fn should_descend_local_directory(kind: NoteKind, root: &Path, directory: &Path) -> bool {
    kind == NoteKind::Images && directory.strip_prefix(root).is_ok()
}

fn should_sync_local_file(kind: NoteKind, root: &Path, path: &Path) -> bool {
    if kind == NoteKind::Images {
        return path.strip_prefix(root).is_ok();
    }

    is_markdown_file(path) && path.parent() == Some(root)
}

fn local_relative_name(root: &Path, path: &Path) -> Option<String> {
    path.strip_prefix(root)
        .ok()?
        .components()
        .map(|component| component.as_os_str().to_str())
        .collect::<Option<Vec<_>>>()
        .map(|segments| segments.join("/"))
}

fn local_sync_file_from_path(
    kind: NoteKind,
    name: &str,
    path: &Path,
) -> Result<LocalSyncFile, CloudSyncError> {
    let metadata = fs::metadata(path)?;
    let bytes = fs::read(path)?;
    Ok(LocalSyncFile {
        kind,
        name: name.to_string(),
        relative_path: relative_note_path(kind, name),
        size: metadata.len(),
        modified_ms: modified_ms(&metadata),
        sha256: sha256_hex(&bytes),
        bytes: Some(bytes),
    })
}

fn local_sync_file_from_metadata(
    metadata: &LocalSyncFileMetadata,
) -> Result<LocalSyncFile, CloudSyncError> {
    local_sync_file_from_path(metadata.kind, &metadata.name, &metadata.path)
}

fn local_note_metadata_for_upload_request(
    request: &CloudSyncNoteUploadRequest,
) -> Result<LocalSyncFileMetadata, CloudSyncError> {
    let note_path = PathBuf::from(request.note_path.trim());
    if note_path.as_os_str().is_empty() {
        return Err(CloudSyncError::Validation("待上传笔记路径为空".to_string()));
    }
    if !note_path.exists() {
        return Err(CloudSyncError::Validation("待上传笔记不存在".to_string()));
    }

    for kind in NoteKind::all() {
        let root = local_directory_for_note_upload(request, kind);
        let Some(name) = local_relative_name_if_inside(&root, &note_path) else {
            continue;
        };
        if should_sync_local_file(kind, &root, &note_path) && is_markdown_file(&note_path) {
            let metadata = fs::metadata(&note_path)?;
            return Ok(LocalSyncFileMetadata {
                kind,
                relative_path: relative_note_path(kind, &name),
                name,
                path: note_path,
                size: metadata.len(),
                modified_ms: modified_ms(&metadata),
            });
        }
    }

    Err(CloudSyncError::Validation(
        "待上传笔记不在当前笔记目录内".to_string(),
    ))
}

fn modified_ms(metadata: &fs::Metadata) -> i64 {
    metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0)
}

fn remote_bytes(file: &RemoteSyncFile) -> Result<&[u8], CloudSyncError> {
    file.bytes
        .as_deref()
        .ok_or_else(|| CloudSyncError::Parse("远端文件内容尚未读取".to_string()))
}

fn local_bytes(file: &LocalSyncFile) -> Result<&[u8], CloudSyncError> {
    file.bytes
        .as_deref()
        .ok_or_else(|| CloudSyncError::Parse("本地文件内容尚未读取".to_string()))
}

fn remote_metadata_changed(file: &WebDavFile, previous: &SyncManifestEntry) -> bool {
    if !file.etag.is_empty()
        && !previous.remote_etag.is_empty()
        && file.etag == previous.remote_etag
    {
        return false;
    }
    if !file.modified.is_empty()
        && !previous.remote_modified.is_empty()
        && file.modified == previous.remote_modified
        && file.size >= 0
        && file.size == previous.remote_size
    {
        return false;
    }
    true
}

async fn scan_remote_notes<C: WebDavClient + Sync>(
    client: &C,
    context: &CloudSyncContext,
    config: &CloudSyncConfig,
    previous_entries: &HashMap<String, SyncManifestEntry>,
) -> Result<HashMap<String, RemoteSyncFile>, CloudSyncError> {
    let mut result = HashMap::new();
    for kind in NoteKind::all() {
        let mut pending = vec![(context.remote_note_directory_url(kind), String::new())];
        while let Some((directory_url, relative_directory)) = pending.pop() {
            let files = client.list_files(&directory_url, config).await?;
            for file in files {
                let child_name = if relative_directory.is_empty() {
                    file.name.clone()
                } else {
                    format!("{relative_directory}/{}", file.name)
                };
                if file.is_directory {
                    if should_descend_remote_directory(kind, &child_name) {
                        pending.push((file.url, child_name));
                    }
                    continue;
                }
                if !should_sync_remote_file(kind, &child_name) {
                    continue;
                }
                let Some(name) = sanitize_remote_relative_name(&child_name) else {
                    continue;
                };
                let relative_path = relative_note_path(kind, &name);
                let previous = previous_entries
                    .get(&relative_path)
                    .filter(|entry| !entry.deleted && !entry.sha256.is_empty());
                let needs_hash = previous
                    .map(|entry| remote_metadata_changed(&file, entry))
                    .unwrap_or(true);
                let (bytes, sha256) = if needs_hash {
                    let bytes = client.read_bytes(&file.url, config).await?;
                    let sha256 = sha256_hex(&bytes);
                    (Some(bytes), sha256)
                } else {
                    (
                        None,
                        previous
                            .map(|entry| entry.sha256.clone())
                            .unwrap_or_default(),
                    )
                };
                result.insert(
                    relative_path.clone(),
                    RemoteSyncFile {
                        kind,
                        name,
                        url: file.url,
                        size: file.size,
                        modified: file.modified,
                        modified_ms: file.modified_ms,
                        etag: file.etag,
                        bytes,
                        sha256,
                    },
                );
            }
        }
    }
    Ok(result)
}

fn should_descend_remote_directory(kind: NoteKind, name: &str) -> bool {
    kind == NoteKind::Images && !name.is_empty()
}

fn should_sync_remote_file(kind: NoteKind, name: &str) -> bool {
    if kind == NoteKind::Images {
        return true;
    }

    !name.contains('/') && name.to_lowercase().ends_with(".md")
}

fn sanitize_remote_relative_name(name: &str) -> Option<String> {
    let normalized = name.replace('\\', "/");
    let mut segments = Vec::new();
    for segment in normalized.split('/') {
        if segment.is_empty() || segment == "." || segment == ".." {
            return None;
        }
        segments.push(segment);
    }
    if segments.is_empty() {
        return None;
    }
    Some(segments.join("/"))
}

async fn upload_local_file<C: WebDavClient + Sync>(
    client: &C,
    context: &CloudSyncContext,
    config: &CloudSyncConfig,
    file: &LocalSyncFile,
) -> Result<(), CloudSyncError> {
    ensure_remote_parent_directories(client, context, config, file.kind, &file.name).await?;
    let bytes = local_bytes(file)?;
    client
        .write_bytes(
            &context.remote_note_file_url(file.kind, &file.name),
            config,
            bytes,
        )
        .await
}

fn collect_referenced_local_images(
    request: &CloudSyncNoteUploadRequest,
    note: &LocalSyncFile,
) -> Result<Vec<LocalSyncFile>, CloudSyncError> {
    let markdown = String::from_utf8_lossy(local_bytes(note)?);
    let mut names = BTreeSet::new();
    for target in markdown_link_targets(&markdown) {
        if let Some(name) = shared_image_name_from_markdown_target(&target) {
            names.insert(name);
        }
    }

    let mut files = Vec::new();
    for name in names {
        let root = local_directory_for_note_upload(request, NoteKind::Images);
        let path = local_path_from_relative_name(&root, &name);
        if !path.exists() || !should_sync_local_file(NoteKind::Images, &root, &path) {
            continue;
        }
        files.push(local_sync_file_from_path(NoteKind::Images, &name, &path)?);
    }
    Ok(files)
}

fn download_remote_file(
    request: &CloudSyncRequest,
    file: &RemoteSyncFile,
) -> Result<LocalSyncFile, CloudSyncError> {
    let local_path = local_directory_for(request, file.kind).join(&file.name);
    if let Some(parent) = local_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let bytes = remote_bytes(file)?.to_vec();
    fs::write(&local_path, &bytes)?;
    local_sync_file_from_path(file.kind, &file.name, &local_path)
}

fn delete_local_file(
    request: &CloudSyncRequest,
    file: &LocalSyncFile,
) -> Result<(), CloudSyncError> {
    let path = local_directory_for(request, file.kind).join(&file.name);
    if path.exists() {
        fs::remove_file(path)?;
    }
    Ok(())
}

async fn delete_remote_file<C: WebDavClient + Sync>(
    client: &C,
    config: &CloudSyncConfig,
    file: &RemoteSyncFile,
) -> Result<(), CloudSyncError> {
    client.delete_file(&file.url, config).await
}

async fn write_conflict_copy<C: WebDavClient + Sync>(
    client: &C,
    request: &CloudSyncRequest,
    context: &CloudSyncContext,
    config: &CloudSyncConfig,
    remote: &RemoteSyncFile,
) -> Result<LocalSyncFile, CloudSyncError> {
    let conflict_name = conflict_name(&remote.name);
    let conflict_path = local_directory_for(request, remote.kind).join(&conflict_name);
    if let Some(parent) = conflict_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let bytes = remote_bytes(remote)?.to_vec();
    fs::write(&conflict_path, &bytes)?;

    let conflict = local_sync_file_from_path(remote.kind, &conflict_name, &conflict_path)?;
    upload_local_file(client, context, config, &conflict).await?;
    Ok(conflict)
}

async fn ensure_remote_parent_directories<C: WebDavClient + Sync>(
    client: &C,
    context: &CloudSyncContext,
    config: &CloudSyncConfig,
    kind: NoteKind,
    name: &str,
) -> Result<(), CloudSyncError> {
    let segments = name.split('/').collect::<Vec<_>>();
    if segments.len() <= 1 {
        return Ok(());
    }
    let mut current = context.remote_note_directory_url(kind);
    for segment in &segments[..segments.len() - 1] {
        current = append_path(
            &Url::parse(&current).map_err(|error| CloudSyncError::Url(error.to_string()))?,
            segment,
            true,
        )?;
        client.ensure_directory(&current, config).await?;
    }
    Ok(())
}

fn read_local_manifest(request: &CloudSyncRequest) -> Result<SyncManifest, CloudSyncError> {
    let path = Path::new(&request.data_directory).join(MANIFEST_FILE_NAME);
    if !path.exists() {
        return Ok(SyncManifest::default());
    }
    let content = fs::read_to_string(path)?;
    Ok(serde_json::from_str(&content).unwrap_or_default())
}

fn write_local_manifest(
    request: &CloudSyncRequest,
    manifest: &SyncManifest,
) -> Result<(), CloudSyncError> {
    let path = Path::new(&request.data_directory).join(MANIFEST_FILE_NAME);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(
        path,
        format!("{}\n", serde_json::to_string(manifest).unwrap_or_default()),
    )?;
    Ok(())
}

async fn read_remote_manifest<C: WebDavClient + Sync>(
    client: &C,
    context: &CloudSyncContext,
    config: &CloudSyncConfig,
) -> Result<SyncManifest, CloudSyncError> {
    match client
        .read_bytes(&context.remote_manifest_url, config)
        .await
    {
        Ok(bytes) => serde_json::from_slice(&bytes)
            .map_err(|error| CloudSyncError::Parse(format!("远端同步清单解析失败: {error}"))),
        Err(CloudSyncError::NotFound(_)) => Ok(SyncManifest::default()),
        Err(error) => Err(error),
    }
}

async fn write_remote_manifest<C: WebDavClient + Sync>(
    client: &C,
    context: &CloudSyncContext,
    config: &CloudSyncConfig,
    manifest: &SyncManifest,
) -> Result<(), CloudSyncError> {
    let bytes =
        serde_json::to_vec(manifest).map_err(|error| CloudSyncError::Parse(error.to_string()))?;
    client
        .write_bytes(&context.remote_manifest_url, config, &bytes)
        .await
}

async fn update_manifests_after_note_upload<C: WebDavClient + Sync>(
    client: &C,
    context: &CloudSyncContext,
    request: &CloudSyncNoteUploadRequest,
    files: &[LocalSyncFile],
    synced_at: &str,
) -> Result<(), CloudSyncError> {
    let sync_request = sync_request_from_note_upload_request(request);

    let mut local_manifest = read_local_manifest(&sync_request)?;
    for file in files {
        local_manifest.entries.insert(
            file.relative_path.clone(),
            SyncManifestEntry::from_uploaded(file, synced_at),
        );
    }
    write_local_manifest(&sync_request, &local_manifest)?;

    let mut remote_manifest = read_remote_manifest(client, context, &request.config).await?;
    for file in files {
        remote_manifest.entries.insert(
            file.relative_path.clone(),
            SyncManifestEntry::from_uploaded(file, synced_at),
        );
    }
    write_remote_manifest(client, context, &request.config, &remote_manifest).await
}

fn local_directory_for(request: &CloudSyncRequest, kind: NoteKind) -> PathBuf {
    match kind {
        NoteKind::Daily => PathBuf::from(&request.daily_notes_directory),
        NoteKind::Weekly => PathBuf::from(&request.weekly_notes_directory),
        NoteKind::Monthly => PathBuf::from(&request.monthly_notes_directory),
        NoteKind::Images => shared_images_directory(&request.daily_notes_directory),
    }
}

fn local_directory_for_note_upload(
    request: &CloudSyncNoteUploadRequest,
    kind: NoteKind,
) -> PathBuf {
    match kind {
        NoteKind::Daily => PathBuf::from(&request.daily_notes_directory),
        NoteKind::Weekly => PathBuf::from(&request.weekly_notes_directory),
        NoteKind::Monthly => PathBuf::from(&request.monthly_notes_directory),
        NoteKind::Images => shared_images_directory(&request.daily_notes_directory),
    }
}

fn shared_images_directory(daily_notes_directory: &str) -> PathBuf {
    let daily = PathBuf::from(daily_notes_directory);
    daily
        .parent()
        .map(|parent| parent.join(IMAGES_DIRECTORY_NAME))
        .unwrap_or_else(|| PathBuf::from(IMAGES_DIRECTORY_NAME))
}

fn sync_request_from_note_upload_request(request: &CloudSyncNoteUploadRequest) -> CloudSyncRequest {
    CloudSyncRequest {
        config: request.config.clone(),
        data_directory: request.data_directory.clone(),
        daily_notes_directory: request.daily_notes_directory.clone(),
        weekly_notes_directory: request.weekly_notes_directory.clone(),
        monthly_notes_directory: request.monthly_notes_directory.clone(),
        trigger: "auto_note_upload".to_string(),
        confirmed_delete_local: Vec::new(),
        confirmed_delete_remote: Vec::new(),
        confirmed_overwrite_local: Vec::new(),
        confirmed_overwrite_remote: Vec::new(),
        skipped_delete_modify_conflicts: Vec::new(),
    }
}

fn local_relative_name_if_inside(root: &Path, path: &Path) -> Option<String> {
    if let Some(name) = local_relative_name(root, path) {
        return Some(name);
    }

    let root = normalize_local_path_for_compare(root);
    let path = path.to_string_lossy().replace('\\', "/");
    let comparable_root = root.to_lowercase();
    let comparable_path = path.to_lowercase();
    let prefix = format!("{comparable_root}/");
    if !comparable_path.starts_with(&prefix) {
        return None;
    }
    let relative = path[root.len() + 1..].to_string();
    sanitize_remote_relative_name(&relative)
}

fn normalize_local_path_for_compare(path: &Path) -> String {
    path.to_string_lossy()
        .replace('\\', "/")
        .trim_end_matches('/')
        .to_string()
}

fn local_path_from_relative_name(root: &Path, name: &str) -> PathBuf {
    let mut path = root.to_path_buf();
    for segment in name.split('/') {
        path.push(segment);
    }
    path
}

fn markdown_link_targets(markdown: &str) -> Vec<String> {
    let bytes = markdown.as_bytes();
    let mut targets = Vec::new();
    let mut offset = 0;
    while let Some(open) = markdown[offset..].find("](") {
        let start = offset + open + 2;
        let mut end = start;
        let mut escaped = false;
        while end < bytes.len() {
            let byte = bytes[end];
            if escaped {
                escaped = false;
                end += 1;
                continue;
            }
            if byte == b'\\' {
                escaped = true;
                end += 1;
                continue;
            }
            if byte == b')' {
                break;
            }
            end += 1;
        }
        if end >= bytes.len() {
            break;
        }
        targets.push(markdown[start..end].trim().to_string());
        offset = end + 1;
    }
    targets
}

fn shared_image_name_from_markdown_target(target: &str) -> Option<String> {
    let target = markdown_target_path_part(target)?;
    let target = strip_query_and_fragment(target);
    if target.is_empty()
        || target.starts_with('/')
        || target.contains("://")
        || target.to_lowercase().starts_with("file:")
        || target.contains(':')
    {
        return None;
    }

    let decoded = percent_encoding::percent_decode_str(target)
        .decode_utf8_lossy()
        .replace('\\', "/");
    let mut segments = Vec::new();
    for segment in decoded.split('/') {
        if segment.is_empty() || segment == "." {
            return None;
        }
        segments.push(segment);
    }

    if segments.len() >= 3
        && segments[0] == ".."
        && segments[1].eq_ignore_ascii_case(IMAGES_DIRECTORY_NAME)
        && !segments[2..].iter().any(|segment| *segment == "..")
    {
        return Some(segments[2..].join("/"));
    }

    None
}

fn markdown_target_path_part(target: &str) -> Option<&str> {
    let value = target.trim();
    if value.is_empty() {
        return None;
    }
    if let Some(rest) = value.strip_prefix('<') {
        return rest.find('>').map(|end| &rest[..end]);
    }
    if let Some(index) = value.find(char::is_whitespace) {
        let rest = value[index..].trim_start();
        if rest.starts_with('"') || rest.starts_with('\'') || rest.starts_with('(') {
            return Some(&value[..index]);
        }
    }
    Some(value)
}

fn strip_query_and_fragment(value: &str) -> &str {
    let query = value.find('?');
    let fragment = value.find('#');
    let cutoff = match (query, fragment) {
        (Some(left), Some(right)) => left.min(right),
        (Some(value), None) | (None, Some(value)) => value,
        (None, None) => value.len(),
    };
    &value[..cutoff]
}

fn relative_note_path(kind: NoteKind, name: &str) -> String {
    format!("notes/{}/{name}", kind.directory_name())
}

fn conflict_name(name: &str) -> String {
    let stamp = Local::now().format("%Y%m%d%H%M%S");
    if let Some((base, extension)) = name.rsplit_once('.') {
        return format!("{base}.conflict-{stamp}.{extension}");
    }
    format!("{name}.conflict-{stamp}")
}

fn success_message(
    trigger: &str,
    uploaded: i32,
    downloaded: i32,
    conflicts: i32,
    deleted: i32,
) -> String {
    let prefix = match trigger {
        "startup" => "启动同步完成",
        _ => "手动同步完成",
    };
    let delete_suffix = if deleted > 0 {
        format!(", 删除 {deleted}")
    } else {
        String::new()
    };
    format!("{prefix}: 上传 {uploaded}, 下载 {downloaded}, 冲突 {conflicts}{delete_suffix}")
}

fn is_markdown_file(path: &Path) -> bool {
    path.extension()
        .and_then(|value| value.to_str())
        .map(|value| value.eq_ignore_ascii_case("md"))
        .unwrap_or(false)
}

fn sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn append_path(base: &Url, segment: &str, directory: bool) -> Result<String, CloudSyncError> {
    let mut url = base.clone();
    {
        let mut segments = url
            .path_segments_mut()
            .map_err(|_| CloudSyncError::Url("无法追加路径".to_string()))?;
        segments.pop_if_empty();
        segments.push(segment);
        if directory {
            segments.push("");
        }
    }
    Ok(url.to_string())
}

fn directory_url(url: &str) -> Result<String, CloudSyncError> {
    let parsed = Url::parse(url).map_err(|error| CloudSyncError::Url(error.to_string()))?;
    if parsed.path().ends_with('/') {
        return Ok(parsed.to_string());
    }
    let mut with_slash = parsed;
    with_slash.set_path(&format!("{}/", with_slash.path()));
    Ok(with_slash.to_string())
}

fn normalize_path(path: &str, directory: bool) -> String {
    let mut result = path.replace('\\', "/");
    while result.contains("//") {
        result = result.replace("//", "/");
    }
    if !result.starts_with('/') {
        result = format!("/{result}");
    }
    if directory && !result.ends_with('/') {
        result.push('/');
    }
    if !directory {
        result = result.trim_end_matches('/').to_string();
    }
    result
}

fn decode_xml(value: &str) -> String {
    value
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
}

fn decode_percent_path_segment(value: &str) -> String {
    percent_encoding::percent_decode_str(value)
        .decode_utf8_lossy()
        .to_string()
}

fn tag_text(source: &str, tag: &str) -> String {
    let Some(start) = find_tag(source, tag, 0, true) else {
        return String::new();
    };
    let Some(end) = find_tag(source, tag, start.end, false) else {
        return String::new();
    };
    decode_xml(source[start.end..end.start].trim())
}

fn parse_webdav_modified_ms(value: &str) -> i64 {
    if value.trim().is_empty() {
        return 0;
    }
    DateTime::parse_from_rfc2822(value.trim())
        .or_else(|_| DateTime::parse_from_rfc3339(value.trim()))
        .map(|time| time.timestamp_millis())
        .unwrap_or(0)
}

fn parse_propfind_files(
    directory_url_value: &str,
    xml: &str,
) -> Result<Vec<WebDavFile>, CloudSyncError> {
    let directory = Url::parse(&directory_url(directory_url_value)?)
        .map_err(|error| CloudSyncError::Url(error.to_string()))?;
    let directory_path = normalize_path(directory.path(), true);
    let mut files = Vec::new();
    let mut offset = 0;

    while let Some(response_start) = find_tag(xml, "response", offset, true) {
        let Some(response_end) = find_tag(xml, "response", response_start.end, false) else {
            break;
        };
        let block = &xml[response_start.end..response_end.start];
        offset = response_end.end;

        let Some(href_start) = find_tag(block, "href", 0, true) else {
            continue;
        };
        let Some(href_end) = find_tag(block, "href", href_start.end, false) else {
            continue;
        };
        let href = decode_xml(block[href_start.end..href_end.start].trim());
        let href_url = directory
            .join(&href)
            .map_err(|error| CloudSyncError::Url(error.to_string()))?;
        let href_path = normalize_path(href_url.path(), href_url.path().ends_with('/'));
        if href_path == directory_path {
            continue;
        }
        let resource_type = tag_text(block, "resourcetype");
        let is_directory =
            href_path.ends_with('/') || resource_type.to_lowercase().contains("collection");
        let remainder = href_path
            .strip_prefix(&directory_path)
            .unwrap_or(&href_path)
            .trim_matches('/');
        if remainder.is_empty() || remainder.contains('/') {
            continue;
        }
        let modified = tag_text(block, "getlastmodified");
        let size = tag_text(block, "getcontentlength")
            .parse::<i64>()
            .unwrap_or(-1);
        files.push(WebDavFile {
            name: decode_percent_path_segment(remainder),
            url: href_url.to_string(),
            is_directory,
            modified_ms: parse_webdav_modified_ms(&modified),
            modified,
            size,
            etag: tag_text(block, "getetag"),
        });
    }

    Ok(files)
}

#[derive(Clone, Copy, Debug)]
struct TagMatch {
    start: usize,
    end: usize,
}

fn find_tag(source: &str, tag: &str, offset: usize, opening: bool) -> Option<TagMatch> {
    let needle = if opening {
        format!("<{tag}")
    } else {
        format!("</{tag}")
    };
    let prefixed_needle = if opening {
        format!(":{tag}")
    } else {
        format!(":{}", tag)
    };
    let lower = source[offset..].to_lowercase();
    let mut search_offset = 0;
    loop {
        let plain = lower[search_offset..].find(&needle);
        let prefixed = lower[search_offset..].find(&prefixed_needle);
        let relative = match (plain, prefixed) {
            (Some(left), Some(right)) => Some(left.min(right)),
            (Some(value), None) | (None, Some(value)) => Some(value),
            (None, None) => None,
        }?;
        let start = offset + search_offset + relative;
        let tag_start = source[..start].rfind('<')?;
        if tag_start > start || !source[tag_start..].starts_with('<') {
            search_offset += relative + 1;
            continue;
        }
        let end = source[start..].find('>').map(|value| start + value + 1)?;
        return Some(TagMatch {
            start: tag_start,
            end,
        });
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
enum NoteKind {
    Daily,
    Weekly,
    Monthly,
    Images,
}

impl NoteKind {
    fn all() -> [NoteKind; 4] {
        [
            NoteKind::Daily,
            NoteKind::Weekly,
            NoteKind::Monthly,
            NoteKind::Images,
        ]
    }

    fn directory_name(self) -> &'static str {
        match self {
            NoteKind::Daily => "daily",
            NoteKind::Weekly => "weekly",
            NoteKind::Monthly => "monthly",
            NoteKind::Images => "images",
        }
    }
}

#[derive(Clone, Debug)]
struct LocalSyncFile {
    kind: NoteKind,
    name: String,
    relative_path: String,
    size: u64,
    modified_ms: i64,
    bytes: Option<Vec<u8>>,
    sha256: String,
}

#[derive(Clone, Debug)]
struct LocalSyncFileMetadata {
    kind: NoteKind,
    name: String,
    relative_path: String,
    path: PathBuf,
    size: u64,
    modified_ms: i64,
}

#[derive(Clone, Debug)]
struct RemoteSyncFile {
    kind: NoteKind,
    name: String,
    url: String,
    size: i64,
    modified: String,
    modified_ms: i64,
    etag: String,
    bytes: Option<Vec<u8>>,
    sha256: String,
}

#[derive(Clone, Debug)]
struct CloudSyncContext {
    remote_root_url: String,
    remote_notes_url: String,
    remote_manifest_url: String,
}

impl CloudSyncContext {
    fn new(config: &CloudSyncConfig) -> Result<Self, CloudSyncError> {
        let mut base = Url::parse(config.server_url.trim())
            .map_err(|error| CloudSyncError::Url(error.to_string()))?;
        if base.path().is_empty() {
            base.set_path("/");
        }
        if !base.path().ends_with('/') {
            base.set_path(&format!("{}/", base.path()));
        }
        let remote_root_url = append_path(&base, REMOTE_ROOT_DIRECTORY, true)?;
        let remote_root =
            Url::parse(&remote_root_url).map_err(|error| CloudSyncError::Url(error.to_string()))?;
        let remote_notes_url = append_path(&remote_root, REMOTE_NOTES_DIRECTORY, true)?;
        let remote_manifest_url = append_path(&remote_root, MANIFEST_FILE_NAME, false)?;
        Ok(Self {
            remote_root_url,
            remote_notes_url,
            remote_manifest_url,
        })
    }

    fn remote_note_directory_url(&self, kind: NoteKind) -> String {
        append_path(
            &Url::parse(&self.remote_notes_url).expect("context url must be valid"),
            kind.directory_name(),
            true,
        )
        .expect("context url must support path segments")
    }

    fn remote_note_file_url(&self, kind: NoteKind, name: &str) -> String {
        let mut url =
            Url::parse(&self.remote_note_directory_url(kind)).expect("context url must be valid");
        {
            let mut segments = url
                .path_segments_mut()
                .expect("context url must support path segments");
            segments.pop_if_empty();
            for segment in name.split('/') {
                segments.push(segment);
            }
        }
        url.to_string()
    }
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
struct SyncManifest {
    #[serde(default = "manifest_version")]
    version: String,
    #[serde(default)]
    entries: HashMap<String, SyncManifestEntry>,
}

fn manifest_version() -> String {
    MANIFEST_VERSION.to_string()
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct SyncManifestEntry {
    #[serde(default)]
    sha256: String,
    #[serde(default)]
    size: u64,
    #[serde(default)]
    local_modified_ms: i64,
    #[serde(default)]
    remote_modified: String,
    #[serde(default)]
    remote_modified_ms: i64,
    #[serde(default)]
    remote_size: i64,
    #[serde(default)]
    remote_etag: String,
    #[serde(default)]
    synced_at: String,
    #[serde(default)]
    deleted: bool,
    #[serde(default)]
    deleted_at: String,
}

impl SyncManifestEntry {
    fn from_synced(local: &LocalSyncFile, remote: &RemoteSyncFile, synced_at: &str) -> Self {
        Self {
            sha256: local.sha256.clone(),
            size: local.size,
            local_modified_ms: local.modified_ms,
            remote_modified: remote.modified.clone(),
            remote_modified_ms: remote.modified_ms,
            remote_size: remote.size,
            remote_etag: remote.etag.clone(),
            synced_at: synced_at.to_string(),
            deleted: false,
            deleted_at: String::new(),
        }
    }

    fn from_local(local: &LocalSyncFile, synced_at: &str) -> Self {
        Self {
            sha256: local.sha256.clone(),
            size: local.size,
            local_modified_ms: local.modified_ms,
            remote_modified: String::new(),
            remote_modified_ms: 0,
            remote_size: local.size as i64,
            remote_etag: String::new(),
            synced_at: synced_at.to_string(),
            deleted: false,
            deleted_at: String::new(),
        }
    }

    fn from_uploaded(local: &LocalSyncFile, synced_at: &str) -> Self {
        Self::from_local(local, synced_at)
    }

    fn from_remote(remote: &RemoteSyncFile, synced_at: &str) -> Self {
        Self {
            sha256: remote.sha256.clone(),
            size: remote.size.max(0) as u64,
            local_modified_ms: 0,
            remote_modified: remote.modified.clone(),
            remote_modified_ms: remote.modified_ms,
            remote_size: remote.size,
            remote_etag: remote.etag.clone(),
            synced_at: synced_at.to_string(),
            deleted: false,
            deleted_at: String::new(),
        }
    }

    fn deleted(local: &LocalSyncFile, synced_at: &str) -> Self {
        Self {
            sha256: local.sha256.clone(),
            size: local.size,
            local_modified_ms: local.modified_ms,
            remote_modified: String::new(),
            remote_modified_ms: 0,
            remote_size: 0,
            remote_etag: String::new(),
            synced_at: synced_at.to_string(),
            deleted: true,
            deleted_at: synced_at.to_string(),
        }
    }

    fn deleted_remote(remote: &RemoteSyncFile, synced_at: &str) -> Self {
        Self {
            sha256: remote.sha256.clone(),
            size: remote.size.max(0) as u64,
            local_modified_ms: 0,
            remote_modified: remote.modified.clone(),
            remote_modified_ms: remote.modified_ms,
            remote_size: remote.size,
            remote_etag: remote.etag.clone(),
            synced_at: synced_at.to_string(),
            deleted: true,
            deleted_at: synced_at.to_string(),
        }
    }
}

impl CloudSyncResult {
    fn success(message: &str, uploaded: i32, downloaded: i32, conflicts: i32) -> Self {
        Self {
            ok: true,
            message: message.to_string(),
            uploaded,
            downloaded,
            conflicts,
            synced_at: String::new(),
            error_code: String::new(),
            needs_delete_confirmation: false,
            pending_delete_local: Vec::new(),
            pending_delete_remote: Vec::new(),
            needs_delete_modify_confirmation: false,
            pending_delete_modify_conflicts: Vec::new(),
        }
    }

    fn failure(message: &str, error_code: &str) -> Self {
        Self {
            ok: false,
            message: message.to_string(),
            uploaded: 0,
            downloaded: 0,
            conflicts: 0,
            synced_at: String::new(),
            error_code: error_code.to_string(),
            needs_delete_confirmation: false,
            pending_delete_local: Vec::new(),
            pending_delete_remote: Vec::new(),
            needs_delete_modify_confirmation: false,
            pending_delete_modify_conflicts: Vec::new(),
        }
    }

    fn error(error: CloudSyncError) -> Self {
        let error_code = match &error {
            CloudSyncError::Validation(_) => "validation",
            CloudSyncError::WebDav { .. } => "webdav",
            CloudSyncError::NotFound(_) => "not_found",
            CloudSyncError::Network(_) => "network",
            CloudSyncError::Io(_) => "io",
            CloudSyncError::Url(_) => "url",
            CloudSyncError::Parse(_) => "parse",
        };
        Self::failure(&error.to_string(), error_code)
    }
}

struct HttpWebDavClient {
    client: Client,
}

impl HttpWebDavClient {
    fn new() -> Self {
        let client = Client::builder()
            .connect_timeout(Duration::from_secs(HTTP_TIMEOUT_SECS))
            .timeout(Duration::from_secs(HTTP_TIMEOUT_SECS))
            .user_agent("SpringNote WebDAV Sync")
            .build()
            .expect("reqwest client should build");
        Self { client }
    }

    async fn request(
        &self,
        method: &str,
        url: &str,
        config: &CloudSyncConfig,
        headers: &[(&str, &str)],
        body: Option<Vec<u8>>,
    ) -> Result<(StatusCode, Vec<u8>), CloudSyncError> {
        let method = Method::from_bytes(method.as_bytes())
            .map_err(|error| CloudSyncError::Network(error.to_string()))?;
        let mut request = self
            .client
            .request(method, url)
            .basic_auth(config.username.trim(), Some(&config.password));
        for (key, value) in headers {
            request = request.header(*key, *value);
        }
        if let Some(body) = body {
            request = request.body(body);
        }
        let response = request.send().await?;
        let status = response.status();
        let bytes = response.bytes().await?.to_vec();
        Ok((status, bytes))
    }
}

impl WebDavClient for HttpWebDavClient {
    async fn ensure_directory(
        &self,
        url: &str,
        config: &CloudSyncConfig,
    ) -> Result<(), CloudSyncError> {
        let url = directory_url(url)?;
        let (status, _) = self.request("MKCOL", &url, config, &[], None).await?;
        if status == StatusCode::CREATED
            || status == StatusCode::METHOD_NOT_ALLOWED
            || status == StatusCode::OK
        {
            return Ok(());
        }
        Err(CloudSyncError::WebDav {
            action: "创建远端目录失败".to_string(),
            status: status.as_u16(),
        })
    }

    async fn list_files(
        &self,
        url: &str,
        config: &CloudSyncConfig,
    ) -> Result<Vec<WebDavFile>, CloudSyncError> {
        let url = directory_url(url)?;
        let body = br#"<?xml version="1.0" encoding="utf-8" ?><propfind xmlns="DAV:"><prop><resourcetype /><getlastmodified /><getcontentlength /><getetag /></prop></propfind>"#.to_vec();
        let (status, bytes) = self
            .request("PROPFIND", &url, config, &[("Depth", "1")], Some(body))
            .await?;
        if status == StatusCode::NOT_FOUND {
            return Ok(Vec::new());
        }
        if status != StatusCode::MULTI_STATUS {
            return Err(CloudSyncError::WebDav {
                action: "读取远端目录失败".to_string(),
                status: status.as_u16(),
            });
        }
        let xml =
            String::from_utf8(bytes).map_err(|error| CloudSyncError::Parse(error.to_string()))?;
        parse_propfind_files(&url, &xml)
    }

    async fn read_bytes(
        &self,
        url: &str,
        config: &CloudSyncConfig,
    ) -> Result<Vec<u8>, CloudSyncError> {
        let (status, bytes) = self.request("GET", url, config, &[], None).await?;
        if status == StatusCode::NOT_FOUND {
            return Err(CloudSyncError::NotFound(url.to_string()));
        }
        if status != StatusCode::OK {
            return Err(CloudSyncError::WebDav {
                action: "下载远端文件失败".to_string(),
                status: status.as_u16(),
            });
        }
        Ok(bytes)
    }

    async fn write_bytes(
        &self,
        url: &str,
        config: &CloudSyncConfig,
        bytes: &[u8],
    ) -> Result<(), CloudSyncError> {
        let (status, _) = self
            .request("PUT", url, config, &[], Some(bytes.to_vec()))
            .await?;
        if status == StatusCode::CREATED
            || status == StatusCode::NO_CONTENT
            || status == StatusCode::OK
        {
            return Ok(());
        }
        Err(CloudSyncError::WebDav {
            action: "上传远端文件失败".to_string(),
            status: status.as_u16(),
        })
    }

    async fn delete_file(&self, url: &str, config: &CloudSyncConfig) -> Result<(), CloudSyncError> {
        let (status, _) = self.request("DELETE", url, config, &[], None).await?;
        if status == StatusCode::NO_CONTENT
            || status == StatusCode::OK
            || status == StatusCode::ACCEPTED
            || status == StatusCode::NOT_FOUND
        {
            return Ok(());
        }
        Err(CloudSyncError::WebDav {
            action: "删除远端文件失败".to_string(),
            status: status.as_u16(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;
    use std::sync::{Arc, Mutex};
    use std::time::{SystemTime, UNIX_EPOCH};

    #[derive(Clone, Default)]
    struct MemoryWebDavClient {
        directories: Arc<Mutex<HashSet<String>>>,
        files: Arc<Mutex<HashMap<String, Vec<u8>>>>,
        reads: Arc<Mutex<HashMap<String, usize>>>,
    }

    impl MemoryWebDavClient {
        fn put_text(&self, path: &str, content: &str) {
            self.files
                .lock()
                .unwrap()
                .insert(normalize_path(path, false), content.as_bytes().to_vec());
        }

        fn text(&self, path: &str) -> Option<String> {
            self.files
                .lock()
                .unwrap()
                .get(&normalize_path(path, false))
                .map(|bytes| String::from_utf8_lossy(bytes).to_string())
        }

        fn has_directory(&self, path: &str) -> bool {
            self.directories
                .lock()
                .unwrap()
                .contains(&normalize_path(path, true))
        }

        fn read_count(&self, path: &str) -> usize {
            self.reads
                .lock()
                .unwrap()
                .get(&normalize_path(path, false))
                .copied()
                .unwrap_or(0)
        }
    }

    impl WebDavClient for MemoryWebDavClient {
        async fn ensure_directory(
            &self,
            url: &str,
            _config: &CloudSyncConfig,
        ) -> Result<(), CloudSyncError> {
            let parsed = Url::parse(url).map_err(|error| CloudSyncError::Url(error.to_string()))?;
            self.directories
                .lock()
                .unwrap()
                .insert(normalize_path(parsed.path(), true));
            Ok(())
        }

        async fn list_files(
            &self,
            url: &str,
            _config: &CloudSyncConfig,
        ) -> Result<Vec<WebDavFile>, CloudSyncError> {
            let parsed = Url::parse(url).map_err(|error| CloudSyncError::Url(error.to_string()))?;
            let directory = normalize_path(parsed.path(), true);
            let mut entries = Vec::new();
            let mut seen_directories = HashSet::new();
            for (path, bytes) in self
                .files
                .lock()
                .unwrap()
                .iter()
                .filter(|(path, _)| path.starts_with(&directory))
            {
                let Some(remainder) = path.strip_prefix(&directory) else {
                    continue;
                };
                if remainder.is_empty() {
                    continue;
                }
                if let Some((segment, _)) = remainder.split_once('/') {
                    if seen_directories.insert(segment.to_string()) {
                        entries.push(WebDavFile {
                            name: segment.to_string(),
                            url: parsed
                                .join(&format!("{segment}/"))
                                .ok()
                                .unwrap()
                                .to_string(),
                            is_directory: true,
                            modified: String::new(),
                            modified_ms: 0,
                            size: -1,
                            etag: String::new(),
                        });
                    }
                    continue;
                }
                entries.push(WebDavFile {
                    name: remainder.to_string(),
                    url: parsed.join(remainder).ok().unwrap().to_string(),
                    is_directory: false,
                    modified: "Sat, 29 Jun 2026 01:23:45 GMT".to_string(),
                    modified_ms: parse_webdav_modified_ms("Sat, 29 Jun 2026 01:23:45 GMT"),
                    size: bytes.len() as i64,
                    etag: format!("\"{}\"", sha256_hex(bytes)),
                });
            }
            Ok(entries)
        }

        async fn read_bytes(
            &self,
            url: &str,
            _config: &CloudSyncConfig,
        ) -> Result<Vec<u8>, CloudSyncError> {
            let parsed = Url::parse(url).map_err(|error| CloudSyncError::Url(error.to_string()))?;
            let path = normalize_path(parsed.path(), false);
            *self.reads.lock().unwrap().entry(path.clone()).or_default() += 1;
            self.files
                .lock()
                .unwrap()
                .get(&path)
                .cloned()
                .ok_or_else(|| CloudSyncError::NotFound(url.to_string()))
        }

        async fn write_bytes(
            &self,
            url: &str,
            _config: &CloudSyncConfig,
            bytes: &[u8],
        ) -> Result<(), CloudSyncError> {
            let parsed = Url::parse(url).map_err(|error| CloudSyncError::Url(error.to_string()))?;
            self.files
                .lock()
                .unwrap()
                .insert(normalize_path(parsed.path(), false), bytes.to_vec());
            Ok(())
        }

        async fn delete_file(
            &self,
            url: &str,
            _config: &CloudSyncConfig,
        ) -> Result<(), CloudSyncError> {
            let parsed = Url::parse(url).map_err(|error| CloudSyncError::Url(error.to_string()))?;
            self.files
                .lock()
                .unwrap()
                .remove(&normalize_path(parsed.path(), false));
            Ok(())
        }
    }

    #[derive(Clone, Default)]
    struct ManifestReadErrorClient {
        inner: MemoryWebDavClient,
    }

    impl WebDavClient for ManifestReadErrorClient {
        async fn ensure_directory(
            &self,
            url: &str,
            config: &CloudSyncConfig,
        ) -> Result<(), CloudSyncError> {
            self.inner.ensure_directory(url, config).await
        }

        async fn list_files(
            &self,
            url: &str,
            config: &CloudSyncConfig,
        ) -> Result<Vec<WebDavFile>, CloudSyncError> {
            self.inner.list_files(url, config).await
        }

        async fn read_bytes(
            &self,
            url: &str,
            config: &CloudSyncConfig,
        ) -> Result<Vec<u8>, CloudSyncError> {
            let parsed = Url::parse(url).map_err(|error| CloudSyncError::Url(error.to_string()))?;
            let path = normalize_path(parsed.path(), false);
            if path.ends_with(MANIFEST_FILE_NAME) {
                return Err(CloudSyncError::Network("读取远端同步清单超时".to_string()));
            }
            self.inner.read_bytes(url, config).await
        }

        async fn write_bytes(
            &self,
            url: &str,
            config: &CloudSyncConfig,
            bytes: &[u8],
        ) -> Result<(), CloudSyncError> {
            self.inner.write_bytes(url, config, bytes).await
        }

        async fn delete_file(
            &self,
            url: &str,
            config: &CloudSyncConfig,
        ) -> Result<(), CloudSyncError> {
            self.inner.delete_file(url, config).await
        }
    }

    struct TestDir {
        path: PathBuf,
    }

    impl TestDir {
        fn new(prefix: &str) -> Self {
            let suffix = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            Self {
                path: std::env::temp_dir().join(format!("{prefix}_{suffix}")),
            }
        }
    }

    impl Drop for TestDir {
        fn drop(&mut self) {
            fs::remove_dir_all(&self.path).ok();
        }
    }

    #[tokio::test]
    async fn validates_connection_and_creates_webdav_root() {
        let client = MemoryWebDavClient::default();
        let config = sync_config();

        test_connection_with_client(&client, &config).await.unwrap();

        assert!(client.has_directory("/dav/SpringNote/"));
        assert!(client.has_directory("/dav/SpringNote/notes/"));
    }

    #[tokio::test]
    async fn uploads_local_notes_and_downloads_remote_notes() {
        let dir = TestDir::new("spring_note_sync");
        let request = request(&dir.path);
        fs::create_dir_all(&request.daily_notes_directory).unwrap();
        fs::write(
            Path::new(&request.daily_notes_directory).join("2026-06-28.md"),
            "# 本地日报\n",
        )
        .unwrap();
        let shared_image =
            shared_images_directory(&request.daily_notes_directory).join("shared.png");
        fs::create_dir_all(shared_image.parent().unwrap()).unwrap();
        fs::write(&shared_image, b"shared image").unwrap();

        let client = MemoryWebDavClient::default();
        client.put_text("/dav/SpringNote/notes/weekly/2026-W26.md", "# 远端周报\n");
        client.put_text(
            "/dav/SpringNote/notes/images/remote-shared.png",
            "remote shared image",
        );

        let result = sync_with_client(&client, request.clone()).await.unwrap();

        assert!(result.ok);
        assert_eq!(result.uploaded, 2);
        assert_eq!(result.downloaded, 2);
        assert_eq!(
            client.text("/dav/SpringNote/notes/daily/2026-06-28.md"),
            Some("# 本地日报\n".to_string())
        );
        assert_eq!(
            client.text("/dav/SpringNote/notes/images/shared.png"),
            Some("shared image".to_string())
        );
        assert_eq!(
            fs::read_to_string(Path::new(&request.weekly_notes_directory).join("2026-W26.md"))
                .unwrap(),
            "# 远端周报\n"
        );
        assert_eq!(
            fs::read_to_string(
                shared_images_directory(&request.daily_notes_directory).join("remote-shared.png")
            )
            .unwrap(),
            "remote shared image"
        );
    }

    #[tokio::test]
    async fn uploads_selected_note_and_referenced_images_only() {
        let dir = TestDir::new("spring_note_upload_note");
        let request = request(&dir.path);
        let note_path = Path::new(&request.daily_notes_directory).join("2026-06-29.md");
        fs::write(
            &note_path,
            "# 自动同步\n\n![截图](../images/local%20pic.png)\n![缺失](../images/missing.png)\n",
        )
        .unwrap();
        let image_directory = shared_images_directory(&request.daily_notes_directory);
        fs::create_dir_all(&image_directory).unwrap();
        fs::write(image_directory.join("local pic.png"), b"local image").unwrap();
        fs::write(image_directory.join("unused.png"), b"unused image").unwrap();

        let client = MemoryWebDavClient::default();
        let result = upload_note_with_client(&client, note_upload_request(&request, &note_path))
            .await
            .unwrap();

        assert!(result.ok);
        assert_eq!(result.uploaded, 2);
        assert_eq!(
            client.text("/dav/SpringNote/notes/daily/2026-06-29.md"),
            Some(
                "# 自动同步\n\n![截图](../images/local%20pic.png)\n![缺失](../images/missing.png)\n"
                    .to_string()
            )
        );
        assert_eq!(
            client.text("/dav/SpringNote/notes/images/local%20pic.png"),
            Some("local image".to_string())
        );
        assert_eq!(client.text("/dav/SpringNote/notes/images/unused.png"), None);
    }

    #[tokio::test]
    async fn upload_note_skips_cloud_when_local_metadata_is_unchanged() {
        let dir = TestDir::new("spring_note_upload_note_unchanged");
        let request = request(&dir.path);
        let note_path = Path::new(&request.daily_notes_directory).join("2026-06-29.md");
        fs::write(&note_path, "# 自动同步\n").unwrap();

        let client = MemoryWebDavClient::default();
        let first = upload_note_with_client(&client, note_upload_request(&request, &note_path))
            .await
            .unwrap();
        assert!(first.ok);
        assert_eq!(first.uploaded, 1);

        let second = upload_note_with_client(&client, note_upload_request(&request, &note_path))
            .await
            .unwrap();
        assert!(second.ok);
        assert_eq!(second.uploaded, 0);
        assert_eq!(second.message, "笔记未变化");
        assert_eq!(
            client.text("/dav/SpringNote/notes/daily/2026-06-29.md"),
            Some("# 自动同步\n".to_string())
        );
    }

    #[tokio::test]
    async fn skips_remote_get_when_metadata_matches_manifest() {
        let dir = TestDir::new("spring_note_metadata");
        let request = request(&dir.path);
        let client = MemoryWebDavClient::default();
        client.put_text("/dav/SpringNote/notes/daily/2026-06-29.md", "# 远端日报\n");

        let first = sync_with_client(&client, request.clone()).await.unwrap();
        assert!(first.ok);
        assert_eq!(first.downloaded, 1);
        assert_eq!(
            client.read_count("/dav/SpringNote/notes/daily/2026-06-29.md"),
            1
        );

        let second = sync_with_client(&client, request).await.unwrap();
        assert!(second.ok);
        assert_eq!(second.downloaded, 0);
        assert_eq!(
            client.read_count("/dav/SpringNote/notes/daily/2026-06-29.md"),
            1
        );
    }

    #[tokio::test]
    async fn skips_local_file_read_when_metadata_matches_manifest() {
        let dir = TestDir::new("spring_note_local_metadata");
        let request = request(&dir.path);
        let note_path = Path::new(&request.daily_notes_directory).join("2026-06-29.md");
        fs::write(&note_path, "# 本地日报\n").unwrap();
        let client = MemoryWebDavClient::default();

        let first = sync_with_client(&client, request.clone()).await.unwrap();
        assert!(first.ok);
        assert_eq!(first.uploaded, 1);

        let manifest = read_local_manifest(&request).unwrap();
        let files = scan_local_notes(&request, &manifest.entries).unwrap();
        let file = files.get("notes/daily/2026-06-29.md").unwrap();

        assert_eq!(
            file.sha256,
            manifest.entries["notes/daily/2026-06-29.md"].sha256
        );
        assert!(file.bytes.is_none());
    }

    #[tokio::test]
    async fn new_device_downloads_remote_instead_of_deleting_it() {
        let dir = TestDir::new("spring_note_new_device");
        let request = request(&dir.path);
        let client = MemoryWebDavClient::default();
        client.put_text("/dav/SpringNote/notes/daily/2026-06-29.md", "# 远端日报\n");

        let result = sync_with_client(&client, request.clone()).await.unwrap();

        assert!(result.ok);
        assert!(!result.needs_delete_confirmation);
        assert_eq!(result.downloaded, 1);
        assert_eq!(
            client.text("/dav/SpringNote/notes/daily/2026-06-29.md"),
            Some("# 远端日报\n".to_string())
        );
        assert_eq!(
            fs::read_to_string(Path::new(&request.daily_notes_directory).join("2026-06-29.md"))
                .unwrap(),
            "# 远端日报\n"
        );
    }

    #[tokio::test]
    async fn remote_manifest_read_error_aborts_sync() {
        let dir = TestDir::new("spring_note_manifest_read_error");
        let request = request(&dir.path);
        let note_path = Path::new(&request.daily_notes_directory).join("2026-06-29.md");
        fs::write(&note_path, "# 本地日报\n").unwrap();
        let client = ManifestReadErrorClient::default();

        let result = sync_with_client(&client, request.clone()).await;

        assert!(matches!(result, Err(CloudSyncError::Network(_))));
        assert!(note_path.exists());
        assert_eq!(
            client.inner.text("/dav/SpringNote/.springnote-sync.json"),
            None
        );
        assert_eq!(
            client
                .inner
                .text("/dav/SpringNote/notes/daily/2026-06-29.md"),
            None
        );
    }

    #[tokio::test]
    async fn invalid_remote_manifest_aborts_sync() {
        let dir = TestDir::new("spring_note_invalid_remote_manifest");
        let request = request(&dir.path);
        let note_path = Path::new(&request.daily_notes_directory).join("2026-06-29.md");
        fs::write(&note_path, "# 本地日报\n").unwrap();
        let client = MemoryWebDavClient::default();
        client.put_text("/dav/SpringNote/.springnote-sync.json", "{not-json");

        let result = sync_with_client(&client, request.clone()).await;

        assert!(matches!(result, Err(CloudSyncError::Parse(_))));
        assert!(note_path.exists());
        assert_eq!(
            client.text("/dav/SpringNote/.springnote-sync.json"),
            Some("{not-json".to_string())
        );
        assert_eq!(
            client.text("/dav/SpringNote/notes/daily/2026-06-29.md"),
            None
        );
    }

    #[tokio::test]
    async fn local_delete_requires_confirmation_before_remote_delete() {
        let dir = TestDir::new("spring_note_local_delete");
        let mut request = request(&dir.path);
        let note_path = Path::new(&request.daily_notes_directory).join("2026-06-29.md");
        fs::write(&note_path, "# 初始\n").unwrap();
        let client = MemoryWebDavClient::default();
        sync_with_client(&client, request.clone()).await.unwrap();

        fs::remove_file(&note_path).unwrap();
        let pending = sync_with_client(&client, request.clone()).await.unwrap();

        assert!(pending.ok);
        assert!(pending.needs_delete_confirmation);
        assert_eq!(
            pending.pending_delete_remote,
            vec!["notes/daily/2026-06-29.md"]
        );
        assert_eq!(
            client.text("/dav/SpringNote/notes/daily/2026-06-29.md"),
            Some("# 初始\n".to_string())
        );

        request.confirmed_delete_remote = pending.pending_delete_remote;
        let confirmed = sync_with_client(&client, request).await.unwrap();

        assert!(confirmed.ok);
        assert!(!confirmed.needs_delete_confirmation);
        assert_eq!(
            client.text("/dav/SpringNote/notes/daily/2026-06-29.md"),
            None
        );
    }

    #[tokio::test]
    async fn remote_delete_requires_confirmation_before_local_delete() {
        let dir = TestDir::new("spring_note_remote_delete");
        let mut request = request(&dir.path);
        let note_path = Path::new(&request.daily_notes_directory).join("2026-06-29.md");
        fs::write(&note_path, "# 初始\n").unwrap();
        let client = MemoryWebDavClient::default();
        sync_with_client(&client, request.clone()).await.unwrap();

        client
            .delete_file(
                "https://example.com/dav/SpringNote/notes/daily/2026-06-29.md",
                &request.config,
            )
            .await
            .unwrap();
        let pending = sync_with_client(&client, request.clone()).await.unwrap();

        assert!(pending.ok);
        assert!(pending.needs_delete_confirmation);
        assert_eq!(
            pending.pending_delete_local,
            vec!["notes/daily/2026-06-29.md"]
        );
        assert!(note_path.exists());

        request.confirmed_delete_local = pending.pending_delete_local;
        let confirmed = sync_with_client(&client, request).await.unwrap();

        assert!(confirmed.ok);
        assert!(!confirmed.needs_delete_confirmation);
        assert!(!note_path.exists());
    }

    #[tokio::test]
    async fn local_modified_remote_deleted_can_overwrite_remote_without_conflict_loop() {
        let dir = TestDir::new("spring_note_local_modified_remote_deleted_remote_wins");
        let mut request = request(&dir.path);
        let note_path = Path::new(&request.daily_notes_directory).join("2026-06-29.md");
        fs::write(&note_path, "# 初始\n").unwrap();
        let client = MemoryWebDavClient::default();
        sync_with_client(&client, request.clone()).await.unwrap();

        client
            .delete_file(
                "https://example.com/dav/SpringNote/notes/daily/2026-06-29.md",
                &request.config,
            )
            .await
            .unwrap();
        fs::write(&note_path, "# 本地修改\n").unwrap();

        let pending = sync_with_client(&client, request.clone()).await.unwrap();

        assert!(pending.ok);
        assert!(pending.needs_delete_modify_confirmation);
        assert_eq!(
            pending.pending_delete_modify_conflicts,
            vec![DeleteModifyConflict {
                relative_path: "notes/daily/2026-06-29.md".to_string(),
                direction: "local_modified_remote_deleted".to_string(),
            }]
        );
        assert_eq!(pending.conflicts, 0);

        request.confirmed_overwrite_remote = vec!["notes/daily/2026-06-29.md".to_string()];
        let confirmed = sync_with_client(&client, request.clone()).await.unwrap();

        assert!(confirmed.ok);
        assert!(!confirmed.needs_delete_modify_confirmation);
        assert_eq!(confirmed.uploaded, 1);
        assert_eq!(
            client.text("/dav/SpringNote/notes/daily/2026-06-29.md"),
            Some("# 本地修改\n".to_string())
        );
        assert_eq!(fs::read_to_string(&note_path).unwrap(), "# 本地修改\n");

        request.confirmed_overwrite_remote.clear();
        let next = sync_with_client(&client, request).await.unwrap();
        assert!(next.ok);
        assert!(!next.needs_delete_modify_confirmation);
        assert_eq!(next.uploaded, 0);
    }

    #[tokio::test]
    async fn local_modified_remote_deleted_can_overwrite_local() {
        let dir = TestDir::new("spring_note_local_modified_remote_deleted_local_wins");
        let mut request = request(&dir.path);
        let note_path = Path::new(&request.daily_notes_directory).join("2026-06-29.md");
        fs::write(&note_path, "# 初始\n").unwrap();
        let client = MemoryWebDavClient::default();
        sync_with_client(&client, request.clone()).await.unwrap();

        client
            .delete_file(
                "https://example.com/dav/SpringNote/notes/daily/2026-06-29.md",
                &request.config,
            )
            .await
            .unwrap();
        fs::write(&note_path, "# 本地修改\n").unwrap();

        let pending = sync_with_client(&client, request.clone()).await.unwrap();
        assert!(pending.needs_delete_modify_confirmation);

        request.confirmed_overwrite_local = vec!["notes/daily/2026-06-29.md".to_string()];
        let confirmed = sync_with_client(&client, request).await.unwrap();

        assert!(confirmed.ok);
        assert!(!confirmed.needs_delete_modify_confirmation);
        assert_eq!(confirmed.uploaded, 0);
        assert_eq!(
            client.text("/dav/SpringNote/notes/daily/2026-06-29.md"),
            None
        );
        assert!(!note_path.exists());
    }

    #[tokio::test]
    async fn local_modified_remote_deleted_can_be_skipped_without_conflict_copy() {
        let dir = TestDir::new("spring_note_local_modified_remote_deleted_skip");
        let mut request = request(&dir.path);
        let note_path = Path::new(&request.daily_notes_directory).join("2026-06-29.md");
        fs::write(&note_path, "# 初始\n").unwrap();
        let client = MemoryWebDavClient::default();
        sync_with_client(&client, request.clone()).await.unwrap();

        client
            .delete_file(
                "https://example.com/dav/SpringNote/notes/daily/2026-06-29.md",
                &request.config,
            )
            .await
            .unwrap();
        fs::write(&note_path, "# 本地修改\n").unwrap();

        let pending = sync_with_client(&client, request.clone()).await.unwrap();
        assert!(pending.needs_delete_modify_confirmation);

        request.skipped_delete_modify_conflicts = vec!["notes/daily/2026-06-29.md".to_string()];
        let skipped = sync_with_client(&client, request.clone()).await.unwrap();

        assert!(skipped.ok);
        assert!(!skipped.needs_delete_modify_confirmation);
        assert_eq!(skipped.uploaded, 0);
        assert_eq!(skipped.conflicts, 0);
        assert_eq!(
            client.text("/dav/SpringNote/notes/daily/2026-06-29.md"),
            None
        );
        assert_eq!(fs::read_to_string(&note_path).unwrap(), "# 本地修改\n");

        request.skipped_delete_modify_conflicts.clear();
        let next = sync_with_client(&client, request).await.unwrap();
        assert!(next.needs_delete_modify_confirmation);
        assert_eq!(next.conflicts, 0);
    }

    #[tokio::test]
    async fn local_deleted_remote_modified_can_overwrite_local() {
        let dir = TestDir::new("spring_note_local_deleted_remote_modified_local");
        let mut request = request(&dir.path);
        let note_path = Path::new(&request.daily_notes_directory).join("2026-06-29.md");
        fs::write(&note_path, "# 初始\n").unwrap();
        let client = MemoryWebDavClient::default();
        sync_with_client(&client, request.clone()).await.unwrap();

        fs::remove_file(&note_path).unwrap();
        client.put_text("/dav/SpringNote/notes/daily/2026-06-29.md", "# 远端修改\n");

        let pending = sync_with_client(&client, request.clone()).await.unwrap();

        assert!(pending.ok);
        assert!(pending.needs_delete_modify_confirmation);
        assert_eq!(
            pending.pending_delete_modify_conflicts,
            vec![DeleteModifyConflict {
                relative_path: "notes/daily/2026-06-29.md".to_string(),
                direction: "local_deleted_remote_modified".to_string(),
            }]
        );
        assert_eq!(pending.conflicts, 0);

        request.confirmed_overwrite_local = vec!["notes/daily/2026-06-29.md".to_string()];
        let confirmed = sync_with_client(&client, request.clone()).await.unwrap();

        assert!(confirmed.ok);
        assert!(!confirmed.needs_delete_modify_confirmation);
        assert_eq!(confirmed.downloaded, 1);
        assert_eq!(fs::read_to_string(&note_path).unwrap(), "# 远端修改\n");

        request.confirmed_overwrite_local.clear();
        let next = sync_with_client(&client, request).await.unwrap();
        assert!(next.ok);
        assert!(!next.needs_delete_modify_confirmation);
        assert_eq!(next.downloaded, 0);
    }

    #[tokio::test]
    async fn local_deleted_remote_modified_can_overwrite_remote() {
        let dir = TestDir::new("spring_note_local_deleted_remote_modified_remote");
        let mut request = request(&dir.path);
        let note_path = Path::new(&request.daily_notes_directory).join("2026-06-29.md");
        fs::write(&note_path, "# 初始\n").unwrap();
        let client = MemoryWebDavClient::default();
        sync_with_client(&client, request.clone()).await.unwrap();

        fs::remove_file(&note_path).unwrap();
        client.put_text("/dav/SpringNote/notes/daily/2026-06-29.md", "# 远端修改\n");

        let pending = sync_with_client(&client, request.clone()).await.unwrap();
        assert!(pending.needs_delete_modify_confirmation);

        request.confirmed_overwrite_remote = vec!["notes/daily/2026-06-29.md".to_string()];
        let confirmed = sync_with_client(&client, request).await.unwrap();

        assert!(confirmed.ok);
        assert!(!confirmed.needs_delete_modify_confirmation);
        assert_eq!(confirmed.downloaded, 0);
        assert_eq!(
            client.text("/dav/SpringNote/notes/daily/2026-06-29.md"),
            None
        );
        assert!(!note_path.exists());
    }

    #[tokio::test]
    async fn keeps_both_sides_when_same_note_conflicts() {
        let dir = TestDir::new("spring_note_conflict");
        let request = request(&dir.path);
        fs::create_dir_all(&request.daily_notes_directory).unwrap();
        let note_path = Path::new(&request.daily_notes_directory).join("2026-06-28.md");
        fs::write(&note_path, "# 初始\n").unwrap();

        let client = MemoryWebDavClient::default();
        let first = sync_with_client(&client, request.clone()).await.unwrap();
        assert!(first.ok);

        fs::write(&note_path, "# 本地修改\n").unwrap();
        client.put_text("/dav/SpringNote/notes/daily/2026-06-28.md", "# 远端修改\n");

        let result = sync_with_client(&client, request.clone()).await.unwrap();

        assert!(result.ok);
        assert_eq!(result.conflicts, 1);
        assert_eq!(fs::read_to_string(&note_path).unwrap(), "# 本地修改\n");
        assert_eq!(
            client.text("/dav/SpringNote/notes/daily/2026-06-28.md"),
            Some("# 本地修改\n".to_string())
        );
        let conflict_files = fs::read_dir(&request.daily_notes_directory)
            .unwrap()
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .filter(|path| path.to_string_lossy().contains(".conflict-"))
            .collect::<Vec<_>>();
        assert_eq!(conflict_files.len(), 1);
        assert_eq!(
            fs::read_to_string(conflict_files.first().unwrap()).unwrap(),
            "# 远端修改\n"
        );
    }

    #[test]
    fn parses_propfind_files_with_namespaces_and_decoding() {
        let xml = r#"
            <d:multistatus xmlns:d="DAV:">
              <d:response><d:href>/dav/SpringNote/notes/daily/</d:href></d:response>
              <d:response><d:href>/dav/SpringNote/notes/daily/archive/</d:href></d:response>
              <d:response>
                <d:href>/dav/SpringNote/notes/daily/2026-06-28.md</d:href>
                <d:propstat><d:prop>
                  <d:getlastmodified>Mon, 29 Jun 2026 01:23:45 GMT</d:getlastmodified>
                  <d:getcontentlength>128</d:getcontentlength>
                  <d:getetag>&quot;etag-1&quot;</d:getetag>
                </d:prop></d:propstat>
              </d:response>
              <d:response><d:href>/dav/SpringNote/notes/daily/%E6%97%A5%E6%8A%A5.md</d:href></d:response>
            </d:multistatus>
        "#;

        let files =
            parse_propfind_files("https://example.com/dav/SpringNote/notes/daily/", xml).unwrap();

        assert_eq!(files.len(), 3);
        assert_eq!(files[0].name, "archive");
        assert!(files[0].is_directory);
        assert_eq!(files[1].name, "2026-06-28.md");
        assert!(!files[1].is_directory);
        assert_eq!(files[1].modified, "Mon, 29 Jun 2026 01:23:45 GMT");
        assert_eq!(files[1].size, 128);
        assert_eq!(files[1].etag, "\"etag-1\"");
        assert!(files[1].modified_ms > 0);
        assert_eq!(files[2].name, "日报.md");
    }

    fn sync_config() -> CloudSyncConfig {
        CloudSyncConfig {
            enabled: true,
            server_url: "https://example.com/dav/".to_string(),
            username: "user".to_string(),
            password: "token".to_string(),
        }
    }

    fn request(root: &Path) -> CloudSyncRequest {
        let notes = root.join("notes");
        let daily = notes.join("daily");
        let weekly = notes.join("weekly");
        let monthly = notes.join("monthly");
        fs::create_dir_all(&daily).unwrap();
        fs::create_dir_all(&weekly).unwrap();
        fs::create_dir_all(&monthly).unwrap();
        CloudSyncRequest {
            config: sync_config(),
            data_directory: root.to_string_lossy().to_string(),
            daily_notes_directory: daily.to_string_lossy().to_string(),
            weekly_notes_directory: weekly.to_string_lossy().to_string(),
            monthly_notes_directory: monthly.to_string_lossy().to_string(),
            trigger: "manual".to_string(),
            confirmed_delete_local: Vec::new(),
            confirmed_delete_remote: Vec::new(),
            confirmed_overwrite_local: Vec::new(),
            confirmed_overwrite_remote: Vec::new(),
            skipped_delete_modify_conflicts: Vec::new(),
        }
    }

    fn note_upload_request(
        request: &CloudSyncRequest,
        note_path: &Path,
    ) -> CloudSyncNoteUploadRequest {
        CloudSyncNoteUploadRequest {
            config: request.config.clone(),
            data_directory: request.data_directory.clone(),
            daily_notes_directory: request.daily_notes_directory.clone(),
            weekly_notes_directory: request.weekly_notes_directory.clone(),
            monthly_notes_directory: request.monthly_notes_directory.clone(),
            note_path: note_path.to_string_lossy().to_string(),
        }
    }
}
