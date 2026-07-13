use crate::note_index::{
    self, NoteContentResult, NoteIndexListResult, NoteIndexRefreshResult, NoteSearchResult,
};

pub fn list_indexed_notes(directory_path: String, kind: String) -> NoteIndexListResult {
    note_index::list(&directory_path, &kind)
}

pub fn refresh_note_index(directory_path: String, kind: String) -> NoteIndexRefreshResult {
    note_index::refresh(&directory_path, &kind)
}

pub fn index_note_file(
    directory_path: String,
    kind: String,
    note_path: String,
) -> NoteIndexRefreshResult {
    note_index::index_file(&directory_path, &kind, &note_path)
}

pub fn load_note_content(directory_path: String, note_path: String) -> NoteContentResult {
    note_index::load_content(&directory_path, &note_path)
}

pub fn search_indexed_notes(
    directory_path: String,
    kind: String,
    query: String,
) -> NoteSearchResult {
    note_index::search(&directory_path, &kind, &query)
}

pub fn search_indexed_notes_by_kind(
    directory_path: String,
    kind: String,
    queries: Vec<String>,
    max_results: i32,
) -> NoteSearchResult {
    note_index::search_kind(&directory_path, &kind, &queries, max_results)
}

pub fn search_all_indexed_notes(
    daily_directory_path: String,
    weekly_directory_path: String,
    monthly_directory_path: String,
    queries: Vec<String>,
    max_results: i32,
) -> NoteSearchResult {
    note_index::search_all(
        &daily_directory_path,
        &weekly_directory_path,
        &monthly_directory_path,
        &queries,
        max_results,
    )
}
