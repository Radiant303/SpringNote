use crate::note_image_cleanup::{self, NoteImageCleanupDeleteResult, NoteImageCleanupScanResult};

pub fn scan_note_images(data_directory: String) -> NoteImageCleanupScanResult {
    note_image_cleanup::scan(&data_directory)
}

pub fn delete_unused_note_images(
    data_directory: String,
    candidate_relative_paths: Vec<String>,
) -> NoteImageCleanupDeleteResult {
    note_image_cleanup::delete_unused(&data_directory, candidate_relative_paths)
}
