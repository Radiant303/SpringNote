use crate::ai::{
    AiChatRequest, AiImageAttachment, AiModel, AiProvider, AiTextResult, extract_text, http_client,
    usage_from_value,
};
use crate::ai_log::{ApiNetworkLog, write_api_network_log};
use serde_json::{Value, json};
use std::time::Instant;

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

    let content = extract_text(
        &value,
        &[&["candidates", "0", "content", "parts", "0", "text"]],
    )
    .ok_or_else(|| "Gemini response missing candidates[0].content.parts[0].text".to_string())?;
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
    let mut parts = vec![json!({"text": request.user_prompt})];
    parts.extend(request.images.iter().map(gemini_image_part));

    json!({
        "systemInstruction": {
            "parts": [{"text": request.system_prompt}]
        },
        "contents": [{
            "role": "user",
            "parts": parts
        }],
        "generationConfig": {
            "temperature": 0.2
        }
    })
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
}
