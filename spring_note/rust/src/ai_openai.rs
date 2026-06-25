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
    let uses_responses = is_responses_endpoint(&request.provider);
    let body = if uses_responses {
        build_responses_chat_body(request)
    } else {
        build_chat_body(request)
    };
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

    let content = if uses_responses {
        responses_output_text(&value)
    } else {
        extract_text(&value, &[&["choices", "0", "message", "content"]]).ok_or_else(|| {
            "OpenAI-compatible response missing choices[0].message.content".to_string()
        })?
    };
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

pub async fn memory_tool_responses(
    request: &MemoryToolChatRequest,
    system_prompt: &str,
) -> Result<MemoryToolChatResult, String> {
    let log_request = memory_as_chat_request(request, system_prompt);
    let url = join_url(&request.provider.base_url, &request.provider.api_path);
    let body = build_memory_tool_responses_body(request, system_prompt);
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
    let content = responses_output_text(&value);
    let reasoning_content = responses_reasoning_text(&value);
    let tool_calls = parse_responses_function_calls(&value);
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

pub async fn memory_tool_responses_stream(
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
    let body = build_memory_tool_responses_stream_body(&request, system_prompt);
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
            if let Some(message) = responses_stream_error_message(&value) {
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
                let _ = sink.add(MemoryToolChatStreamEvent::error("request_failed", &message));
                return Ok(());
            }

            let delta = apply_responses_stream_event(&mut accumulator, &value);
            if !delta.content_delta.is_empty() || !delta.reasoning_delta.is_empty() {
                let _ = sink.add(MemoryToolChatStreamEvent {
                    event_type: "delta".to_string(),
                    content_delta: delta.content_delta,
                    reasoning_delta: delta.reasoning_delta,
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
    let url = models_url(provider);
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

pub fn build_responses_chat_body(request: &AiChatRequest) -> Value {
    json!({
        "model": request.model.model_id,
        "instructions": request.system_prompt,
        "input": request.user_prompt,
        "temperature": 0.2
    })
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

pub fn build_memory_tool_responses_body(
    request: &MemoryToolChatRequest,
    system_prompt: &str,
) -> Value {
    let mut body = json!({
        "model": request.model.model_id,
        "instructions": system_prompt,
        "input": responses_memory_input(&request.messages),
        "tools": responses_memory_tools_json(),
        "tool_choice": "auto"
    });
    apply_responses_thinking_options(
        &mut body,
        request.thinking_enabled,
        &request.reasoning_effort,
    );
    body
}

pub fn build_memory_tool_responses_stream_body(
    request: &MemoryToolChatRequest,
    system_prompt: &str,
) -> Value {
    let mut body = build_memory_tool_responses_body(request, system_prompt);
    body["stream"] = Value::Bool(true);
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

fn responses_memory_input(messages: &[AiChatMessage]) -> Vec<Value> {
    let mut result = Vec::new();
    for message in messages {
        if message.role == "assistant" && !message.tool_calls.is_empty() {
            if !message.content.trim().is_empty() {
                result.push(json!({
                    "role": "assistant",
                    "content": message.content
                }));
            }
            for tool_call in &message.tool_calls {
                result.push(json!({
                    "type": "function_call",
                    "call_id": tool_call.id,
                    "name": tool_call.name,
                    "arguments": tool_call.arguments,
                    "status": "completed"
                }));
            }
            continue;
        }

        if message.role == "tool" {
            if !message.tool_call_id.trim().is_empty() {
                result.push(json!({
                    "type": "function_call_output",
                    "call_id": message.tool_call_id,
                    "output": message.content,
                    "status": "completed"
                }));
            }
            continue;
        }

        result.push(json!({
            "role": if message.role == "assistant" { "assistant" } else { message.role.as_str() },
            "content": message.content
        }));
    }
    result
}

fn apply_thinking_options(body: &mut Value, enabled: bool, effort: &str) {
    if enabled {
        body["thinking"] = json!({"type": "enabled"});
        body["reasoning_effort"] =
            Value::String(normalize_chat_reasoning_effort(effort).to_string());
    } else {
        body["thinking"] = json!({"type": "disabled"});
        body["temperature"] = Value::from(0.2);
    }
}

fn apply_responses_thinking_options(body: &mut Value, enabled: bool, effort: &str) {
    if enabled {
        body["reasoning"] = json!({
            "effort": normalize_responses_reasoning_effort(effort)
        });
    } else {
        body["temperature"] = Value::from(0.2);
    }
}

fn normalize_chat_reasoning_effort(effort: &str) -> &str {
    match effort {
        "max" | "xhigh" => "max",
        _ => "high",
    }
}

fn normalize_responses_reasoning_effort(effort: &str) -> &str {
    match effort {
        "max" | "xhigh" => "xhigh",
        "high" => "high",
        "medium" => "medium",
        "low" => "low",
        "minimal" => "minimal",
        "none" => "none",
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

fn responses_memory_tools_json() -> Value {
    let tools = memory_tools_json()
        .as_array()
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|item| {
            let function = item.get("function")?;
            Some(json!({
                "type": "function",
                "name": function.get("name").cloned().unwrap_or(Value::String(String::new())),
                "description": function.get("description").cloned().unwrap_or(Value::String(String::new())),
                "parameters": function.get("parameters").cloned().unwrap_or_else(|| json!({ "type": "object", "properties": {} })),
                "strict": function.get("strict").cloned().unwrap_or(Value::Bool(true))
            }))
        })
        .collect::<Vec<_>>();
    Value::Array(tools)
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

fn parse_responses_function_calls(value: &Value) -> Vec<AiToolCall> {
    value
        .get("output")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter(|item| item.get("type").and_then(Value::as_str) == Some("function_call"))
                .map(|item| AiToolCall {
                    id: item
                        .get("call_id")
                        .or_else(|| item.get("id"))
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_string(),
                    name: item
                        .get("name")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_string(),
                    arguments: item
                        .get("arguments")
                        .and_then(Value::as_str)
                        .unwrap_or("{}")
                        .to_string(),
                })
                .filter(|tool_call| !tool_call.id.is_empty() && !tool_call.name.is_empty())
                .collect()
        })
        .unwrap_or_default()
}

fn responses_output_text(value: &Value) -> String {
    if let Some(text) = value.get("output_text").and_then(Value::as_str) {
        return text.to_string();
    }

    value
        .get("output")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter(|item| item.get("type").and_then(Value::as_str) == Some("message"))
                .flat_map(|item| {
                    item.get("content")
                        .and_then(Value::as_array)
                        .cloned()
                        .unwrap_or_default()
                })
                .filter_map(|content| {
                    let content_type = content.get("type").and_then(Value::as_str);
                    if matches!(content_type, Some("output_text") | Some("text")) {
                        content
                            .get("text")
                            .and_then(Value::as_str)
                            .map(str::to_string)
                    } else {
                        None
                    }
                })
                .collect::<Vec<_>>()
                .join("")
        })
        .unwrap_or_default()
}

fn responses_reasoning_text(value: &Value) -> String {
    value
        .get("output")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter(|item| item.get("type").and_then(Value::as_str) == Some("reasoning"))
                .flat_map(|item| {
                    item.get("summary")
                        .and_then(Value::as_array)
                        .cloned()
                        .unwrap_or_default()
                })
                .filter_map(|summary| {
                    summary
                        .get("text")
                        .and_then(Value::as_str)
                        .map(str::to_string)
                })
                .collect::<Vec<_>>()
                .join("\n")
        })
        .unwrap_or_default()
}

#[derive(Default)]
struct ResponsesStreamDelta {
    content_delta: String,
    reasoning_delta: String,
}

fn responses_stream_error_message(value: &Value) -> Option<String> {
    let event_type = value.get("type").and_then(Value::as_str).unwrap_or("");
    if event_type != "error"
        && event_type != "response.failed"
        && event_type != "response.incomplete"
    {
        return None;
    }

    value
        .get("error")
        .and_then(|error| error.get("message").or_else(|| error.get("code")))
        .and_then(Value::as_str)
        .or_else(|| value.get("message").and_then(Value::as_str))
        .or_else(|| {
            value.get("response").and_then(|response| {
                response
                    .get("error")
                    .and_then(|error| error.get("message").or_else(|| error.get("code")))
                    .and_then(Value::as_str)
                    .or_else(|| {
                        response
                            .get("incomplete_details")
                            .and_then(|details| details.get("reason"))
                            .and_then(Value::as_str)
                    })
            })
        })
        .map(str::to_string)
        .or_else(|| Some(event_type.to_string()))
}

fn apply_responses_stream_event(
    accumulator: &mut StreamAccumulator,
    value: &Value,
) -> ResponsesStreamDelta {
    let event_type = value.get("type").and_then(Value::as_str).unwrap_or("");
    let mut delta = ResponsesStreamDelta::default();
    match event_type {
        "response.output_text.delta" => {
            delta.content_delta = read_string_field(value, "delta");
            accumulator.content.push_str(&delta.content_delta);
        }
        "response.reasoning_summary_text.delta" | "response.reasoning_text.delta" => {
            delta.reasoning_delta = read_string_field(value, "delta");
            accumulator
                .reasoning_content
                .push_str(&delta.reasoning_delta);
        }
        "response.output_item.added" => {
            if let Some(item) = value.get("item") {
                accumulator.merge_responses_output_item(value, item);
            }
        }
        "response.output_item.done" => {
            if let Some(item) = value.get("item") {
                accumulator.merge_responses_output_item(value, item);
            }
        }
        "response.function_call_arguments.delta" => {
            accumulator.merge_responses_function_arguments_delta(value);
        }
        "response.function_call_arguments.done" => {
            accumulator.merge_responses_function_arguments_done(value);
        }
        "response.completed" => {
            if let Some(response) = value.get("response") {
                accumulator.merge_responses_completed(response, &mut delta);
            }
        }
        _ => {
            if value.get("output").is_some() {
                accumulator.merge_responses_completed(value, &mut delta);
            }
        }
    }
    delta
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

    fn merge_responses_output_item(&mut self, event: &Value, item: &Value) {
        if item.get("type").and_then(Value::as_str) != Some("function_call") {
            return;
        }
        let index = self.responses_tool_index(event, item);
        let target = &mut self.tool_calls[index];
        if let Some(id) = item
            .get("call_id")
            .or_else(|| item.get("id"))
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty())
        {
            target.id = id.to_string();
        }
        if let Some(name) = item
            .get("name")
            .and_then(Value::as_str)
            .filter(|name| !name.is_empty())
        {
            target.name = name.to_string();
        }
        if let Some(arguments) = item.get("arguments").and_then(Value::as_str) {
            target.arguments = arguments.to_string();
        }
    }

    fn merge_responses_function_arguments_delta(&mut self, value: &Value) {
        let index = self.responses_tool_index(value, value);
        let target = &mut self.tool_calls[index];
        if let Some(id) = value
            .get("call_id")
            .or_else(|| value.get("item_id"))
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty())
        {
            target.id = id.to_string();
        }
        if let Some(name) = value
            .get("name")
            .and_then(Value::as_str)
            .filter(|name| !name.is_empty())
        {
            target.name = name.to_string();
        }
        if let Some(arguments) = value.get("delta").and_then(Value::as_str) {
            target.arguments.push_str(arguments);
        }
    }

    fn merge_responses_function_arguments_done(&mut self, value: &Value) {
        let index = self.responses_tool_index(value, value);
        let target = &mut self.tool_calls[index];
        if let Some(id) = value
            .get("call_id")
            .or_else(|| value.get("item_id"))
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty())
        {
            target.id = id.to_string();
        }
        if let Some(arguments) = value.get("arguments").and_then(Value::as_str) {
            target.arguments = arguments.to_string();
        }
    }

    fn merge_responses_completed(&mut self, response: &Value, delta: &mut ResponsesStreamDelta) {
        let completed_content = responses_output_text(response);
        if !completed_content.is_empty() && self.content.is_empty() {
            delta.content_delta = completed_content.clone();
            self.content = completed_content;
        }
        let completed_reasoning = responses_reasoning_text(response);
        if !completed_reasoning.is_empty() && self.reasoning_content.is_empty() {
            delta.reasoning_delta = completed_reasoning.clone();
            self.reasoning_content = completed_reasoning;
        }
        for item in response
            .get("output")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default()
        {
            self.merge_responses_output_item(&json!({}), &item);
        }
        let (input, output, cached) = usage_from_value(response);
        if input != 0 || output != 0 || cached != 0 {
            self.input_tokens = input;
            self.output_tokens = output;
            self.cached_tokens = cached;
        }
    }

    fn responses_tool_index(&mut self, event: &Value, item: &Value) -> usize {
        let explicit_index = event
            .get("output_index")
            .or_else(|| event.get("item_index"))
            .or_else(|| event.get("index"))
            .or_else(|| item.get("output_index"))
            .or_else(|| item.get("item_index"))
            .or_else(|| item.get("index"))
            .and_then(Value::as_u64)
            .map(|value| value as usize);
        if let Some(index) = explicit_index {
            while self.tool_calls.len() <= index {
                self.tool_calls.push(ToolCallAccumulator::default());
            }
            return index;
        }

        let ids = [
            item.get("call_id").and_then(Value::as_str),
            event.get("call_id").and_then(Value::as_str),
            item.get("id").and_then(Value::as_str),
            event.get("item_id").and_then(Value::as_str),
        ];
        if let Some(index) = self.tool_calls.iter().position(|tool_call| {
            ids.iter()
                .flatten()
                .any(|id| !id.is_empty() && !tool_call.id.is_empty() && tool_call.id == *id)
        }) {
            return index;
        }

        self.tool_calls.push(ToolCallAccumulator::default());
        self.tool_calls.len() - 1
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
    if is_responses_endpoint(provider) {
        return join_url(&provider_endpoint_base(provider), "/responses");
    }
    join_url(&provider_endpoint_base(provider), "/completions")
}

fn models_url(provider: &AiProvider) -> String {
    join_url(&provider_endpoint_base(provider), "/models")
}

fn provider_endpoint_base(provider: &AiProvider) -> String {
    let base = trim_endpoint_suffix(&provider.base_url);
    if provider.api_path.trim().is_empty() {
        return base;
    }

    let endpoint = join_url(&base, &provider.api_path);
    let trimmed = trim_endpoint_suffix(&endpoint);
    if trimmed != endpoint.trim_end_matches('/') {
        return trimmed;
    }
    base
}

fn trim_endpoint_suffix(url: &str) -> String {
    let mut result = url.trim_end_matches('/').to_string();
    for suffix in [
        "/chat/completions",
        "/responses",
        "/completions",
        "/messages",
    ] {
        if result.ends_with(suffix) {
            let next_len = result.len() - suffix.len();
            result.truncate(next_len);
            break;
        }
    }
    result
}

pub fn is_responses_endpoint(provider: &AiProvider) -> bool {
    join_url(&provider.base_url, &provider.api_path)
        .trim_end_matches('/')
        .ends_with("/responses")
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
    fn builds_openai_responses_chat_payload() {
        let request = AiChatRequest {
            app_data_dir: ".".to_string(),
            provider: AiProvider {
                id: "p".to_string(),
                name: "OpenAI".to_string(),
                protocol: "openaiCompatible".to_string(),
                api_key: "key".to_string(),
                base_url: "https://api.example.com/v1".to_string(),
                api_path: "/responses".to_string(),
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

        let body = build_responses_chat_body(&request);
        assert_eq!(body["model"], "gpt-test");
        assert_eq!(body["instructions"], "system");
        assert_eq!(body["input"], "user");
        assert!(body.get("messages").is_none());
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
    fn builds_memory_tool_responses_payload_with_call_ids() {
        let request = MemoryToolChatRequest {
            app_data_dir: ".".to_string(),
            provider: AiProvider {
                id: "p".to_string(),
                name: "OpenAI Compatible".to_string(),
                protocol: "openaiCompatible".to_string(),
                api_key: "key".to_string(),
                base_url: "https://api.example.com/v1".to_string(),
                api_path: "/responses".to_string(),
            },
            model: AiModel {
                model_id: "responses-test".to_string(),
                display_name: "Responses Test".to_string(),
            },
            messages: vec![
                AiChatMessage {
                    role: "user".to_string(),
                    content: "什么时候删除 nacos 配置？".to_string(),
                    reasoning_content: String::new(),
                    tool_call_id: String::new(),
                    tool_calls: vec![],
                },
                AiChatMessage {
                    role: "assistant".to_string(),
                    content: String::new(),
                    reasoning_content: String::new(),
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
            thinking_enabled: true,
            reasoning_effort: "high".to_string(),
            api_log_enabled: false,
        };

        let body = build_memory_tool_responses_body(&request, "system");
        assert_eq!(body["model"], "responses-test");
        assert_eq!(body["instructions"], "system");
        assert_eq!(body["tool_choice"], "auto");
        assert!(body.get("messages").is_none());
        assert_eq!(body["tools"][1]["name"], "keyword_search");
        assert_eq!(body["tools"][1]["strict"], true);
        assert_eq!(body["input"][1]["type"], "function_call");
        assert_eq!(body["input"][1]["call_id"], "call_1");
        assert_eq!(body["input"][1]["name"], "keyword_search");
        assert_eq!(body["input"][2]["type"], "function_call_output");
        assert_eq!(body["input"][2]["call_id"], "call_1");
        assert_eq!(body["input"][2]["output"], "{\"results\":[]}");
        assert_eq!(body["reasoning"]["effort"], "high");
        assert!(body.get("thinking").is_none());
        assert!(body.get("reasoning_effort").is_none());
    }

    #[test]
    fn builds_memory_tool_responses_stream_payload() {
        let request = MemoryToolChatRequest {
            app_data_dir: ".".to_string(),
            provider: AiProvider {
                id: "p".to_string(),
                name: "OpenAI Compatible".to_string(),
                protocol: "openaiCompatible".to_string(),
                api_key: "key".to_string(),
                base_url: "https://api.example.com/v1".to_string(),
                api_path: "/responses".to_string(),
            },
            model: AiModel {
                model_id: "responses-test".to_string(),
                display_name: "Responses Test".to_string(),
            },
            messages: vec![AiChatMessage {
                role: "user".to_string(),
                content: "问题".to_string(),
                reasoning_content: String::new(),
                tool_call_id: String::new(),
                tool_calls: vec![],
            }],
            thinking_enabled: true,
            reasoning_effort: "max".to_string(),
            api_log_enabled: false,
        };

        let body = build_memory_tool_responses_stream_body(&request, "system");
        assert_eq!(body["stream"], true);
        assert_eq!(body["reasoning"]["effort"], "xhigh");
        assert!(body.get("stream_options").is_none());
    }

    #[test]
    fn preserves_responses_reasoning_effort_xhigh() {
        let request = MemoryToolChatRequest {
            app_data_dir: ".".to_string(),
            provider: AiProvider {
                id: "p".to_string(),
                name: "OpenAI Responses".to_string(),
                protocol: "openaiCompatible".to_string(),
                api_key: "key".to_string(),
                base_url: "https://api.example.com/v1".to_string(),
                api_path: "/responses".to_string(),
            },
            model: AiModel {
                model_id: "gpt-test".to_string(),
                display_name: "GPT Test".to_string(),
            },
            messages: vec![],
            thinking_enabled: true,
            reasoning_effort: "xhigh".to_string(),
            api_log_enabled: false,
        };

        let body = build_memory_tool_responses_body(&request, "system");
        assert_eq!(body["reasoning"]["effort"], "xhigh");
    }

    #[test]
    fn parses_responses_stream_events() {
        let mut accumulator = StreamAccumulator::default();

        let delta = apply_responses_stream_event(
            &mut accumulator,
            &json!({
                "type": "response.output_text.delta",
                "delta": "你好"
            }),
        );
        assert_eq!(delta.content_delta, "你好");
        assert_eq!(accumulator.content, "你好");

        let delta = apply_responses_stream_event(
            &mut accumulator,
            &json!({
                "type": "response.reasoning_summary_text.delta",
                "delta": "先查资料"
            }),
        );
        assert_eq!(delta.reasoning_delta, "先查资料");
        assert_eq!(accumulator.reasoning_content, "先查资料");

        apply_responses_stream_event(
            &mut accumulator,
            &json!({
                "type": "response.output_item.added",
                "item": {
                    "type": "function_call",
                    "output_index": 1,
                    "call_id": "call_1",
                    "name": "keyword_search",
                    "arguments": ""
                }
            }),
        );
        apply_responses_stream_event(
            &mut accumulator,
            &json!({
                "type": "response.function_call_arguments.delta",
                "output_index": 1,
                "delta": "{\"keywords\":"
            }),
        );
        apply_responses_stream_event(
            &mut accumulator,
            &json!({
                "type": "response.function_call_arguments.delta",
                "output_index": 1,
                "delta": "[\"回忆书\"]}"
            }),
        );
        let tool_calls = accumulator.tool_calls();
        assert_eq!(tool_calls.len(), 1);
        assert_eq!(tool_calls[0].id, "call_1");
        assert_eq!(tool_calls[0].name, "keyword_search");
        assert_eq!(tool_calls[0].arguments, "{\"keywords\":[\"回忆书\"]}");
    }

    #[test]
    fn merges_responses_stream_events_by_outer_output_index() {
        let mut accumulator = StreamAccumulator::default();

        apply_responses_stream_event(
            &mut accumulator,
            &json!({
                "type": "response.output_item.added",
                "output_index": 0,
                "item": {
                    "type": "function_call",
                    "call_id": "call_date",
                    "name": "get_current_date",
                    "arguments": ""
                }
            }),
        );
        apply_responses_stream_event(
            &mut accumulator,
            &json!({
                "type": "response.function_call_arguments.delta",
                "output_index": 0,
                "delta": "{}"
            }),
        );
        apply_responses_stream_event(
            &mut accumulator,
            &json!({
                "type": "response.output_item.done",
                "output_index": 0,
                "item": {
                    "type": "function_call",
                    "call_id": "call_date",
                    "name": "get_current_date",
                    "arguments": "{}"
                }
            }),
        );

        let tool_calls = accumulator.tool_calls();
        assert_eq!(tool_calls.len(), 1);
        assert_eq!(tool_calls[0].id, "call_date");
        assert_eq!(tool_calls[0].name, "get_current_date");
        assert_eq!(tool_calls[0].arguments, "{}");
    }

    #[test]
    fn parses_responses_function_calls() {
        let value = json!({
            "output": [
                {
                    "type": "function_call",
                    "call_id": "call_abc",
                    "name": "keyword_search",
                    "arguments": "{\"keywords\":[\"回忆书\"]}"
                }
            ]
        });

        let tool_calls = parse_responses_function_calls(&value);
        assert_eq!(tool_calls.len(), 1);
        assert_eq!(tool_calls[0].id, "call_abc");
        assert_eq!(tool_calls[0].name, "keyword_search");
        assert_eq!(tool_calls[0].arguments, "{\"keywords\":[\"回忆书\"]}");
    }

    #[test]
    fn reads_responses_output_text() {
        let value = json!({
            "output_text": "直接答案"
        });

        assert_eq!(responses_output_text(&value), "直接答案");
    }

    #[test]
    fn detects_responses_endpoint() {
        let provider = AiProvider {
            id: "p".to_string(),
            name: "OpenAI Compatible".to_string(),
            protocol: "openaiCompatible".to_string(),
            api_key: "key".to_string(),
            base_url: "https://api.openai.com/v1".to_string(),
            api_path: "/responses".to_string(),
        };
        assert!(is_responses_endpoint(&provider));

        let provider = AiProvider {
            api_path: "/chat/completions".to_string(),
            ..provider
        };
        assert!(!is_responses_endpoint(&provider));
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

    #[test]
    fn fim_keeps_deepseek_beta_base_url() {
        let provider = AiProvider {
            id: "deepseek".to_string(),
            name: "DeepSeek".to_string(),
            protocol: "openaiCompatible".to_string(),
            api_key: "key".to_string(),
            base_url: "https://api.deepseek.com/beta".to_string(),
            api_path: "/chat/completions".to_string(),
        };

        assert_eq!(
            completions_url(&provider),
            "https://api.deepseek.com/beta/completions"
        );
    }

    #[test]
    fn endpoint_base_strips_configured_chat_endpoint() {
        let provider = AiProvider {
            id: "p".to_string(),
            name: "OpenAI Compatible".to_string(),
            protocol: "openaiCompatible".to_string(),
            api_key: "key".to_string(),
            base_url: "https://api.example.com/v1/chat/completions".to_string(),
            api_path: String::new(),
        };

        assert_eq!(models_url(&provider), "https://api.example.com/v1/models");
        assert_eq!(
            completions_url(&provider),
            "https://api.example.com/v1/completions"
        );
    }

    #[test]
    fn endpoint_base_strips_responses_endpoint() {
        let provider = AiProvider {
            id: "p".to_string(),
            name: "OpenAI Responses".to_string(),
            protocol: "openaiCompatible".to_string(),
            api_key: "key".to_string(),
            base_url: "https://api.example.com/v1".to_string(),
            api_path: "/responses".to_string(),
        };

        assert_eq!(models_url(&provider), "https://api.example.com/v1/models");
        assert_eq!(
            completions_url(&provider),
            "https://api.example.com/v1/responses"
        );
    }
}
