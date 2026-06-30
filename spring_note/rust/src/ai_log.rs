use chrono::Utc;
use serde_json::{Value, json};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::Path;

pub struct ApiNetworkLog<'a> {
    pub app_data_dir: &'a str,
    pub enabled: bool,
    pub provider_id: &'a str,
    pub provider_name: &'a str,
    pub protocol: &'a str,
    pub model_id: &'a str,
    pub purpose: &'a str,
    pub method: &'a str,
    pub url: &'a str,
    pub request_body: &'a str,
    pub response_status: Option<u16>,
    pub response_body: &'a str,
    pub duration_ms: u128,
    pub error: &'a str,
}

pub fn write_api_network_log(entry: ApiNetworkLog<'_>) {
    if !entry.enabled {
        return;
    }

    let directory = Path::new(entry.app_data_dir).join("logs");
    if fs::create_dir_all(&directory).is_err() {
        return;
    }

    let request_body = redacted_request_body(entry.request_body);
    let line = json!({
        "timestamp": Utc::now().to_rfc3339(),
        "providerId": entry.provider_id,
        "providerName": entry.provider_name,
        "protocol": entry.protocol,
        "modelId": entry.model_id,
        "purpose": entry.purpose,
        "method": entry.method,
        "url": entry.url,
        "requestBody": request_body,
        "responseStatus": entry.response_status,
        "responseBody": entry.response_body,
        "durationMs": entry.duration_ms,
        "error": entry.error,
    })
    .to_string();

    let path = directory.join("api_network.log");
    let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) else {
        return;
    };
    let _ = writeln!(file, "{line}");
}

fn redacted_request_body(request_body: &str) -> String {
    let Ok(mut value) = serde_json::from_str::<Value>(request_body) else {
        return request_body.to_string();
    };
    redact_image_payloads(&mut value);
    serde_json::to_string_pretty(&value).unwrap_or_else(|_| request_body.to_string())
}

fn redact_image_payloads(value: &mut Value) {
    match value {
        Value::Object(map) => {
            if let Some(image_url) = map.get_mut("image_url") {
                match image_url {
                    Value::String(url) => redact_data_url(url),
                    Value::Object(image_url) => {
                        if let Some(Value::String(url)) = image_url.get_mut("url") {
                            redact_data_url(url);
                        }
                    }
                    _ => {}
                }
            }
            if let Some(Value::Object(inline_data)) = map.get_mut("inline_data") {
                if has_image_mime(inline_data, "mime_type") {
                    if let Some(Value::String(data)) = inline_data.get_mut("data") {
                        redact_base64_data(data);
                    }
                }
            }
            if let Some(Value::Object(source)) = map.get_mut("source") {
                if has_image_mime(source, "media_type") {
                    if let Some(Value::String(data)) = source.get_mut("data") {
                        redact_base64_data(data);
                    }
                }
            }
            if has_image_mime(map, "mime_type") {
                if let Some(Value::String(data)) = map.get_mut("data") {
                    redact_base64_data(data);
                }
            }
            if has_image_mime(map, "media_type") {
                if let Some(Value::String(data)) = map.get_mut("data") {
                    redact_base64_data(data);
                }
            }
            for child in map.values_mut() {
                redact_image_payloads(child);
            }
        }
        Value::Array(items) => {
            for item in items {
                redact_image_payloads(item);
            }
        }
        Value::String(text) => redact_data_url(text),
        _ => {}
    }
}

fn has_image_mime(map: &serde_json::Map<String, Value>, key: &str) -> bool {
    map.get(key)
        .and_then(Value::as_str)
        .map(|mime_type| mime_type.trim().starts_with("image/"))
        .unwrap_or(false)
}

fn redact_data_url(value: &mut String) {
    let Some((prefix, data)) = value.split_once(";base64,") else {
        return;
    };
    if !prefix.trim_start().starts_with("data:image/") {
        return;
    }
    if data.starts_with("[redacted image base64:") {
        return;
    }
    *value = format!("{prefix};base64,{}", redacted_base64_marker(data.len()));
}

fn redact_base64_data(value: &mut String) {
    if value.starts_with("[redacted image base64:") {
        return;
    }
    *value = redacted_base64_marker(value.len());
}

fn redacted_base64_marker(length: usize) -> String {
    format!("[redacted image base64: {length} chars]")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn writes_full_request_and_response_body() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("spring_note_api_log_{suffix}"));
        let app_data_dir = dir.to_string_lossy().to_string();

        write_api_network_log(ApiNetworkLog {
            app_data_dir: &app_data_dir,
            enabled: true,
            provider_id: "p",
            provider_name: "OpenAI",
            protocol: "openaiCompatible",
            model_id: "gpt-test",
            purpose: "test",
            method: "POST",
            url: "https://api.example.com/v1/chat/completions",
            request_body: r#"{"messages":[{"content":"完整请求"}]}"#,
            response_status: Some(200),
            response_body: r#"{"choices":[{"message":{"content":"完整响应"}}]}"#,
            duration_ms: 12,
            error: "",
        });

        let content = fs::read_to_string(dir.join("logs").join("api_network.log")).unwrap();
        assert!(content.contains("完整请求"));
        assert!(content.contains("完整响应"));
        fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn writes_fim_request_and_response_body() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("spring_note_fim_api_log_{suffix}"));
        let app_data_dir = dir.to_string_lossy().to_string();

        write_api_network_log(ApiNetworkLog {
            app_data_dir: &app_data_dir,
            enabled: true,
            provider_id: "p",
            provider_name: "OpenAI Compatible",
            protocol: "openaiCompatible",
            model_id: "deepseek-v4-pro",
            purpose: "fim_edit_completion",
            method: "POST",
            url: "https://api.example.com/v1/completions",
            request_body: r#"{"model":"deepseek-v4-pro","prompt":"def fib(a):","suffix":"    return fib(a-1) + fib(a-2)","max_tokens":128}"#,
            response_status: Some(200),
            response_body: r#"{"choices":[{"text":"\n    if a <= 1:\n        return a"}]}"#,
            duration_ms: 12,
            error: "",
        });

        let content = fs::read_to_string(dir.join("logs").join("api_network.log")).unwrap();
        assert!(content.contains("fim_edit_completion"));
        assert!(content.contains("def fib(a):"));
        assert!(content.contains("return fib(a-1) + fib(a-2)"));
        assert!(content.contains("if a <= 1"));
        fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn redacts_openai_chat_image_data_urls_from_request_body() {
        let request_body = r#"{
            "messages": [{
                "role": "user",
                "content": [{
                    "type": "image_url",
                    "image_url": {
                        "url": "data:image/png;base64,aW1hZ2U="
                    }
                }]
            }]
        }"#;

        let redacted = redacted_request_body(request_body);

        assert!(!redacted.contains("aW1hZ2U="));
        assert!(redacted.contains("data:image/png;base64,[redacted image base64: 8 chars]"));
        assert!(redacted.contains("image_url"));
    }

    #[test]
    fn redacts_openai_responses_image_data_urls_from_request_body() {
        let request_body = r#"{
            "input": [{
                "role": "user",
                "content": [{
                    "type": "input_image",
                    "image_url": "data:image/webp;base64,d2VicA=="
                }]
            }]
        }"#;

        let redacted = redacted_request_body(request_body);

        assert!(!redacted.contains("d2VicA=="));
        assert!(redacted.contains("data:image/webp;base64,[redacted image base64: 8 chars]"));
        assert!(redacted.contains("input_image"));
    }

    #[test]
    fn redacts_gemini_inline_image_data_from_request_body() {
        let request_body = r#"{
            "contents": [{
                "parts": [{
                    "inline_data": {
                        "mime_type": "image/jpeg",
                        "data": "anBlZw=="
                    }
                }]
            }]
        }"#;

        let redacted = redacted_request_body(request_body);

        assert!(!redacted.contains("anBlZw=="));
        assert!(redacted.contains("\"mime_type\": \"image/jpeg\""));
        assert!(redacted.contains("[redacted image base64: 8 chars]"));
    }

    #[test]
    fn redacts_claude_source_image_data_from_request_body() {
        let request_body = r#"{
            "messages": [{
                "content": [{
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": "image/png",
                        "data": "cG5n"
                    }
                }]
            }]
        }"#;

        let redacted = redacted_request_body(request_body);

        assert!(!redacted.contains("cG5n"));
        assert!(redacted.contains("\"media_type\": \"image/png\""));
        assert!(redacted.contains("[redacted image base64: 4 chars]"));
    }
}
