use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use ollama_rs::generation::chat::request::ChatMessageRequest;
use ollama_rs::generation::chat::ChatMessage;
use ollama_rs::generation::parameters::ThinkType;
use ollama_rs::models::ModelOptions;
use ollama_rs::Ollama;
use tokio_stream::StreamExt;

use crate::{CoreError, GenerationOptions, Message, ThinkingMode};

pub struct ChatOutput {
    pub content: String,
    pub thinking: String,
}

/// Stream a chat completion for the given history, invoking `on_token` for
/// each delta. Returns the full assistant response (partial if cancelled).
pub async fn stream_chat(
    model: String,
    history: Vec<Message>,
    options: GenerationOptions,
    cancel: Arc<AtomicBool>,
    mut on_token: impl FnMut(String),
    mut on_thinking: impl FnMut(String),
) -> Result<ChatOutput, CoreError> {
    let messages: Vec<ChatMessage> = history
        .iter()
        .map(|m| match m.role.as_str() {
            "user" => ChatMessage::user(m.content.clone()),
            "system" => ChatMessage::system(m.content.clone()),
            _ => ChatMessage::assistant(m.content.clone()),
        })
        .collect();

    let request = build_request(model, messages, &options);
    let ollama = Ollama::default();
    let mut stream = ollama
        .send_chat_messages_stream(request)
        .await
        .map_err(|e| CoreError::Ollama { msg: e.to_string() })?;

    let mut full = String::new();
    let mut thinking = String::new();
    while let Some(item) = stream.next().await {
        if cancel.load(Ordering::Relaxed) {
            break;
        }
        // The stream's mid-flight error type is `()`, so no detail is available.
        let response = item.map_err(|_| CoreError::Ollama {
            msg: "response stream was interrupted".to_string(),
        })?;
        let token = response.message.content;
        if !token.is_empty() {
            full.push_str(&token);
            on_token(token);
        }
        if let Some(token) = response.message.thinking.filter(|token| !token.is_empty()) {
            thinking.push_str(&token);
            on_thinking(token);
        }
    }
    Ok(ChatOutput {
        content: full,
        thinking,
    })
}

fn build_request(
    model: String,
    messages: Vec<ChatMessage>,
    options: &GenerationOptions,
) -> ChatMessageRequest {
    let mut request = ChatMessageRequest::new(model, messages);
    let mut model_options = ModelOptions::default();
    let mut has_model_options = false;

    macro_rules! apply {
        ($field:ident, $method:ident) => {
            if let Some(value) = options.$field {
                model_options = model_options.$method(value as _);
                has_model_options = true;
            }
        };
    }

    apply!(temperature, temperature);
    apply!(num_ctx, num_ctx);
    apply!(num_predict, num_predict);
    apply!(seed, seed);
    apply!(top_k, top_k);
    apply!(top_p, top_p);
    apply!(min_p, min_p);
    apply!(repeat_last_n, repeat_last_n);
    apply!(repeat_penalty, repeat_penalty);
    apply!(tfs_z, tfs_z);
    apply!(mirostat, mirostat);
    apply!(mirostat_eta, mirostat_eta);
    apply!(mirostat_tau, mirostat_tau);
    if let Some(stop) = options.stop.clone() {
        model_options = model_options.stop(stop);
        has_model_options = true;
    }
    if has_model_options {
        request = request.options(model_options);
    }

    match options.thinking {
        ThinkingMode::ModelDefault => request,
        ThinkingMode::On => request.think(ThinkType::True),
        ThinkingMode::Off => request.think(ThinkType::False),
        ThinkingMode::Low => request.think(ThinkType::Low),
        ThinkingMode::Medium => request.think(ThinkType::Medium),
        ThinkingMode::High => request.think(ThinkType::High),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn model_defaults_are_omitted() {
        let request = build_request("model".into(), vec![], &GenerationOptions::default());
        let json = serde_json::to_value(request).unwrap();
        assert!(json.get("options").is_none());
        assert!(json.get("think").is_none());
    }

    #[test]
    fn overrides_and_thinking_mode_are_serialized() {
        let options = GenerationOptions {
            thinking: ThinkingMode::High,
            temperature: Some(0.25),
            stop: Some(vec!["END".into()]),
            ..GenerationOptions::default()
        };
        let request = build_request("model".into(), vec![], &options);
        let json = serde_json::to_value(request).unwrap();
        assert_eq!(json["think"], "high");
        assert_eq!(json["options"]["temperature"], 0.25);
        assert_eq!(json["options"]["stop"][0], "END");
    }
}
