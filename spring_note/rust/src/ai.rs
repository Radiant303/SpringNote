use crate::frb_generated::StreamSink;
use crate::{ai_claude, ai_gemini, ai_openai, stats};
use reqwest::Client;
use serde_json::{Value, json};
use std::collections::HashMap;
use std::time::Duration;

/// TCP 连接超时（秒），适用于所有 AI HTTP 请求。
const CONNECT_TIMEOUT_SECS: u64 = 15;
/// 非流式请求总超时（秒），防止网络异常时无限期挂起。
const REQUEST_TIMEOUT_SECS: u64 = 300;
/// 流式请求每块读取超时（秒），避免切断长回答，同时检测连接僵死。
const STREAM_READ_TIMEOUT_SECS: u64 = 120;

/// 为非流式 AI HTTP 请求构建 `reqwest::Client`，已配置连接超时和总超时。
pub(crate) fn http_client() -> Result<Client, String> {
    build_http_client(
        Duration::from_secs(CONNECT_TIMEOUT_SECS),
        Duration::from_secs(REQUEST_TIMEOUT_SECS),
    )
}

/// 为流式 AI HTTP 请求构建 `reqwest::Client`，已配置连接超时和每块读取超时，
/// 不设总超时，避免长回答被过早切断。
pub(crate) fn http_stream_client() -> Result<Client, String> {
    build_http_stream_client(
        Duration::from_secs(CONNECT_TIMEOUT_SECS),
        Duration::from_secs(STREAM_READ_TIMEOUT_SECS),
    )
}

/// 构建带连接超时与请求总超时的 `reqwest::Client`；供本模块测试注入短 Duration 验证超时行为。
fn build_http_client(connect: Duration, request: Duration) -> Result<Client, String> {
    Client::builder()
        .connect_timeout(connect)
        .timeout(request)
        .build()
        .map_err(|error| error.to_string())
}

/// 构建带连接超时与读取超时的 `reqwest::Client`（无总超时）；供本模块测试注入短 Duration 验证超时行为。
fn build_http_stream_client(connect: Duration, read: Duration) -> Result<Client, String> {
    Client::builder()
        .connect_timeout(connect)
        .read_timeout(read)
        .build()
        .map_err(|error| error.to_string())
}

#[derive(Clone, Debug)]
pub struct AiProvider {
    pub id: String,
    pub name: String,
    pub protocol: String,
    pub api_key: String,
    pub base_url: String,
    pub api_path: String,
}

#[derive(Clone, Debug)]
pub struct AiModel {
    pub model_id: String,
    pub display_name: String,
}

#[derive(Clone, Debug)]
pub struct AiImageAttachment {
    pub name: String,
    pub mime_type: String,
    pub data_base64: String,
}

#[derive(Clone, Debug)]
pub struct AiChatRequest {
    pub app_data_dir: String,
    pub provider: AiProvider,
    pub model: AiModel,
    pub system_prompt: String,
    pub user_prompt: String,
    pub images: Vec<AiImageAttachment>,
    pub purpose: String,
    pub api_log_enabled: bool,
}

#[derive(Clone, Debug)]
pub struct AiChatMessage {
    pub role: String,
    pub content: String,
    pub reasoning_content: String,
    pub tool_call_id: String,
    pub tool_calls: Vec<AiToolCall>,
}

#[derive(Clone, Debug)]
pub struct AiToolCall {
    pub id: String,
    pub name: String,
    pub arguments: String,
}

#[derive(Clone, Debug)]
pub struct StructuredNoteSectionDefinition {
    pub id: String,
    pub title: String,
    pub ai_instruction: String,
}

#[derive(Clone, Debug)]
pub struct StructuredNoteSection {
    pub id: String,
    pub items: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct StructuredNoteRequest {
    pub app_data_dir: String,
    pub provider: AiProvider,
    pub model: AiModel,
    pub input: String,
    pub images: Vec<AiImageAttachment>,
    pub sections: Vec<StructuredNoteSectionDefinition>,
    pub industry: String,
    pub api_log_enabled: bool,
}

#[derive(Clone, Debug)]
pub struct DailyMergeRequest {
    pub app_data_dir: String,
    pub provider: AiProvider,
    pub model: AiModel,
    pub existing_markdown: String,
    pub raw_input: String,
    pub date: String,
    pub industry: String,
    pub merge_prompt: String,
    pub api_log_enabled: bool,
}

#[derive(Clone, Debug)]
pub struct ReportRequest {
    pub app_data_dir: String,
    pub provider: AiProvider,
    pub model: AiModel,
    pub source_markdown: String,
    pub period_label: String,
    pub industry: String,
    pub api_log_enabled: bool,
}

#[derive(Clone, Debug)]
pub struct MemoryToolChatRequest {
    pub app_data_dir: String,
    pub provider: AiProvider,
    pub model: AiModel,
    pub messages: Vec<AiChatMessage>,
    pub thinking_enabled: bool,
    pub reasoning_effort: String,
    pub api_log_enabled: bool,
}

#[derive(Clone, Debug)]
pub struct FimCompleteRequest {
    pub app_data_dir: String,
    pub provider: AiProvider,
    pub model: AiModel,
    pub prompt: String,
    pub suffix: String,
    pub api_log_enabled: bool,
}

#[derive(Clone, Debug)]
pub struct AiTextResult {
    pub ok: bool,
    pub content: String,
    pub error_code: String,
    pub error_message: String,
    pub input_tokens: i32,
    pub output_tokens: i32,
    pub cached_tokens: i32,
    pub provider_name: String,
    pub model_id: String,
}

#[derive(Clone, Debug)]
pub struct MemoryToolChatResult {
    pub ok: bool,
    pub content: String,
    pub reasoning_content: String,
    pub tool_calls: Vec<AiToolCall>,
    pub error_code: String,
    pub error_message: String,
    pub input_tokens: i32,
    pub output_tokens: i32,
    pub cached_tokens: i32,
    pub provider_name: String,
    pub model_id: String,
}

#[derive(Clone, Debug)]
pub struct MemoryToolChatStreamEvent {
    pub event_type: String,
    pub content_delta: String,
    pub reasoning_delta: String,
    pub content: String,
    pub reasoning_content: String,
    pub tool_calls: Vec<AiToolCall>,
    pub error_code: String,
    pub error_message: String,
    pub input_tokens: i32,
    pub output_tokens: i32,
    pub cached_tokens: i32,
}

#[derive(Clone, Debug)]
pub struct StructuredNoteResult {
    pub ok: bool,
    pub sections: Vec<StructuredNoteSection>,
    pub raw_content: String,
    pub error_code: String,
    pub error_message: String,
    pub input_tokens: i32,
    pub output_tokens: i32,
    pub cached_tokens: i32,
}

#[derive(Clone, Debug)]
pub struct ProviderTestResult {
    pub ok: bool,
    pub message: String,
    pub error_code: String,
}

#[derive(Clone, Debug)]
pub struct ModelListResult {
    pub ok: bool,
    pub models: Vec<AiModel>,
    pub error_code: String,
    pub error_message: String,
}

pub async fn chat(request: AiChatRequest) -> AiTextResult {
    if request.provider.api_key.trim().is_empty() {
        return AiTextResult::error(
            &request,
            "missing_api_key",
            "供应商 API Key 为空，已保留 mock 流程。",
            0,
            0,
            0,
        );
    }

    let response = match request.provider.protocol.as_str() {
        "gemini" => ai_gemini::chat(&request).await,
        "claude" => ai_claude::chat(&request).await,
        _ => ai_openai::chat(&request).await,
    };

    let result = match response {
        Ok(result) => result,
        Err(error) => AiTextResult::error(&request, "request_failed", &error, 0, 0, 0),
    };

    stats::record_model_call_or_warn("chat", &request.app_data_dir, &request, &result);
    result
}

pub async fn test_provider_connection(
    app_data_dir: String,
    provider: AiProvider,
    model: AiModel,
    api_log_enabled: bool,
) -> ProviderTestResult {
    let request = AiChatRequest {
        app_data_dir,
        provider,
        model,
        system_prompt: "You are a connection test endpoint. Reply with OK only.".to_string(),
        user_prompt: "Say OK.".to_string(),
        images: vec![],
        purpose: "provider_connection_test".to_string(),
        api_log_enabled,
    };
    let result = chat(request).await;
    if result.ok {
        ProviderTestResult {
            ok: true,
            message: "连接成功".to_string(),
            error_code: String::new(),
        }
    } else {
        ProviderTestResult {
            ok: false,
            message: result.error_message,
            error_code: result.error_code,
        }
    }
}

pub async fn fetch_provider_models(
    app_data_dir: String,
    provider: AiProvider,
    api_log_enabled: bool,
) -> ModelListResult {
    if provider.api_key.trim().is_empty() {
        return ModelListResult {
            ok: false,
            models: vec![],
            error_code: "missing_api_key".to_string(),
            error_message: "供应商 API Key 为空。".to_string(),
        };
    }

    let result = match provider.protocol.as_str() {
        "gemini" => ai_gemini::fetch_models(&app_data_dir, &provider, api_log_enabled).await,
        "claude" => ai_claude::fetch_models(&app_data_dir, &provider, api_log_enabled).await,
        _ => ai_openai::fetch_models(&app_data_dir, &provider, api_log_enabled).await,
    };

    match result {
        Ok(models) => {
            let request = AiChatRequest {
                app_data_dir,
                provider: provider.clone(),
                model: AiModel {
                    model_id: "models".to_string(),
                    display_name: "Models".to_string(),
                },
                system_prompt: String::new(),
                user_prompt: String::new(),
                images: vec![],
                purpose: "fetch_provider_models".to_string(),
                api_log_enabled,
            };
            let call_result = AiTextResult::success(&request, "", 0, 0, 0);
            stats::record_model_call_or_warn(
                "fetch_provider_models",
                &request.app_data_dir,
                &request,
                &call_result,
            );
            ModelListResult {
                ok: true,
                models,
                error_code: String::new(),
                error_message: String::new(),
            }
        }
        Err(error) => ModelListResult {
            ok: false,
            models: vec![],
            error_code: "request_failed".to_string(),
            error_message: error,
        },
    }
}

pub async fn generate_structured_note(request: StructuredNoteRequest) -> StructuredNoteResult {
    let sections = request.sections.clone();
    let system_prompt = structured_system_prompt(&request.industry, &sections);
    let result = chat(AiChatRequest {
        app_data_dir: request.app_data_dir,
        provider: request.provider,
        model: request.model,
        system_prompt,
        user_prompt: request.input,
        images: request.images,
        purpose: "home_structured_note".to_string(),
        api_log_enabled: request.api_log_enabled,
    })
    .await;
    if !result.ok {
        return StructuredNoteResult {
            ok: false,
            sections: vec![],
            raw_content: result.content,
            error_code: result.error_code,
            error_message: result.error_message,
            input_tokens: result.input_tokens,
            output_tokens: result.output_tokens,
            cached_tokens: result.cached_tokens,
        };
    }

    parse_structured_note(&result, &sections)
}

pub async fn merge_daily_note(request: DailyMergeRequest) -> AiTextResult {
    chat(AiChatRequest {
        app_data_dir: request.app_data_dir.clone(),
        provider: request.provider.clone(),
        model: request.model.clone(),
        system_prompt: daily_merge_system_prompt(&request),
        user_prompt: daily_merge_user_prompt(&request),
        images: vec![],
        purpose: "daily_note_merge".to_string(),
        api_log_enabled: request.api_log_enabled,
    })
    .await
}

pub async fn generate_weekly_report(request: ReportRequest) -> AiTextResult {
    let user_prompt = report_user_prompt(&request.period_label, &request.source_markdown);
    let system_prompt = with_markdown_attachment_preservation_instruction(with_industry_context(
        WEEKLY_REPORT_SYSTEM_PROMPT,
        &request.industry,
    ));
    chat(AiChatRequest {
        app_data_dir: request.app_data_dir,
        provider: request.provider,
        model: request.model,
        system_prompt,
        user_prompt,
        images: vec![],
        purpose: "weekly_report".to_string(),
        api_log_enabled: request.api_log_enabled,
    })
    .await
}

pub async fn generate_monthly_report(request: ReportRequest) -> AiTextResult {
    let user_prompt = report_user_prompt(&request.period_label, &request.source_markdown);
    let system_prompt = with_markdown_attachment_preservation_instruction(with_industry_context(
        MONTHLY_REPORT_SYSTEM_PROMPT,
        &request.industry,
    ));
    chat(AiChatRequest {
        app_data_dir: request.app_data_dir,
        provider: request.provider,
        model: request.model,
        system_prompt,
        user_prompt,
        images: vec![],
        purpose: "monthly_report".to_string(),
        api_log_enabled: request.api_log_enabled,
    })
    .await
}

pub async fn memory_tool_chat(request: MemoryToolChatRequest) -> MemoryToolChatResult {
    let chat_request = AiChatRequest {
        app_data_dir: request.app_data_dir.clone(),
        provider: request.provider.clone(),
        model: request.model.clone(),
        system_prompt: MEMORY_TOOL_SYSTEM_PROMPT.to_string(),
        user_prompt: request
            .messages
            .iter()
            .map(|message| message.content.as_str())
            .collect::<Vec<_>>()
            .join("\n"),
        images: vec![],
        purpose: "memory_tool_chat".to_string(),
        api_log_enabled: request.api_log_enabled,
    };

    if request.provider.api_key.trim().is_empty() {
        return MemoryToolChatResult::error(
            &chat_request,
            "missing_api_key",
            "供应商 API Key 为空，已保留 mock 流程。",
            0,
            0,
            0,
        );
    }

    if request.provider.protocol != "openaiCompatible" && request.provider.protocol != "gemini" {
        return MemoryToolChatResult::error(
            &chat_request,
            "unsupported_tool_protocol",
            "回忆书工具调用目前仅支持 OpenAI-compatible(Chat Completions / Responses)或 Gemini 供应商。",
            0,
            0,
            0,
        );
    }

    let response = if request.provider.protocol == "gemini" {
        ai_gemini::memory_tool_chat(&request, MEMORY_TOOL_SYSTEM_PROMPT).await
    } else if ai_openai::is_responses_endpoint(&request.provider) {
        ai_openai::memory_tool_responses(&request, MEMORY_TOOL_SYSTEM_PROMPT).await
    } else {
        ai_openai::memory_tool_chat(&request, MEMORY_TOOL_SYSTEM_PROMPT).await
    };
    let result = match response {
        Ok(result) => result,
        Err(error) => MemoryToolChatResult::error(&chat_request, "request_failed", &error, 0, 0, 0),
    };

    let text_result = AiTextResult {
        ok: result.ok,
        content: result.content.clone(),
        error_code: result.error_code.clone(),
        error_message: result.error_message.clone(),
        input_tokens: result.input_tokens,
        output_tokens: result.output_tokens,
        cached_tokens: result.cached_tokens,
        provider_name: result.provider_name.clone(),
        model_id: result.model_id.clone(),
    };
    stats::record_model_call_or_warn(
        "memory_tool_chat",
        &request.app_data_dir,
        &chat_request,
        &text_result,
    );
    result
}

pub async fn memory_tool_chat_stream(
    request: MemoryToolChatRequest,
    sink: StreamSink<MemoryToolChatStreamEvent>,
) {
    let chat_request = AiChatRequest {
        app_data_dir: request.app_data_dir.clone(),
        provider: request.provider.clone(),
        model: request.model.clone(),
        system_prompt: MEMORY_TOOL_SYSTEM_PROMPT.to_string(),
        user_prompt: request
            .messages
            .iter()
            .map(|message| message.content.as_str())
            .collect::<Vec<_>>()
            .join("\n"),
        images: vec![],
        purpose: "memory_tool_chat_stream".to_string(),
        api_log_enabled: request.api_log_enabled,
    };

    if request.provider.protocol != "openaiCompatible" && request.provider.protocol != "gemini" {
        let _ = sink.add(MemoryToolChatStreamEvent::error(
            "unsupported_tool_protocol",
            "回忆书流式工具调用目前仅支持 OpenAI-compatible(Chat Completions / Responses)或 Gemini 供应商。",
        ));
        return;
    }

    let response = if request.provider.protocol == "gemini" {
        ai_gemini::memory_tool_chat_stream(request.clone(), MEMORY_TOOL_SYSTEM_PROMPT, sink.clone())
            .await
    } else if ai_openai::is_responses_endpoint(&request.provider) {
        ai_openai::memory_tool_responses_stream(
            request.clone(),
            MEMORY_TOOL_SYSTEM_PROMPT,
            sink.clone(),
        )
        .await
    } else {
        ai_openai::memory_tool_chat_stream(request.clone(), MEMORY_TOOL_SYSTEM_PROMPT, sink.clone())
            .await
    };

    if let Err(error) = response {
        let _ = sink.add(MemoryToolChatStreamEvent::error("request_failed", &error));
        let result = AiTextResult::error(&chat_request, "request_failed", &error, 0, 0, 0);
        stats::record_model_call_or_warn(
            "memory_tool_chat_stream",
            &request.app_data_dir,
            &chat_request,
            &result,
        );
    }
}

pub async fn fim_complete(request: FimCompleteRequest) -> AiTextResult {
    let chat_request = AiChatRequest {
        app_data_dir: request.app_data_dir.clone(),
        provider: request.provider.clone(),
        model: request.model.clone(),
        system_prompt: String::new(),
        user_prompt: request.prompt.clone(),
        images: vec![],
        purpose: "fim_edit_completion".to_string(),
        api_log_enabled: request.api_log_enabled,
    };

    if request.provider.api_key.trim().is_empty() {
        return AiTextResult::error(
            &chat_request,
            "missing_api_key",
            "供应商 API Key 为空，无法执行编辑补全。",
            0,
            0,
            0,
        );
    }

    if request.provider.protocol != "openaiCompatible" {
        return AiTextResult::error(
            &chat_request,
            "unsupported_fim_protocol",
            "编辑补全仅支持 OpenAI-compatible completions 协议。",
            0,
            0,
            0,
        );
    }

    let result = match ai_openai::fim_complete(&request).await {
        Ok(result) => result,
        Err(error) => AiTextResult::error(&chat_request, "request_failed", &error, 0, 0, 0),
    };

    stats::record_model_call_or_warn(
        "fim_complete",
        &request.app_data_dir,
        &chat_request,
        &result,
    );
    result
}

pub fn estimate_tokens(text: &str) -> i32 {
    let chars = text.chars().count() as i32;
    (chars / 4).max(1)
}

pub fn extract_text(value: &Value, paths: &[&[&str]]) -> Option<String> {
    for path in paths {
        let mut current = value;
        for segment in *path {
            if let Ok(index) = segment.parse::<usize>() {
                current = current.as_array()?.get(index)?;
            } else {
                current = current.get(*segment)?;
            }
        }
        if let Some(text) = current.as_str() {
            return Some(text.to_string());
        }
    }
    None
}

pub fn usage_from_value(value: &Value) -> (i32, i32, i32) {
    let input = read_i32(value, &["usage", "prompt_tokens"])
        .or_else(|| read_i32(value, &["usageMetadata", "promptTokenCount"]))
        .or_else(|| read_i32(value, &["usage", "input_tokens"]))
        .unwrap_or(0);
    let output = read_i32(value, &["usage", "completion_tokens"])
        .or_else(|| read_i32(value, &["usageMetadata", "candidatesTokenCount"]))
        .or_else(|| read_i32(value, &["usage", "output_tokens"]))
        .unwrap_or(0);
    let cached = read_i32(value, &["usage", "prompt_tokens_details", "cached_tokens"]).unwrap_or(0);
    (input, output, cached)
}

fn read_i32(value: &Value, path: &[&str]) -> Option<i32> {
    let mut current = value;
    for segment in path {
        current = current.get(*segment)?;
    }
    current.as_i64().map(|value| value as i32)
}

fn daily_merge_system_prompt(request: &DailyMergeRequest) -> String {
    let custom_prompt = request.merge_prompt.trim();
    if !custom_prompt.is_empty() {
        return with_markdown_attachment_preservation_instruction(custom_prompt.to_string());
    }

    with_markdown_attachment_preservation_instruction(render_daily_merge_prompt(
        DAILY_MERGE_SYSTEM_PROMPT,
        request,
    ))
}

fn render_daily_merge_prompt(template: &str, request: &DailyMergeRequest) -> String {
    template
        .replace("{date}", request.date.trim())
        .replace(
            "{existing_markdown}",
            if request.existing_markdown.trim().is_empty() {
                "（空）"
            } else {
                request.existing_markdown.trim()
            },
        )
        .replace("{raw_input}", request.raw_input.trim())
        .replace(
            "{industry}",
            if request.industry.trim().is_empty() {
                "未设置"
            } else {
                request.industry.trim()
            },
        )
}

fn daily_merge_user_prompt(_request: &DailyMergeRequest) -> String {
    String::new()
}

fn report_user_prompt(period_label: &str, source_markdown: &str) -> String {
    format!(
        "周期：{}\n\n原始 Markdown 内容：\n{}",
        period_label.trim(),
        source_markdown.trim()
    )
}

fn parse_structured_note(
    result: &AiTextResult,
    definitions: &[StructuredNoteSectionDefinition],
) -> StructuredNoteResult {
    let parsed = serde_json::from_str::<Value>(&strip_markdown_fence(&result.content));
    let Ok(value) = parsed else {
        return invalid_structured_note_result(result, "AI 返回内容不是可解析的结构化 JSON。");
    };

    let parsed_sections = match value.get("sections") {
        Some(sections) => parse_section_array(sections, definitions),
        None => parse_legacy_sections(&value, definitions),
    };
    let sections = match parsed_sections {
        Ok(sections) => sections,
        Err(error) => {
            return invalid_structured_note_result(
                result,
                &format!("AI 返回的结构化 JSON 不符合要求：{error}"),
            );
        }
    };

    StructuredNoteResult {
        ok: true,
        sections,
        raw_content: result.content.clone(),
        error_code: String::new(),
        error_message: String::new(),
        input_tokens: result.input_tokens,
        output_tokens: result.output_tokens,
        cached_tokens: result.cached_tokens,
    }
}

fn invalid_structured_note_result(
    result: &AiTextResult,
    error_message: &str,
) -> StructuredNoteResult {
    StructuredNoteResult {
        ok: false,
        sections: vec![],
        raw_content: result.content.clone(),
        error_code: "invalid_structured_output".to_string(),
        error_message: error_message.to_string(),
        input_tokens: result.input_tokens,
        output_tokens: result.output_tokens,
        cached_tokens: result.cached_tokens,
    }
}

fn parse_section_array(
    value: &Value,
    definitions: &[StructuredNoteSectionDefinition],
) -> Result<Vec<StructuredNoteSection>, String> {
    let sections = value
        .as_array()
        .ok_or_else(|| "sections 必须是数组。".to_string())?;
    let mut items_by_id = HashMap::new();

    for section in sections {
        let id = section
            .get("id")
            .and_then(Value::as_str)
            .ok_or_else(|| "每个栏目都必须包含字符串 id。".to_string())?;
        if !definitions.iter().any(|definition| definition.id == id) {
            return Err(format!("包含未知栏目 ID：{id}。"));
        }
        if items_by_id.contains_key(id) {
            return Err(format!("栏目 ID 重复：{id}。"));
        }
        let items = section
            .get("items")
            .ok_or_else(|| format!("栏目 {id} 缺少 items。"))?;
        items_by_id.insert(id.to_string(), read_string_list(items, id)?);
    }

    definitions
        .iter()
        .map(|definition| {
            let items = items_by_id
                .remove(&definition.id)
                .ok_or_else(|| format!("缺少栏目 ID：{}。", definition.id))?;
            Ok(StructuredNoteSection {
                id: definition.id.clone(),
                items,
            })
        })
        .collect()
}

fn parse_legacy_sections(
    value: &Value,
    definitions: &[StructuredNoteSectionDefinition],
) -> Result<Vec<StructuredNoteSection>, String> {
    definitions
        .iter()
        .map(|definition| {
            let key = match definition.id.as_str() {
                "oa" => "completed",
                "ob" => "issues",
                "oc" => "plans",
                _ => return Err(format!("无法映射旧格式栏目 ID：{}。", definition.id)),
            };
            let items = value
                .get(key)
                .ok_or_else(|| format!("旧格式缺少字段：{key}。"))?;
            Ok(StructuredNoteSection {
                id: definition.id.clone(),
                items: read_string_list(items, key)?,
            })
        })
        .collect()
}

fn read_string_list(value: &Value, field: &str) -> Result<Vec<String>, String> {
    let items = value
        .as_array()
        .ok_or_else(|| format!("{field} 必须是数组。"))?;
    let mut result = Vec::with_capacity(items.len());
    for item in items {
        let item = item
            .as_str()
            .ok_or_else(|| format!("{field} 只能包含字符串。"))?
            .trim();
        if !item.is_empty() {
            result.push(item.to_string());
        }
    }
    Ok(result)
}

fn strip_markdown_fence(content: &str) -> String {
    let trimmed = content.trim();
    if !trimmed.starts_with("```") {
        return trimmed.to_string();
    }
    trimmed
        .lines()
        .skip(1)
        .take_while(|line| !line.trim_start().starts_with("```"))
        .collect::<Vec<_>>()
        .join("\n")
}

impl AiTextResult {
    pub fn success(
        request: &AiChatRequest,
        content: impl Into<String>,
        input_tokens: i32,
        output_tokens: i32,
        cached_tokens: i32,
    ) -> Self {
        Self {
            ok: true,
            content: content.into(),
            error_code: String::new(),
            error_message: String::new(),
            input_tokens,
            output_tokens,
            cached_tokens,
            provider_name: request.provider.name.clone(),
            model_id: request.model.model_id.clone(),
        }
    }

    pub fn error(
        request: &AiChatRequest,
        code: impl Into<String>,
        message: impl Into<String>,
        input_tokens: i32,
        output_tokens: i32,
        cached_tokens: i32,
    ) -> Self {
        Self {
            ok: false,
            content: String::new(),
            error_code: code.into(),
            error_message: message.into(),
            input_tokens,
            output_tokens,
            cached_tokens,
            provider_name: request.provider.name.clone(),
            model_id: request.model.model_id.clone(),
        }
    }
}

impl MemoryToolChatResult {
    pub fn success(
        request: &MemoryToolChatRequest,
        content: impl Into<String>,
        reasoning_content: impl Into<String>,
        tool_calls: Vec<AiToolCall>,
        input_tokens: i32,
        output_tokens: i32,
        cached_tokens: i32,
    ) -> Self {
        Self {
            ok: true,
            content: content.into(),
            reasoning_content: reasoning_content.into(),
            tool_calls,
            error_code: String::new(),
            error_message: String::new(),
            input_tokens,
            output_tokens,
            cached_tokens,
            provider_name: request.provider.name.clone(),
            model_id: request.model.model_id.clone(),
        }
    }

    pub fn error(
        request: &AiChatRequest,
        code: impl Into<String>,
        message: impl Into<String>,
        input_tokens: i32,
        output_tokens: i32,
        cached_tokens: i32,
    ) -> Self {
        Self {
            ok: false,
            content: String::new(),
            reasoning_content: String::new(),
            tool_calls: vec![],
            error_code: code.into(),
            error_message: message.into(),
            input_tokens,
            output_tokens,
            cached_tokens,
            provider_name: request.provider.name.clone(),
            model_id: request.model.model_id.clone(),
        }
    }
}

impl MemoryToolChatStreamEvent {
    pub fn error(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            event_type: "error".to_string(),
            content_delta: String::new(),
            reasoning_delta: String::new(),
            content: String::new(),
            reasoning_content: String::new(),
            tool_calls: vec![],
            error_code: code.into(),
            error_message: message.into(),
            input_tokens: 0,
            output_tokens: 0,
            cached_tokens: 0,
        }
    }
}

fn structured_system_prompt(
    industry: &str,
    sections: &[StructuredNoteSectionDefinition],
) -> String {
    let descriptions = sections
        .iter()
        .map(|section| {
            format!(
                "- {}（{}）：{}",
                section.id,
                section.title.trim(),
                section.ai_instruction.trim()
            )
        })
        .collect::<Vec<_>>()
        .join("\n");
    let example = json!({
        "sections": sections
            .iter()
            .map(|section| json!({"id": section.id, "items": [section.title]}))
            .collect::<Vec<_>>()
    });
    let prompt = format!(
        "你是 SpringNote 的日报结构化助手。请把用户的中文工作记录和图片中可见的工作信息整理成 JSON，不要输出 Markdown，不要解释。\n\n栏目定义：\n{}\n\nJSON 格式必须是：\n{}\n必须原样返回以上栏目 ID；如果某一栏目没有内容，items 返回空数组。\n可以根据图片中明确可见的界面、文字、报错、流程或任务状态总结事实；不得编造图片外的信息。",
        descriptions, example
    );
    with_industry_context(&prompt, industry)
}

const DAILY_MERGE_SYSTEM_PROMPT: &str = r#"你是 SpringNote 的日报整理助手。
你的任务是根据已有日报和新增随手记录，整理生成一篇自然、真实、便于继续编辑的日报。

已知信息：
- 日期：{date}
- 已有日报：{existing_markdown}
- 新增随手记录：{raw_input}
- 用户所在行业：{industry}

整理要求：
1. 综合利用所有已提供的信息进行整理，空变量自动忽略。
2. 如果已有日报存在，优先保留其中仍然有效的内容，并将新增记录自然融合进去；如果已有日报为空，则根据新增记录整理生成日报。
3. 严格保留事实，不得编造任何不存在的任务、时间、人员、原因、进展、结果、计划、评价或情绪。
4. 在不改变事实的前提下，可以自由整理语言，包括补充完整句子、调整语序、合并重复内容、优化表达，使内容更加自然流畅。
5. 当新增记录只是关键词、短语或简短描述时，应主动整理成符合正常书面表达的完整内容，而不是直接照抄原文。允许适度扩展描述，使表达更加自然，但扩展内容只能服务于表达已有事实，不得引入新的事实信息。
6. 将零散记录整理成连贯的工作记录，使全文具有连续阅读体验，读起来像用户亲自整理后的日报，而不是 AI 自动汇总的结果。
7. 内容较少时保持简洁，避免为了丰富内容而重复表达；内容较多时可自然分段或按主题组织，但不要为了分组而分组。
8. 表达应符合真实开发者或职场人士日常记录工作的习惯，语言自然、克制、顺畅，避免机械、模板化或过于正式的总结语气。
9. 可以结合所在行业调整专业术语和表达习惯，但不得补充任何事实。
10. 如果已有日报与新增记录存在重复，应保留表达更完整、更自然的一份，避免重复描述。
11. 保留已有日报的整体结构和可继续编辑性，不随意改变已有内容的组织方式。
12. 不输出变量名称，不解释整理过程，不添加任何说明，仅输出最终日报内容。"#;

fn with_industry_context(base_prompt: &str, industry: &str) -> String {
    let industry = industry.trim();
    if industry.is_empty() {
        return base_prompt.to_string();
    }

    format!(
        "{base_prompt}\n用户偏好：用户所在行业是「{industry}」。请结合该行业的常见工作语境理解术语、任务和表达，但不要脱离输入内容编造事实。"
    )
}

fn with_markdown_attachment_preservation_instruction(prompt: String) -> String {
    let trimmed = prompt.trim_end();
    if trimmed.contains(MARKDOWN_ATTACHMENT_PRESERVATION_INSTRUCTION) {
        return trimmed.to_string();
    }

    format!("{trimmed}\n{MARKDOWN_ATTACHMENT_PRESERVATION_INSTRUCTION}")
}

const MARKDOWN_ATTACHMENT_PRESERVATION_INSTRUCTION: &str = "输出内容时，必须将给定的所有 Markdown 图片（`![]()`）和其他文件链接原样包含在内，不得省略、修改或重新生成；图片路径、文件名和语法必须与原始提供完全一致，同时，这些内容应自然融入上下文之中。";

const WEEKLY_REPORT_SYSTEM_PROMPT: &str = r#"你是 SpringNote 的周报整理助手。请基于一周日报 Markdown 生成一篇自然、有重点、可直接编辑的周报。
写作原则：
1. 保留来源中的事实，不编造没有依据的成果、风险或计划。
2. 不需要固定套用“主要工作 / 关键进展 / 问题 / 下周计划”等模板，可以根据材料自由组织结构。
3. Markdown 要层次清楚、阅读舒服；可以使用标题、段落、列表、重点小结，但避免机械堆栏目。
4. 优先呈现这一周真正发生了什么、推进到了哪里、遇到什么卡点、接下来怎么走。
5. 语气自然，像一个认真复盘工作的人的周报，不要像 AI 模板。
6. 只输出最终 Markdown，不要解释。"#;

const MONTHLY_REPORT_SYSTEM_PROMPT: &str = r#"你是 SpringNote 的月报整理助手。请基于月度周报 Markdown 生成一篇自然、有复盘感、可继续编辑的月报。
写作原则：
1. 保留来源中的事实，不编造成果、数据、评价或计划。
2. 不需要固定套用“核心成果 / 项目进展 / 问题复盘 / 个人成长 / 下月计划”等模板，可以根据材料自由组织结构。
3. Markdown 要美观、有呼吸感；可以使用标题、短段落、列表、总结和展望，但不要写成僵硬表格。
4. 重点体现这个月的主线、阶段性变化、值得保留的经验、还没解决的问题和自然的下一步。
5. 语气克制、真诚、有人的表达，不要过度包装，也不要像 AI 汇报模板。
6. 只输出最终 Markdown，不要解释。"#;

const MEMORY_TOOL_SYSTEM_PROMPT: &str = r#"你是 SpringNote 的回忆书问答助手。你必须基于用户的历史日报、周报、月报回答问题。
你可以自主调用工具检索或读取记录；需要信息时先调用工具，不要让应用预先替你检索。
连续追问时结合完整消息历史理解省略指代，例如“什么时候”“这个配置”“刚才说的”等。
回答必须只依据工具返回和对话上下文；材料不足时明确说明缺少依据，不要编造事实。
最终回答使用自然中文和清晰 Markdown，不要输出工具调用 JSON。"#;

#[cfg(test)]
mod tests {
    use super::*;

    fn request() -> AiChatRequest {
        AiChatRequest {
            app_data_dir: ".".to_string(),
            provider: AiProvider {
                id: "openai".to_string(),
                name: "OpenAI".to_string(),
                protocol: "openaiCompatible".to_string(),
                api_key: "key".to_string(),
                base_url: "https://api.example.com/v1".to_string(),
                api_path: "/chat/completions".to_string(),
            },
            model: AiModel {
                model_id: "gpt-test".to_string(),
                display_name: "GPT Test".to_string(),
            },
            system_prompt: String::new(),
            user_prompt: String::new(),
            images: vec![],
            purpose: "test".to_string(),
            api_log_enabled: false,
        }
    }

    fn structured_definitions() -> Vec<StructuredNoteSectionDefinition> {
        vec![
            StructuredNoteSectionDefinition {
                id: "oa".to_string(),
                title: "A".to_string(),
                ai_instruction: "A".to_string(),
            },
            StructuredNoteSectionDefinition {
                id: "ob".to_string(),
                title: "B".to_string(),
                ai_instruction: "B".to_string(),
            },
            StructuredNoteSectionDefinition {
                id: "oc".to_string(),
                title: "C".to_string(),
                ai_instruction: "C".to_string(),
            },
        ]
    }

    fn parse_structured_content(content: &str) -> StructuredNoteResult {
        let result = AiTextResult::success(&request(), content, 1, 2, 0);
        parse_structured_note(&result, &structured_definitions())
    }

    #[test]
    fn parses_structured_note_json() {
        let parsed = parse_structured_content(
            r#"{"sections":[{"id":"oa","items":["A"]},{"id":"ob","items":["B"]},{"id":"oc","items":["C"]}]}"#,
        );
        assert!(parsed.ok);
        assert_eq!(parsed.sections[0].items, vec!["A"]);
        assert_eq!(parsed.sections[1].items, vec!["B"]);
        assert_eq!(parsed.sections[2].items, vec!["C"]);
    }

    #[test]
    fn parses_legacy_structured_note_json() {
        let parsed =
            parse_structured_content(r#"{"completed":["A"],"issues":["B"],"plans":["C"]}"#);
        assert!(parsed.ok);
        assert_eq!(parsed.sections[0].items, vec!["A"]);
        assert_eq!(parsed.sections[1].items, vec!["B"]);
        assert_eq!(parsed.sections[2].items, vec!["C"]);
    }

    #[test]
    fn rejects_structured_note_with_missing_section() {
        let parsed = parse_structured_content(
            r#"{"sections":[{"id":"oa","items":["A"]},{"id":"ob","items":["B"]}]}"#,
        );

        assert!(!parsed.ok);
        assert_eq!(parsed.error_code, "invalid_structured_output");
        assert!(parsed.error_message.contains("缺少栏目 ID：oc"));
    }

    #[test]
    fn rejects_structured_note_with_unknown_or_duplicate_section() {
        let unknown = parse_structured_content(
            r#"{"sections":[{"id":"oa","items":["A"]},{"id":"ob","items":["B"]},{"id":"wrong","items":["C"]}]}"#,
        );
        let duplicate = parse_structured_content(
            r#"{"sections":[{"id":"oa","items":["A"]},{"id":"ob","items":["B"]},{"id":"ob","items":["C"]}]}"#,
        );

        assert!(!unknown.ok);
        assert!(unknown.error_message.contains("未知栏目 ID：wrong"));
        assert!(!duplicate.ok);
        assert!(duplicate.error_message.contains("栏目 ID 重复：ob"));
    }

    #[test]
    fn rejects_structured_note_with_non_string_items() {
        let parsed = parse_structured_content(
            r#"{"sections":[{"id":"oa","items":["A"]},{"id":"ob","items":[1]},{"id":"oc","items":[]}]}"#,
        );

        assert!(!parsed.ok);
        assert!(parsed.error_message.contains("ob 只能包含字符串"));
    }

    #[test]
    fn rejects_incomplete_legacy_structured_note() {
        let parsed = parse_structured_content(r#"{"completed":["A"],"issues":[]}"#);

        assert!(!parsed.ok);
        assert!(parsed.error_message.contains("旧格式缺少字段：plans"));
    }

    #[test]
    fn structured_prompt_uses_configured_sections() {
        let sections = vec![StructuredNoteSectionDefinition {
            id: "oa".to_string(),
            title: "今日进展".to_string(),
            ai_instruction: "提取今天取得的工作进展。".to_string(),
        }];

        let prompt = structured_system_prompt("互联网", &sections);

        assert!(prompt.contains("oa（今日进展）：提取今天取得的工作进展。"));
        assert!(prompt.contains(r#""id":"oa""#));
        assert!(prompt.contains("用户所在行业是「互联网」"));
    }

    #[test]
    fn strips_markdown_json_fence() {
        let stripped = strip_markdown_fence("```json\n{\"completed\":[]}\n```");
        assert_eq!(stripped, "{\"completed\":[]}");
    }

    #[test]
    fn renders_default_daily_merge_system_prompt_in_rust() {
        let date = "2026-06-18";
        let request = DailyMergeRequest {
            app_data_dir: ".".to_string(),
            provider: request().provider,
            model: request().model,
            existing_markdown: "# old".to_string(),
            raw_input: "done".to_string(),
            date: date.to_string(),
            industry: String::new(),
            merge_prompt: String::new(),
            api_log_enabled: false,
        };

        let prompt = daily_merge_system_prompt(&request);
        assert!(prompt.contains(&format!("日期：{date}")));
        assert!(prompt.contains("已有日报：# old"));
        assert!(prompt.contains("新增随手记录：done"));
        assert!(prompt.contains("用户所在行业：未设置"));
        assert!(prompt.ends_with(MARKDOWN_ATTACHMENT_PRESERVATION_INSTRUCTION));
        assert!(!prompt.contains("{date}"));
        assert!(!prompt.contains("{existing_markdown}"));
        assert!(!prompt.contains("{raw_input}"));
        assert!(!prompt.contains("{industry}"));
        assert_eq!(daily_merge_user_prompt(&request), "");
    }

    #[test]
    fn custom_daily_merge_prompt_appends_markdown_attachment_instruction() {
        let request = DailyMergeRequest {
            app_data_dir: ".".to_string(),
            provider: request().provider,
            model: request().model,
            existing_markdown: "# old".to_string(),
            raw_input: "done".to_string(),
            date: "2026-06-18".to_string(),
            industry: String::new(),
            merge_prompt: "custom system prompt".to_string(),
            api_log_enabled: false,
        };

        let prompt = daily_merge_system_prompt(&request);
        assert!(prompt.starts_with("custom system prompt\n"));
        assert!(prompt.ends_with(MARKDOWN_ATTACHMENT_PRESERVATION_INSTRUCTION));
        assert_eq!(daily_merge_user_prompt(&request), "");
    }

    #[test]
    fn report_system_prompts_append_markdown_attachment_instruction() {
        let weekly_prompt = with_markdown_attachment_preservation_instruction(
            with_industry_context(WEEKLY_REPORT_SYSTEM_PROMPT, "互联网"),
        );
        let monthly_prompt = with_markdown_attachment_preservation_instruction(
            with_industry_context(MONTHLY_REPORT_SYSTEM_PROMPT, "互联网"),
        );

        assert!(weekly_prompt.contains("周报整理助手"));
        assert!(monthly_prompt.contains("月报整理助手"));
        assert!(weekly_prompt.ends_with(MARKDOWN_ATTACHMENT_PRESERVATION_INSTRUCTION));
        assert!(monthly_prompt.ends_with(MARKDOWN_ATTACHMENT_PRESERVATION_INSTRUCTION));
    }

    #[test]
    fn http_client_builds_without_panic() {
        // 非流式客户端必须成功构建，验证超时常量有效
        let _client = http_client().unwrap();
    }

    #[test]
    fn http_stream_client_builds_without_panic() {
        // 流式客户端必须成功构建，验证超时常量有效
        let _client = http_stream_client().unwrap();
    }

    #[tokio::test]
    async fn non_streaming_client_hits_request_timeout() {
        // 构造一个接受连接但永不响应的本地 mock server。
        // 用短 Duration 构建 client，验证 request timeout 确实触发超时错误。
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        // 后台接受连接后持有 stream 超过 client 短超时时间，避免连接立即断开导致假阳性。
        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            tokio::time::sleep(Duration::from_millis(500)).await;
            drop(stream);
        });

        let client = build_http_client(
            Duration::from_secs(5),     // connect timeout
            Duration::from_millis(200), // short request timeout
        )
        .unwrap();

        let error = client
            .get(format!("http://{addr}/"))
            .send()
            .await
            .unwrap_err();

        assert!(
            error.is_timeout(),
            "request should have timed out, got: {error}"
        );
    }

    #[tokio::test]
    async fn streaming_client_hits_read_timeout() {
        // 构造本地 mock server：接受连接，写 HTTP 头让 stream 开始，
        // 然后停止发送，等待 read timeout 触发。
        use tokio::io::AsyncWriteExt;

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            // 写 HTTP 头，让 reqwest 判定连接成功并进入读取 body 阶段
            stream
                .write_all(
                    b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nTransfer-Encoding: chunked\r\n\r\n",
                )
                .await
                .ok();
            // 持有 stream 超过 client 短超时时间，不发送任何 chunk body，等待 client read timeout
            tokio::time::sleep(Duration::from_millis(500)).await;
            drop(stream);
        });

        let client = build_http_stream_client(
            Duration::from_secs(5),     // connect timeout
            Duration::from_millis(200), // short read timeout
        )
        .unwrap();

        // send() 本身成功（已收到 HTTP 头），但后续读取 body 会触发 read timeout。
        // 因此这里调用 text() 等待完整响应体。
        let resp = client.get(format!("http://{addr}/")).send().await.unwrap();
        let error = resp.text().await.unwrap_err();

        assert!(
            error.is_timeout(),
            "streaming request body read should have timed out, got: {error}"
        );
    }
}
