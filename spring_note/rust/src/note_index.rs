use rusqlite::{Connection, OptionalExtension, Transaction, params};
use std::collections::{HashMap, HashSet};
use std::fmt;
use std::fs::{self, Metadata};
use std::io;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const INDEX_DB_FILENAME: &str = ".springnote-note-index.db";
const INDEX_SCHEMA_VERSION: i32 = 3;
const DB_BUSY_TIMEOUT: Duration = Duration::from_secs(5);
const MIN_CONTENT_QUERY_CHARS: usize = 2;
const MAX_SEARCH_FILES: usize = 100;
const LARGE_REMOVAL_MIN_FILES: usize = 64;

static INITIALIZED_DATABASES: OnceLock<Mutex<HashSet<PathBuf>>> = OnceLock::new();

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NoteIndexEntry {
    pub path: String,
    pub name: String,
    pub title: String,
    pub preview: String,
    pub kind: String,
    pub modified_millis: i64,
    pub size_bytes: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NoteIndexListResult {
    pub ok: bool,
    pub error_message: String,
    pub notes: Vec<NoteIndexEntry>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NoteIndexRefreshResult {
    pub ok: bool,
    pub error_message: String,
    pub indexed_count: i32,
    pub removed_count: i32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NoteContentResult {
    pub ok: bool,
    pub error_message: String,
    pub content: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NoteSearchResult {
    pub ok: bool,
    pub error_message: String,
    pub notes: Vec<NoteIndexEntry>,
}

#[derive(Debug)]
enum IndexError {
    Validation(String),
    Io {
        action: &'static str,
        path: PathBuf,
        source: io::Error,
    },
    Database(rusqlite::Error),
}

impl IndexError {
    fn io(action: &'static str, path: impl Into<PathBuf>, source: io::Error) -> Self {
        Self::Io {
            action,
            path: path.into(),
            source,
        }
    }
}

impl fmt::Display for IndexError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Validation(message) => formatter.write_str(message),
            Self::Io {
                action,
                path,
                source,
            } => write!(formatter, "{action}: {} ({source})", path.display()),
            Self::Database(source) => write!(formatter, "便签索引数据库错误: {source}"),
        }
    }
}

impl From<rusqlite::Error> for IndexError {
    fn from(value: rusqlite::Error) -> Self {
        Self::Database(value)
    }
}

struct IndexedDocument {
    entry: NoteIndexEntry,
    scope: String,
    content: String,
    modified_nanos: i64,
}

pub fn list(directory_path: &str, kind: &str) -> NoteIndexListResult {
    match list_internal(directory_path, kind) {
        Ok(notes) => NoteIndexListResult {
            ok: true,
            error_message: String::new(),
            notes,
        },
        Err(error) => NoteIndexListResult {
            ok: false,
            error_message: error.to_string(),
            notes: Vec::new(),
        },
    }
}

pub fn refresh(directory_path: &str, kind: &str) -> NoteIndexRefreshResult {
    match refresh_internal(directory_path, kind) {
        Ok((indexed_count, removed_count)) => NoteIndexRefreshResult {
            ok: true,
            error_message: String::new(),
            indexed_count: count_to_i32(indexed_count),
            removed_count: count_to_i32(removed_count),
        },
        Err(error) => NoteIndexRefreshResult {
            ok: false,
            error_message: error.to_string(),
            indexed_count: 0,
            removed_count: 0,
        },
    }
}

pub fn index_file(directory_path: &str, kind: &str, note_path: &str) -> NoteIndexRefreshResult {
    match index_file_internal(directory_path, kind, note_path) {
        Ok((indexed_count, removed_count)) => NoteIndexRefreshResult {
            ok: true,
            error_message: String::new(),
            indexed_count: count_to_i32(indexed_count),
            removed_count: count_to_i32(removed_count),
        },
        Err(error) => NoteIndexRefreshResult {
            ok: false,
            error_message: error.to_string(),
            indexed_count: 0,
            removed_count: 0,
        },
    }
}

pub fn load_content(directory_path: &str, note_path: &str) -> NoteContentResult {
    match load_content_internal(directory_path, note_path) {
        Ok(content) => NoteContentResult {
            ok: true,
            error_message: String::new(),
            content,
        },
        Err(error) => NoteContentResult {
            ok: false,
            error_message: error.to_string(),
            content: String::new(),
        },
    }
}

pub fn search(directory_path: &str, kind: &str, query: &str) -> NoteSearchResult {
    match search_internal(directory_path, kind, query) {
        Ok(notes) => NoteSearchResult {
            ok: true,
            error_message: String::new(),
            notes,
        },
        Err(error) => NoteSearchResult {
            ok: false,
            error_message: error.to_string(),
            notes: Vec::new(),
        },
    }
}

pub fn search_all(
    daily_directory_path: &str,
    weekly_directory_path: &str,
    monthly_directory_path: &str,
    queries: &[String],
    max_results: i32,
) -> NoteSearchResult {
    match search_all_internal(
        daily_directory_path,
        weekly_directory_path,
        monthly_directory_path,
        queries,
        max_results,
    ) {
        Ok(notes) => NoteSearchResult {
            ok: true,
            error_message: String::new(),
            notes,
        },
        Err(error) => NoteSearchResult {
            ok: false,
            error_message: error.to_string(),
            notes: Vec::new(),
        },
    }
}

fn list_internal(directory_path: &str, kind: &str) -> Result<Vec<NoteIndexEntry>, IndexError> {
    validate_kind(kind)?;
    let directory = prepare_directory(directory_path)?;
    let scope = scope_key(&directory);
    let connection = open_connection(&directory)?;
    let mut statement = connection.prepare(
        "SELECT path, name, title, preview, kind, modified_millis, size_bytes
         FROM note_index
         WHERE scope = ?1 AND kind = ?2
         ORDER BY name COLLATE NOCASE DESC",
    )?;
    let rows = statement.query_map(params![scope, kind], note_entry_from_row)?;
    let notes = rows.collect::<Result<Vec<_>, _>>()?;
    let reconciled = connection
        .query_row(
            "SELECT 1 FROM note_index_state WHERE scope = ?1 AND kind = ?2",
            params![scope, kind],
            |_| Ok(()),
        )
        .optional()?
        .is_some();
    if !reconciled {
        let mut merged = list_metadata_entries(&directory, kind)?
            .into_iter()
            .map(|note| (note.path.clone(), note))
            .collect::<HashMap<_, _>>();
        for note in notes {
            merged.insert(note.path.clone(), note);
        }
        let mut notes = merged.into_values().collect::<Vec<_>>();
        notes.sort_by(|left, right| right.name.to_lowercase().cmp(&left.name.to_lowercase()));
        return Ok(notes);
    }
    Ok(notes)
}

fn list_metadata_entries(directory: &Path, kind: &str) -> Result<Vec<NoteIndexEntry>, IndexError> {
    let entries = fs::read_dir(directory)
        .map_err(|source| IndexError::io("无法扫描便签目录", directory, source))?;
    let mut notes = Vec::new();
    for entry in entries {
        let entry =
            entry.map_err(|source| IndexError::io("无法读取便签目录项", directory, source))?;
        let path = entry.path();
        if !is_markdown_file(&path) {
            continue;
        }
        let file_type = entry
            .file_type()
            .map_err(|source| IndexError::io("无法读取便签类型", &path, source))?;
        if !file_type.is_file() {
            continue;
        }
        let metadata = entry
            .metadata()
            .map_err(|source| IndexError::io("无法读取便签信息", &path, source))?;
        let name = entry.file_name().to_string_lossy().into_owned();
        let modified_nanos = modified_nanos(&metadata);
        notes.push(NoteIndexEntry {
            path: path_key(&path),
            title: name
                .strip_suffix(".md")
                .or_else(|| name.strip_suffix(".MD"))
                .unwrap_or(&name)
                .to_owned(),
            name,
            preview: String::new(),
            kind: kind.to_owned(),
            modified_millis: modified_nanos / 1_000_000,
            size_bytes: i64::try_from(metadata.len()).unwrap_or(i64::MAX),
        });
    }
    notes.sort_by(|left, right| right.name.to_lowercase().cmp(&left.name.to_lowercase()));
    Ok(notes)
}

fn refresh_internal(directory_path: &str, kind: &str) -> Result<(usize, usize), IndexError> {
    validate_kind(kind)?;
    let directory = prepare_directory(directory_path)?;
    let scope = scope_key(&directory);
    let mut connection = open_connection(&directory)?;
    let existing = existing_fingerprints(&connection, &scope, kind)?;
    let mut seen = HashSet::new();
    let mut changed = Vec::new();

    let entries = fs::read_dir(&directory)
        .map_err(|source| IndexError::io("无法扫描便签目录", &directory, source))?;
    for entry in entries {
        let entry =
            entry.map_err(|source| IndexError::io("无法读取便签目录项", &directory, source))?;
        let path = entry.path();
        if !is_markdown_file(&path) {
            continue;
        }
        let file_type = entry
            .file_type()
            .map_err(|source| IndexError::io("无法读取便签类型", &path, source))?;
        if !file_type.is_file() {
            continue;
        }

        let path_key = path_key(&path);
        seen.insert(path_key.clone());
        let metadata = entry
            .metadata()
            .map_err(|source| IndexError::io("无法读取便签信息", &path, source))?;
        let fingerprint = metadata_fingerprint(&metadata);
        if existing
            .get(&path_key)
            .is_some_and(|value| *value == fingerprint)
        {
            continue;
        }
        changed.push(read_indexed_document(&directory, &scope, kind, &path)?);
    }

    let stale = existing
        .keys()
        .filter(|path| !seen.contains(*path) && !Path::new(path.as_str()).exists())
        .cloned()
        .collect::<Vec<_>>();
    let should_compact = should_compact_after_removal(stale.len(), existing.len());
    let transaction = connection.transaction()?;
    let migrated_scope_rows = transaction.execute(
        "DELETE FROM note_index WHERE kind = ?1 AND scope <> ?2",
        params![kind, scope],
    )?;
    transaction.execute(
        "DELETE FROM note_index_state WHERE kind = ?1 AND scope <> ?2",
        params![kind, scope],
    )?;
    let mut indexed_count = 0;
    for document in &changed {
        indexed_count += usize::from(upsert_document(&transaction, document)?);
    }
    for path in &stale {
        transaction.execute("DELETE FROM note_index WHERE path = ?1", params![path])?;
    }
    if should_compact {
        transaction.execute(
            "INSERT INTO note_index_maintenance (key, value)
             VALUES ('compaction_pending', 1)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            [],
        )?;
    }
    transaction.execute(
        "INSERT INTO note_index_state (scope, kind, refreshed_millis)
         VALUES (?1, ?2, ?3)
         ON CONFLICT(scope, kind) DO UPDATE SET
            refreshed_millis = excluded.refreshed_millis",
        params![
            scope,
            kind,
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis()
                .min(i64::MAX as u128) as i64,
        ],
    )?;
    transaction.commit()?;
    let _ = run_pending_compaction(&connection);
    Ok((
        indexed_count,
        stale.len().saturating_add(migrated_scope_rows),
    ))
}

fn index_file_internal(
    directory_path: &str,
    kind: &str,
    note_path: &str,
) -> Result<(usize, usize), IndexError> {
    validate_kind(kind)?;
    let directory = prepare_directory(directory_path)?;
    let path = validate_note_path(&directory, note_path)?;
    let scope = scope_key(&directory);
    let mut connection = open_connection(&directory)?;
    if !path.exists() {
        let removed = connection.execute(
            "DELETE FROM note_index WHERE path = ?1 AND scope = ?2 AND kind = ?3",
            params![path_key(&path), scope, kind],
        )?;
        return Ok((0, removed));
    }

    let document = read_indexed_document(&directory, &scope, kind, &path)?;
    let transaction = connection.transaction()?;
    let indexed = upsert_document(&transaction, &document)?;
    transaction.commit()?;
    Ok((usize::from(indexed), 0))
}

fn load_content_internal(directory_path: &str, note_path: &str) -> Result<String, IndexError> {
    let directory = prepare_directory(directory_path)?;
    let path = validate_note_path(&directory, note_path)?;
    if !path.exists() {
        return Ok(String::new());
    }
    fs::read_to_string(&path).map_err(|source| IndexError::io("无法读取便签", path, source))
}

fn search_internal(
    directory_path: &str,
    kind: &str,
    raw_query: &str,
) -> Result<Vec<NoteIndexEntry>, IndexError> {
    validate_kind(kind)?;
    let query = raw_query.trim();
    if query.chars().count() < MIN_CONTENT_QUERY_CHARS {
        return Ok(Vec::new());
    }

    let directory = prepare_directory(directory_path)?;
    let scope = scope_key(&directory);
    let connection = open_connection(&directory)?;
    fts_search_entries(&connection, &scope, kind, query).map_err(IndexError::from)
}

fn search_all_internal(
    daily_directory_path: &str,
    weekly_directory_path: &str,
    monthly_directory_path: &str,
    queries: &[String],
    max_results: i32,
) -> Result<Vec<NoteIndexEntry>, IndexError> {
    let Some(expression) = bigram_search_expression(queries) else {
        return Ok(Vec::new());
    };
    let daily = prepare_directory(daily_directory_path)?;
    let weekly = prepare_directory(weekly_directory_path)?;
    let monthly = prepare_directory(monthly_directory_path)?;
    let database_path = index_database_path(&daily)?;
    if index_database_path(&weekly)? != database_path
        || index_database_path(&monthly)? != database_path
    {
        return Err(IndexError::Validation(
            "日报、周报和月报目录未共用同一个索引数据库".to_owned(),
        ));
    }

    for (directory, kind) in [
        (&daily, "daily"),
        (&weekly, "weekly"),
        (&monthly, "monthly"),
    ] {
        refresh_internal(directory.to_string_lossy().as_ref(), kind)?;
    }

    let connection = open_connection(&daily)?;
    fts_search_all_entries(
        &connection,
        &scope_key(&daily),
        &scope_key(&weekly),
        &scope_key(&monthly),
        &expression,
        max_results.clamp(1, 200) as usize,
    )
    .map_err(IndexError::from)
}

fn fts_search_entries(
    connection: &Connection,
    scope: &str,
    kind: &str,
    query: &str,
) -> Result<Vec<NoteIndexEntry>, rusqlite::Error> {
    let expression = format!("\"{}\"", bigram_token_stream(query));
    let mut statement = connection.prepare(
        "SELECT note_index.path, note_index.name, note_index.title,
                note_index.preview, note_index.kind,
                note_index.modified_millis, note_index.size_bytes
         FROM note_index_fts
         JOIN note_index ON note_index.id = note_index_fts.rowid
         WHERE note_index_fts MATCH ?1
           AND note_index.scope = ?2
           AND note_index.kind = ?3
         ORDER BY note_index.name COLLATE NOCASE DESC
         LIMIT ?4",
    )?;
    let rows = statement.query_map(
        params![expression, scope, kind, MAX_SEARCH_FILES as i64],
        note_entry_from_row,
    )?;
    rows.collect::<Result<Vec<_>, _>>()
}

fn fts_search_all_entries(
    connection: &Connection,
    daily_scope: &str,
    weekly_scope: &str,
    monthly_scope: &str,
    expression: &str,
    max_results: usize,
) -> Result<Vec<NoteIndexEntry>, rusqlite::Error> {
    let mut statement = connection.prepare(
        "SELECT note_index.path, note_index.name, note_index.title,
                note_index.preview, note_index.kind,
                note_index.modified_millis, note_index.size_bytes
         FROM note_index_fts
         JOIN note_index ON note_index.id = note_index_fts.rowid
         WHERE note_index_fts MATCH ?1
           AND ((note_index.scope = ?2 AND note_index.kind = 'daily')
             OR (note_index.scope = ?3 AND note_index.kind = 'weekly')
             OR (note_index.scope = ?4 AND note_index.kind = 'monthly'))
         ORDER BY bm25(note_index_fts), note_index.name COLLATE NOCASE DESC
         LIMIT ?5",
    )?;
    let rows = statement.query_map(
        params![
            expression,
            daily_scope,
            weekly_scope,
            monthly_scope,
            max_results as i64,
        ],
        note_entry_from_row,
    )?;
    rows.collect::<Result<Vec<_>, _>>()
}

fn bigram_search_expression(queries: &[String]) -> Option<String> {
    let mut seen = HashSet::new();
    let phrases = queries
        .iter()
        .map(|query| query.trim())
        .filter(|query| query.chars().count() >= MIN_CONTENT_QUERY_CHARS)
        .filter_map(|query| {
            let tokens = bigram_token_stream(query);
            seen.insert(tokens.clone()).then(|| format!("\"{tokens}\""))
        })
        .collect::<Vec<_>>();
    (!phrases.is_empty()).then(|| phrases.join(" OR "))
}

fn existing_fingerprints(
    connection: &Connection,
    scope: &str,
    kind: &str,
) -> Result<HashMap<String, (i64, i64)>, rusqlite::Error> {
    let mut statement = connection.prepare(
        "SELECT path, modified_nanos, size_bytes
         FROM note_index WHERE scope = ?1 AND kind = ?2",
    )?;
    let rows = statement.query_map(params![scope, kind], |row| {
        Ok((
            row.get::<_, String>(0)?,
            (row.get::<_, i64>(1)?, row.get::<_, i64>(2)?),
        ))
    })?;
    rows.collect::<Result<HashMap<_, _>, _>>()
}

fn upsert_document(
    transaction: &Transaction<'_>,
    document: &IndexedDocument,
) -> Result<bool, rusqlite::Error> {
    let row_id = transaction
        .query_row(
            "INSERT INTO note_index (
            path, scope, kind, name, title, preview,
            modified_nanos, modified_millis, size_bytes
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
         ON CONFLICT(path) DO UPDATE SET
            scope = excluded.scope,
            kind = excluded.kind,
            name = excluded.name,
            title = excluded.title,
            preview = excluded.preview,
            modified_nanos = excluded.modified_nanos,
            modified_millis = excluded.modified_millis,
            size_bytes = excluded.size_bytes
         WHERE excluded.modified_nanos >= note_index.modified_nanos
         RETURNING id",
            params![
                document.entry.path,
                document.scope,
                document.entry.kind,
                document.entry.name,
                document.entry.title,
                document.entry.preview,
                document.modified_nanos,
                document.entry.modified_millis,
                document.entry.size_bytes,
            ],
            |row| row.get::<_, i64>(0),
        )
        .optional()?;
    let Some(row_id) = row_id else {
        return Ok(false);
    };

    transaction.execute(
        "DELETE FROM note_index_fts WHERE rowid = ?1",
        params![row_id],
    )?;
    transaction.execute(
        "INSERT INTO note_index_fts(rowid, name_bigrams, title_bigrams, content_bigrams)
         VALUES (?1, ?2, ?3, ?4)",
        params![
            row_id,
            bigram_token_stream(&document.entry.name),
            bigram_token_stream(&document.entry.title),
            bigram_token_stream(&document.content),
        ],
    )?;
    Ok(true)
}

fn bigram_token_stream(value: &str) -> String {
    let normalized = value.to_lowercase();
    let pair_count = normalized.chars().count().saturating_sub(1);
    let mut characters = normalized.chars();
    let Some(mut previous) = characters.next() else {
        return String::new();
    };
    let mut tokens = String::with_capacity(pair_count.saturating_mul(13));
    for current in characters {
        if !tokens.is_empty() {
            tokens.push(' ');
        }
        let pair = ((previous as u64) << 21) | current as u64;
        push_hex_bigram_token(&mut tokens, pair);
        previous = current;
    }
    tokens
}

fn push_hex_bigram_token(output: &mut String, pair: u64) {
    const HEX_DIGITS: &[u8; 16] = b"0123456789abcdef";
    output.push('b');
    let digit_count = ((u64::BITS - pair.leading_zeros()).max(1) as usize).div_ceil(4);
    for index in (0..digit_count).rev() {
        let digit = ((pair >> (index * 4)) & 0x0f) as usize;
        output.push(HEX_DIGITS[digit] as char);
    }
}

fn read_indexed_document(
    directory: &Path,
    scope: &str,
    kind: &str,
    path: &Path,
) -> Result<IndexedDocument, IndexError> {
    validate_note_path(directory, path.to_string_lossy().as_ref())?;
    let (content, metadata) = read_stable(path)?;
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| IndexError::Validation("便签文件名不是有效文本".to_owned()))?
        .to_owned();
    let modified_nanos = modified_nanos(&metadata);
    Ok(IndexedDocument {
        entry: NoteIndexEntry {
            path: path_key(path),
            name: name.clone(),
            title: title_from_content(&content, &name),
            preview: preview_from_content(&content),
            kind: kind.to_owned(),
            modified_millis: modified_nanos / 1_000_000,
            size_bytes: i64::try_from(metadata.len()).unwrap_or(i64::MAX),
        },
        scope: scope.to_owned(),
        content,
        modified_nanos,
    })
}

fn read_stable(path: &Path) -> Result<(String, Metadata), IndexError> {
    for _ in 0..2 {
        let before = fs::metadata(path)
            .map_err(|source| IndexError::io("无法读取便签信息", path, source))?;
        let content = fs::read_to_string(path)
            .map_err(|source| IndexError::io("无法读取便签", path, source))?;
        let after = fs::metadata(path)
            .map_err(|source| IndexError::io("无法再次读取便签信息", path, source))?;
        if metadata_fingerprint(&before) == metadata_fingerprint(&after) {
            return Ok((content, after));
        }
    }
    Err(IndexError::Validation(format!(
        "便签在建立索引时持续变化: {}",
        path.display()
    )))
}

fn open_connection(directory: &Path) -> Result<Connection, IndexError> {
    let database_path = index_database_path(directory)?;
    let database_existed = database_path.exists();
    let connection = Connection::open(&database_path)?;
    connection.busy_timeout(DB_BUSY_TIMEOUT)?;
    let initialized_databases = INITIALIZED_DATABASES.get_or_init(|| Mutex::new(HashSet::new()));
    let mut initialized = initialized_databases
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if database_existed && initialized.contains(&database_path) {
        return Ok(connection);
    }
    connection.execute_batch(
        "PRAGMA journal_mode = WAL;
         PRAGMA synchronous = NORMAL;",
    )?;
    let schema_version =
        connection.pragma_query_value(None, "user_version", |row| row.get::<_, i32>(0))?;
    if schema_version != INDEX_SCHEMA_VERSION {
        rebuild_schema(&connection, database_existed)?;
    } else {
        create_schema(&connection)?;
    }
    let _ = run_pending_compaction(&connection);
    initialized.insert(database_path);
    Ok(connection)
}

fn rebuild_schema(connection: &Connection, database_existed: bool) -> Result<(), IndexError> {
    connection.execute_batch(
        "DROP TRIGGER IF EXISTS note_index_ai;
         DROP TRIGGER IF EXISTS note_index_ad;
         DROP TRIGGER IF EXISTS note_index_au;
         DROP TABLE IF EXISTS note_index_fts;
         DROP TABLE IF EXISTS note_index_state;
         DROP TABLE IF EXISTS note_index_maintenance;
         DROP TABLE IF EXISTS note_index;",
    )?;
    if database_existed {
        connection.execute_batch("PRAGMA wal_checkpoint(TRUNCATE); VACUUM;")?;
    }
    create_schema(connection)
}

fn create_schema(connection: &Connection) -> Result<(), IndexError> {
    connection.execute_batch(
        "CREATE TABLE IF NOT EXISTS note_index (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL UNIQUE,
            scope TEXT NOT NULL,
            kind TEXT NOT NULL,
            name TEXT NOT NULL,
            title TEXT NOT NULL,
            preview TEXT NOT NULL,
            modified_nanos INTEGER NOT NULL,
            modified_millis INTEGER NOT NULL,
            size_bytes INTEGER NOT NULL
         );
         CREATE INDEX IF NOT EXISTS note_index_scope_kind_name
            ON note_index(scope, kind, name COLLATE NOCASE DESC);
         CREATE TABLE IF NOT EXISTS note_index_state (
            scope TEXT NOT NULL,
            kind TEXT NOT NULL,
            refreshed_millis INTEGER NOT NULL,
            PRIMARY KEY(scope, kind)
         );
         CREATE TABLE IF NOT EXISTS note_index_maintenance (
            key TEXT PRIMARY KEY,
            value INTEGER NOT NULL
         );
         CREATE VIRTUAL TABLE IF NOT EXISTS note_index_fts USING fts5(
            name_bigrams,
            title_bigrams,
            content_bigrams,
            content = '',
            contentless_delete = 1,
            tokenize = 'unicode61'
         );
         CREATE TRIGGER IF NOT EXISTS note_index_ad AFTER DELETE ON note_index BEGIN
            DELETE FROM note_index_fts WHERE rowid = old.id;
         END;
         PRAGMA user_version = 3;",
    )?;
    Ok(())
}

fn should_compact_after_removal(removed_count: usize, previous_count: usize) -> bool {
    removed_count >= LARGE_REMOVAL_MIN_FILES
        && previous_count > 0
        && removed_count.saturating_mul(2) >= previous_count
}

fn run_pending_compaction(connection: &Connection) -> Result<(), rusqlite::Error> {
    let pending = connection
        .query_row(
            "SELECT value FROM note_index_maintenance WHERE key = 'compaction_pending'",
            [],
            |row| row.get::<_, i64>(0),
        )
        .optional()?
        .is_some_and(|value| value != 0);
    if !pending {
        return Ok(());
    }

    connection.execute(
        "INSERT INTO note_index_fts(note_index_fts) VALUES('optimize')",
        [],
    )?;
    connection.execute_batch("PRAGMA wal_checkpoint(TRUNCATE); VACUUM;")?;
    connection.execute(
        "DELETE FROM note_index_maintenance WHERE key = 'compaction_pending'",
        [],
    )?;
    Ok(())
}

fn index_database_path(directory: &Path) -> Result<PathBuf, IndexError> {
    let notes_directory = directory
        .parent()
        .ok_or_else(|| IndexError::Validation("便签目录缺少父目录".to_owned()))?;
    let root = if notes_directory
        .file_name()
        .and_then(|value| value.to_str())
        .is_some_and(|value| value.eq_ignore_ascii_case("notes"))
    {
        notes_directory.parent().unwrap_or(notes_directory)
    } else {
        notes_directory
    };
    Ok(root.join(INDEX_DB_FILENAME))
}

fn prepare_directory(directory_path: &str) -> Result<PathBuf, IndexError> {
    let directory = PathBuf::from(directory_path);
    fs::create_dir_all(&directory)
        .map_err(|source| IndexError::io("无法创建便签目录", &directory, source))?;
    fs::canonicalize(&directory)
        .map_err(|source| IndexError::io("无法定位便签目录", directory, source))
}

fn validate_note_path(directory: &Path, note_path: &str) -> Result<PathBuf, IndexError> {
    let path = PathBuf::from(note_path);
    if !is_markdown_file(&path) {
        return Err(IndexError::Validation(
            "只允许读取 Markdown 便签".to_owned(),
        ));
    }

    if path.exists() {
        let canonical = fs::canonicalize(&path)
            .map_err(|source| IndexError::io("无法定位便签", &path, source))?;
        if canonical.parent() != Some(directory) {
            return Err(IndexError::Validation("便签不在当前便签目录中".to_owned()));
        }
        return Ok(canonical);
    }

    let parent = path
        .parent()
        .ok_or_else(|| IndexError::Validation("便签路径缺少父目录".to_owned()))?;
    let canonical_parent = fs::canonicalize(parent)
        .map_err(|source| IndexError::io("无法定位便签父目录", parent, source))?;
    if canonical_parent != directory {
        return Err(IndexError::Validation("便签不在当前便签目录中".to_owned()));
    }
    Ok(path)
}

fn validate_kind(kind: &str) -> Result<(), IndexError> {
    match kind {
        "daily" | "weekly" | "monthly" => Ok(()),
        _ => Err(IndexError::Validation("未知的便签类型".to_owned())),
    }
}

fn scope_key(directory: &Path) -> String {
    path_key(directory)
}

fn path_key(path: &Path) -> String {
    let raw = path.to_string_lossy().replace('\\', "/");
    let value = if let Some(network_path) = raw.strip_prefix("//?/UNC/") {
        format!("//{network_path}")
    } else {
        raw.strip_prefix("//?/").unwrap_or(&raw).to_owned()
    };
    if cfg!(windows) {
        value.to_lowercase()
    } else {
        value
    }
}

fn is_markdown_file(path: &Path) -> bool {
    path.extension()
        .and_then(|value| value.to_str())
        .is_some_and(|value| value.eq_ignore_ascii_case("md"))
}

fn metadata_fingerprint(metadata: &Metadata) -> (i64, i64) {
    (
        modified_nanos(metadata),
        i64::try_from(metadata.len()).unwrap_or(i64::MAX),
    )
}

fn modified_nanos(metadata: &Metadata) -> i64 {
    metadata
        .modified()
        .unwrap_or(SystemTime::UNIX_EPOCH)
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos()
        .min(i64::MAX as u128) as i64
}

fn title_from_content(content: &str, fallback_name: &str) -> String {
    for line in content.lines() {
        let trimmed = line.trim();
        if let Some(title) = trimmed.strip_prefix("# ") {
            return title.trim().to_owned();
        }
        if !trimmed.is_empty() {
            return truncate_chars(trimmed, 28, true);
        }
    }
    fallback_name
        .strip_suffix(".md")
        .or_else(|| fallback_name.strip_suffix(".MD"))
        .unwrap_or(fallback_name)
        .to_owned()
}

fn preview_from_content(content: &str) -> String {
    let body = body_text_from_content(content, true);
    truncate_chars(&body, 72, true)
}

fn body_text_from_content(content: &str, skip_first_line: bool) -> String {
    let lines = content
        .lines()
        .map(str::trim)
        .map(strip_heading_prefix)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>();
    lines
        .into_iter()
        .skip(usize::from(skip_first_line))
        .collect::<Vec<_>>()
        .join(" ")
}

fn strip_heading_prefix(line: &str) -> &str {
    let bytes = line.as_bytes();
    let hashes = bytes.iter().take_while(|value| **value == b'#').count();
    if (1..=6).contains(&hashes)
        && bytes
            .get(hashes)
            .is_some_and(|value| value.is_ascii_whitespace())
    {
        return line[hashes..].trim_start();
    }
    line
}

fn truncate_chars(value: &str, limit: usize, ellipsis: bool) -> String {
    let mut characters = value.chars();
    let prefix = characters.by_ref().take(limit).collect::<String>();
    if ellipsis && characters.next().is_some() {
        format!("{prefix}...")
    } else {
        prefix
    }
}

fn note_entry_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<NoteIndexEntry> {
    Ok(NoteIndexEntry {
        path: row.get(0)?,
        name: row.get(1)?,
        title: row.get(2)?,
        preview: row.get(3)?,
        kind: row.get(4)?,
        modified_millis: row.get(5)?,
        size_bytes: row.get(6)?,
    })
}

fn count_to_i32(value: usize) -> i32 {
    i32::try_from(value).unwrap_or(i32::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

    #[test]
    fn refresh_lists_loads_and_searches_notes_incrementally() {
        let root = temp_root();
        let daily = root.join("notes").join("daily");
        fs::create_dir_all(&daily).unwrap();
        let first = daily.join("2026-07-12.md");
        fs::write(&first, "# 2026-07-12 日报\n\n😀 完成 Rust 全文搜索算法\n").unwrap();

        let initial_list = list(daily.to_str().unwrap(), "daily");
        assert!(initial_list.ok, "{}", initial_list.error_message);
        assert_eq!(initial_list.notes.len(), 1);
        assert_eq!(initial_list.notes[0].title, "2026-07-12");

        let refreshed = refresh(daily.to_str().unwrap(), "daily");
        assert!(refreshed.ok, "{}", refreshed.error_message);
        assert_eq!(refreshed.indexed_count, 1);
        assert_eq!(refresh(daily.to_str().unwrap(), "daily").indexed_count, 0);

        let listed = list(daily.to_str().unwrap(), "daily");
        assert!(listed.ok, "{}", listed.error_message);
        assert_eq!(listed.notes.len(), 1);
        assert_eq!(listed.notes[0].title, "2026-07-12 日报");

        let search_result = search(daily.to_str().unwrap(), "daily", "搜索算法");
        assert!(search_result.ok, "{}", search_result.error_message);
        assert_eq!(search_result.notes.len(), 1);
        assert_eq!(search_result.notes[0].path, path_key(&first));

        let bigram_query = search(daily.to_str().unwrap(), "daily", "搜索");
        assert!(bigram_query.ok, "{}", bigram_query.error_message);
        assert_eq!(bigram_query.notes.len(), 1);

        let case_insensitive_query = search(daily.to_str().unwrap(), "daily", "RUST");
        assert!(
            case_insensitive_query.ok,
            "{}",
            case_insensitive_query.error_message
        );
        assert_eq!(case_insensitive_query.notes.len(), 1);

        let short_query = search(daily.to_str().unwrap(), "daily", "搜");
        assert!(short_query.ok, "{}", short_query.error_message);
        assert!(short_query.notes.is_empty());

        let loaded = load_content(daily.to_str().unwrap(), first.to_str().unwrap());
        assert!(loaded.ok, "{}", loaded.error_message);
        assert!(loaded.content.contains("Rust 全文搜索"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn schema_keeps_search_content_only_in_contentless_fts() {
        let root = temp_root();
        let daily = root.join("notes").join("daily");
        fs::create_dir_all(&daily).unwrap();
        fs::write(
            daily.join("2026-07-12.md"),
            "# 日报\n\n数据库不保存完整正文副本\n",
        )
        .unwrap();
        assert!(refresh(daily.to_str().unwrap(), "daily").ok);

        let connection = Connection::open(index_database_path(&daily).unwrap()).unwrap();
        let columns = connection
            .prepare("PRAGMA table_info(note_index)")
            .unwrap()
            .query_map([], |row| row.get::<_, String>(1))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert!(!columns.iter().any(|column| column == "content"));
        let fts_schema = connection
            .query_row(
                "SELECT sql FROM sqlite_master WHERE name = 'note_index_fts'",
                [],
                |row| row.get::<_, String>(0),
            )
            .unwrap();
        let normalized_fts_schema = fts_schema.split_whitespace().collect::<String>();
        assert!(normalized_fts_schema.contains("contentless_delete=1"));
        assert!(normalized_fts_schema.contains("name_bigrams"));
        assert!(!normalized_fts_schema.contains("tokenize='trigram'"));

        drop(connection);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn global_search_queries_daily_weekly_and_monthly_in_one_database() {
        let root = temp_root();
        let notes = root.join("notes");
        let daily = notes.join("daily");
        let weekly = notes.join("weekly");
        let monthly = notes.join("monthly");
        fs::create_dir_all(&daily).unwrap();
        fs::create_dir_all(&weekly).unwrap();
        fs::create_dir_all(&monthly).unwrap();
        fs::write(daily.join("2026-07-12.md"), "# 日报\n\n完成全局检索\n").unwrap();
        fs::write(weekly.join("2026-W28.md"), "# 周报\n\n复盘全局检索\n").unwrap();
        fs::write(monthly.join("2026-07.md"), "# 月报\n\n总结全局检索\n").unwrap();

        let result = search_all(
            daily.to_str().unwrap(),
            weekly.to_str().unwrap(),
            monthly.to_str().unwrap(),
            &["全局".to_owned(), "检索".to_owned(), "单".to_owned()],
            10,
        );
        assert!(result.ok, "{}", result.error_message);
        assert_eq!(result.notes.len(), 3);
        assert_eq!(
            result
                .notes
                .iter()
                .map(|note| note.kind.as_str())
                .collect::<HashSet<_>>(),
            HashSet::from(["daily", "weekly", "monthly"]),
        );

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn large_removal_compacts_database() {
        let root = temp_root();
        let daily = root.join("notes").join("daily");
        fs::create_dir_all(&daily).unwrap();
        for index in 0..96 {
            fs::write(
                daily.join(format!("2026-{index:04}.md")),
                format!(
                    "# 第 {index} 篇日报\n\n{}\n",
                    format!("唯一搜索内容{index:04} Rust SQLite ").repeat(160)
                ),
            )
            .unwrap();
        }
        assert!(refresh(daily.to_str().unwrap(), "daily").ok);
        let database = index_database_path(&daily).unwrap();
        let before = fs::metadata(&database).unwrap().len();

        for index in 3..96 {
            fs::remove_file(daily.join(format!("2026-{index:04}.md"))).unwrap();
        }
        let refreshed = refresh(daily.to_str().unwrap(), "daily");
        assert!(refreshed.ok, "{}", refreshed.error_message);
        assert_eq!(refreshed.removed_count, 93);
        let after = fs::metadata(&database).unwrap().len();
        assert!(
            after < before,
            "database did not shrink: {before} -> {after}"
        );
        assert_eq!(list(daily.to_str().unwrap(), "daily").notes.len(), 3);

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn refresh_removes_deleted_notes_and_rejects_outside_paths() {
        let root = temp_root();
        let daily = root.join("notes").join("daily");
        fs::create_dir_all(&daily).unwrap();
        let note = daily.join("2026-07-11.md");
        fs::write(&note, "# 日报\n").unwrap();
        assert!(refresh(daily.to_str().unwrap(), "daily").ok);

        fs::remove_file(&note).unwrap();
        let refreshed = refresh(daily.to_str().unwrap(), "daily");
        assert!(refreshed.ok, "{}", refreshed.error_message);
        assert_eq!(refreshed.removed_count, 1);
        assert!(list(daily.to_str().unwrap(), "daily").notes.is_empty());

        let outside = root.join("outside.md");
        fs::write(&outside, "# outside").unwrap();
        let loaded = load_content(daily.to_str().unwrap(), outside.to_str().unwrap());
        assert!(!loaded.ok);

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn unreconciled_list_merges_indexed_and_metadata_only_notes() {
        let root = temp_root();
        let daily = root.join("notes").join("daily");
        fs::create_dir_all(&daily).unwrap();
        let first = daily.join("2026-07-12.md");
        let second = daily.join("2026-07-11.md");
        fs::write(&first, "# 已索引日报\n").unwrap();
        fs::write(&second, "# 尚未索引日报\n").unwrap();

        let indexed = index_file(daily.to_str().unwrap(), "daily", first.to_str().unwrap());
        assert!(indexed.ok, "{}", indexed.error_message);
        let listed = list(daily.to_str().unwrap(), "daily");
        assert!(listed.ok, "{}", listed.error_message);
        assert_eq!(listed.notes.len(), 2);
        assert!(listed.notes.iter().any(|note| note.title == "已索引日报"));
        assert!(listed.notes.iter().any(|note| note.title == "2026-07-11"));

        fs::remove_dir_all(root).unwrap();
    }

    fn temp_root() -> PathBuf {
        let counter = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!(
            "springnote-note-index-{}-{nanos}-{counter}",
            std::process::id()
        ))
    }
}
