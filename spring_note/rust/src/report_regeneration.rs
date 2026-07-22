use std::fs;
use std::path::{Path, PathBuf};

use chrono::{Datelike, Duration, NaiveDate, Weekday};

use crate::ai::{self, AiModel, AiProvider, AiTextResult, DailyMergeRequest, ReportRequest};

#[derive(Clone, Debug)]
pub struct RegenerateReportRequest {
    pub app_data_dir: String,
    pub provider: AiProvider,
    pub model: AiModel,
    pub kind: String,
    pub target_path: String,
    pub daily_notes_directory: String,
    pub weekly_notes_directory: String,
    pub industry: String,
    pub daily_merge_prompt: String,
    pub api_log_enabled: bool,
}

#[derive(Clone, Debug)]
pub struct RegenerateReportResult {
    pub ok: bool,
    pub path: String,
    pub error_code: String,
    pub error_message: String,
}

impl RegenerateReportResult {
    fn success(path: &Path) -> Self {
        Self {
            ok: true,
            path: path.to_string_lossy().to_string(),
            error_code: String::new(),
            error_message: String::new(),
        }
    }

    fn failure(code: &str, message: impl Into<String>) -> Self {
        Self {
            ok: false,
            path: String::new(),
            error_code: code.to_string(),
            error_message: message.into(),
        }
    }
}

enum ReportPeriod {
    Daily(NaiveDate),
    Weekly(NaiveDate),
    Monthly(NaiveDate),
}

pub async fn regenerate_report(request: RegenerateReportRequest) -> RegenerateReportResult {
    let target_path = PathBuf::from(&request.target_path);
    let Some(file_stem) = target_path.file_stem().and_then(|stem| stem.to_str()) else {
        return RegenerateReportResult::failure(
            "invalid_period",
            format!("无法从文件名解析报告周期：{}", request.target_path),
        );
    };

    let Some(period) = parse_period(&request.kind, file_stem) else {
        return RegenerateReportResult::failure(
            "invalid_period",
            format!("无法从文件名解析报告周期：{file_stem}"),
        );
    };

    match period {
        ReportPeriod::Daily(date) => regenerate_daily(&request, &target_path, date).await,
        ReportPeriod::Weekly(week_start) => {
            regenerate_weekly(&request, &target_path, week_start).await
        }
        ReportPeriod::Monthly(month) => regenerate_monthly(&request, &target_path, month).await,
    }
}

async fn regenerate_daily(
    request: &RegenerateReportRequest,
    target_path: &Path,
    date: NaiveDate,
) -> RegenerateReportResult {
    let Some(existing) = read_meaningful_markdown(target_path) else {
        return RegenerateReportResult::failure("empty_source", "当前日报没有内容可整理。");
    };

    let date_label = format_date(date);
    let merge_prompt = render_daily_merge_template(
        &request.daily_merge_prompt,
        &date_label,
        &existing,
        &request.industry,
    );
    let response = ai::merge_daily_note(DailyMergeRequest {
        app_data_dir: request.app_data_dir.clone(),
        provider: request.provider.clone(),
        model: request.model.clone(),
        existing_markdown: existing.clone(),
        raw_input: String::new(),
        date: date_label,
        industry: request.industry.clone(),
        merge_prompt,
        api_log_enabled: request.api_log_enabled,
    })
    .await;
    write_generated(target_path, response, Some(&existing))
}

async fn regenerate_weekly(
    request: &RegenerateReportRequest,
    target_path: &Path,
    week_start: NaiveDate,
) -> RegenerateReportResult {
    let source = daily_source_for_week(Path::new(&request.daily_notes_directory), week_start);
    if source.is_empty() {
        return RegenerateReportResult::failure("empty_source", "该周没有可用的日报内容。");
    }

    let week_end = week_start + Duration::days(6);
    let period_label = format!(
        "{}（{} 至 {}）",
        format_iso_week(week_start),
        format_date(week_start),
        format_date(week_end)
    );
    let response = ai::generate_weekly_report(ReportRequest {
        app_data_dir: request.app_data_dir.clone(),
        provider: request.provider.clone(),
        model: request.model.clone(),
        source_markdown: source,
        period_label,
        industry: request.industry.clone(),
        api_log_enabled: request.api_log_enabled,
    })
    .await;
    write_generated(target_path, response, None)
}

async fn regenerate_monthly(
    request: &RegenerateReportRequest,
    target_path: &Path,
    month: NaiveDate,
) -> RegenerateReportResult {
    let source = weekly_source_for_month(Path::new(&request.weekly_notes_directory), month);
    if source.is_empty() {
        return RegenerateReportResult::failure("empty_source", "该月没有可用的周报内容。");
    }

    let period_label = format!("{} 月报", format_month(month));
    let response = ai::generate_monthly_report(ReportRequest {
        app_data_dir: request.app_data_dir.clone(),
        provider: request.provider.clone(),
        model: request.model.clone(),
        source_markdown: source,
        period_label,
        industry: request.industry.clone(),
        api_log_enabled: request.api_log_enabled,
    })
    .await;
    write_generated(target_path, response, None)
}

fn write_generated(
    target_path: &Path,
    response: AiTextResult,
    expected_unchanged: Option<&str>,
) -> RegenerateReportResult {
    if !response.ok {
        let message = if response.error_message.trim().is_empty() {
            "模型调用失败，请稍后重试。".to_string()
        } else {
            response.error_message
        };
        return RegenerateReportResult::failure("ai_failed", message);
    }
    if response.content.trim().is_empty() {
        return RegenerateReportResult::failure("ai_failed", "模型返回内容为空。");
    }

    if let Some(expected) = expected_unchanged {
        let current = fs::read_to_string(target_path).unwrap_or_default();
        if current.trim_end() != expected.trim_end() {
            return RegenerateReportResult::failure(
                "conflict",
                "生成期间日报有新内容写入，未覆盖，请重新生成。",
            );
        }
    }

    let content = format!("{}\n", response.content.trim_end());
    match fs::write(target_path, content) {
        Ok(()) => RegenerateReportResult::success(target_path),
        Err(error) => {
            RegenerateReportResult::failure("io_failed", format!("无法写入文件：{error}"))
        }
    }
}

fn parse_period(kind: &str, file_stem: &str) -> Option<ReportPeriod> {
    match kind {
        "daily" => {
            let date = NaiveDate::parse_from_str(file_stem, "%Y-%m-%d").ok()?;
            if format_date(date) != file_stem {
                return None;
            }
            Some(ReportPeriod::Daily(date))
        }
        "weekly" => {
            let (year, week) = file_stem.split_once('-')?;
            let week = week.strip_prefix('W').or_else(|| week.strip_prefix('w'))?;
            if year.len() != 4 || week.len() != 2 {
                return None;
            }
            let year = year.parse::<i32>().ok()?;
            let week = week.parse::<u32>().ok()?;
            let monday = NaiveDate::from_isoywd_opt(year, week, Weekday::Mon)?;
            Some(ReportPeriod::Weekly(monday))
        }
        "monthly" => {
            let (year, month) = file_stem.split_once('-')?;
            if year.len() != 4 || month.len() != 2 {
                return None;
            }
            let year = year.parse::<i32>().ok()?;
            let month = month.parse::<u32>().ok()?;
            let first = NaiveDate::from_ymd_opt(year, month, 1)?;
            if format_month(first) != file_stem {
                return None;
            }
            Some(ReportPeriod::Monthly(first))
        }
        _ => None,
    }
}

fn daily_source_for_week(daily_dir: &Path, week_start: NaiveDate) -> String {
    let mut source = String::new();
    for index in 0..7 {
        let date = week_start + Duration::days(index);
        let path = daily_dir.join(format!("{}.md", format_date(date)));
        let Some(content) = read_meaningful_markdown(&path) else {
            continue;
        };
        source.push_str(&format!("## {} 日报\n\n{}\n\n", format_date(date), content));
    }
    source.trim_end().to_string()
}

fn weekly_source_for_month(weekly_dir: &Path, month: NaiveDate) -> String {
    let (year, month_number) = (month.year(), month.month());
    let Some(next_month) = (if month_number == 12 {
        NaiveDate::from_ymd_opt(year + 1, 1, 1)
    } else {
        NaiveDate::from_ymd_opt(year, month_number + 1, 1)
    }) else {
        return String::new();
    };
    let month_end = next_month - Duration::days(1);

    let mut source = String::new();
    let mut week_start = week_start(month);
    while week_start <= month_end {
        let label = format_iso_week(week_start);
        let upper_path = weekly_dir.join(format!("{label}.md"));
        let lower_path = weekly_dir.join(format!("{}.md", label.replacen('W', "w", 1)));
        let content =
            read_meaningful_markdown(&upper_path).or_else(|| read_meaningful_markdown(&lower_path));
        if let Some(content) = content {
            source.push_str(&format!("## {label} 周报\n\n{content}\n\n"));
        }
        week_start += Duration::days(7);
    }
    source.trim_end().to_string()
}

fn read_meaningful_markdown(path: &Path) -> Option<String> {
    let content = fs::read_to_string(path).ok()?;
    if !has_meaningful_content(&content) {
        return None;
    }
    Some(content.trim_end().to_string())
}

fn has_meaningful_content(content: &str) -> bool {
    content
        .lines()
        .map(str::trim)
        .any(|line| !line.is_empty() && !line.starts_with('#'))
}

fn render_daily_merge_template(
    template: &str,
    date: &str,
    existing_markdown: &str,
    industry: &str,
) -> String {
    let existing = if existing_markdown.trim().is_empty() {
        "（空）"
    } else {
        existing_markdown.trim()
    };
    let industry = if industry.trim().is_empty() {
        "未设置"
    } else {
        industry.trim()
    };
    template
        .replace("{date}", date)
        .replace("{existing_markdown}", existing)
        .replace("{raw_input}", "")
        .replace("{completed}", "（空）")
        .replace("{issues}", "（空）")
        .replace("{plans}", "（空）")
        .replace("{industry}", industry)
}

fn week_start(date: NaiveDate) -> NaiveDate {
    date - Duration::days(date.weekday().num_days_from_monday() as i64)
}

fn format_date(date: NaiveDate) -> String {
    date.format("%Y-%m-%d").to_string()
}

fn format_month(date: NaiveDate) -> String {
    date.format("%Y-%m").to_string()
}

fn format_iso_week(date: NaiveDate) -> String {
    let week = date.iso_week();
    format!("{:04}-W{:02}", week.year(), week.week())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

    #[test]
    fn parse_daily_period_accepts_padded_date() {
        let Some(ReportPeriod::Daily(date)) = parse_period("daily", "2026-07-22") else {
            panic!("expected daily period");
        };
        assert_eq!(date, NaiveDate::from_ymd_opt(2026, 7, 22).unwrap());
    }

    #[test]
    fn parse_daily_period_rejects_unpadded_or_invalid_date() {
        assert!(parse_period("daily", "2026-7-22").is_none());
        assert!(parse_period("daily", "2026-13-01").is_none());
        assert!(parse_period("daily", "note").is_none());
    }

    #[test]
    fn parse_weekly_period_returns_iso_week_monday() {
        let Some(ReportPeriod::Weekly(monday)) = parse_period("weekly", "2026-W30") else {
            panic!("expected weekly period");
        };
        assert_eq!(monday.weekday(), Weekday::Mon);
        assert_eq!(format_iso_week(monday), "2026-W30");
    }

    #[test]
    fn parse_weekly_period_handles_cross_year_week() {
        let Some(ReportPeriod::Weekly(monday)) = parse_period("weekly", "2026-W01") else {
            panic!("expected weekly period");
        };
        assert_eq!(monday, NaiveDate::from_ymd_opt(2025, 12, 29).unwrap());
    }

    #[test]
    fn parse_weekly_period_accepts_lowercase_w() {
        let Some(ReportPeriod::Weekly(monday)) = parse_period("weekly", "2026-w29") else {
            panic!("expected weekly period");
        };
        assert_eq!(monday.weekday(), Weekday::Mon);
        assert_eq!(format_iso_week(monday), "2026-W29");
    }

    #[test]
    fn parse_weekly_period_rejects_invalid_week() {
        assert!(parse_period("weekly", "2026-W54").is_none());
        assert!(parse_period("weekly", "2026-W1").is_none());
        assert!(parse_period("weekly", "W30").is_none());
    }

    #[test]
    fn parse_monthly_period_returns_first_day() {
        let Some(ReportPeriod::Monthly(month)) = parse_period("monthly", "2026-07") else {
            panic!("expected monthly period");
        };
        assert_eq!(month, NaiveDate::from_ymd_opt(2026, 7, 1).unwrap());
        assert!(parse_period("monthly", "2026-13").is_none());
    }

    #[test]
    fn parse_period_rejects_unknown_kind() {
        assert!(parse_period("yearly", "2026").is_none());
    }

    #[test]
    fn meaningful_content_requires_non_heading_text() {
        assert!(!has_meaningful_content(""));
        assert!(!has_meaningful_content("# 标题\n\n## 小节\n"));
        assert!(has_meaningful_content("# 标题\n\n今天完成了接口联调。\n"));
    }

    #[test]
    fn daily_source_for_week_skips_missing_and_empty_notes() {
        let root = temp_root();
        let daily = root.join("daily");
        fs::create_dir_all(&daily).unwrap();
        fs::write(
            daily.join("2026-07-20.md"),
            "# 2026-07-20 日报\n\n完成了联调。\n",
        )
        .unwrap();
        fs::write(daily.join("2026-07-21.md"), "# 只有标题\n").unwrap();
        fs::write(daily.join("2026-07-23.md"), "\n\n排查了线上问题。\n").unwrap();

        let week_start = NaiveDate::from_ymd_opt(2026, 7, 20).unwrap();
        let source = daily_source_for_week(&daily, week_start);

        assert!(source.contains("## 2026-07-20 日报"));
        assert!(source.contains("完成了联调。"));
        assert!(source.contains("## 2026-07-23 日报"));
        assert!(source.contains("排查了线上问题。"));
        assert!(!source.contains("2026-07-21"));
        assert!(!source.contains("2026-07-22"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn daily_source_for_week_returns_empty_without_notes() {
        let root = temp_root();
        let daily = root.join("daily");
        fs::create_dir_all(&daily).unwrap();
        let week_start = NaiveDate::from_ymd_opt(2026, 7, 20).unwrap();
        assert!(daily_source_for_week(&daily, week_start).is_empty());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn weekly_source_for_month_includes_cross_month_week_in_both_months() {
        let root = temp_root();
        let weekly = root.join("weekly");
        fs::create_dir_all(&weekly).unwrap();
        fs::write(weekly.join("2026-W01.md"), "# 周报\n\n跨月周的内容。\n").unwrap();
        fs::write(weekly.join("2026-W05.md"), "# 只有标题\n").unwrap();

        let january =
            weekly_source_for_month(&weekly, NaiveDate::from_ymd_opt(2026, 1, 1).unwrap());
        let december =
            weekly_source_for_month(&weekly, NaiveDate::from_ymd_opt(2025, 12, 1).unwrap());

        assert!(january.contains("## 2026-W01 周报"));
        assert!(january.contains("跨月周的内容。"));
        assert!(december.contains("## 2026-W01 周报"));
        assert!(december.contains("跨月周的内容。"));
        assert!(!january.contains("2026-W05"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn weekly_source_for_month_finds_lowercase_weekly_file() {
        let root = temp_root();
        let weekly = root.join("weekly");
        fs::create_dir_all(&weekly).unwrap();
        fs::write(weekly.join("2026-w29.md"), "# 周报\n\n小写文件名周报。\n").unwrap();

        let july = weekly_source_for_month(&weekly, NaiveDate::from_ymd_opt(2026, 7, 1).unwrap());

        assert!(july.contains("## 2026-W29 周报"));
        assert!(july.contains("小写文件名周报。"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn render_daily_merge_template_replaces_all_placeholders() {
        let rendered = render_daily_merge_template(
            "日期:{date} 已有:{existing_markdown} 新增:{raw_input} 完成:{completed} 问题:{issues} 计划:{plans} 行业:{industry}",
            "2026-07-22",
            "  已有内容。  ",
            "",
        );
        assert_eq!(
            rendered,
            "日期:2026-07-22 已有:已有内容。 新增: 完成:（空） 问题:（空） 计划:（空） 行业:未设置"
        );
    }

    #[test]
    fn write_generated_skips_write_when_content_changed_during_generation() {
        let root = temp_root();
        fs::create_dir_all(&root).unwrap();
        let target = root.join("2026-07-22.md");
        fs::write(&target, "# 日报\n\n首页新写入的内容\n").unwrap();

        let result = write_generated(
            &target,
            ok_response("AI 整理后的内容"),
            Some("# 日报\n\n生成开始前的内容"),
        );

        assert!(!result.ok);
        assert_eq!(result.error_code, "conflict");
        assert_eq!(
            fs::read_to_string(&target).unwrap(),
            "# 日报\n\n首页新写入的内容\n"
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn write_generated_writes_when_content_unchanged() {
        let root = temp_root();
        fs::create_dir_all(&root).unwrap();
        let target = root.join("2026-07-22.md");
        fs::write(&target, "# 日报\n\n生成开始前的内容\n").unwrap();

        let result = write_generated(
            &target,
            ok_response("AI 整理后的内容"),
            Some("# 日报\n\n生成开始前的内容"),
        );

        assert!(result.ok, "{}", result.error_message);
        assert_eq!(fs::read_to_string(&target).unwrap(), "AI 整理后的内容\n");
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn write_generated_rejects_empty_ai_content() {
        let root = temp_root();
        fs::create_dir_all(&root).unwrap();
        let target = root.join("2026-07-22.md");
        fs::write(&target, "# 日报\n\n原有内容\n").unwrap();

        let result = write_generated(&target, ok_response("   "), None);

        assert!(!result.ok);
        assert_eq!(result.error_code, "ai_failed");
        assert_eq!(fs::read_to_string(&target).unwrap(), "# 日报\n\n原有内容\n");
        fs::remove_dir_all(root).unwrap();
    }

    fn ok_response(content: &str) -> AiTextResult {
        AiTextResult {
            ok: true,
            content: content.to_string(),
            error_code: String::new(),
            error_message: String::new(),
            input_tokens: 0,
            output_tokens: 0,
            cached_tokens: 0,
            provider_name: String::new(),
            model_id: String::new(),
        }
    }

    fn temp_root() -> PathBuf {
        let counter = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!(
            "springnote-report-regeneration-{}-{nanos}-{counter}",
            std::process::id()
        ))
    }
}
