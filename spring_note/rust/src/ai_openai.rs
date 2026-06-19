use crate::ai::{
    AiChatMessage, AiChatRequest, AiModel, AiProvider, AiTextResult, AiToolCall,
    FimCompleteRequest, MemoryToolChatRequest, MemoryToolChatResult, MemoryToolChatStreamEvent,
    extract_text, usage_from_value,
};
use crate::ai_log::{ApiNetworkLog, write_api_network_log};
use crate::frb_generated::StreamSink;
use crate::stats;
use reqwest::Client;
use serde_json::{Value, json};
use std::time::Instant;

pub async fn chat(request: &AiChatRequest) -> Result<AiTextResult, String> {
    let url = join_url(&request.provider.base_url, &request.provider.api_path);
    let body = build_chat_body(request);
    let request_body = body_to_string(&body);
    let started_at = Instant::now();
    let response = Client::new()
        .post(&url)
        .bearer_auth(&request.provider.api_key)
        .json(&body)
        .send()
        .await
        .map_err(|error| {
            let message = error.to_string();
            log_chat(
                request,
                "POST",
                &url,
                &request_body,
                None,
                "",
                started_at,
                &message,
            );
            message
        })?;
    let status = response.status();
    let response_body = response.text().await.map_err(|error| {
        let message = error.to_string();
        log_chat(
            request,
            "POST",
            &url,
            &request_body,
            Some(status.as_u16()),
            "",
            started_at,
            &message,
        );
        message
    })?;
    log_chat(
        request,
        "POST",
        &url,
        &request_body,
        Some(status.as_u16()),
        &response_body,
        started_at,
        "",
    );
    if !status.is_success() {
        return Err(format!("HTTP {status}: {response_body}"));
    }
    let value = serde_json::from_str::<Value>(&response_body).map_err(|error| error.to_string())?;

    let content =
        extract_text(&value, &[&["choices", "0", "message", "content"]]).ok_or_else(|| {
            "OpenAI-compatible response missing choices[0].message.content".to_string()
        })?;
    let (input, output, cached) = usage_from_value(&value);
    Ok(AiTextResult::success(
        request, content, input, output, cached,
    ))
}

pub async fn memory_tool_chat(
    request: &MemoryToolChatRequest,
    system_prompt: &str,
) -> Result<MemoryToolChatResult, String> {
    let log_request = memory_as_chat_request(request, system_prompt);
    let url = join_url(&request.provider.base_url, &request.provider.api_path);
    let body = build_memory_tool_body(request, system_prompt);
    let request_body = body_to_string(&body);
    let started_at = Instant::now();
    let response = Client::new()
        .post(&url)
        .bearer_auth(&request.provider.api_key)
        .json(&body)
        .send()
        .await
        .map_err(|error| {
            let message = error.to_string();
            log_chat(
                &log_request,
                "POST",
                &url,
                &request_body,
                None,
                "",
                started_at,
                &message,
            );
            message
        })?;
    let status = response.status();
    let response_body = response.text().await.map_err(|error| {
        let message = error.to_string();
        log_chat(
            &log_request,
            "POST",
            &url,
            &request_body,
            Some(status.as_u16()),
            "",
            started_at,
            &message,
        );
        message
    })?;
    log_chat(
        &log_request,
        "POST",
        &url,
        &request_body,
        Some(status.as_u16()),
        &response_body,
        started_at,
        "",
    );
    if !status.is_success() {
        return Err(format!("HTTP {status}: {response_body}"));
    }
    let value = serde_json::from_str::<Value>(&response_body).map_err(|error| error.to_string())?;
    let message = value
        .get("choices")
        .and_then(Value::as_array)
        .and_then(|choices| choices.first())
        .and_then(|choice| choice.get("message"))
        .ok_or_else(|| "OpenAI-compatible response missing choices[0].message".to_string())?;
    let content = read_string_field(message, "content");
    let reasoning_content = read_string_field(message, "reasoning_content");
    let tool_calls = parse_tool_calls(message);
    let (input, output, cached) = usage_from_value(&value);
    Ok(MemoryToolChatResult::success(
        request,
        content,
        reasoning_content,
        tool_calls,
        input,
        output,
        cached,
    ))
}

pub async fn memory_tool_chat_stream(
    request: MemoryToolChatRequest,
    system_prompt: &str,
    sink: StreamSink<MemoryToolChatStreamEvent>,
) -> Result<(), String> {
    let log_request = memory_as_chat_request(&request, system_prompt);
    if request.provider.api_key.trim().is_empty() {
        let _ = sink.add(MemoryToolChatStreamEvent::error(
            "missing_api_key",
            "供应商 API Key 为空。",
        ));
        return Ok(());
    }

    let url = join_url(&request.provider.base_url, &request.provider.api_path);
    let body = build_memory_tool_stream_body(&request, system_prompt);
    let request_body = body_to_string(&body);
    let started_at = Instant::now();
    let response = Client::new()
        .post(&url)
        .bearer_auth(&request.provider.api_key)
        .json(&body)
        .send()
        .await
        .map_err(|error| {
            let message = error.to_string();
            log_chat(
                &log_request,
                "POST",
                &url,
                &request_body,
                None,
                "",
                started_at,
                &message,
            );
            message
        })?;
    let status = response.status();
    if !status.is_success() {
        let response_body = response.text().await.unwrap_or_default();
        log_chat(
            &log_request,
            "POST",
            &url,
            &request_body,
            Some(status.as_u16()),
            &response_body,
            started_at,
            "",
        );
        let message = format!("HTTP {status}: {response_body}");
        let _ = sink.add(MemoryToolChatStreamEvent::error("request_failed", &message));
        return Ok(());
    }

    let mut response = response;
    let mut parser = SseParser::default();
    let mut raw_response = String::new();
    let mut accumulator = StreamAccumulator::default();
    while let Some(chunk) = response.chunk().await.map_err(|error| error.to_string())? {
        let text = String::from_utf8_lossy(&chunk);
        raw_response.push_str(&text);
        for payload in parser.push(&text) {
            if payload.trim() == "[DONE]" {
                continue;
            }
            let Ok(value) = serde_json::from_str::<Value>(&payload) else {
                continue;
            };
            if let Some(usage) = value.get("usage") {
                let (input, output, cached) = usage_from_value(&json!({ "usage": usage }));
                accumulator.input_tokens = input;
                accumulator.output_tokens = output;
                accumulator.cached_tokens = cached;
            }
            let Some(delta) = value
                .get("choices")
                .and_then(Value::as_array)
                .and_then(|choices| choices.first())
                .and_then(|choice| choice.get("delta"))
            else {
                continue;
            };
            let content_delta = read_string_field(delta, "content");
            let reasoning_delta = read_string_field(delta, "reasoning_content");
            accumulator.content.push_str(&content_delta);
            accumulator.reasoning_content.push_str(&reasoning_delta);
            accumulator.merge_tool_delta(delta);
            if !content_delta.is_empty() || !reasoning_delta.is_empty() {
                let _ = sink.add(MemoryToolChatStreamEvent {
                    event_type: "delta".to_string(),
                    content_delta,
                    reasoning_delta,
                    content: accumulator.content.clone(),
                    reasoning_content: accumulator.reasoning_content.clone(),
                    tool_calls: vec![],
                    error_code: String::new(),
                    error_message: String::new(),
                    input_tokens: 0,
                    output_tokens: 0,
                    cached_tokens: 0,
                });
            }
        }
    }

    log_chat(
        &log_request,
        "POST",
        &url,
        &request_body,
        Some(status.as_u16()),
        &raw_response,
        started_at,
        "",
    );
    let tool_calls = accumulator.tool_calls();
    let content = accumulator.content;
    let reasoning_content = accumulator.reasoning_content;
    let input_tokens = accumulator.input_tokens;
    let output_tokens = accumulator.output_tokens;
    let cached_tokens = accumulator.cached_tokens;
    let result = AiTextResult::success(
        &log_request,
        content.clone(),
        input_tokens,
        output_tokens,
        cached_tokens,
    );
    let _ = stats::record_model_call(&request.app_data_dir, &log_request, &result);
    let _ = sink.add(MemoryToolChatStreamEvent {
        event_type: "done".to_string(),
        content_delta: String::new(),
        reasoning_delta: String::new(),
        content,
        reasoning_content,
        tool_calls,
        error_code: String::new(),
        error_message: String::new(),
        input_tokens,
        output_tokens,
        cached_tokens,
    });
    Ok(())
}

pub async fn fetch_models(
    app_data_dir: &str,
    provider: &AiProvider,
    api_log_enabled: bool,
) -> Result<Vec<AiModel>, String> {
    let url = join_url(&provider.base_url, "/models");
    let started_at = Instant::now();
    let response = Client::new()
        .get(&url)
        .bearer_auth(&provider.api_key)
        .send()
        .await
        .map_err(|error| {
            let message = error.to_string();
            log_fetch_models(
                app_data_dir,
                provider,
                api_log_enabled,
                "GET",
                &url,
                None,
                "",
                started_at,
                &message,
            );
            message
        })?;
    let status = response.status();
    let response_body = response.text().await.map_err(|error| {
        let message = error.to_string();
        log_fetch_models(
            app_data_dir,
            provider,
            api_log_enabled,
            "GET",
            &url,
            Some(status.as_u16()),
            "",
            started_at,
            &message,
        );
        message
    })?;
    log_fetch_models(
        app_data_dir,
        provider,
        api_log_enabled,
        "GET",
        &url,
        Some(status.as_u16()),
        &response_body,
        started_at,
        "",
    );
    if !status.is_success() {
        return Err(format!("HTTP {status}: {response_body}"));
    }
    let value = serde_json::from_str::<Value>(&response_body).map_err(|error| error.to_string())?;

    let models = value
        .get("data")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.get("id").and_then(Value::as_str))
                .map(|id| AiModel {
                    model_id: id.to_string(),
                    display_name: id.to_string(),
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    Ok(models)
}

pub async fn fim_complete(request: &FimCompleteRequest) -> Result<AiTextResult, String> {
    let chat_request = fim_as_chat_request(request);
    let url = completions_url(&request.provider);
    let body = build_fim_body(request);
    let request_body = body_to_string(&body);
    let started_at = Instant::now();
    let response = Client::new()
        .post(&url)
        .bearer_auth(&request.provider.api_key)
        .json(&body)
        .send()
        .await
        .map_err(|error| {
            let message = error.to_string();
            log_chat(
                &chat_request,
                "POST",
                &url,
                &request_body,
                None,
                "",
                started_at,
                &message,
            );
            message
        })?;
    let status = response.status();
    let response_body = response.text().await.map_err(|error| {
        let message = error.to_string();
        log_chat(
            &chat_request,
            "POST",
            &url,
            &request_body,
            Some(status.as_u16()),
            "",
            started_at,
            &message,
        );
        message
    })?;
    log_chat(
        &chat_request,
        "POST",
        &url,
        &request_body,
        Some(status.as_u16()),
        &response_body,
        started_at,
        "",
    );
    if !status.is_success() {
        return Err(format!("HTTP {status}: {response_body}"));
    }
    let value = serde_json::from_str::<Value>(&response_body).map_err(|error| error.to_string())?;
    let content = extract_text(&value, &[&["choices", "0", "text"]])
        .ok_or_else(|| "OpenAI-compatible FIM response missing choices[0].text".to_string())?;
    let (input, output, cached) = usage_from_value(&value);
    Ok(AiTextResult::success(
        &chat_request,
        content,
        input,
        output,
        cached,
    ))
}

pub fn build_chat_body(request: &AiChatRequest) -> Value {
    let mut body = json!({
        "model": request.model.model_id,
        "messages": [
            {"role": "system", "content": request.system_prompt},
            {"role": "user", "content": request.user_prompt}
        ],
        "temperature": 0.2
    });
    if disables_thinking(&request.purpose) {
        body["thinking"] = json!({"type": "disabled"});
    }
    body
}

pub fn build_memory_tool_body(request: &MemoryToolChatRequest, system_prompt: &str) -> Value {
    let mut body = json!({
        "model": request.model.model_id,
        "messages": memory_messages_json(system_prompt, &request.messages),
        "tools": memory_tools_json(),
        "tool_choice": "auto"
    });
    apply_thinking_options(
        &mut body,
        request.thinking_enabled,
        &request.reasoning_effort,
    );
    body
}

pub fn build_memory_tool_stream_body(
    request: &MemoryToolChatRequest,
    system_prompt: &str,
) -> Value {
    let mut body = build_memory_tool_body(request, system_prompt);
    body["stream"] = Value::Bool(true);
    body["stream_options"] = json!({"include_usage": true});
    body
}

pub fn build_fim_body(request: &FimCompleteRequest) -> Value {
    json!({
        "model": request.model.model_id,
        "prompt": request.prompt,
        "suffix": request.suffix,
        "max_tokens": 128,
        "temperature": 0.2
    })
}

fn memory_messages_json(system_prompt: &str, messages: &[AiChatMessage]) -> Vec<Value> {
    let mut result = vec![json!({"role": "system", "content": system_prompt})];
    result.extend(messages.iter().map(memory_message_json));
    result
}

fn memory_message_json(message: &AiChatMessage) -> Value {
    if message.role == "assistant" && !message.tool_calls.is_empty() {
        let mut result = json!({
            "role": "assistant",
            "content": if message.content.is_empty() { Value::Null } else { Value::String(message.content.clone()) },
            "tool_calls": message.tool_calls.iter().map(|tool_call| {
                json!({
                    "id": tool_call.id,
                    "type": "function",
                    "function": {
                        "name": tool_call.name,
                        "arguments": tool_call.arguments
                    }
                })
            }).collect::<Vec<_>>()
        });
        if !message.reasoning_content.trim().is_empty() {
            result["reasoning_content"] = Value::String(message.reasoning_content.clone());
        }
        return result;
    }

    if message.role == "tool" {
        return json!({
            "role": "tool",
            "tool_call_id": message.tool_call_id,
            "content": message.content
        });
    }

    json!({
        "role": message.role,
        "content": message.content
    })
}

fn apply_thinking_options(body: &mut Value, enabled: bool, effort: &str) {
    if enabled {
        body["thinking"] = json!({"type": "enabled"});
        body["reasoning_effort"] = Value::String(normalize_reasoning_effort(effort).to_string());
    } else {
        body["thinking"] = json!({"type": "disabled"});
        body["temperature"] = Value::from(0.2);
    }
}

fn normalize_reasoning_effort(effort: &str) -> &str {
    match effort {
        "max" | "xhigh" => "max",
        _ => "high",
    }
}

fn disables_thinking(purpose: &str) -> bool {
    matches!(purpose, "home_structured_note" | "daily_note_merge")
}

fn read_string_field(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string()
}

pub fn memory_tools_json() -> Value {
    json!([
        {
            "type": "function",
            "function": {
                "name": "get_current_date",
                "strict": true,
                "description": "Get the current local date. Use this before resolving relative dates such as today, yesterday, this week, this month.",
                "parameters": {
                    "type": "object",
                    "properties": {},
                    "required": [],
                    "additionalProperties": false
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "keyword_search",
                "strict": true,
                "description": "Search SpringNote daily, weekly, and monthly Markdown records by one or more keywords. Returns zero or more matching records.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "keywords": {
                            "type": "array",
                            "description": "One or more concise keywords or phrases, sorted by importance.",
                            "items": {
                                "type": "string",
                                "description": "A concise keyword or phrase."
                            }
                        }
                    },
                    "required": ["keywords"],
                    "additionalProperties": false
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "read_daily_note",
                "strict": true,
                "description": "Read the full daily Markdown note for a specific date.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "date": {
                            "type": "string",
                            "description": "The date in YYYY-MM-DD format.",
                            "pattern": "^20\\d{2}-(0[1-9]|1[0-2])-([0-2][0-9]|3[0-1])$"
                        }
                    },
                    "required": ["date"],
                    "additionalProperties": false
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "read_week_daily_notes",
                "strict": true,
                "description": "Read all available daily notes in a date range, typically one week.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "startDate": {
                            "type": "string",
                            "description": "Range start date in YYYY-MM-DD format.",
                            "pattern": "^20\\d{2}-(0[1-9]|1[0-2])-([0-2][0-9]|3[0-1])$"
                        },
                        "endDate": {
                            "type": "string",
                            "description": "Range end date in YYYY-MM-DD format.",
                            "pattern": "^20\\d{2}-(0[1-9]|1[0-2])-([0-2][0-9]|3[0-1])$"
                        }
                    },
                    "required": ["startDate", "endDate"],
                    "additionalProperties": false
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "read_month_report",
                "strict": true,
                "description": "Read only the monthly report Markdown for a specific month. Do not return daily notes.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "month": {
                            "type": "string",
                            "description": "The month in YYYY-MM format.",
                            "pattern": "^20\\d{2}-(0[1-9]|1[0-2])$"
                        }
                    },
                    "required": ["month"],
                    "additionalProperties": false
                }
            }
        }
    ])
}

fn parse_tool_calls(message: &Value) -> Vec<AiToolCall> {
    message
        .get("tool_calls")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|item| {
                    let function = item.get("function")?;
                    Some(AiToolCall {
                        id: item
                            .get("id")
                            .and_then(Value::as_str)
                            .unwrap_or("")
                            .to_string(),
                        name: function
                            .get("name")
                            .and_then(Value::as_str)
                            .unwrap_or("")
                            .to_string(),
                        arguments: function
                            .get("arguments")
                            .and_then(Value::as_str)
                            .unwrap_or("{}")
                            .to_string(),
                    })
                })
                .filter(|tool_call| !tool_call.id.is_empty() && !tool_call.name.is_empty())
                .collect()
        })
        .unwrap_or_default()
}

#[derive(Default)]
struct SseParser {
    buffer: String,
}

impl SseParser {
    fn push(&mut self, chunk: &str) -> Vec<String> {
        self.buffer.push_str(chunk);
        let mut payloads = Vec::new();
        while let Some(index) = self.buffer.find("\n\n") {
            let frame = self.buffer[..index].to_string();
            self.buffer = self.buffer[index + 2..].to_string();
            let payload = frame
                .lines()
                .filter_map(|line| line.strip_prefix("data:"))
                .map(str::trim)
                .collect::<Vec<_>>()
                .join("\n");
            if !payload.is_empty() {
                payloads.push(payload);
            }
        }
        payloads
    }
}

#[derive(Default)]
struct StreamAccumulator {
    content: String,
    reasoning_content: String,
    tool_calls: Vec<ToolCallAccumulator>,
    input_tokens: i32,
    output_tokens: i32,
    cached_tokens: i32,
}

#[derive(Default)]
struct ToolCallAccumulator {
    id: String,
    name: String,
    arguments: String,
}

impl StreamAccumulator {
    fn merge_tool_delta(&mut self, delta: &Value) {
        let Some(tool_calls) = delta.get("tool_calls").and_then(Value::as_array) else {
            return;
        };
        for item in tool_calls {
            let index = item.get("index").and_then(Value::as_u64).unwrap_or(0) as usize;
            while self.tool_calls.len() <= index {
                self.tool_calls.push(ToolCallAccumulator::default());
            }
            let target = &mut self.tool_calls[index];
            if let Some(id) = item.get("id").and_then(Value::as_str) {
                target.id = id.to_string();
            }
            if let Some(function) = item.get("function") {
                if let Some(name) = function.get("name").and_then(Value::as_str) {
                    target.name.push_str(name);
                }
                if let Some(arguments) = function.get("arguments").and_then(Value::as_str) {
                    target.arguments.push_str(arguments);
                }
            }
        }
    }

    fn tool_calls(&self) -> Vec<AiToolCall> {
        self.tool_calls
            .iter()
            .filter(|tool_call| !tool_call.id.is_empty() && !tool_call.name.is_empty())
            .map(|tool_call| AiToolCall {
                id: tool_call.id.clone(),
                name: tool_call.name.clone(),
                arguments: if tool_call.arguments.trim().is_empty() {
                    "{}".to_string()
                } else {
                    tool_call.arguments.clone()
                },
            })
            .collect()
    }
}

fn join_url(base_url: &str, path: &str) -> String {
    if path.trim().is_empty() {
        return base_url.trim_end_matches('/').to_string();
    }
    format!(
        "{}/{}",
        base_url.trim_end_matches('/'),
        path.trim_start_matches('/')
    )
}

fn completions_url(provider: &AiProvider) -> String {
    join_url(&provider.base_url, "/completions")
}

fn body_to_string(body: &Value) -> String {
    serde_json::to_string_pretty(body).unwrap_or_else(|_| body.to_string())
}

fn fim_as_chat_request(request: &FimCompleteRequest) -> AiChatRequest {
    AiChatRequest {
        app_data_dir: request.app_data_dir.clone(),
        provider: request.provider.clone(),
        model: request.model.clone(),
        system_prompt: String::new(),
        user_prompt: request.prompt.clone(),
        purpose: "fim_edit_completion".to_string(),
        api_log_enabled: request.api_log_enabled,
    }
}

fn memory_as_chat_request(request: &MemoryToolChatRequest, system_prompt: &str) -> AiChatRequest {
    AiChatRequest {
        app_data_dir: request.app_data_dir.clone(),
        provider: request.provider.clone(),
        model: request.model.clone(),
        system_prompt: system_prompt.to_string(),
        user_prompt: request
            .messages
            .iter()
            .map(|message| message.content.as_str())
            .collect::<Vec<_>>()
            .join("\n"),
        purpose: "memory_tool_chat".to_string(),
        api_log_enabled: request.api_log_enabled,
    }
}

fn log_chat(
    request: &AiChatRequest,
    method: &str,
    url: &str,
    request_body: &str,
    response_status: Option<u16>,
    response_body: &str,
    started_at: Instant,
    error: &str,
) {
    write_api_network_log(ApiNetworkLog {
        app_data_dir: &request.app_data_dir,
        enabled: request.api_log_enabled,
        provider_id: &request.provider.id,
        provider_name: &request.provider.name,
        protocol: &request.provider.protocol,
        model_id: &request.model.model_id,
        purpose: &request.purpose,
        method,
        url,
        request_body,
        response_status,
        response_body,
        duration_ms: started_at.elapsed().as_millis(),
        error,
    });
}

fn log_fetch_models(
    app_data_dir: &str,
    provider: &AiProvider,
    enabled: bool,
    method: &str,
    url: &str,
    response_status: Option<u16>,
    response_body: &str,
    started_at: Instant,
    error: &str,
) {
    write_api_network_log(ApiNetworkLog {
        app_data_dir,
        enabled,
        provider_id: &provider.id,
        provider_name: &provider.name,
        protocol: &provider.protocol,
        model_id: "models",
        purpose: "fetch_provider_models",
        method,
        url,
        request_body: "",
        response_status,
        response_body,
        duration_ms: started_at.elapsed().as_millis(),
        error,
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_openai_chat_payload() {
        let request = AiChatRequest {
            app_data_dir: ".".to_string(),
            provider: AiProvider {
                id: "p".to_string(),
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
            system_prompt: "system".to_string(),
            user_prompt: "user".to_string(),
            purpose: "test".to_string(),
            api_log_enabled: false,
        };

        let body = build_chat_body(&request);
        assert_eq!(body["model"], "gpt-test");
        assert_eq!(body["messages"][0]["role"], "system");
        assert_eq!(body["messages"][1]["content"], "user");
    }

    #[test]
    fn joins_url_without_double_slashes() {
        assert_eq!(
            join_url("https://api.example.com/v1/", "/chat/completions"),
            "https://api.example.com/v1/chat/completions"
        );
    }

    #[test]
    fn empty_api_path_uses_configured_base_url_as_endpoint() {
        assert_eq!(
            join_url("https://api.example.com/v1/chat/completions/", ""),
            "https://api.example.com/v1/chat/completions"
        );
    }

    #[test]
    fn builds_fim_payload_with_prompt_and_suffix() {
        let request = FimCompleteRequest {
            app_data_dir: ".".to_string(),
            provider: AiProvider {
                id: "p".to_string(),
                name: "OpenAI Compatible".to_string(),
                protocol: "openaiCompatible".to_string(),
                api_key: "key".to_string(),
                base_url: "https://api.example.com/v1".to_string(),
                api_path: "/completions".to_string(),
            },
            model: AiModel {
                model_id: "fim-test".to_string(),
                display_name: "FIM Test".to_string(),
            },
            prompt: "prefix".to_string(),
            suffix: "suffix".to_string(),
            api_log_enabled: false,
        };

        let body = build_fim_body(&request);
        assert_eq!(body["model"], "fim-test");
        assert_eq!(body["prompt"], "prefix");
        assert_eq!(body["suffix"], "suffix");
        assert_eq!(body["max_tokens"], 128);
        assert!(body.get("messages").is_none());
    }

    #[test]
    fn builds_memory_tool_payload_with_strict_tools() {
        let request = MemoryToolChatRequest {
            app_data_dir: ".".to_string(),
            provider: AiProvider {
                id: "p".to_string(),
                name: "OpenAI Compatible".to_string(),
                protocol: "openaiCompatible".to_string(),
                api_key: "key".to_string(),
                base_url: "https://api.example.com/v1".to_string(),
                api_path: "/chat/completions".to_string(),
            },
            model: AiModel {
                model_id: "chat-test".to_string(),
                display_name: "Chat Test".to_string(),
            },
            messages: vec![AiChatMessage {
                role: "user".to_string(),
                content: "什么时候删除 nacos 配置？".to_string(),
                reasoning_content: String::new(),
                tool_call_id: String::new(),
                tool_calls: vec![],
            }],
            thinking_enabled: true,
            reasoning_effort: "high".to_string(),
            api_log_enabled: false,
        };

        let body = build_memory_tool_body(&request, "system");
        assert_eq!(body["messages"][0]["role"], "system");
        assert_eq!(body["messages"][1]["role"], "user");
        assert_eq!(body["tool_choice"], "auto");
        assert_eq!(body["tools"][0]["function"]["strict"], true);
        assert_eq!(
            body["tools"][1]["function"]["parameters"]["required"][0],
            "keywords"
        );
        assert_eq!(
            body["tools"][1]["function"]["parameters"]["additionalProperties"],
            false
        );
    }

    #[test]
    fn serializes_assistant_tool_calls_and_tool_results() {
        let messages = memory_messages_json(
            "system",
            &[
                AiChatMessage {
                    role: "assistant".to_string(),
                    content: String::new(),
                    reasoning_content: "need search".to_string(),
                    tool_call_id: String::new(),
                    tool_calls: vec![AiToolCall {
                        id: "call_1".to_string(),
                        name: "keyword_search".to_string(),
                        arguments: "{\"keywords\":[\"nacos\"]}".to_string(),
                    }],
                },
                AiChatMessage {
                    role: "tool".to_string(),
                    content: "{\"results\":[]}".to_string(),
                    reasoning_content: String::new(),
                    tool_call_id: "call_1".to_string(),
                    tool_calls: vec![],
                },
            ],
        );

        assert_eq!(messages[1]["role"], "assistant");
        assert_eq!(messages[1]["reasoning_content"], "need search");
        assert_eq!(messages[1]["tool_calls"][0]["id"], "call_1");
        assert_eq!(messages[2]["role"], "tool");
        assert_eq!(messages[2]["tool_call_id"], "call_1");
    }

    #[test]
    fn fim_uses_completions_endpoint_not_chat_completions() {
        let provider = AiProvider {
            id: "p".to_string(),
            name: "OpenAI Compatible".to_string(),
            protocol: "openaiCompatible".to_string(),
            api_key: "key".to_string(),
            base_url: "https://api.example.com/v1".to_string(),
            api_path: "/chat/completions".to_string(),
        };

        assert_eq!(
            completions_url(&provider),
            "https://api.example.com/v1/completions"
        );
    }

    #[test]
    fn fim_ignores_configured_api_path() {
        let provider = AiProvider {
            id: "p".to_string(),
            name: "OpenAI Compatible".to_string(),
            protocol: "openaiCompatible".to_string(),
            api_key: "key".to_string(),
            base_url: "https://api.example.com/v1".to_string(),
            api_path: "/custom/fim".to_string(),
        };

        assert_eq!(
            completions_url(&provider),
            "https://api.example.com/v1/completions"
        );
    }

    #[test]
    fn fim_uses_completions_even_when_api_path_is_empty() {
        let provider = AiProvider {
            id: "p".to_string(),
            name: "OpenAI Compatible".to_string(),
            protocol: "openaiCompatible".to_string(),
            api_key: "key".to_string(),
            base_url: "https://api.example.com/v1".to_string(),
            api_path: String::new(),
        };

        assert_eq!(
            completions_url(&provider),
            "https://api.example.com/v1/completions"
        );
    }
}
