use crate::ai::{
    AiChatMessage, AiChatRequest, AiImageAttachment, AiModel, AiProvider, AiTextResult, AiToolCall,
    MemoryToolChatRequest, MemoryToolChatResult, MemoryToolChatStreamEvent, extract_text,
    http_client, http_stream_client, usage_from_value,
};
use crate::ai_log::{ApiNetworkLog, write_api_network_log};
use crate::frb_generated::StreamSink;
use crate::{ai_openai, stats};
use serde_json::{Value, json};
use std::time::Instant;

/// 结构化日报用途标识;该用途在 /v1/messages 上附加 output_config.format 约束输出 JSON。
const STRUCTURED_NOTE_PURPOSE: &str = "home_structured_note";

pub async fn chat(request: &AiChatRequest) -> Result<AiTextResult, String> {
    let url = messages_url(&request.provider);
    let body = build_messages_body(request);
    let value = post_messages(request, &url, &body).await?;

    let content = extract_chat_text(&value)
        .ok_or_else(|| "Claude response missing content text block".to_string())?;
    let (input, output, cached) = usage_from_value(&value);
    Ok(AiTextResult::success(
        request, content, input, output, cached,
    ))
}

// ---------------------------------------------------------------------------
// Claude Messages API(/v1/messages)
//
// 以下能力基于 /v1/messages 实现:
// - 工具调用:tools 声明 {name, description, input_schema};响应 content 中的
//   tool_use 块,历史以 user 消息的 tool_result 块(必须位于 content 最前)回传;
//   流式时 tool_use 的 input 以 input_json_delta.partial_json 增量拼接
// - 扩展思考:thinking 配置(Opus 4.6 及之后模型用自适应思考,
//   更早模型用 enabled + budget_tokens),content 中 type = thinking 的块映射为推理内容
// - 结构化输出:output_config.format = {type: "json_schema", schema}
// ---------------------------------------------------------------------------

/// 回忆书问答(非流式):工具调用 + 扩展思考,走 /v1/messages。
pub async fn memory_tool_chat(
    request: &MemoryToolChatRequest,
    system_prompt: &str,
) -> Result<MemoryToolChatResult, String> {
    let log_request = memory_as_chat_request(request, system_prompt);
    let url = messages_url(&request.provider);
    let body = build_memory_tool_body(request, system_prompt);
    let value = post_messages(&log_request, &url, &body).await?;
    let blocks = content_blocks(&value);
    let content = blocks_text(&blocks, false);
    let reasoning_content = blocks_text(&blocks, true);
    let tool_calls = blocks_tool_calls(&blocks);
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

/// 回忆书问答(流式):同一 /v1/messages 端点加 stream = true,按 SSE 事件逐块下发。
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

    let url = messages_url(&request.provider);
    let mut body = build_memory_tool_body(&request, system_prompt);
    body["stream"] = json!(true);
    let request_body = body_to_string(&body);
    let started_at = Instant::now();
    let response = http_stream_client()?
        .post(&url)
        .header("x-api-key", &request.provider.api_key)
        .header("anthropic-version", "2023-06-01")
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
        let message = claude_http_error(status, &response_body);
        let _ = sink.add(MemoryToolChatStreamEvent::error("request_failed", &message));
        return Ok(());
    }

    let mut response = response;
    let mut parser = SseParser::default();
    let mut raw_response = String::new();
    let mut accumulator = ClaudeStreamAccumulator::default();
    while let Some(chunk) = response.chunk().await.map_err(|error| error.to_string())? {
        let text = String::from_utf8_lossy(&chunk);
        raw_response.push_str(&text);
        for payload in parser.push(&text) {
            let Ok(value) = serde_json::from_str::<Value>(&payload) else {
                continue;
            };
            if value.get("type").and_then(Value::as_str) == Some("error") {
                let message = value
                    .get("error")
                    .and_then(|error| error.get("message"))
                    .and_then(Value::as_str)
                    .unwrap_or("未知错误")
                    .to_string();
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
            let delta = apply_claude_stream_event(&mut accumulator, &value);
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
    let tool_calls = accumulator
        .tool_calls
        .into_iter()
        .map(|mut tool_call| {
            if tool_call.arguments.is_empty() {
                tool_call.arguments = "{}".to_string();
            }
            tool_call
        })
        .collect::<Vec<_>>();
    let content = accumulator.content;
    let reasoning_content = accumulator.reasoning_content;
    let input_tokens = accumulator.input_tokens;
    let output_tokens = accumulator.output_tokens;
    let result = AiTextResult::success(
        &log_request,
        content.clone(),
        input_tokens,
        output_tokens,
        0,
    );
    stats::record_model_call_or_warn(
        "memory_tool_claude_stream",
        &request.app_data_dir,
        &log_request,
        &result,
    );
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
        cached_tokens: 0,
    });
    Ok(())
}

/// 发送一次非流式 /v1/messages 请求并写网络日志,返回解析后的响应 JSON。
async fn post_messages(
    log_request: &AiChatRequest,
    url: &str,
    body: &Value,
) -> Result<Value, String> {
    let request_body = body_to_string(body);
    let started_at = Instant::now();
    let response = http_client()?
        .post(url)
        .header("x-api-key", &log_request.provider.api_key)
        .header("anthropic-version", "2023-06-01")
        .json(body)
        .send()
        .await
        .map_err(|error| {
            let message = error.to_string();
            log_chat(
                log_request,
                "POST",
                url,
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
            log_request,
            "POST",
            url,
            &request_body,
            Some(status.as_u16()),
            "",
            started_at,
            &message,
        );
        message
    })?;
    log_chat(
        log_request,
        "POST",
        url,
        &request_body,
        Some(status.as_u16()),
        &response_body,
        started_at,
        "",
    );
    if !status.is_success() {
        return Err(claude_http_error(status, &response_body));
    }
    serde_json::from_str::<Value>(&response_body).map_err(|error| error.to_string())
}

/// 回忆书工具调用的 /v1/messages 请求体;流式仅追加 stream = true,请求体相同。
pub fn build_memory_tool_body(request: &MemoryToolChatRequest, system_prompt: &str) -> Value {
    let mut body = json!({
        "model": request.model.model_id,
        // budget_tokens 必须小于 max_tokens;思考预算档位上限 12288 为此预留。
        "max_tokens": 16384,
        "system": system_prompt,
        "messages": claude_messages(&request.messages),
        "tools": claude_memory_tools(),
        // 思考开启时 tool_choice 仅支持 auto / none。
        "tool_choice": {"type": "auto"},
    });
    if let Some(config) = thinking_config(
        &request.model.model_id,
        request.thinking_enabled,
        &request.reasoning_effort,
    ) {
        if config.get("type").and_then(Value::as_str) == Some("disabled") {
            // 思考与 temperature 修改不兼容,仅在思考显式关闭时自定义采样。
            body["temperature"] = json!(0.2);
        } else if config.get("type").and_then(Value::as_str) == Some("adaptive") {
            // 自适应思考的深度由 output_config.effort 软性引导。
            body["output_config"] = json!({"effort": adaptive_effort(&request.reasoning_effort)});
        }
        body["thinking"] = config;
    }
    body
}

/// 自适应思考的 effort 档位:max 在所有自适应模型上可用;
/// xhigh 仅部分旗舰模型支持,统一按 max 处理。
fn adaptive_effort(effort: &str) -> &str {
    match effort {
        "max" | "xhigh" => "max",
        "medium" => "medium",
        "minimal" | "none" | "low" => "low",
        _ => "high",
    }
}

/// 扩展思考配置:Opus 4.6 及之后模型用自适应思考(budget_tokens 已弃用或不支持),
/// 更早模型用 enabled + budget_tokens;display 显式取 summarized 以返回思考摘要。
/// Fable 5 / Mythos 5 思考常开且不支持 disabled,关闭时返回 None(省略 thinking 字段)。
fn thinking_config(model_id: &str, enabled: bool, effort: &str) -> Option<Value> {
    if enabled {
        if is_adaptive_thinking_model(model_id) {
            Some(json!({"type": "adaptive", "display": "summarized"}))
        } else {
            Some(json!({
                "type": "enabled",
                "budget_tokens": thinking_budget(effort),
                "display": "summarized"
            }))
        }
    } else if thinking_always_on(model_id) {
        None
    } else {
        Some(json!({"type": "disabled"}))
    }
}

/// Opus 4.6 及之后的模型仅支持(或推荐)自适应思考;更早模型用 budget_tokens。
fn is_adaptive_thinking_model(model_id: &str) -> bool {
    let id = model_id.to_ascii_lowercase();
    id.contains("4-8")
        || id.contains("4.8")
        || id.contains("4-7")
        || id.contains("4.7")
        || id.contains("4-6")
        || id.contains("4.6")
        || id.contains("sonnet-5")
        || thinking_always_on(&id)
}

/// Fable 5 / Mythos 5(含 Mythos Preview)思考常开,不支持 budget_tokens 与 disabled。
fn thinking_always_on(model_id: &str) -> bool {
    let id = model_id.to_ascii_lowercase();
    id.contains("fable") || id.contains("mythos")
}

/// thinking_budget 档位:下限 1024,上限在 max_tokens(16384)内为回答预留空间。
fn thinking_budget(effort: &str) -> i32 {
    match effort {
        "minimal" | "none" | "low" => 2048,
        "medium" => 4096,
        "high" => 8192,
        _ => 12288,
    }
}

/// 把应用内消息历史转成 /v1/messages 的 messages。
/// assistant 的工具调用映射为 tool_use 块;连续的 tool 消息合并为一条 user 消息,
/// content 全为 tool_result 块(tool_result 必须位于 user content 最前,此处天然满足)。
/// 思考块的签名无法在历史中保存与带回,按惯例省略;API 会优雅降级(静默关闭思考),不报错。
fn claude_messages(messages: &[AiChatMessage]) -> Vec<Value> {
    let mut result = Vec::new();
    let mut index = 0;
    while index < messages.len() {
        let message = &messages[index];
        match message.role.as_str() {
            "assistant" => {
                let mut blocks = Vec::new();
                if !message.content.trim().is_empty() {
                    blocks.push(json!({"type": "text", "text": message.content}));
                }
                for tool_call in &message.tool_calls {
                    blocks.push(json!({
                        "type": "tool_use",
                        "id": tool_call.id,
                        "name": tool_call.name,
                        "input": parse_tool_arguments(&tool_call.arguments)
                    }));
                }
                if !blocks.is_empty() {
                    result.push(json!({"role": "assistant", "content": blocks}));
                }
                index += 1;
            }
            "tool" => {
                let mut blocks = Vec::new();
                while index < messages.len() && messages[index].role == "tool" {
                    let tool = &messages[index];
                    blocks.push(json!({
                        "type": "tool_result",
                        "tool_use_id": tool.tool_call_id,
                        "content": tool.content
                    }));
                    index += 1;
                }
                result.push(json!({"role": "user", "content": blocks}));
            }
            _ => {
                result.push(json!({"role": "user", "content": message.content}));
                index += 1;
            }
        }
    }
    result
}

/// tool_use 的 input 必须是 JSON 对象;历史中的字符串参数解析失败时回退为空对象。
fn parse_tool_arguments(arguments: &str) -> Value {
    serde_json::from_str::<Value>(arguments)
        .ok()
        .filter(|value| value.is_object())
        .unwrap_or_else(|| json!({}))
}

/// 复用 OpenAI 侧的回忆书工具定义,转换为 /v1/messages 工具格式。
/// 非严格模式的 input_schema 接受任意 JSON Schema,minLength/pattern 等原样保留。
fn claude_memory_tools() -> Value {
    let tools = ai_openai::memory_tools_json()
        .as_array()
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|item| {
            let function = item.get("function")?;
            Some(json!({
                "name": function.get("name").cloned().unwrap_or(Value::String(String::new())),
                "description": function.get("description").cloned().unwrap_or(Value::String(String::new())),
                "input_schema": function
                    .get("parameters")
                    .cloned()
                    .unwrap_or_else(|| json!({"type": "object", "properties": {}}))
            }))
        })
        .collect::<Vec<_>>();
    Value::Array(tools)
}

/// 与 Rust 侧 parse_structured_note 解析逻辑匹配的输出 Schema;
/// Claude 结构化输出要求所有对象显式声明 additionalProperties: false。
fn structured_note_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "sections": {
                "type": "array",
                "description": "Structured note sections. Every configured section id must appear exactly once.",
                "items": {
                    "type": "object",
                    "properties": {
                        "id": {
                            "type": "string",
                            "description": "The configured section id."
                        },
                        "items": {
                            "type": "array",
                            "description": "Bullet items for this section; empty when nothing was recorded.",
                            "items": {"type": "string"}
                        }
                    },
                    "required": ["id", "items"],
                    "additionalProperties": false
                }
            }
        },
        "required": ["sections"],
        "additionalProperties": false
    })
}

/// 取出响应的 content 块数组;缺失时返回空数组。
fn content_blocks(value: &Value) -> Vec<Value> {
    value
        .get("content")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

/// 从 /v1/messages 响应中取正式回答:跳过 thinking 块,拼接所有 text 块
/// (思考模型的正式回答可能不在 content[0]);全部缺失时兜底取 content[0].text,兼容旧行为。
fn extract_chat_text(value: &Value) -> Option<String> {
    let blocks = content_blocks(value);
    let content = blocks_text(&blocks, false);
    if !content.is_empty() {
        return Some(content);
    }
    extract_text(value, &[&["content", "0", "text"]])
}

/// 拼接 content 块中的文本;thinking = true 取 thinking 块的思考摘要,否则取 text 块正文。
fn blocks_text(blocks: &[Value], thinking: bool) -> String {
    let block_type = if thinking { "thinking" } else { "text" };
    let separator = if thinking { "\n" } else { "" };
    blocks
        .iter()
        .filter(|block| block.get("type").and_then(Value::as_str) == Some(block_type))
        .filter_map(|block| block.get(block_type).and_then(Value::as_str))
        .collect::<Vec<_>>()
        .join(separator)
}

/// 提取 content 块中的 tool_use;input 序列化为 JSON 字符串。
fn blocks_tool_calls(blocks: &[Value]) -> Vec<AiToolCall> {
    blocks
        .iter()
        .filter(|block| block.get("type").and_then(Value::as_str) == Some("tool_use"))
        .map(|block| AiToolCall {
            id: block
                .get("id")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string(),
            name: block
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string(),
            arguments: block
                .get("input")
                .map(|input| serde_json::to_string(input).unwrap_or_else(|_| "{}".to_string()))
                .unwrap_or_else(|| "{}".to_string()),
        })
        .filter(|tool_call| !tool_call.name.is_empty())
        .collect()
}

/// 组装非 2xx 响应的错误文本;优先提取 API 返回的错误消息,
/// 兼容普通 JSON 错误与 SSE error 事件两种响应形态。
fn claude_http_error(status: reqwest::StatusCode, body: &str) -> String {
    if let Some(message) = extract_api_error_message(body) {
        return format!("HTTP {status}: {message}");
    }
    format!("HTTP {status}: {body}")
}

fn extract_api_error_message(body: &str) -> Option<String> {
    fn message_from_value(value: &Value) -> Option<String> {
        value
            .get("error")
            .and_then(|error| error.get("message"))
            .and_then(Value::as_str)
            .map(str::to_string)
    }
    if let Ok(value) = serde_json::from_str::<Value>(body) {
        if let Some(message) = message_from_value(&value) {
            return Some(message);
        }
    }
    body.lines()
        .filter_map(|line| line.strip_prefix("data:"))
        .filter_map(|payload| serde_json::from_str::<Value>(payload.trim()).ok())
        .find_map(|value| message_from_value(&value))
}

#[derive(Default)]
struct ClaudeStreamDelta {
    content_delta: String,
    reasoning_delta: String,
}

#[derive(Default)]
struct ClaudeStreamAccumulator {
    content: String,
    reasoning_content: String,
    tool_calls: Vec<AiToolCall>,
    /// 每个 content_block index 对应的 tool_calls 下标;非 tool_use 块为 None。
    block_tool_calls: Vec<Option<usize>>,
    input_tokens: i32,
    output_tokens: i32,
}

/// 处理单个 SSE 事件,返回需要下发给前端的增量。
/// thinking / text / tool_use 共享 content_block index 序列;
/// tool_use 的参数以 input_json_delta.partial_json 增量拼接,signature_delta 等忽略。
fn apply_claude_stream_event(
    accumulator: &mut ClaudeStreamAccumulator,
    value: &Value,
) -> ClaudeStreamDelta {
    let mut delta = ClaudeStreamDelta::default();
    match value.get("type").and_then(Value::as_str).unwrap_or("") {
        "message_start" => {
            if let Some(usage) = value
                .get("message")
                .and_then(|message| message.get("usage"))
            {
                accumulator.input_tokens = usage
                    .get("input_tokens")
                    .and_then(Value::as_i64)
                    .unwrap_or(0) as i32;
            }
        }
        "content_block_start" => {
            let index = value.get("index").and_then(Value::as_u64).unwrap_or(0) as usize;
            if accumulator.block_tool_calls.len() <= index {
                accumulator.block_tool_calls.resize(index + 1, None);
            }
            let block = value.get("content_block");
            if block
                .and_then(|block| block.get("type"))
                .and_then(Value::as_str)
                == Some("tool_use")
            {
                accumulator.tool_calls.push(AiToolCall {
                    id: block
                        .and_then(|block| block.get("id"))
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_string(),
                    name: block
                        .and_then(|block| block.get("name"))
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_string(),
                    arguments: String::new(),
                });
                accumulator.block_tool_calls[index] = Some(accumulator.tool_calls.len() - 1);
            }
        }
        "content_block_delta" => {
            let index = value.get("index").and_then(Value::as_u64).unwrap_or(0) as usize;
            let Some(delta_value) = value.get("delta") else {
                return delta;
            };
            match delta_value
                .get("type")
                .and_then(Value::as_str)
                .unwrap_or("")
            {
                "thinking_delta" => {
                    if let Some(text) = delta_value.get("thinking").and_then(Value::as_str) {
                        delta.reasoning_delta.push_str(text);
                        accumulator.reasoning_content.push_str(text);
                    }
                }
                "text_delta" => {
                    if let Some(text) = delta_value.get("text").and_then(Value::as_str) {
                        delta.content_delta.push_str(text);
                        accumulator.content.push_str(text);
                    }
                }
                "input_json_delta" => {
                    if let Some(partial) = delta_value.get("partial_json").and_then(Value::as_str) {
                        if let Some(Some(position)) = accumulator.block_tool_calls.get(index) {
                            if let Some(tool_call) = accumulator.tool_calls.get_mut(*position) {
                                tool_call.arguments.push_str(partial);
                            }
                        }
                    }
                }
                _ => {}
            }
        }
        "message_delta" => {
            if let Some(output) = value
                .get("usage")
                .and_then(|usage| usage.get("output_tokens"))
                .and_then(Value::as_i64)
            {
                accumulator.output_tokens = output as i32;
            }
        }
        _ => {}
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
        images: vec![],
        purpose: "memory_tool_chat".to_string(),
        api_log_enabled: request.api_log_enabled,
    }
}

pub async fn fetch_models(
    app_data_dir: &str,
    provider: &AiProvider,
    api_log_enabled: bool,
) -> Result<Vec<AiModel>, String> {
    let url = format!("{}/v1/models", provider.base_url.trim_end_matches('/'));
    let started_at = Instant::now();
    let response = http_client()?
        .get(&url)
        .header("x-api-key", &provider.api_key)
        .header("anthropic-version", "2023-06-01")
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

pub fn build_messages_body(request: &AiChatRequest) -> Value {
    let content = if request.images.is_empty() {
        // Claude 不允许空 user 内容;空输入时补占位空格。
        if request.user_prompt.is_empty() {
            Value::String(" ".to_string())
        } else {
            Value::String(request.user_prompt.clone())
        }
    } else {
        claude_user_content(request)
    };

    let mut body = json!({
        "model": request.model.model_id,
        "system": request.system_prompt,
        "messages": [{
            "role": "user",
            "content": content
        }],
        "max_tokens": 4096
    });
    if request.purpose == STRUCTURED_NOTE_PURPOSE {
        // 结构化日报:约束输出为栏目 JSON。
        body["output_config"] = json!({
            "format": {
                "type": "json_schema",
                "schema": structured_note_schema()
            }
        });
    }
    if disables_thinking(&request.purpose) {
        if let Some(config) = thinking_config(&request.model.model_id, false, "") {
            body["thinking"] = config;
        }
    }
    if temperature_allowed(&request.model.model_id, &request.purpose) {
        body["temperature"] = json!(0.2);
    }
    body
}

/// 与 OpenAI / Gemini 侧一致:结构化日报与日报合并关闭思考,降低成本并避免思考块干扰解析。
fn disables_thinking(purpose: &str) -> bool {
    matches!(purpose, "home_structured_note" | "daily_note_merge")
}

/// 思考开启(显式配置或自适应模型默认开启)时不能自定义 temperature;
/// 仅当思考确定关闭(显式 disabled,或旧模型默认不思考)时才设置 temperature: 0.2。
fn temperature_allowed(model_id: &str, purpose: &str) -> bool {
    if disables_thinking(purpose) {
        thinking_config(model_id, false, "").is_some()
    } else {
        !is_adaptive_thinking_model(model_id)
    }
}

fn claude_user_content(request: &AiChatRequest) -> Value {
    let mut parts = Vec::new();
    if !request.user_prompt.trim().is_empty() {
        parts.push(json!({
            "type": "text",
            "text": request.user_prompt
        }));
    }
    parts.extend(request.images.iter().map(claude_image_part));
    Value::Array(parts)
}

fn claude_image_part(image: &AiImageAttachment) -> Value {
    json!({
        "type": "image",
        "source": {
            "type": "base64",
            "media_type": normalized_image_mime_type(&image.mime_type),
            "data": image.data_base64
        }
    })
}

fn normalized_image_mime_type(mime_type: &str) -> &str {
    let trimmed = mime_type.trim();
    if trimmed.starts_with("image/") {
        trimmed
    } else {
        "image/png"
    }
}

fn messages_url(provider: &AiProvider) -> String {
    let path = if provider.api_path.trim().is_empty() {
        "/v1/messages"
    } else {
        &provider.api_path
    };
    format!(
        "{}/{}",
        provider.base_url.trim_end_matches('/'),
        path.trim_start_matches('/')
    )
}

fn body_to_string(body: &Value) -> String {
    serde_json::to_string_pretty(body).unwrap_or_else(|_| body.to_string())
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

    fn request() -> AiChatRequest {
        AiChatRequest {
            app_data_dir: ".".to_string(),
            provider: AiProvider {
                id: "p".to_string(),
                name: "Claude".to_string(),
                protocol: "claude".to_string(),
                api_key: "key".to_string(),
                base_url: "https://api.anthropic.com".to_string(),
                api_path: "/v1/messages".to_string(),
            },
            model: AiModel {
                model_id: "claude-test".to_string(),
                display_name: "Claude Test".to_string(),
            },
            system_prompt: "system".to_string(),
            user_prompt: "user".to_string(),
            images: vec![],
            purpose: "test".to_string(),
            api_log_enabled: false,
        }
    }

    #[test]
    fn builds_claude_messages_payload() {
        let request = request();

        let body = build_messages_body(&request);
        assert_eq!(body["model"], "claude-test");
        assert_eq!(body["system"], "system");
        assert_eq!(body["messages"][0]["content"], "user");
    }

    #[test]
    fn builds_claude_messages_payload_with_images() {
        let request = AiChatRequest {
            images: vec![AiImageAttachment {
                name: "screen.jpeg".to_string(),
                mime_type: "image/jpeg".to_string(),
                data_base64: "aW1hZ2U=".to_string(),
            }],
            ..request()
        };

        let body = build_messages_body(&request);
        let content = body["messages"][0]["content"].as_array().unwrap();
        assert_eq!(content[0]["type"], "text");
        assert_eq!(content[0]["text"], "user");
        assert_eq!(content[1]["type"], "image");
        assert_eq!(content[1]["source"]["type"], "base64");
        assert_eq!(content[1]["source"]["media_type"], "image/jpeg");
        assert_eq!(content[1]["source"]["data"], "aW1hZ2U=");
    }

    #[test]
    fn builds_messages_body_pads_empty_prompt() {
        let request = AiChatRequest {
            user_prompt: String::new(),
            ..request()
        };

        let body = build_messages_body(&request);
        assert_eq!(body["messages"][0]["content"], " ");
    }

    #[test]
    fn builds_structured_note_body() {
        let request = AiChatRequest {
            purpose: "home_structured_note".to_string(),
            model: AiModel {
                model_id: "claude-haiku-4-5".to_string(),
                display_name: "Haiku".to_string(),
            },
            ..request()
        };

        let body = build_messages_body(&request);
        let format = &body["output_config"]["format"];
        assert_eq!(format["type"], "json_schema");
        assert_eq!(format["schema"]["type"], "object");
        assert_eq!(format["schema"]["additionalProperties"], false);
        assert_eq!(
            format["schema"]["properties"]["sections"]["items"]["additionalProperties"],
            false
        );
        // 结构化日报关闭思考,思考关闭时才允许自定义 temperature。
        assert_eq!(body["thinking"]["type"], "disabled");
        assert_eq!(body["temperature"], 0.2);
    }

    #[test]
    fn structured_note_body_omits_thinking_and_temperature_for_always_on_models() {
        let request = AiChatRequest {
            purpose: "home_structured_note".to_string(),
            model: AiModel {
                model_id: "claude-fable-5".to_string(),
                display_name: "Fable".to_string(),
            },
            ..request()
        };

        let body = build_messages_body(&request);
        assert!(body.get("thinking").is_none());
        assert!(body.get("temperature").is_none());
        assert_eq!(body["output_config"]["format"]["type"], "json_schema");
    }

    #[test]
    fn adaptive_models_do_not_set_temperature_for_regular_purposes() {
        let request = AiChatRequest {
            purpose: "weekly_report".to_string(),
            model: AiModel {
                model_id: "claude-opus-4-8".to_string(),
                display_name: "Opus".to_string(),
            },
            ..request()
        };

        let body = build_messages_body(&request);
        assert!(body.get("thinking").is_none());
        assert!(body.get("temperature").is_none());
    }

    fn memory_request(
        model_id: &str,
        thinking_enabled: bool,
        effort: &str,
    ) -> MemoryToolChatRequest {
        MemoryToolChatRequest {
            app_data_dir: ".".to_string(),
            provider: AiProvider {
                id: "p".to_string(),
                name: "Claude".to_string(),
                protocol: "claude".to_string(),
                api_key: "key".to_string(),
                base_url: "https://api.anthropic.com".to_string(),
                api_path: "/v1/messages".to_string(),
            },
            model: AiModel {
                model_id: model_id.to_string(),
                display_name: model_id.to_string(),
            },
            messages: vec![AiChatMessage {
                role: "user".to_string(),
                content: "今天做了什么?".to_string(),
                reasoning_content: String::new(),
                tool_call_id: String::new(),
                tool_calls: vec![],
            }],
            thinking_enabled,
            reasoning_effort: effort.to_string(),
            api_log_enabled: false,
        }
    }

    #[test]
    fn builds_memory_tool_body_with_tools_and_budget_thinking() {
        let request = memory_request("claude-haiku-4-5", true, "medium");

        let body = build_memory_tool_body(&request, "system");
        assert_eq!(body["model"], "claude-haiku-4-5");
        assert_eq!(body["max_tokens"], 16384);
        assert_eq!(body["system"], "system");
        assert_eq!(body["tool_choice"]["type"], "auto");
        assert_eq!(body["thinking"]["type"], "enabled");
        assert_eq!(body["thinking"]["budget_tokens"], 4096);
        assert_eq!(body["thinking"]["display"], "summarized");
        // 思考开启时不能自定义 temperature。
        assert!(body.get("temperature").is_none());

        let tools = body["tools"].as_array().unwrap();
        assert_eq!(tools.len(), 10);
        let keyword_search = tools
            .iter()
            .find(|tool| tool["name"] == "keyword_search")
            .unwrap();
        assert!(keyword_search.get("description").is_some());
        // 非严格模式的 input_schema 保留 minItems / maxItems 等约束,不带 strict 包装。
        let keywords = &keyword_search["input_schema"]["properties"]["keywords"];
        assert_eq!(keywords["minItems"], 1);
        assert_eq!(keywords["maxItems"], 8);
        assert!(keyword_search.get("strict").is_none());
        assert!(keyword_search.get("type").is_none());
    }

    #[test]
    fn memory_tool_body_uses_adaptive_thinking_for_new_models() {
        for model_id in [
            "claude-opus-4-8",
            "claude-opus-4-7",
            "claude-sonnet-5",
            "claude-sonnet-4-6",
        ] {
            let request = memory_request(model_id, true, "high");
            let body = build_memory_tool_body(&request, "system");
            assert_eq!(body["thinking"]["type"], "adaptive", "{model_id}");
            assert_eq!(body["thinking"]["display"], "summarized", "{model_id}");
            assert!(
                body["thinking"].get("budget_tokens").is_none(),
                "{model_id}"
            );
            // 自适应思考的深度由 output_config.effort 引导。
            assert_eq!(body["output_config"]["effort"], "high", "{model_id}");
        }

        let request = memory_request("claude-opus-4-8", true, "max");
        let body = build_memory_tool_body(&request, "system");
        assert_eq!(body["output_config"]["effort"], "max");
    }

    #[test]
    fn memory_tool_body_disables_thinking_with_temperature() {
        let request = memory_request("claude-haiku-4-5", false, "high");

        let body = build_memory_tool_body(&request, "system");
        assert_eq!(body["thinking"]["type"], "disabled");
        assert_eq!(body["temperature"], 0.2);
    }

    #[test]
    fn memory_tool_body_omits_thinking_for_always_on_models() {
        let request = memory_request("claude-mythos-5", false, "low");

        let body = build_memory_tool_body(&request, "system");
        assert!(body.get("thinking").is_none());
        assert!(body.get("temperature").is_none());
    }

    #[test]
    fn converts_history_with_tool_use_and_tool_results() {
        let mut request = memory_request("claude-haiku-4-5", false, "");
        request.messages = vec![
            AiChatMessage {
                role: "user".to_string(),
                content: "查一下今天的日报".to_string(),
                reasoning_content: String::new(),
                tool_call_id: String::new(),
                tool_calls: vec![],
            },
            AiChatMessage {
                role: "assistant".to_string(),
                content: "我来查一下。".to_string(),
                reasoning_content: "应该先读日报".to_string(),
                tool_call_id: String::new(),
                tool_calls: vec![
                    AiToolCall {
                        id: "toolu_01".to_string(),
                        name: "read_daily_note".to_string(),
                        arguments: "{\"date\":\"2026-07-18\"}".to_string(),
                    },
                    AiToolCall {
                        id: "toolu_02".to_string(),
                        name: "get_current_date".to_string(),
                        arguments: "not json".to_string(),
                    },
                ],
            },
            AiChatMessage {
                role: "tool".to_string(),
                content: "# 2026-07-18 日报".to_string(),
                reasoning_content: String::new(),
                tool_call_id: "toolu_01".to_string(),
                tool_calls: vec![],
            },
            AiChatMessage {
                role: "tool".to_string(),
                content: "2026-07-18".to_string(),
                reasoning_content: String::new(),
                tool_call_id: "toolu_02".to_string(),
                tool_calls: vec![],
            },
        ];

        let messages = claude_messages(&request.messages);
        assert_eq!(messages.len(), 3);

        let assistant_blocks = messages[1]["content"].as_array().unwrap();
        assert_eq!(assistant_blocks[0]["type"], "text");
        assert_eq!(assistant_blocks[1]["type"], "tool_use");
        assert_eq!(assistant_blocks[1]["id"], "toolu_01");
        assert_eq!(assistant_blocks[1]["input"]["date"], "2026-07-18");
        assert_eq!(assistant_blocks[2]["type"], "tool_use");
        // 非法 JSON 参数回退为空对象。
        assert_eq!(assistant_blocks[2]["input"], json!({}));
        // 思考摘要无法带回历史,直接省略。
        assert!(
            assistant_blocks
                .iter()
                .all(|block| block["type"] != "thinking")
        );

        // 连续 tool 消息合并为一条 user 消息,content 全为 tool_result 块(位于最前)。
        let tool_result_blocks = messages[2]["content"].as_array().unwrap();
        assert_eq!(messages[2]["role"], "user");
        assert_eq!(tool_result_blocks.len(), 2);
        assert_eq!(tool_result_blocks[0]["type"], "tool_result");
        assert_eq!(tool_result_blocks[0]["tool_use_id"], "toolu_01");
        assert_eq!(tool_result_blocks[0]["content"], "# 2026-07-18 日报");
        assert_eq!(tool_result_blocks[1]["tool_use_id"], "toolu_02");
    }

    #[test]
    fn parses_response_with_thinking_and_tool_use() {
        let value = json!({
            "content": [
                {"type": "thinking", "thinking": "先想想", "signature": "sig"},
                {"type": "text", "text": "我去查一下"},
                {"type": "tool_use", "id": "toolu_01", "name": "keyword_search", "input": {"keywords": ["日报"]}}
            ],
            "usage": {"input_tokens": 120, "output_tokens": 45}
        });

        let blocks = content_blocks(&value);
        assert_eq!(blocks_text(&blocks, false), "我去查一下");
        assert_eq!(blocks_text(&blocks, true), "先想想");
        let tool_calls = blocks_tool_calls(&blocks);
        assert_eq!(tool_calls.len(), 1);
        assert_eq!(tool_calls[0].id, "toolu_01");
        assert_eq!(tool_calls[0].name, "keyword_search");
        assert_eq!(tool_calls[0].arguments, "{\"keywords\":[\"日报\"]}");
        assert_eq!(usage_from_value(&value), (120, 45, 0));
    }

    #[test]
    fn extract_chat_text_skips_thinking_blocks() {
        let value = json!({
            "content": [
                {"type": "thinking", "thinking": "摘要", "signature": "sig"},
                {"type": "text", "text": "正式回答"}
            ]
        });
        assert_eq!(extract_chat_text(&value).as_deref(), Some("正式回答"));

        // 无 text 块时兜底取 content[0].text,兼容旧行为。
        let legacy = json!({"content": [{"text": "旧格式"}]});
        assert_eq!(extract_chat_text(&legacy).as_deref(), Some("旧格式"));
    }

    #[test]
    fn accumulates_stream_events() {
        let mut accumulator = ClaudeStreamAccumulator::default();

        apply_claude_stream_event(
            &mut accumulator,
            &json!({"type": "message_start", "message": {"usage": {"input_tokens": 321, "output_tokens": 1}}}),
        );
        apply_claude_stream_event(
            &mut accumulator,
            &json!({"type": "content_block_start", "index": 0, "content_block": {"type": "thinking", "thinking": "", "signature": ""}}),
        );
        let delta = apply_claude_stream_event(
            &mut accumulator,
            &json!({"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": "思考一下"}}),
        );
        assert_eq!(delta.reasoning_delta, "思考一下");
        assert!(delta.content_delta.is_empty());
        apply_claude_stream_event(
            &mut accumulator,
            &json!({"type": "content_block_delta", "index": 0, "delta": {"type": "signature_delta", "signature": "sig"}}),
        );
        apply_claude_stream_event(
            &mut accumulator,
            &json!({"type": "content_block_start", "index": 1, "content_block": {"type": "tool_use", "id": "toolu_01", "name": "keyword_search"}}),
        );
        apply_claude_stream_event(
            &mut accumulator,
            &json!({"type": "content_block_delta", "index": 1, "delta": {"type": "input_json_delta", "partial_json": "{\"keywords\":"}}),
        );
        apply_claude_stream_event(
            &mut accumulator,
            &json!({"type": "content_block_delta", "index": 1, "delta": {"type": "input_json_delta", "partial_json": "[\"日报\"]}"}}),
        );
        apply_claude_stream_event(
            &mut accumulator,
            &json!({"type": "content_block_start", "index": 2, "content_block": {"type": "text", "text": ""}}),
        );
        let delta = apply_claude_stream_event(
            &mut accumulator,
            &json!({"type": "content_block_delta", "index": 2, "delta": {"type": "text_delta", "text": "答案"}}),
        );
        assert_eq!(delta.content_delta, "答案");
        apply_claude_stream_event(
            &mut accumulator,
            &json!({"type": "message_delta", "delta": {"stop_reason": "tool_use"}, "usage": {"output_tokens": 88}}),
        );

        assert_eq!(accumulator.content, "答案");
        assert_eq!(accumulator.reasoning_content, "思考一下");
        assert_eq!(accumulator.input_tokens, 321);
        assert_eq!(accumulator.output_tokens, 88);
        assert_eq!(accumulator.tool_calls.len(), 1);
        assert_eq!(accumulator.tool_calls[0].id, "toolu_01");
        assert_eq!(accumulator.tool_calls[0].name, "keyword_search");
        assert_eq!(
            accumulator.tool_calls[0].arguments,
            "{\"keywords\":[\"日报\"]}"
        );
    }

    #[test]
    fn sse_parser_splits_frames_across_chunks() {
        let mut parser = SseParser::default();
        assert!(
            parser
                .push("event: message_start\ndata: {\"type\":\"message")
                .is_empty()
        );
        let payloads = parser.push("_start\"}\n\ndata: {\"type\":\"ping\"}\n\n");
        assert_eq!(payloads.len(), 2);
        assert_eq!(payloads[0], "{\"type\":\"message_start\"}");
        assert_eq!(payloads[1], "{\"type\":\"ping\"}");
    }
}
