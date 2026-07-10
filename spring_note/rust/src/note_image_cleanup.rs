use crate::markdown_links::{markdown_link_targets, shared_image_name_from_note_target};
use std::collections::{BTreeMap, BTreeSet};
use std::fmt;
use std::fs::{self, Metadata};
use std::io;
use std::path::{Component, Path, PathBuf};

const NOTES_DIRECTORY_NAME: &str = "notes";
const IMAGES_DIRECTORY_NAME: &str = "images";
const ALLOWED_IMAGE_EXTENSIONS: &[&str] = &[
    "png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "jfif", "bmp",
];

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NoteImageCleanupEntry {
    pub relative_path: String,
    pub size_bytes: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NoteImageCleanupScanResult {
    pub ok: bool,
    pub error_message: String,
    pub total_image_count: i32,
    pub referenced_image_count: i32,
    pub total_size_bytes: i64,
    pub unused_images: Vec<NoteImageCleanupEntry>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NoteImageCleanupDeleteResult {
    pub ok: bool,
    pub error_message: String,
    pub deleted_images: Vec<NoteImageCleanupEntry>,
    pub failed_images: Vec<NoteImageCleanupEntry>,
    pub skipped_count: i32,
}

#[derive(Debug)]
enum CleanupError {
    Validation(String),
    Io {
        action: &'static str,
        path: PathBuf,
        source: io::Error,
    },
}

impl CleanupError {
    fn io(action: &'static str, path: impl Into<PathBuf>, source: io::Error) -> Self {
        Self::Io {
            action,
            path: path.into(),
            source,
        }
    }
}

impl fmt::Display for CleanupError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CleanupError::Validation(message) => formatter.write_str(message),
            CleanupError::Io {
                action,
                path,
                source,
            } => write!(formatter, "{action}: {} ({source})", path.display()),
        }
    }
}

struct ManagedImagesRoot {
    notes_path: PathBuf,
    images_path: PathBuf,
    canonical_images_path: PathBuf,
}

struct ManagedImage {
    entry: NoteImageCleanupEntry,
    identity: secure_fs::FileIdentity,
}

struct ScanState {
    root: Option<ManagedImagesRoot>,
    total_image_count: usize,
    referenced_image_count: usize,
    total_size_bytes: u64,
    unused: BTreeMap<String, ManagedImage>,
}

enum SecureDeleteOutcome {
    Deleted,
    Skipped,
}

pub fn scan(data_directory: &str) -> NoteImageCleanupScanResult {
    match scan_internal(data_directory) {
        Ok(state) => scan_result_from_state(state),
        Err(error) => NoteImageCleanupScanResult::error(error.to_string()),
    }
}

pub fn delete_unused(
    data_directory: &str,
    candidate_relative_paths: Vec<String>,
) -> NoteImageCleanupDeleteResult {
    let requested = candidate_relative_paths
        .iter()
        .map(|value| requested_key(value))
        .filter(|value| !value.is_empty())
        .collect::<BTreeSet<_>>();
    if requested.is_empty() {
        return NoteImageCleanupDeleteResult::success(Vec::new(), Vec::new(), 0);
    }

    let valid_candidates = candidate_relative_paths
        .iter()
        .filter_map(|value| normalize_relative_candidate(value))
        .map(|value| relative_key(&value))
        .collect::<BTreeSet<_>>();
    let mut state = match scan_internal(data_directory) {
        Ok(state) => state,
        Err(error) => {
            return NoteImageCleanupDeleteResult::error(error.to_string(), requested.len());
        }
    };
    let Some(root) = state.root.take() else {
        return NoteImageCleanupDeleteResult::success(Vec::new(), Vec::new(), requested.len());
    };

    let mut deleted = Vec::new();
    let mut failed = Vec::new();
    for candidate in valid_candidates {
        let Some(image) = state.unused.remove(&candidate) else {
            continue;
        };
        let relative_path = Path::new(&image.entry.relative_path);
        match secure_fs::delete_relative_file(&root.images_path, relative_path, &image.identity) {
            Ok(SecureDeleteOutcome::Deleted) => deleted.push(image.entry),
            Ok(SecureDeleteOutcome::Skipped) => {}
            Err(_) => failed.push(image.entry),
        }
    }

    let handled = deleted.len().saturating_add(failed.len());
    NoteImageCleanupDeleteResult::success(deleted, failed, requested.len().saturating_sub(handled))
}

impl NoteImageCleanupScanResult {
    fn error(message: String) -> Self {
        Self {
            ok: false,
            error_message: message,
            total_image_count: 0,
            referenced_image_count: 0,
            total_size_bytes: 0,
            unused_images: Vec::new(),
        }
    }
}

impl NoteImageCleanupDeleteResult {
    fn success(
        deleted_images: Vec<NoteImageCleanupEntry>,
        failed_images: Vec<NoteImageCleanupEntry>,
        skipped_count: usize,
    ) -> Self {
        Self {
            ok: true,
            error_message: String::new(),
            deleted_images,
            failed_images,
            skipped_count: count_to_i32(skipped_count),
        }
    }

    fn error(message: String, skipped_count: usize) -> Self {
        Self {
            ok: false,
            error_message: message,
            deleted_images: Vec::new(),
            failed_images: Vec::new(),
            skipped_count: count_to_i32(skipped_count),
        }
    }
}

fn scan_result_from_state(state: ScanState) -> NoteImageCleanupScanResult {
    NoteImageCleanupScanResult {
        ok: true,
        error_message: String::new(),
        total_image_count: count_to_i32(state.total_image_count),
        referenced_image_count: count_to_i32(state.referenced_image_count),
        total_size_bytes: bytes_to_i64(state.total_size_bytes),
        unused_images: state
            .unused
            .into_values()
            .map(|image| image.entry)
            .collect(),
    }
}

fn scan_internal(data_directory: &str) -> Result<ScanState, CleanupError> {
    let root = resolve_managed_images_root(data_directory)?;
    let Some(root) = root else {
        return Ok(ScanState {
            root: None,
            total_image_count: 0,
            referenced_image_count: 0,
            total_size_bytes: 0,
            unused: BTreeMap::new(),
        });
    };

    let images = read_managed_images(&root)?;
    let total_image_count = images.len();
    let total_size_bytes = images
        .values()
        .map(|image| image.entry.size_bytes.max(0) as u64)
        .sum();
    let mut unused = images;

    if !unused.is_empty() {
        visit_regular_files(&root.notes_path, &mut |note_path, _| {
            if unused.is_empty() || !has_extension(note_path, "md") {
                return Ok(());
            }
            let markdown = fs::read_to_string(note_path)
                .map_err(|error| CleanupError::io("Failed to read note", note_path, error))?;
            for target in markdown_link_targets(&markdown) {
                let Some(relative_path) =
                    shared_image_name_from_note_target(&root.notes_path, note_path, &target)
                else {
                    continue;
                };
                unused.remove(&relative_key(&relative_path));
            }
            Ok(())
        })?;
    }

    Ok(ScanState {
        root: Some(root),
        total_image_count,
        referenced_image_count: total_image_count.saturating_sub(unused.len()),
        total_size_bytes,
        unused,
    })
}

fn resolve_managed_images_root(
    data_directory: &str,
) -> Result<Option<ManagedImagesRoot>, CleanupError> {
    let data_directory = data_directory.trim();
    if data_directory.is_empty() {
        return Err(CleanupError::Validation(
            "Data directory cannot be empty.".to_string(),
        ));
    }

    let notes_path = PathBuf::from(data_directory).join(NOTES_DIRECTORY_NAME);
    let notes_metadata = match fs::symlink_metadata(&notes_path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(CleanupError::io(
                "Failed to inspect notes directory",
                &notes_path,
                error,
            ));
        }
    };
    ensure_real_directory(&notes_path, &notes_metadata, "notes")?;

    let images_path = notes_path.join(IMAGES_DIRECTORY_NAME);
    let images_metadata = match fs::symlink_metadata(&images_path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(CleanupError::io(
                "Failed to inspect images directory",
                &images_path,
                error,
            ));
        }
    };
    ensure_real_directory(&images_path, &images_metadata, "images")?;

    let canonical_notes_path = fs::canonicalize(&notes_path).map_err(|error| {
        CleanupError::io("Failed to resolve notes directory", &notes_path, error)
    })?;
    let canonical_images_path = fs::canonicalize(&images_path).map_err(|error| {
        CleanupError::io("Failed to resolve images directory", &images_path, error)
    })?;
    if !is_strictly_inside(&canonical_images_path, &canonical_notes_path) {
        return Err(CleanupError::Validation(
            "Images directory resolves outside the notes directory.".to_string(),
        ));
    }
    secure_fs::validate_root(&images_path)?;

    Ok(Some(ManagedImagesRoot {
        notes_path,
        images_path,
        canonical_images_path,
    }))
}

fn ensure_real_directory(
    path: &Path,
    metadata: &Metadata,
    label: &str,
) -> Result<(), CleanupError> {
    if is_link_like(metadata) || !metadata.is_dir() {
        return Err(CleanupError::Validation(format!(
            "The {label} directory is not a safe regular directory: {}",
            path.display()
        )));
    }
    Ok(())
}

fn read_managed_images(
    root: &ManagedImagesRoot,
) -> Result<BTreeMap<String, ManagedImage>, CleanupError> {
    let mut images = BTreeMap::new();
    visit_regular_files(&root.images_path, &mut |image_path, metadata| {
        if !has_allowed_image_extension(image_path) {
            return Ok(());
        }
        let canonical_path = fs::canonicalize(image_path)
            .map_err(|error| CleanupError::io("Failed to resolve image", image_path, error))?;
        if !is_strictly_inside(&canonical_path, &root.canonical_images_path) {
            return Err(CleanupError::Validation(format!(
                "Image resolves outside the managed directory: {}",
                image_path.display()
            )));
        }
        let relative_path =
            relative_path_string(&root.images_path, image_path).ok_or_else(|| {
                CleanupError::Validation(format!(
                    "Image has an unsupported file name: {}",
                    image_path.display()
                ))
            })?;
        let identity = secure_fs::file_identity(image_path)?;
        let entry = NoteImageCleanupEntry {
            relative_path: relative_path.clone(),
            size_bytes: bytes_to_i64(metadata.len()),
        };
        images.insert(
            relative_key(&relative_path),
            ManagedImage { entry, identity },
        );
        Ok(())
    })?;
    Ok(images)
}

fn visit_regular_files<F>(directory: &Path, visitor: &mut F) -> Result<(), CleanupError>
where
    F: FnMut(&Path, &Metadata) -> Result<(), CleanupError>,
{
    let entries = fs::read_dir(directory)
        .map_err(|error| CleanupError::io("Failed to list directory", directory, error))?;
    for entry in entries {
        let entry = entry.map_err(|error| {
            CleanupError::io("Failed to read directory entry", directory, error)
        })?;
        let path = entry.path();
        let metadata = fs::symlink_metadata(&path)
            .map_err(|error| CleanupError::io("Failed to inspect file", &path, error))?;
        if is_link_like(&metadata) {
            return Err(CleanupError::Validation(format!(
                "Linked filesystem entries are not allowed during cleanup: {}",
                path.display()
            )));
        }
        if metadata.is_dir() {
            visit_regular_files(&path, visitor)?;
        } else if metadata.is_file() {
            visitor(&path, &metadata)?;
        }
    }
    Ok(())
}

fn is_link_like(metadata: &Metadata) -> bool {
    if metadata.file_type().is_symlink() {
        return true;
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        const FILE_ATTRIBUTE_REPARSE_POINT_VALUE: u32 = 0x0000_0400;
        metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT_VALUE != 0
    }
    #[cfg(not(windows))]
    false
}

fn has_allowed_image_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| {
            ALLOWED_IMAGE_EXTENSIONS
                .iter()
                .any(|allowed| extension.eq_ignore_ascii_case(allowed))
        })
}

fn has_extension(path: &Path, expected: &str) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| extension.eq_ignore_ascii_case(expected))
}

fn relative_path_string(root: &Path, value: &Path) -> Option<String> {
    value
        .strip_prefix(root)
        .ok()?
        .components()
        .map(|component| match component {
            Component::Normal(value) => value.to_str().map(str::to_owned),
            _ => None,
        })
        .collect::<Option<Vec<_>>>()
        .filter(|parts| !parts.is_empty())
        .map(|parts| parts.join("/"))
}

fn normalize_relative_candidate(value: &str) -> Option<String> {
    let value = value.trim();
    if value.is_empty() {
        return None;
    }
    let parts = Path::new(value)
        .components()
        .map(|component| match component {
            Component::Normal(value) => value.to_str().map(str::to_owned),
            _ => None,
        })
        .collect::<Option<Vec<_>>>()?;
    if parts.is_empty() {
        return None;
    }
    #[cfg(windows)]
    if parts.iter().any(|part| part.contains(':')) {
        return None;
    }
    let normalized = parts.join("/");
    has_allowed_image_extension(Path::new(&normalized)).then_some(normalized)
}

fn requested_key(value: &str) -> String {
    let normalized = value.trim().replace('\\', "/");
    relative_key(&normalized)
}

fn relative_key(value: &str) -> String {
    #[cfg(windows)]
    {
        value.to_lowercase()
    }
    #[cfg(not(windows))]
    {
        value.to_string()
    }
}

fn is_strictly_inside(child: &Path, parent: &Path) -> bool {
    child != parent && child.starts_with(parent)
}

fn bytes_to_i64(value: u64) -> i64 {
    value.min(i64::MAX as u64) as i64
}

fn count_to_i32(value: usize) -> i32 {
    value.min(i32::MAX as usize) as i32
}

#[cfg(unix)]
mod secure_fs {
    use super::{CleanupError, SecureDeleteOutcome};
    use std::ffi::{CString, OsStr, OsString};
    use std::fs;
    use std::io;
    use std::mem::MaybeUninit;
    use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
    use std::os::unix::ffi::OsStrExt;
    use std::os::unix::fs::MetadataExt;
    use std::path::{Component, Path};

    #[derive(Clone, Debug, PartialEq, Eq)]
    pub struct FileIdentity {
        device: u64,
        inode: u64,
    }

    pub fn validate_root(root: &Path) -> Result<(), CleanupError> {
        open_directory(root).map(drop)
    }

    pub fn file_identity(path: &Path) -> Result<FileIdentity, CleanupError> {
        let metadata = fs::symlink_metadata(path)
            .map_err(|error| CleanupError::io("Failed to inspect image", path, error))?;
        if !metadata.is_file() || metadata.file_type().is_symlink() {
            return Err(CleanupError::Validation(format!(
                "Image is not a regular file: {}",
                path.display()
            )));
        }
        Ok(FileIdentity {
            device: metadata.dev(),
            inode: metadata.ino(),
        })
    }

    pub fn delete_relative_file(
        root: &Path,
        relative_path: &Path,
        expected: &FileIdentity,
    ) -> Result<SecureDeleteOutcome, CleanupError> {
        let parts = relative_components(relative_path)?;
        let Some((file_name, directories)) = parts.split_last() else {
            return Ok(SecureDeleteOutcome::Skipped);
        };
        let mut directory = open_directory(root)?;
        for part in directories {
            directory = open_directory_at(&directory, part, relative_path)?;
        }

        let file_name = c_string(file_name).ok_or_else(|| {
            CleanupError::Validation("Image name contains a null byte.".to_string())
        })?;
        let mut stat = MaybeUninit::<libc::stat>::zeroed();
        let stat_result = unsafe {
            libc::fstatat(
                directory.as_raw_fd(),
                file_name.as_ptr(),
                stat.as_mut_ptr(),
                libc::AT_SYMLINK_NOFOLLOW,
            )
        };
        if stat_result != 0 {
            let error = io::Error::last_os_error();
            if error.kind() == io::ErrorKind::NotFound {
                return Ok(SecureDeleteOutcome::Skipped);
            }
            return Err(CleanupError::io(
                "Failed to inspect image before deletion",
                relative_path,
                error,
            ));
        }
        let stat = unsafe { stat.assume_init() };
        if stat.st_mode & libc::S_IFMT != libc::S_IFREG
            || stat.st_dev as u64 != expected.device
            || stat.st_ino as u64 != expected.inode
        {
            return Ok(SecureDeleteOutcome::Skipped);
        }

        let result = unsafe { libc::unlinkat(directory.as_raw_fd(), file_name.as_ptr(), 0) };
        if result != 0 {
            return Err(CleanupError::io(
                "Failed to delete image",
                relative_path,
                io::Error::last_os_error(),
            ));
        }
        Ok(SecureDeleteOutcome::Deleted)
    }

    fn relative_components(path: &Path) -> Result<Vec<OsString>, CleanupError> {
        path.components()
            .map(|component| match component {
                Component::Normal(value) => Ok(value.to_os_string()),
                _ => Err(CleanupError::Validation(
                    "Image candidate must be a relative path.".to_string(),
                )),
            })
            .collect()
    }

    fn open_directory(path: &Path) -> Result<OwnedFd, CleanupError> {
        let path_string = c_string(path.as_os_str()).ok_or_else(|| {
            CleanupError::Validation("Directory path contains a null byte.".to_string())
        })?;
        let raw = unsafe {
            libc::open(
                path_string.as_ptr(),
                libc::O_RDONLY | libc::O_CLOEXEC | libc::O_DIRECTORY | libc::O_NOFOLLOW,
            )
        };
        if raw < 0 {
            return Err(CleanupError::io(
                "Failed to open images directory securely",
                path,
                io::Error::last_os_error(),
            ));
        }
        Ok(unsafe { OwnedFd::from_raw_fd(raw) })
    }

    fn open_directory_at(
        parent: &OwnedFd,
        name: &OsStr,
        display_path: &Path,
    ) -> Result<OwnedFd, CleanupError> {
        let name = c_string(name).ok_or_else(|| {
            CleanupError::Validation("Directory name contains a null byte.".to_string())
        })?;
        let raw = unsafe {
            libc::openat(
                parent.as_raw_fd(),
                name.as_ptr(),
                libc::O_RDONLY | libc::O_CLOEXEC | libc::O_DIRECTORY | libc::O_NOFOLLOW,
            )
        };
        if raw < 0 {
            return Err(CleanupError::io(
                "Failed to open nested image directory securely",
                display_path,
                io::Error::last_os_error(),
            ));
        }
        Ok(unsafe { OwnedFd::from_raw_fd(raw) })
    }

    fn c_string(value: &OsStr) -> Option<CString> {
        CString::new(value.as_bytes()).ok()
    }
}

#[cfg(windows)]
mod secure_fs {
    use super::{CleanupError, SecureDeleteOutcome};
    use std::ffi::OsStr;
    use std::io;
    use std::mem::size_of;
    use std::os::windows::ffi::OsStrExt;
    use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
    use std::path::Path;
    use windows_sys::Win32::Foundation::{HANDLE, INVALID_HANDLE_VALUE};
    use windows_sys::Win32::Storage::FileSystem::{
        CreateFileW, DELETE, FILE_ATTRIBUTE_DIRECTORY, FILE_ATTRIBUTE_REPARSE_POINT,
        FILE_ATTRIBUTE_TAG_INFO, FILE_DISPOSITION_INFO, FILE_FLAG_BACKUP_SEMANTICS,
        FILE_FLAG_OPEN_REPARSE_POINT, FILE_ID_INFO, FILE_NAME_NORMALIZED, FILE_READ_ATTRIBUTES,
        FILE_SHARE_DELETE, FILE_SHARE_READ, FILE_SHARE_WRITE, FileAttributeTagInfo,
        FileDispositionInfo, FileIdInfo, GetFileInformationByHandleEx, GetFinalPathNameByHandleW,
        OPEN_EXISTING, SetFileInformationByHandle, VOLUME_NAME_DOS,
    };

    #[derive(Clone, Debug, PartialEq, Eq)]
    pub struct FileIdentity {
        volume_serial_number: u64,
        file_id: [u8; 16],
    }

    pub fn validate_root(root: &Path) -> Result<(), CleanupError> {
        let handle = open_handle(root, FILE_READ_ATTRIBUTES, true)?;
        let attributes = attribute_info(&handle, root)?;
        if attributes.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT != 0
            || attributes.FileAttributes & FILE_ATTRIBUTE_DIRECTORY == 0
        {
            return Err(CleanupError::Validation(format!(
                "Images directory is a reparse point or not a directory: {}",
                root.display()
            )));
        }
        Ok(())
    }

    pub fn file_identity(path: &Path) -> Result<FileIdentity, CleanupError> {
        let handle = open_handle(path, FILE_READ_ATTRIBUTES, false)?;
        let attributes = attribute_info(&handle, path)?;
        if attributes.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT != 0
            || attributes.FileAttributes & FILE_ATTRIBUTE_DIRECTORY != 0
        {
            return Err(CleanupError::Validation(format!(
                "Image is a reparse point or not a regular file: {}",
                path.display()
            )));
        }
        identity_info(&handle, path)
    }

    pub fn delete_relative_file(
        root: &Path,
        relative_path: &Path,
        expected: &FileIdentity,
    ) -> Result<SecureDeleteOutcome, CleanupError> {
        let root_handle = open_handle(root, FILE_READ_ATTRIBUTES, true)?;
        let root_attributes = attribute_info(&root_handle, root)?;
        if root_attributes.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT != 0
            || root_attributes.FileAttributes & FILE_ATTRIBUTE_DIRECTORY == 0
        {
            return Ok(SecureDeleteOutcome::Skipped);
        }

        let file_path = root.join(relative_path);
        let file_handle = match open_handle(&file_path, FILE_READ_ATTRIBUTES | DELETE, false) {
            Ok(handle) => handle,
            Err(CleanupError::Io { source, .. }) if source.kind() == io::ErrorKind::NotFound => {
                return Ok(SecureDeleteOutcome::Skipped);
            }
            Err(error) => return Err(error),
        };
        let attributes = attribute_info(&file_handle, &file_path)?;
        if attributes.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT != 0
            || attributes.FileAttributes & FILE_ATTRIBUTE_DIRECTORY != 0
        {
            return Ok(SecureDeleteOutcome::Skipped);
        }
        if identity_info(&file_handle, &file_path)? != *expected {
            return Ok(SecureDeleteOutcome::Skipped);
        }

        let root_final = normalize_final_path(&final_path(&root_handle, root)?);
        let file_final = normalize_final_path(&final_path(&file_handle, &file_path)?);
        if !is_inside_final_path(&file_final, &root_final) {
            return Ok(SecureDeleteOutcome::Skipped);
        }

        let disposition = FILE_DISPOSITION_INFO { DeleteFile: true };
        let result = unsafe {
            SetFileInformationByHandle(
                file_handle.as_raw_handle() as HANDLE,
                FileDispositionInfo,
                &disposition as *const _ as *const _,
                size_of::<FILE_DISPOSITION_INFO>() as u32,
            )
        };
        if result == 0 {
            return Err(CleanupError::io(
                "Failed to delete image by handle",
                &file_path,
                io::Error::last_os_error(),
            ));
        }
        drop(file_handle);
        Ok(SecureDeleteOutcome::Deleted)
    }

    fn open_handle(path: &Path, access: u32, directory: bool) -> Result<OwnedHandle, CleanupError> {
        let wide = wide_null(path.as_os_str());
        let flags = FILE_FLAG_OPEN_REPARSE_POINT
            | if directory {
                FILE_FLAG_BACKUP_SEMANTICS
            } else {
                0
            };
        let raw = unsafe {
            CreateFileW(
                wide.as_ptr(),
                access,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                std::ptr::null(),
                OPEN_EXISTING,
                flags,
                std::ptr::null_mut(),
            )
        };
        if raw == INVALID_HANDLE_VALUE {
            return Err(CleanupError::io(
                "Failed to open path securely",
                path,
                io::Error::last_os_error(),
            ));
        }
        Ok(unsafe { OwnedHandle::from_raw_handle(raw) })
    }

    fn attribute_info(
        handle: &OwnedHandle,
        path: &Path,
    ) -> Result<FILE_ATTRIBUTE_TAG_INFO, CleanupError> {
        let mut info = FILE_ATTRIBUTE_TAG_INFO::default();
        let result = unsafe {
            GetFileInformationByHandleEx(
                handle.as_raw_handle() as HANDLE,
                FileAttributeTagInfo,
                &mut info as *mut _ as *mut _,
                size_of::<FILE_ATTRIBUTE_TAG_INFO>() as u32,
            )
        };
        if result == 0 {
            return Err(CleanupError::io(
                "Failed to read path attributes",
                path,
                io::Error::last_os_error(),
            ));
        }
        Ok(info)
    }

    fn identity_info(handle: &OwnedHandle, path: &Path) -> Result<FileIdentity, CleanupError> {
        let mut info = FILE_ID_INFO::default();
        let result = unsafe {
            GetFileInformationByHandleEx(
                handle.as_raw_handle() as HANDLE,
                FileIdInfo,
                &mut info as *mut _ as *mut _,
                size_of::<FILE_ID_INFO>() as u32,
            )
        };
        if result == 0 {
            return Err(CleanupError::io(
                "Failed to read file identity",
                path,
                io::Error::last_os_error(),
            ));
        }
        Ok(FileIdentity {
            volume_serial_number: info.VolumeSerialNumber,
            file_id: info.FileId.Identifier,
        })
    }

    fn final_path(handle: &OwnedHandle, path: &Path) -> Result<String, CleanupError> {
        let mut buffer = vec![0u16; 1024];
        loop {
            let length = unsafe {
                GetFinalPathNameByHandleW(
                    handle.as_raw_handle() as HANDLE,
                    buffer.as_mut_ptr(),
                    buffer.len() as u32,
                    FILE_NAME_NORMALIZED | VOLUME_NAME_DOS,
                )
            };
            if length == 0 {
                return Err(CleanupError::io(
                    "Failed to resolve final path",
                    path,
                    io::Error::last_os_error(),
                ));
            }
            if length < buffer.len() as u32 {
                return Ok(String::from_utf16_lossy(&buffer[..length as usize]));
            }
            buffer.resize(length as usize + 1, 0);
        }
    }

    fn normalize_final_path(value: &str) -> String {
        let value = value.replace('/', "\\");
        let value = value
            .strip_prefix(r"\\?\UNC\")
            .map(|rest| format!(r"\\{rest}"))
            .or_else(|| value.strip_prefix(r"\\?\").map(str::to_owned))
            .unwrap_or(value);
        value.trim_end_matches('\\').to_lowercase()
    }

    fn is_inside_final_path(child: &str, parent: &str) -> bool {
        child != parent
            && child
                .strip_prefix(parent)
                .is_some_and(|rest| rest.starts_with('\\'))
    }

    fn wide_null(value: &OsStr) -> Vec<u16> {
        value.encode_wide().chain(std::iter::once(0)).collect()
    }
}

#[cfg(not(any(unix, windows)))]
mod secure_fs {
    use super::{CleanupError, SecureDeleteOutcome};
    use std::fs;
    use std::path::Path;
    use std::time::UNIX_EPOCH;

    #[derive(Clone, Debug, PartialEq, Eq)]
    pub struct FileIdentity {
        size: u64,
        modified_nanos: u128,
    }

    pub fn validate_root(root: &Path) -> Result<(), CleanupError> {
        let metadata = fs::symlink_metadata(root)
            .map_err(|error| CleanupError::io("Failed to inspect images directory", root, error))?;
        if !metadata.is_dir() || metadata.file_type().is_symlink() {
            return Err(CleanupError::Validation(
                "Images directory is not a regular directory.".to_string(),
            ));
        }
        Ok(())
    }

    pub fn file_identity(path: &Path) -> Result<FileIdentity, CleanupError> {
        let metadata = fs::symlink_metadata(path)
            .map_err(|error| CleanupError::io("Failed to inspect image", path, error))?;
        Ok(FileIdentity {
            size: metadata.len(),
            modified_nanos: metadata
                .modified()
                .ok()
                .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
                .map(|value| value.as_nanos())
                .unwrap_or_default(),
        })
    }

    pub fn delete_relative_file(
        root: &Path,
        relative_path: &Path,
        expected: &FileIdentity,
    ) -> Result<SecureDeleteOutcome, CleanupError> {
        let path = root.join(relative_path);
        if file_identity(&path)? != *expected {
            return Ok(SecureDeleteOutcome::Skipped);
        }
        fs::remove_file(&path)
            .map_err(|error| CleanupError::io("Failed to delete image", &path, error))?;
        Ok(SecureDeleteOutcome::Deleted)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    struct TempDirectory {
        path: PathBuf,
    }

    impl TempDirectory {
        fn new(prefix: &str) -> Self {
            static NEXT_ID: AtomicU64 = AtomicU64::new(0);
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos();
            let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "{prefix}_{}_{}_{}",
                std::process::id(),
                nonce,
                id
            ));
            fs::create_dir_all(&path).unwrap();
            Self { path }
        }
    }

    impl Drop for TempDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    fn setup_data_directory(prefix: &str) -> TempDirectory {
        let temp = TempDirectory::new(prefix);
        for directory in ["daily", "weekly", "monthly", "images"] {
            fs::create_dir_all(temp.path.join("notes").join(directory)).unwrap();
        }
        temp
    }

    #[test]
    fn scan_finds_only_unreferenced_images() {
        let temp = setup_data_directory("spring_note_image_scan");
        let notes = temp.path.join("notes");
        fs::write(notes.join("images").join("used #1.png"), [1]).unwrap();
        fs::write(notes.join("images").join("unused.webp"), [1, 2]).unwrap();
        fs::write(
            notes.join("daily").join("2026-07-10.md"),
            "![image](../images/used%20%231.png)",
        )
        .unwrap();

        let result = scan(temp.path.to_str().unwrap());

        assert!(result.ok, "{}", result.error_message);
        assert_eq!(result.total_image_count, 2);
        assert_eq!(result.referenced_image_count, 1);
        assert_eq!(result.total_size_bytes, 3);
        assert_eq!(
            result.unused_images,
            vec![NoteImageCleanupEntry {
                relative_path: "unused.webp".to_string(),
                size_bytes: 2,
            }]
        );
    }

    #[test]
    fn scan_matches_complete_image_paths_in_markdown_links() {
        let temp = setup_data_directory("spring_note_image_exact_paths");
        let notes = temp.path.join("notes");
        let images = notes.join("images");
        fs::create_dir_all(images.join("a")).unwrap();
        fs::create_dir_all(images.join("b")).unwrap();
        fs::write(images.join("cover.png"), [1]).unwrap();
        fs::write(images.join("old-cover.png"), [2]).unwrap();
        fs::write(images.join("a").join("cover.png"), [3]).unwrap();
        fs::write(images.join("b").join("cover.png"), [4]).unwrap();
        fs::write(
            notes.join("daily").join("2026-07-10.md"),
            concat!(
                "![old](../images/old-cover.png)\n\n",
                "[chart]: ../images/a/cover.png\n\n",
                "![nested][chart]\n\n",
                "`![code](../images/b/cover.png)`\n",
                "正文中提到 cover.png\n",
            ),
        )
        .unwrap();

        let result = scan(temp.path.to_str().unwrap());
        let unused = result
            .unused_images
            .iter()
            .map(|image| image.relative_path.as_str())
            .collect::<BTreeSet<_>>();

        assert!(result.ok, "{}", result.error_message);
        assert_eq!(result.total_image_count, 4);
        assert_eq!(result.referenced_image_count, 2);
        assert_eq!(unused, BTreeSet::from(["b/cover.png", "cover.png"]));
    }

    #[test]
    fn deletion_rechecks_references_and_accepts_only_relative_candidates() {
        let temp = setup_data_directory("spring_note_image_delete");
        let notes = temp.path.join("notes");
        let keep = notes.join("images").join("keep.png");
        let remove = notes.join("images").join("remove.png");
        let outside = temp.path.join("outside.png");
        fs::write(&keep, [1]).unwrap();
        fs::write(&remove, [2]).unwrap();
        fs::write(&outside, [3]).unwrap();
        let note = notes.join("daily").join("2026-07-10.md");
        fs::write(&note, "no images").unwrap();

        fs::write(&note, "![keep](../images/keep.png)").unwrap();
        let result = delete_unused(
            temp.path.to_str().unwrap(),
            vec![
                "keep.png".to_string(),
                "remove.png".to_string(),
                outside.to_string_lossy().into_owned(),
            ],
        );

        assert!(result.ok, "{}", result.error_message);
        assert_eq!(result.deleted_images.len(), 1);
        assert_eq!(result.deleted_images[0].relative_path, "remove.png");
        assert_eq!(result.skipped_count, 2);
        assert!(keep.exists());
        assert!(!remove.exists());
        assert!(outside.exists());
    }

    #[cfg(unix)]
    #[test]
    fn scan_rejects_a_linked_images_directory() {
        use std::os::unix::fs::symlink;

        let temp = setup_data_directory("spring_note_image_link");
        let images = temp.path.join("notes").join("images");
        let outside = temp.path.join("outside");
        fs::remove_dir(&images).unwrap();
        fs::create_dir_all(&outside).unwrap();
        fs::write(outside.join("outside.png"), [1]).unwrap();
        symlink(&outside, &images).unwrap();

        let result = scan(temp.path.to_str().unwrap());

        assert!(!result.ok);
        assert!(outside.join("outside.png").exists());
    }
}
