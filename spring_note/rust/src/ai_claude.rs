use crate::ai::{
    AiChatRequest, AiImageAttachment, AiModel, AiProvider, AiTextResult, extract_text, http_client,
    usage_from_value,
};
use crate::ai_log::{ApiNetworkLog, write_api_network_log};
use serde_json::{Value, json};
use std::time::Instant;

pub async fn chat(request: &AiChatRequest) -> Result<AiTextResult, String> {
    let url = messages_url(&request.provider);
    let body = build_messages_body(request);
    let request_body = body_to_string(&body);
    let started_at = Instant::now();
    let response = http_client()?
        .post(&url)
        .header("x-api-key", &request.provider.api_key)
        .header("anthropic-version", "2023-06-01")
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

    let content = extract_text(&value, &[&["content", "0", "text"]])
        .ok_or_else(|| "Claude response missing content[0].text".to_string())?;
    let (input, output, cached) = usage_from_value(&value);
    Ok(AiTextResult::success(
        request, content, input, output, cached,
    ))
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
        Value::String(request.user_prompt.clone())
    } else {
        claude_user_content(request)
    };

    json!({
        "model": request.model.model_id,
        "system": request.system_prompt,
        "messages": [{
            "role": "user",
            "content": content
        }],
        "max_tokens": 4096,
        "temperature": 0.2
    })
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
}
