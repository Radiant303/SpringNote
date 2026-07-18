use crate::ai::{
    AiChatMessage, AiChatRequest, AiImageAttachment, AiModel, AiProvider, AiTextResult, AiToolCall,
    MemoryToolChatRequest, MemoryToolChatResult, MemoryToolChatStreamEvent, extract_text,
    http_client, http_stream_client, usage_from_value,
};
use crate::ai_log::{ApiNetworkLog, write_api_network_log};
use crate::frb_generated::StreamSink;
use crate::{ai_openai, stats};
use serde_json::{Value, json};
use std::collections::HashMap;
use std::time::Instant;

/// 结构化日报用途标识;该用途在 generateContent 上附加 responseSchema 约束输出 JSON。
const STRUCTURED_NOTE_PURPOSE: &str = "home_structured_note";
/// 老接口多数模型不返回函数调用 id,解析时用此前缀生成占位 id;占位 id 不会回传给 API。
const GENERATED_CALL_ID_PREFIX: &str = "gemini_call_";

pub async fn chat(request: &AiChatRequest) -> Result<AiTextResult, String> {
    let url = generate_content_url(&request.provider, &request.model.model_id);
    let body = build_generate_content_body(request);
    let request_body = body_to_string(&body);
    let started_at = Instant::now();
    let response = http_client()?
        .post(&url)
        .header("x-goog-api-key", &request.provider.api_key)
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

    let content = extract_chat_text(&value)
        .ok_or_else(|| "Gemini response missing candidates[0].content.parts text".to_string())?;
    let (input, output, cached) = usage_from_value(&value);
    Ok(AiTextResult::success(
        request, content, input, output, cached,
    ))
}

// ---------------------------------------------------------------------------
// Gemini generateContent API(老接口)
//
// 以下能力基于 generateContent / streamGenerateContent 实现:
// - 函数调用:tools.functionDeclarations 声明;candidates parts 中的 functionCall,
//   历史以 functionResponse parts 回传;流式时函数调用随块完整到达
// - 思考模式:generationConfig.thinkingConfig(Gemini 3 及之后用 thinkingLevel,
//   更早模型用 thinkingBudget),parts 中 thought = true 的文本映射为推理内容
// - 结构化输出:generationConfig.responseMimeType + responseSchema
// ---------------------------------------------------------------------------

/// 回忆书问答(非流式):函数调用 + 思考模式,走 generateContent。
pub async fn memory_tool_chat(
    request: &MemoryToolChatRequest,
    system_prompt: &str,
) -> Result<MemoryToolChatResult, String> {
    let log_request = memory_as_chat_request(request, system_prompt);
    let url = generate_content_url(&request.provider, &request.model.model_id);
    let body = build_memory_tool_body(request, system_prompt);
    let value = post_generate_content(&log_request, &url, &body).await?;
    let parts = candidate_parts(&value);
    let content = parts_text(&parts, false);
    let reasoning_content = parts_text(&parts, true);
    let mut generated_call_ids = 0;
    let tool_calls = parts_tool_calls(&parts, &mut generated_call_ids);
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

/// 回忆书问答(流式):streamGenerateContent?alt=sse,函数调用随块完整到达。
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

    let url = stream_generate_content_url(&request.provider, &request.model.model_id);
    let body = build_memory_tool_body(&request, system_prompt);
    let request_body = body_to_string(&body);
    let started_at = Instant::now();
    let response = http_stream_client()?
        .post(&url)
        .header("x-goog-api-key", &request.provider.api_key)
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
        let message = gemini_http_error(status, &response_body);
        let _ = sink.add(MemoryToolChatStreamEvent::error("request_failed", &message));
        return Ok(());
    }

    let mut response = response;
    let mut parser = SseParser::default();
    let mut raw_response = String::new();
    let mut accumulator = GeminiStreamAccumulator::default();
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
            if let Some(message) = value
                .get("error")
                .and_then(|error| error.get("message"))
                .and_then(Value::as_str)
                .map(str::to_string)
            {
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
            let delta = apply_gemini_stream_chunk(&mut accumulator, &value);
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
    let tool_calls = accumulator.tool_calls;
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
    stats::record_model_call_or_warn(
        "memory_tool_gemini_stream",
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
        cached_tokens,
    });
    Ok(())
}

/// 发送一次非流式 generateContent 请求并写网络日志,返回解析后的响应 JSON。
async fn post_generate_content(
    log_request: &AiChatRequest,
    url: &str,
    body: &Value,
) -> Result<Value, String> {
    let request_body = body_to_string(body);
    let started_at = Instant::now();
    let response = http_client()?
        .post(url)
        .header("x-goog-api-key", &log_request.provider.api_key)
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
        return Err(gemini_http_error(status, &response_body));
    }
    serde_json::from_str::<Value>(&response_body).map_err(|error| error.to_string())
}

/// 回忆书工具调用的 generateContent 请求体;流式仅换用 streamGenerateContent 端点,请求体相同。
pub fn build_memory_tool_body(request: &MemoryToolChatRequest, system_prompt: &str) -> Value {
    json!({
        "systemInstruction": {
            "parts": [{"text": system_prompt}]
        },
        "contents": memory_contents(&request.messages),
        "tools": gemini_memory_tools(),
        "toolConfig": {
            "functionCallingConfig": {"mode": "AUTO"}
        },
        "generationConfig": memory_generation_config(request),
    })
}

/// 思考配置:Gemini 3 用 thinkingLevel,2.5 及更早模型用 thinkingBudget;
/// includeThoughts 控制响应中是否携带思考摘要。
fn memory_generation_config(request: &MemoryToolChatRequest) -> Value {
    json!({
        "temperature": 0.2,
        "thinkingConfig": thinking_config(
            &request.model.model_id,
            request.thinking_enabled,
            &request.reasoning_effort
        )
    })
}

fn thinking_config(model_id: &str, enabled: bool, effort: &str) -> Value {
    let mut config = json!({"includeThoughts": enabled});
    if uses_thinking_level(model_id) {
        // thinkingLevel 各模型支持档位不一,关闭时取该模型的最低档。
        let level = if enabled {
            normalize_thinking_level(model_id, effort)
        } else {
            min_thinking_level(model_id)
        };
        config["thinkingLevel"] = json!(level);
    } else {
        let budget = if enabled {
            thinking_budget(effort)
        } else if model_id.contains("-pro") {
            // 2.5 Pro 无法完全关闭思考,预算最低 128。
            128
        } else {
            0
        };
        config["thinkingBudget"] = json!(budget);
    }
    config
}

/// thinkingLevel 适用于 Gemini 3 及之后的主版本(更早版本传了会报错);
/// 更早模型用 thinkingBudget。
fn uses_thinking_level(model_id: &str) -> bool {
    gemini_major_version(model_id).is_some_and(|major| major >= 3)
}

/// 从模型 id 解析主版本号:gemini-3.5-pro → 3,gemini-4.0-flash → 4;
/// 无法解析(如 *-latest 别名)时返回 None,按更早模型处理。
fn gemini_major_version(model_id: &str) -> Option<u32> {
    let id = model_id.to_ascii_lowercase();
    let id = id.trim_start_matches("models/");
    let rest = id
        .strip_prefix("gemini-")
        .or_else(|| id.strip_prefix("gemini"))?;
    let major: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
    major.parse().ok()
}

/// 各 Gemini 3 模型的最低 thinkingLevel;Gemini 3 无法完全关闭思考,禁用思考时取最低档。
/// flash-lite 系列仅支持 MINIMAL / HIGH,其余(3 Pro、3 Flash)最低 LOW。
fn min_thinking_level(model_id: &str) -> &str {
    if model_id.to_ascii_lowercase().contains("flash-lite") {
        "MINIMAL"
    } else {
        "LOW"
    }
}

/// thinkingBudget 档位:high / max 交给模型动态分配(-1),其余给固定预算。
fn thinking_budget(effort: &str) -> i32 {
    match effort {
        "minimal" | "none" | "low" => 1024,
        "medium" => 4096,
        _ => -1,
    }
}

/// 按模型支持的档位映射思考等级:flash-lite 系列仅 MINIMAL / HIGH;
/// 3 Pro 仅 LOW / HIGH;3 Flash 等支持 MINIMAL / LOW / MEDIUM / HIGH 全部四档。
fn normalize_thinking_level(model_id: &str, effort: &str) -> &'static str {
    let id = model_id.to_ascii_lowercase();
    if id.contains("flash-lite") {
        match effort {
            "minimal" | "none" | "low" => "MINIMAL",
            _ => "HIGH",
        }
    } else if id.contains("-pro") {
        match effort {
            "minimal" | "none" | "low" => "LOW",
            _ => "HIGH",
        }
    } else {
        match effort {
            "minimal" | "none" => "MINIMAL",
            "low" => "LOW",
            "medium" => "MEDIUM",
            _ => "HIGH",
        }
    }
}

/// 把应用内消息历史转成老接口 contents。
/// functionResponse 按名称匹配调用,name 从前一条 assistant 消息的工具调用中按 call_id 反查;
/// 连续的 tool 消息合并为同一个 user content 的多个 functionResponse parts。
/// 思考摘要/thoughtSignature 无法在历史中保存与带回,按老接口惯例省略;
/// Gemini 3 模型在无签名时可能拒绝含 functionCall 的历史,这是老接口的已知限制。
fn memory_contents(messages: &[AiChatMessage]) -> Vec<Value> {
    let mut contents = Vec::new();
    let mut tool_names_by_id: HashMap<String, String> = HashMap::new();
    let mut index = 0;
    while index < messages.len() {
        let message = &messages[index];
        match message.role.as_str() {
            "assistant" => {
                let mut parts = Vec::new();
                if !message.content.trim().is_empty() {
                    parts.push(json!({"text": message.content}));
                }
                for tool_call in &message.tool_calls {
                    tool_names_by_id.insert(tool_call.id.clone(), tool_call.name.clone());
                    let mut call = json!({
                        "name": tool_call.name,
                        "args": parse_tool_arguments(&tool_call.arguments)
                    });
                    if !tool_call.id.is_empty()
                        && !tool_call.id.starts_with(GENERATED_CALL_ID_PREFIX)
                    {
                        call["id"] = json!(tool_call.id);
                    }
                    parts.push(json!({"functionCall": call}));
                }
                if !parts.is_empty() {
                    contents.push(json!({"role": "model", "parts": parts}));
                }
                index += 1;
            }
            "tool" => {
                let mut parts = Vec::new();
                while index < messages.len() && messages[index].role == "tool" {
                    let tool = &messages[index];
                    let name = tool_names_by_id
                        .get(tool.tool_call_id.trim())
                        .cloned()
                        .unwrap_or_default();
                    parts.push(json!({
                        "functionResponse": {
                            "name": name,
                            "response": tool_response_object(&tool.content)
                        }
                    }));
                    index += 1;
                }
                contents.push(json!({"role": "user", "parts": parts}));
            }
            _ => {
                contents.push(json!({
                    "role": "user",
                    "parts": [{"text": message.content}]
                }));
                index += 1;
            }
        }
    }
    contents
}

/// functionCall 的 args 必须是 JSON 对象;历史中的字符串参数解析失败时回退为空对象。
fn parse_tool_arguments(arguments: &str) -> Value {
    serde_json::from_str::<Value>(arguments)
        .ok()
        .filter(|value| value.is_object())
        .unwrap_or_else(|| json!({}))
}

/// functionResponse.response 必须是 JSON 对象;工具结果本身是 JSON 对象时直接使用,
/// 否则按惯例包一层 {"result": ...}。
fn tool_response_object(content: &str) -> Value {
    serde_json::from_str::<Value>(content)
        .ok()
        .filter(|value| value.is_object())
        .unwrap_or_else(|| json!({"result": content}))
}

/// 复用 OpenAI 侧的回忆书工具定义,转换为老接口 functionDeclarations 声明格式。
fn gemini_memory_tools() -> Value {
    let declarations = ai_openai::memory_tools_json()
        .as_array()
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|item| {
            let function = item.get("function")?;
            Some(json!({
                "name": function.get("name").cloned().unwrap_or(Value::String(String::new())),
                "description": function.get("description").cloned().unwrap_or(Value::String(String::new())),
                "parameters": classic_schema(
                    &function
                        .get("parameters")
                        .cloned()
                        .unwrap_or_else(|| json!({"type": "object", "properties": {}}))
                )
            }))
        })
        .collect::<Vec<_>>();
    json!([{"functionDeclarations": declarations}])
}

/// 老接口 Schema:type 枚举必须大写,且只保留官方 Schema 子集内的字段。
fn classic_schema(value: &Value) -> Value {
    uppercase_schema_types(&sanitize_schema_subset(value))
}

/// 老接口只支持官方 Schema 子集(REST 参考中的 Schema 资源),
/// 递归按白名单保留字段;additionalProperties 等不在子集内的关键字必须移除,
/// 否则 API 会以 400 拒绝整个请求。
/// 注意 properties 的键是业务属性名而非 Schema 关键字,必须全部保留。
fn sanitize_schema_subset(value: &Value) -> Value {
    const SUPPORTED_KEYS: &[&str] = &[
        "anyOf",
        "default",
        "description",
        "enum",
        "example",
        "format",
        "items",
        "maxItems",
        "maxLength",
        "maxProperties",
        "maximum",
        "minItems",
        "minLength",
        "minProperties",
        "minimum",
        "nullable",
        "pattern",
        "properties",
        "propertyOrdering",
        "required",
        "title",
        "type",
    ];
    match value {
        Value::Object(map) => {
            let mut sanitized = serde_json::Map::new();
            for (key, item) in map {
                if !SUPPORTED_KEYS.contains(&key.as_str()) {
                    continue;
                }
                if key == "properties" {
                    if let Value::Object(properties) = item {
                        let properties = properties
                            .iter()
                            .map(|(name, schema)| (name.clone(), sanitize_schema_subset(schema)))
                            .collect();
                        sanitized.insert(key.clone(), Value::Object(properties));
                        continue;
                    }
                    sanitized.insert(key.clone(), item.clone());
                    continue;
                }
                sanitized.insert(key.clone(), sanitize_schema_subset(item));
            }
            Value::Object(sanitized)
        }
        Value::Array(items) => Value::Array(items.iter().map(sanitize_schema_subset).collect()),
        _ => value.clone(),
    }
}

/// 递归把 Schema 中的 type 值转为老接口要求的大写枚举(如 object -> OBJECT)。
fn uppercase_schema_types(value: &Value) -> Value {
    match value {
        Value::Object(map) => Value::Object(
            map.iter()
                .map(|(key, item)| {
                    let item = if key == "type" {
                        item.as_str()
                            .map(|text| json!(text.to_ascii_uppercase()))
                            .unwrap_or_else(|| item.clone())
                    } else {
                        uppercase_schema_types(item)
                    };
                    (key.clone(), item)
                })
                .collect(),
        ),
        Value::Array(items) => Value::Array(items.iter().map(uppercase_schema_types).collect()),
        _ => value.clone(),
    }
}

/// 与 Rust 侧 parse_structured_note 解析逻辑匹配的输出 Schema(老接口枚举大写)。
fn structured_note_schema() -> Value {
    json!({
        "type": "OBJECT",
        "properties": {
            "sections": {
                "type": "ARRAY",
                "description": "Structured note sections. Every configured section id must appear exactly once.",
                "items": {
                    "type": "OBJECT",
                    "properties": {
                        "id": {
                            "type": "STRING",
                            "description": "The configured section id."
                        },
                        "items": {
                            "type": "ARRAY",
                            "description": "Bullet items for this section; empty when nothing was recorded.",
                            "items": {"type": "STRING"}
                        }
                    },
                    "required": ["id", "items"]
                }
            }
        },
        "required": ["sections"]
    })
}

/// 取出 candidates[0].content.parts;无候选时返回空数组。
fn candidate_parts(value: &Value) -> Vec<Value> {
    value
        .get("candidates")
        .and_then(Value::as_array)
        .and_then(|candidates| candidates.first())
        .and_then(|candidate| candidate.get("content"))
        .and_then(|content| content.get("parts"))
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

/// 从 generateContent 响应中取正式回答:跳过 thought = true 的思考 parts,
/// 拼接其余文本 parts(思考模型的正式回答可能不在 parts[0]);
/// 全部缺失时兜底取首个文本 part,兼容旧行为。
fn extract_chat_text(value: &Value) -> Option<String> {
    let parts = candidate_parts(value);
    let content = parts_text(&parts, false);
    if !content.is_empty() {
        return Some(content);
    }
    extract_text(
        value,
        &[&["candidates", "0", "content", "parts", "0", "text"]],
    )
}

/// 拼接 parts 中的文本;thought = true 取思考摘要,否则取正式回答。
fn parts_text(parts: &[Value], thought: bool) -> String {
    let separator = if thought { "\n" } else { "" };
    parts
        .iter()
        .filter(|part| {
            part.get("thought")
                .and_then(Value::as_bool)
                .unwrap_or(false)
                == thought
        })
        .filter_map(|part| part.get("text").and_then(Value::as_str))
        .collect::<Vec<_>>()
        .join(separator)
}

/// 提取 parts 中的 functionCall;args 序列化为 JSON 字符串,缺失 id 时生成占位 id。
fn parts_tool_calls(parts: &[Value], generated_call_ids: &mut usize) -> Vec<AiToolCall> {
    parts
        .iter()
        .filter_map(|part| part.get("functionCall"))
        .map(|call| {
            let id = call
                .get("id")
                .and_then(Value::as_str)
                .filter(|id| !id.is_empty())
                .map(str::to_string)
                .unwrap_or_else(|| {
                    *generated_call_ids += 1;
                    format!("{GENERATED_CALL_ID_PREFIX}{generated_call_ids}")
                });
            AiToolCall {
                id,
                name: call
                    .get("name")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_string(),
                arguments: call
                    .get("args")
                    .map(|args| serde_json::to_string(args).unwrap_or_else(|_| "{}".to_string()))
                    .unwrap_or_else(|| "{}".to_string()),
            }
        })
        .filter(|tool_call| !tool_call.name.is_empty())
        .collect()
}

/// 组装非 2xx 响应的错误文本;优先提取 API 返回的错误消息,
/// 兼容普通 JSON 错误与 SSE error 事件两种响应形态。
fn gemini_http_error(status: reqwest::StatusCode, body: &str) -> String {
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
struct GeminiStreamDelta {
    content_delta: String,
    reasoning_delta: String,
}

#[derive(Default)]
struct GeminiStreamAccumulator {
    content: String,
    reasoning_content: String,
    tool_calls: Vec<AiToolCall>,
    generated_call_ids: usize,
    input_tokens: i32,
    output_tokens: i32,
    cached_tokens: i32,
}

/// 处理单个流式响应块,返回需要下发给前端的增量。
/// 老接口的函数调用随块完整到达,不需要拼接参数增量。
fn apply_gemini_stream_chunk(
    accumulator: &mut GeminiStreamAccumulator,
    value: &Value,
) -> GeminiStreamDelta {
    let mut delta = GeminiStreamDelta::default();
    for part in candidate_parts(value) {
        if part.get("functionCall").is_some() {
            let mut calls = parts_tool_calls(&[part], &mut accumulator.generated_call_ids);
            accumulator.tool_calls.append(&mut calls);
            continue;
        }
        let is_thought = part
            .get("thought")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        if let Some(text) = part.get("text").and_then(Value::as_str) {
            if is_thought {
                delta.reasoning_delta.push_str(text);
                accumulator.reasoning_content.push_str(text);
            } else {
                delta.content_delta.push_str(text);
                accumulator.content.push_str(text);
            }
        }
    }
    if value.get("usageMetadata").is_some() {
        let (input, output, cached) = usage_from_value(value);
        accumulator.input_tokens = input;
        accumulator.output_tokens = output;
        accumulator.cached_tokens = cached;
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
    let url = format!("{}/v1beta/models", provider.base_url.trim_end_matches('/'));
    let started_at = Instant::now();
    let response = http_client()?
        .get(&url)
        .header("x-goog-api-key", &provider.api_key)
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
        .get("models")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.get("name").and_then(Value::as_str))
                .map(|name| {
                    let id = name.trim_start_matches("models/").to_string();
                    AiModel {
                        display_name: id.clone(),
                        model_id: id,
                    }
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    Ok(models)
}

pub fn build_generate_content_body(request: &AiChatRequest) -> Value {
    let mut parts = Vec::new();
    if !request.user_prompt.trim().is_empty() {
        parts.push(json!({"text": request.user_prompt}));
    }
    parts.extend(request.images.iter().map(gemini_image_part));
    if parts.is_empty() {
        // Gemini 不允许空 text part(oneof data 必须有值);空输入时补占位空格。
        parts.push(json!({"text": " "}));
    }

    let mut generation_config = json!({"temperature": 0.2});
    if request.purpose == STRUCTURED_NOTE_PURPOSE {
        // 结构化日报:约束输出为栏目 JSON。
        generation_config["responseMimeType"] = json!("application/json");
        generation_config["responseSchema"] = structured_note_schema();
    }
    if disables_thinking(&request.purpose) {
        generation_config["thinkingConfig"] = thinking_config(&request.model.model_id, false, "");
    }

    json!({
        "systemInstruction": {
            "parts": [{"text": request.system_prompt}]
        },
        "contents": [{
            "role": "user",
            "parts": parts
        }],
        "generationConfig": generation_config
    })
}

/// 与 OpenAI 侧一致:结构化日报与日报合并关闭思考,降低成本并避免思考 parts 干扰解析。
fn disables_thinking(purpose: &str) -> bool {
    matches!(purpose, "home_structured_note" | "daily_note_merge")
}

fn gemini_image_part(image: &AiImageAttachment) -> Value {
    json!({
        "inline_data": {
            "mime_type": normalized_image_mime_type(&image.mime_type),
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

fn generate_content_url(provider: &AiProvider, model_id: &str) -> String {
    format!(
        "{}/v1beta/models/{}:generateContent",
        provider.base_url.trim_end_matches('/'),
        model_id
    )
}

fn stream_generate_content_url(provider: &AiProvider, model_id: &str) -> String {
    format!(
        "{}/v1beta/models/{}:streamGenerateContent?alt=sse",
        provider.base_url.trim_end_matches('/'),
        model_id
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
                name: "Google".to_string(),
                protocol: "gemini".to_string(),
                api_key: "key".to_string(),
                base_url: "https://generativelanguage.googleapis.com".to_string(),
                api_path: String::new(),
            },
            model: AiModel {
                model_id: "gemini-test".to_string(),
                display_name: "Gemini Test".to_string(),
            },
            system_prompt: "system".to_string(),
            user_prompt: "user".to_string(),
            images: vec![],
            purpose: "test".to_string(),
            api_log_enabled: false,
        }
    }

    #[test]
    fn builds_gemini_payload() {
        let request = request();

        let body = build_generate_content_body(&request);
        assert_eq!(body["systemInstruction"]["parts"][0]["text"], "system");
        assert_eq!(body["contents"][0]["parts"][0]["text"], "user");
    }

    #[test]
    fn builds_gemini_payload_with_images() {
        let request = AiChatRequest {
            images: vec![AiImageAttachment {
                name: "screen.webp".to_string(),
                mime_type: "image/webp".to_string(),
                data_base64: "aW1hZ2U=".to_string(),
            }],
            ..request()
        };

        let body = build_generate_content_body(&request);
        let parts = body["contents"][0]["parts"].as_array().unwrap();
        assert_eq!(parts[0]["text"], "user");
        assert_eq!(parts[1]["inline_data"]["mime_type"], "image/webp");
        assert_eq!(parts[1]["inline_data"]["data"], "aW1hZ2U=");
    }

    #[test]
    fn builds_gemini_payload_with_empty_user_prompt() {
        // 日报合并的 user prompt 为空;Gemini 拒绝空 text part,必须补占位。
        let request = AiChatRequest {
            user_prompt: String::new(),
            purpose: "daily_note_merge".to_string(),
            ..request()
        };

        let body = build_generate_content_body(&request);
        let parts = body["contents"][0]["parts"].as_array().unwrap();
        assert_eq!(parts.len(), 1);
        assert_eq!(parts[0]["text"], " ");
        // 日报合并关闭思考,但不携带结构化输出配置。
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["includeThoughts"],
            false
        );
        assert!(body["generationConfig"].get("responseMimeType").is_none());
    }

    #[test]
    fn extracts_answer_text_after_thought_parts() {
        // 思考模型的响应里 parts[0] 是 thought = true 的摘要,正式回答在后面的 part。
        let value = json!({
            "candidates": [{
                "content": {
                    "role": "model",
                    "parts": [
                        {"thought": true, "text": "让我思考一下"},
                        {"thoughtSignature": "sig", "text": "{\"sections\":[]}"}
                    ]
                }
            }]
        });

        assert_eq!(extract_chat_text(&value).unwrap(), "{\"sections\":[]}");
    }

    #[test]
    fn builds_gemini_url() {
        let provider = AiProvider {
            id: "p".to_string(),
            name: "Google".to_string(),
            protocol: "gemini".to_string(),
            api_key: "key".to_string(),
            base_url: "https://generativelanguage.googleapis.com/".to_string(),
            api_path: String::new(),
        };

        assert_eq!(
            generate_content_url(&provider, "gemini-test"),
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent"
        );
    }

    fn memory_request() -> MemoryToolChatRequest {
        MemoryToolChatRequest {
            app_data_dir: ".".to_string(),
            provider: AiProvider {
                id: "p".to_string(),
                name: "Google".to_string(),
                protocol: "gemini".to_string(),
                api_key: "key".to_string(),
                base_url: "https://generativelanguage.googleapis.com".to_string(),
                api_path: String::new(),
            },
            model: AiModel {
                model_id: "gemini-test".to_string(),
                display_name: "Gemini Test".to_string(),
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
        }
    }

    #[test]
    fn builds_memory_tool_body_with_function_declarations() {
        let body = build_memory_tool_body(&memory_request(), "system");

        assert_eq!(body["systemInstruction"]["parts"][0]["text"], "system");
        assert_eq!(body["contents"][0]["role"], "user");
        assert_eq!(
            body["contents"][0]["parts"][0]["text"],
            "什么时候删除 nacos 配置？"
        );
        assert_eq!(body["toolConfig"]["functionCallingConfig"]["mode"], "AUTO");
        assert_eq!(body["generationConfig"]["temperature"], 0.2);
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["includeThoughts"],
            true
        );

        let declarations = body["tools"][0]["functionDeclarations"].as_array().unwrap();
        assert_eq!(declarations.len(), 10);
        assert_eq!(declarations[0]["name"], "get_current_date");
        assert!(declarations[0].get("strict").is_none());
        assert_eq!(declarations[1]["name"], "keyword_search");
        // 老接口 Schema 的 type 枚举必须大写。
        assert_eq!(declarations[1]["parameters"]["type"], "OBJECT");
        assert_eq!(
            declarations[1]["parameters"]["properties"]["keywords"]["type"],
            "ARRAY"
        );
        assert_eq!(
            declarations[1]["parameters"]["properties"]["keywords"]["items"]["type"],
            "STRING"
        );
    }

    #[test]
    fn strips_unsupported_schema_keywords_from_function_declarations() {
        let body = build_memory_tool_body(&memory_request(), "system");
        let declarations = body["tools"][0]["functionDeclarations"].as_array().unwrap();

        // additionalProperties 不在老接口 Schema 子集内,必须移除,否则 400。
        assert!(
            declarations[1]["parameters"]
                .get("additionalProperties")
                .is_none()
        );
        // minLength / pattern / minItems / maxItems 属于受支持子集,必须保留。
        let keywords = &declarations[1]["parameters"]["properties"]["keywords"];
        assert_eq!(keywords["items"]["minLength"], 2);
        assert_eq!(keywords["maxItems"], 8);
        assert_eq!(
            declarations[5]["parameters"]["properties"]["date"]["pattern"],
            "^20\\d{2}-(0[1-9]|1[0-2])-([0-2][0-9]|3[0-1])$"
        );
        assert_eq!(declarations[1]["parameters"]["required"][0], "keywords");
    }

    #[test]
    fn maps_thinking_config_for_gemini_25_models() {
        let mut request = memory_request();
        request.model.model_id = "gemini-2.5-flash".to_string();
        let body = build_memory_tool_body(&request, "system");
        let thinking = &body["generationConfig"]["thinkingConfig"];
        assert_eq!(thinking["includeThoughts"], true);
        assert_eq!(thinking["thinkingBudget"], -1);
        assert!(thinking.get("thinkingLevel").is_none());

        request.reasoning_effort = "low".to_string();
        let body = build_memory_tool_body(&request, "system");
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["thinkingBudget"],
            1024
        );

        request.thinking_enabled = false;
        let body = build_memory_tool_body(&request, "system");
        let thinking = &body["generationConfig"]["thinkingConfig"];
        assert_eq!(thinking["includeThoughts"], false);
        assert_eq!(thinking["thinkingBudget"], 0);

        // 2.5 Pro 无法完全关闭思考,预算最低 128。
        request.model.model_id = "gemini-2.5-pro".to_string();
        let body = build_memory_tool_body(&request, "system");
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["thinkingBudget"],
            128
        );
    }

    #[test]
    fn maps_thinking_config_for_gemini_3_models() {
        let mut request = memory_request();
        request.model.model_id = "gemini-3-flash-preview".to_string();
        let body = build_memory_tool_body(&request, "system");
        let thinking = &body["generationConfig"]["thinkingConfig"];
        assert_eq!(thinking["includeThoughts"], true);
        assert_eq!(thinking["thinkingLevel"], "HIGH");
        assert!(thinking.get("thinkingBudget").is_none());

        request.reasoning_effort = "low".to_string();
        let body = build_memory_tool_body(&request, "system");
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["thinkingLevel"],
            "LOW"
        );

        request.thinking_enabled = false;
        let body = build_memory_tool_body(&request, "system");
        let thinking = &body["generationConfig"]["thinkingConfig"];
        assert_eq!(thinking["includeThoughts"], false);
        assert_eq!(thinking["thinkingLevel"], "LOW");
    }

    #[test]
    fn maps_thinking_config_for_gemini_3_flash_lite() {
        // flash-lite 系列仅支持 MINIMAL / HIGH 两档。
        let mut request = memory_request();
        request.model.model_id = "gemini-3.1-flash-lite".to_string();
        let body = build_memory_tool_body(&request, "system");
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["thinkingLevel"],
            "HIGH"
        );

        request.reasoning_effort = "low".to_string();
        let body = build_memory_tool_body(&request, "system");
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["thinkingLevel"],
            "MINIMAL"
        );

        request.thinking_enabled = false;
        let body = build_memory_tool_body(&request, "system");
        let thinking = &body["generationConfig"]["thinkingConfig"];
        assert_eq!(thinking["includeThoughts"], false);
        assert_eq!(thinking["thinkingLevel"], "MINIMAL");
    }

    #[test]
    fn maps_thinking_config_for_gemini_3_pro() {
        // 3 Pro 仅支持 LOW / HIGH,medium 映射到 HIGH。
        let mut request = memory_request();
        request.model.model_id = "gemini-3-pro-preview".to_string();
        request.reasoning_effort = "medium".to_string();
        let body = build_memory_tool_body(&request, "system");
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["thinkingLevel"],
            "HIGH"
        );

        request.reasoning_effort = "low".to_string();
        let body = build_memory_tool_body(&request, "system");
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["thinkingLevel"],
            "LOW"
        );
    }

    #[test]
    fn maps_thinking_config_for_future_gemini_versions() {
        // Gemini 3 之后的主版本同样走 thinkingLevel。
        let mut request = memory_request();
        request.model.model_id = "gemini-4.0-flash".to_string();
        let body = build_memory_tool_body(&request, "system");
        let thinking = &body["generationConfig"]["thinkingConfig"];
        assert_eq!(thinking["thinkingLevel"], "HIGH");
        assert!(thinking.get("thinkingBudget").is_none());

        request.thinking_enabled = false;
        let body = build_memory_tool_body(&request, "system");
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["thinkingLevel"],
            "LOW"
        );

        // 3.5 Pro 命中 -pro 分支:仅 LOW / HIGH。
        let mut request = memory_request();
        request.model.model_id = "gemini-3.5-pro".to_string();
        request.reasoning_effort = "medium".to_string();
        let body = build_memory_tool_body(&request, "system");
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["thinkingLevel"],
            "HIGH"
        );
    }

    #[test]
    fn parses_gemini_major_version() {
        assert_eq!(gemini_major_version("gemini-2.5-flash"), Some(2));
        assert_eq!(gemini_major_version("gemini-3.1-flash-lite"), Some(3));
        assert_eq!(gemini_major_version("gemini-4.0-flash"), Some(4));
        assert_eq!(gemini_major_version("models/gemini-3-flash"), Some(3));
        assert_eq!(gemini_major_version("gemini-flash-latest"), None);
    }

    #[test]
    fn converts_tool_exchange_history_to_contents() {
        let mut request = memory_request();
        request.messages.push(AiChatMessage {
            role: "assistant".to_string(),
            content: String::new(),
            reasoning_content: "需要先检索".to_string(),
            tool_call_id: String::new(),
            tool_calls: vec![AiToolCall {
                id: "gemini_call_1".to_string(),
                name: "keyword_search".to_string(),
                arguments: "{\"keywords\":[\"nacos\"]}".to_string(),
            }],
        });
        request.messages.push(AiChatMessage {
            role: "tool".to_string(),
            content: "{\"results\":[]}".to_string(),
            reasoning_content: String::new(),
            tool_call_id: "gemini_call_1".to_string(),
            tool_calls: vec![],
        });
        request.messages.push(AiChatMessage {
            role: "assistant".to_string(),
            content: "没有相关记录。".to_string(),
            reasoning_content: String::new(),
            tool_call_id: String::new(),
            tool_calls: vec![],
        });

        let contents = memory_contents(&request.messages);
        assert_eq!(contents.len(), 4);
        assert_eq!(contents[0]["role"], "user");
        assert_eq!(contents[1]["role"], "model");
        let call = &contents[1]["parts"][0]["functionCall"];
        assert_eq!(call["name"], "keyword_search");
        assert_eq!(call["args"]["keywords"][0], "nacos");
        // 应用内生成的占位 id 不回传给 API。
        assert!(call.get("id").is_none());
        assert_eq!(contents[2]["role"], "user");
        let response = &contents[2]["parts"][0]["functionResponse"];
        assert_eq!(response["name"], "keyword_search");
        assert_eq!(response["response"]["results"], json!([]));
        assert_eq!(contents[3]["role"], "model");
        assert_eq!(contents[3]["parts"][0]["text"], "没有相关记录。");
    }

    #[test]
    fn parses_generate_content_response() {
        let value = json!({
            "candidates": [{
                "content": {
                    "role": "model",
                    "parts": [
                        {"text": "先确认日期范围", "thought": true},
                        {"text": "最终答案"},
                        {"functionCall": {"name": "keyword_search", "args": {"keywords": ["nacos"]}}}
                    ]
                },
                "finishReason": "STOP"
            }],
            "usageMetadata": {
                "promptTokenCount": 62,
                "candidatesTokenCount": 171,
                "totalTokenCount": 233
            }
        });

        let parts = candidate_parts(&value);
        assert_eq!(parts_text(&parts, false), "最终答案");
        assert_eq!(parts_text(&parts, true), "先确认日期范围");
        let mut generated_call_ids = 0;
        let tool_calls = parts_tool_calls(&parts, &mut generated_call_ids);
        assert_eq!(tool_calls.len(), 1);
        assert_eq!(tool_calls[0].id, "gemini_call_1");
        assert_eq!(tool_calls[0].name, "keyword_search");
        assert_eq!(
            serde_json::from_str::<Value>(&tool_calls[0].arguments).unwrap(),
            json!({"keywords": ["nacos"]})
        );
        assert_eq!(usage_from_value(&value), (62, 171, 0));
    }

    #[test]
    fn keeps_api_provided_function_call_id() {
        let parts = vec![json!({
            "functionCall": {"id": "fc_1", "name": "get_weather", "args": {"city": "Boston"}}
        })];
        let mut generated_call_ids = 0;
        let tool_calls = parts_tool_calls(&parts, &mut generated_call_ids);
        assert_eq!(tool_calls[0].id, "fc_1");
        assert_eq!(generated_call_ids, 0);
    }

    #[test]
    fn builds_structured_note_body_with_response_schema() {
        let structured_request = AiChatRequest {
            purpose: "home_structured_note".to_string(),
            ..request()
        };

        let body = build_generate_content_body(&structured_request);
        assert_eq!(
            body["generationConfig"]["responseMimeType"],
            "application/json"
        );
        let schema = &body["generationConfig"]["responseSchema"];
        assert_eq!(schema["type"], "OBJECT");
        assert_eq!(schema["required"][0], "sections");
        assert_eq!(schema["properties"]["sections"]["type"], "ARRAY");
        assert_eq!(
            schema["properties"]["sections"]["items"]["required"][1],
            "items"
        );
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["includeThoughts"],
            false
        );

        // 非结构化用途不携带结构化输出配置。
        let plain = build_generate_content_body(&request());
        assert!(plain["generationConfig"].get("responseMimeType").is_none());
        assert!(plain["generationConfig"].get("responseSchema").is_none());
    }

    #[test]
    fn accumulates_generate_content_stream_chunks() {
        let mut accumulator = GeminiStreamAccumulator::default();

        let delta = apply_gemini_stream_chunk(
            &mut accumulator,
            &json!({
                "candidates": [{
                    "content": {"role": "model", "parts": [{"text": "先想", "thought": true}]}
                }]
            }),
        );
        assert_eq!(delta.reasoning_delta, "先想");
        assert!(delta.content_delta.is_empty());

        let delta = apply_gemini_stream_chunk(
            &mut accumulator,
            &json!({
                "candidates": [{
                    "content": {"role": "model", "parts": [{"text": "回答"}]}
                }]
            }),
        );
        assert_eq!(delta.content_delta, "回答");
        assert_eq!(accumulator.content, "回答");
        assert_eq!(accumulator.reasoning_content, "先想");

        apply_gemini_stream_chunk(
            &mut accumulator,
            &json!({
                "candidates": [{
                    "content": {
                        "role": "model",
                        "parts": [{"functionCall": {"name": "keyword_search", "args": {"keywords": ["nacos"]}}}]
                    }
                }]
            }),
        );
        apply_gemini_stream_chunk(
            &mut accumulator,
            &json!({
                "usageMetadata": {
                    "promptTokenCount": 10,
                    "candidatesTokenCount": 20,
                    "totalTokenCount": 30
                }
            }),
        );

        assert_eq!(accumulator.tool_calls.len(), 1);
        assert_eq!(accumulator.tool_calls[0].id, "gemini_call_1");
        assert_eq!(
            serde_json::from_str::<Value>(&accumulator.tool_calls[0].arguments).unwrap(),
            json!({"keywords": ["nacos"]})
        );
        assert_eq!(accumulator.input_tokens, 10);
        assert_eq!(accumulator.output_tokens, 20);
    }

    #[test]
    fn builds_stream_generate_content_url() {
        let provider = AiProvider {
            id: "p".to_string(),
            name: "Google".to_string(),
            protocol: "gemini".to_string(),
            api_key: "key".to_string(),
            base_url: "https://generativelanguage.googleapis.com/".to_string(),
            api_path: String::new(),
        };

        assert_eq!(
            stream_generate_content_url(&provider, "gemini-test"),
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-test:streamGenerateContent?alt=sse"
        );
    }

    #[test]
    fn extracts_api_error_message_from_json_or_sse_body() {
        // 请求被 400 拒绝时,响应体是普通 JSON 错误;流式场景也可能是 SSE error 事件。
        assert_eq!(
            extract_api_error_message("{\"error\":{\"message\":\"plain error\"}}").as_deref(),
            Some("plain error")
        );
        let sse_body = "event: error\ndata: {\"error\":{\"message\":\"Request contains an invalid argument.\"},\"event_type\":\"error\"}\n\n";
        assert_eq!(
            extract_api_error_message(sse_body).as_deref(),
            Some("Request contains an invalid argument.")
        );
        assert!(extract_api_error_message("not json").is_none());
    }
}
