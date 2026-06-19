use crate::ai::{AiChatRequest, AiTextResult};
use chrono::Local;
use rusqlite::{Connection, OptionalExtension, Result, params};
use std::fs;
use std::path::Path;

#[derive(Clone, Debug)]
pub struct StatsSummary {
    pub summaries: i32,
    pub fim_completions: i32,
    pub total_records: i32,
    pub daily_notes: i32,
    pub weekly_notes: i32,
    pub monthly_notes: i32,
    pub input_tokens: i32,
    pub output_tokens: i32,
    pub cached_tokens: i32,
    pub app_launches: i32,
    pub work_seconds: i32,
    pub coins: f64,
}

#[derive(Clone, Debug)]
pub struct DailyActivity {
    pub date: String,
    pub count: i32,
}

#[derive(Clone, Debug)]
pub struct DailyTokenUsage {
    pub date: String,
    pub input_tokens: i32,
    pub output_tokens: i32,
    pub cached_tokens: i32,
    pub total_tokens: i32,
}

#[derive(Clone, Debug)]
pub struct ProviderTokenUsage {
    pub date: String,
    pub provider_name: String,
    pub model_id: String,
    pub tokens: i32,
}

#[derive(Clone, Debug)]
pub struct StatsSnapshot {
    pub summary: StatsSummary,
    pub activity: Vec<DailyActivity>,
    pub token_usage: Vec<DailyTokenUsage>,
    pub provider_usage: Vec<ProviderTokenUsage>,
}

pub fn record_model_call(
    app_data_dir: &str,
    request: &AiChatRequest,
    result: &AiTextResult,
) -> Result<()> {
    let connection = open_connection(app_data_dir)?;
    initialize(&connection)?;

    connection.execute(
        "INSERT INTO model_call_records (
            created_at,
            provider_id,
            provider_name,
            protocol,
            model_id,
            purpose,
            ok,
            error_code,
            error_message,
            input_tokens,
            output_tokens,
            cached_tokens
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)",
        params![
            Local::now().to_rfc3339(),
            &request.provider.id,
            &request.provider.name,
            &request.provider.protocol,
            &request.model.model_id,
            &request.purpose,
            if result.ok { 1 } else { 0 },
            &result.error_code,
            &result.error_message,
            result.input_tokens,
            result.output_tokens,
            result.cached_tokens,
        ],
    )?;

    connection.execute(
        "INSERT INTO token_usage_daily (
            date,
            input_tokens,
            output_tokens,
            cached_tokens,
            call_count
        ) VALUES (date('now', 'localtime'), ?1, ?2, ?3, 1)
        ON CONFLICT(date) DO UPDATE SET
            input_tokens = input_tokens + excluded.input_tokens,
            output_tokens = output_tokens + excluded.output_tokens,
            cached_tokens = cached_tokens + excluded.cached_tokens,
            call_count = call_count + 1",
        params![
            result.input_tokens,
            result.output_tokens,
            result.cached_tokens,
        ],
    )?;

    if result.ok && request.purpose == "fim_edit_completion" {
        increment_daily_stats(app_data_dir, 0, 1, 0, 0.0, 1)?;
    }

    Ok(())
}

pub fn record_app_startup(app_data_dir: &str) -> Result<()> {
    let connection = open_connection(app_data_dir)?;
    initialize(&connection)?;
    connection.execute(
        "INSERT INTO app_counters (key, value) VALUES ('app_launches', 1)
        ON CONFLICT(key) DO UPDATE SET value = value + 1",
        [],
    )?;
    Ok(())
}

pub fn record_home_generation(app_data_dir: &str) -> Result<()> {
    increment_daily_stats(app_data_dir, 1, 0, 0, 0.0, 1)
}

pub fn record_work_time(app_data_dir: &str, work_seconds: i32, coins: f64) -> Result<()> {
    increment_daily_stats(app_data_dir, 0, 0, work_seconds.max(0), coins.max(0.0), 0)
}

pub fn get_stats_snapshot(
    app_data_dir: &str,
    daily_notes_dir: &str,
    weekly_notes_dir: &str,
    monthly_notes_dir: &str,
    start_date: &str,
    end_date: &str,
) -> Result<StatsSnapshot> {
    let connection = open_connection(app_data_dir)?;
    initialize(&connection)?;

    let (daily_notes, weekly_notes, monthly_notes) = (
        count_markdown_files(daily_notes_dir),
        count_markdown_files(weekly_notes_dir),
        count_markdown_files(monthly_notes_dir),
    );

    let summaries: i32 = connection.query_row(
        "SELECT COALESCE(SUM(CASE
            WHEN home_generations > 10 THEN 10
            ELSE home_generations
        END), 0) FROM daily_stats WHERE date BETWEEN ?1 AND ?2",
        params![start_date, end_date],
        |row| row.get(0),
    )?;
    let fim_completions: i32 = connection.query_row(
        "SELECT COALESCE(SUM(fim_completions), 0) FROM daily_stats WHERE date BETWEEN ?1 AND ?2",
        params![start_date, end_date],
        |row| row.get(0),
    )?;
    let work_seconds: i32 = connection.query_row(
        "SELECT COALESCE(SUM(work_seconds), 0) FROM daily_stats WHERE date BETWEEN ?1 AND ?2",
        params![start_date, end_date],
        |row| row.get(0),
    )?;
    let coins: f64 = connection.query_row(
        "SELECT COALESCE(SUM(coins), 0) FROM daily_stats WHERE date BETWEEN ?1 AND ?2",
        params![start_date, end_date],
        |row| row.get(0),
    )?;
    let (input_tokens, output_tokens, cached_tokens): (i32, i32, i32) = connection.query_row(
        "SELECT
            COALESCE(SUM(input_tokens), 0),
            COALESCE(SUM(output_tokens), 0),
            COALESCE(SUM(cached_tokens), 0)
        FROM token_usage_daily
        WHERE date BETWEEN ?1 AND ?2",
        params![start_date, end_date],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
    )?;
    let app_launches: i32 = connection
        .query_row(
            "SELECT value FROM app_counters WHERE key = 'app_launches'",
            [],
            |row| row.get(0),
        )
        .optional()?
        .unwrap_or(0);

    let mut activity_statement = connection.prepare(
        "SELECT date, active_count FROM daily_stats WHERE date BETWEEN ?1 AND ?2 ORDER BY date",
    )?;
    let activity = activity_statement
        .query_map(params![start_date, end_date], |row| {
            Ok(DailyActivity {
                date: row.get(0)?,
                count: row.get(1)?,
            })
        })?
        .collect::<Result<Vec<_>>>()?;

    let mut token_statement = connection.prepare(
        "SELECT date, input_tokens, output_tokens, cached_tokens
        FROM token_usage_daily
        WHERE date BETWEEN ?1 AND ?2
        ORDER BY date",
    )?;
    let token_usage = token_statement
        .query_map(params![start_date, end_date], |row| {
            let input_tokens: i32 = row.get(1)?;
            let output_tokens: i32 = row.get(2)?;
            let cached_tokens: i32 = row.get(3)?;
            Ok(DailyTokenUsage {
                date: row.get(0)?,
                input_tokens,
                output_tokens,
                cached_tokens,
                total_tokens: input_tokens + output_tokens + cached_tokens,
            })
        })?
        .collect::<Result<Vec<_>>>()?;

    let mut provider_statement = connection.prepare(
        "SELECT
            substr(created_at, 1, 10) AS date,
            provider_name,
            model_id,
            COALESCE(SUM(input_tokens + output_tokens + cached_tokens), 0) AS tokens
        FROM model_call_records
        WHERE substr(created_at, 1, 10) BETWEEN ?1 AND ?2
        GROUP BY date, provider_name, model_id
        ORDER BY date, provider_name, model_id",
    )?;
    let provider_usage = provider_statement
        .query_map(params![start_date, end_date], |row| {
            Ok(ProviderTokenUsage {
                date: row.get(0)?,
                provider_name: row.get(1)?,
                model_id: row.get(2)?,
                tokens: row.get(3)?,
            })
        })?
        .collect::<Result<Vec<_>>>()?;

    Ok(StatsSnapshot {
        summary: StatsSummary {
            summaries,
            fim_completions,
            total_records: daily_notes + weekly_notes + monthly_notes,
            daily_notes,
            weekly_notes,
            monthly_notes,
            input_tokens,
            output_tokens,
            cached_tokens,
            app_launches,
            work_seconds,
            coins,
        },
        activity,
        token_usage,
        provider_usage,
    })
}

fn increment_daily_stats(
    app_data_dir: &str,
    home_generations: i32,
    fim_completions: i32,
    work_seconds: i32,
    coins: f64,
    active_count: i32,
) -> Result<()> {
    let connection = open_connection(app_data_dir)?;
    initialize(&connection)?;
    connection.execute(
        "INSERT INTO daily_stats (
            date,
            home_generations,
            fim_completions,
            work_seconds,
            coins,
            active_count
        ) VALUES (date('now', 'localtime'), ?1, ?2, ?3, ?4, ?5)
        ON CONFLICT(date) DO UPDATE SET
            home_generations = home_generations + excluded.home_generations,
            fim_completions = fim_completions + excluded.fim_completions,
            work_seconds = work_seconds + excluded.work_seconds,
            coins = coins + excluded.coins,
            active_count = active_count + excluded.active_count",
        params![
            home_generations,
            fim_completions,
            work_seconds,
            coins,
            active_count,
        ],
    )?;
    Ok(())
}

fn open_connection(app_data_dir: &str) -> Result<Connection> {
    fs::create_dir_all(app_data_dir).ok();
    let db_path = Path::new(app_data_dir).join("springnote.db");
    Connection::open(db_path)
}

fn initialize(connection: &Connection) -> Result<()> {
    connection.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS model_call_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at TEXT NOT NULL,
            provider_id TEXT NOT NULL,
            provider_name TEXT NOT NULL,
            protocol TEXT NOT NULL,
            model_id TEXT NOT NULL,
            purpose TEXT NOT NULL,
            ok INTEGER NOT NULL,
            error_code TEXT NOT NULL,
            error_message TEXT NOT NULL,
            input_tokens INTEGER NOT NULL DEFAULT 0,
            output_tokens INTEGER NOT NULL DEFAULT 0,
            cached_tokens INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS token_usage_daily (
            date TEXT PRIMARY KEY,
            input_tokens INTEGER NOT NULL DEFAULT 0,
            output_tokens INTEGER NOT NULL DEFAULT 0,
            cached_tokens INTEGER NOT NULL DEFAULT 0,
            call_count INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS daily_stats (
            date TEXT PRIMARY KEY,
            home_generations INTEGER NOT NULL DEFAULT 0,
            fim_completions INTEGER NOT NULL DEFAULT 0,
            work_seconds INTEGER NOT NULL DEFAULT 0,
            coins REAL NOT NULL DEFAULT 0,
            active_count INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS app_counters (
            key TEXT PRIMARY KEY,
            value INTEGER NOT NULL DEFAULT 0
        );
        ",
    )?;
    Ok(())
}

fn count_markdown_files(directory: &str) -> i32 {
    let Ok(entries) = fs::read_dir(directory) else {
        return 0;
    };
    entries
        .filter_map(Result::ok)
        .filter(|entry| {
            entry
                .path()
                .extension()
                .and_then(|extension| extension.to_str())
                .is_some_and(|extension| extension.eq_ignore_ascii_case("md"))
        })
        .count() as i32
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::{AiModel, AiProvider};
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn writes_model_call_records() {
        let dir = temp_dir("spring_note_stats_model");
        let app_data_dir = dir.to_string_lossy().to_string();
        let request = request(&app_data_dir, "test");
        let result = AiTextResult::success(&request, "ok", 3, 5, 1);

        record_model_call(&app_data_dir, &request, &result).unwrap();

        let connection = Connection::open(dir.join("springnote.db")).unwrap();
        let count: i64 = connection
            .query_row("SELECT COUNT(*) FROM model_call_records", [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(count, 1);
        fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn records_and_reads_stats_snapshot() {
        let dir = temp_dir("spring_note_stats_snapshot");
        let app_data_dir = dir.to_string_lossy().to_string();
        let daily = dir.join("notes").join("daily");
        let weekly = dir.join("notes").join("weekly");
        let monthly = dir.join("notes").join("monthly");
        fs::create_dir_all(&daily).unwrap();
        fs::create_dir_all(&weekly).unwrap();
        fs::create_dir_all(&monthly).unwrap();
        fs::write(daily.join("2026-06-18.md"), "# 日报").unwrap();
        fs::write(weekly.join("2026-W25.md"), "# 周报").unwrap();

        record_app_startup(&app_data_dir).unwrap();
        record_home_generation(&app_data_dir).unwrap();
        let fim_request = request(&app_data_dir, "fim_edit_completion");
        let fim_result = AiTextResult::success(&fim_request, "ok", 10, 6, 2);
        record_model_call(&app_data_dir, &fim_request, &fim_result).unwrap();

        let today = Local::now().format("%Y-%m-%d").to_string();
        let snapshot = get_stats_snapshot(
            &app_data_dir,
            &daily.to_string_lossy(),
            &weekly.to_string_lossy(),
            &monthly.to_string_lossy(),
            &today,
            &today,
        )
        .unwrap();

        assert_eq!(snapshot.summary.app_launches, 1);
        assert_eq!(snapshot.summary.summaries, 1);
        assert_eq!(snapshot.summary.fim_completions, 1);
        assert_eq!(snapshot.summary.total_records, 2);
        assert_eq!(snapshot.summary.input_tokens, 10);
        assert_eq!(snapshot.summary.output_tokens, 6);
        assert_eq!(snapshot.summary.cached_tokens, 2);
        assert_eq!(snapshot.activity.first().unwrap().count, 2);
        assert_eq!(snapshot.token_usage.first().unwrap().total_tokens, 18);
        assert_eq!(snapshot.provider_usage.first().unwrap().tokens, 18);
        fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn caps_home_generations_at_ten_per_day_for_valid_submissions() {
        let dir = temp_dir("spring_note_stats_generation_cap");
        let app_data_dir = dir.to_string_lossy().to_string();
        let daily = dir.join("notes").join("daily");
        let weekly = dir.join("notes").join("weekly");
        let monthly = dir.join("notes").join("monthly");
        fs::create_dir_all(&daily).unwrap();
        fs::create_dir_all(&weekly).unwrap();
        fs::create_dir_all(&monthly).unwrap();

        for _ in 0..12 {
            record_home_generation(&app_data_dir).unwrap();
        }

        let today = Local::now().format("%Y-%m-%d").to_string();
        let snapshot = get_stats_snapshot(
            &app_data_dir,
            &daily.to_string_lossy(),
            &weekly.to_string_lossy(),
            &monthly.to_string_lossy(),
            &today,
            &today,
        )
        .unwrap();

        assert_eq!(snapshot.summary.summaries, 10);
        fs::remove_dir_all(dir).ok();
    }

    fn request(app_data_dir: &str, purpose: &str) -> AiChatRequest {
        AiChatRequest {
            app_data_dir: app_data_dir.to_string(),
            provider: AiProvider {
                id: "p".to_string(),
                name: "OpenAI".to_string(),
                protocol: "openaiCompatible".to_string(),
                api_key: "key".to_string(),
                base_url: "https://api.example.com".to_string(),
                api_path: "/chat/completions".to_string(),
            },
            model: AiModel {
                model_id: "gpt-test".to_string(),
                display_name: "GPT Test".to_string(),
            },
            system_prompt: String::new(),
            user_prompt: String::new(),
            purpose: purpose.to_string(),
            api_log_enabled: false,
        }
    }

    fn temp_dir(prefix: &str) -> std::path::PathBuf {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("{prefix}_{suffix}"))
    }
}
