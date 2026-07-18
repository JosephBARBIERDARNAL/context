use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use ollama_rs::generation::chat::request::ChatMessageRequest;
use ollama_rs::generation::chat::ChatMessage;
use ollama_rs::Ollama;
use tokio_stream::StreamExt;

use crate::{CoreError, Message};

/// Stream a chat completion for the given history, invoking `on_token` for
/// each delta. Returns the full assistant response (partial if cancelled).
pub async fn stream_chat(
    model: String,
    history: Vec<Message>,
    cancel: Arc<AtomicBool>,
    mut on_token: impl FnMut(String),
) -> Result<String, CoreError> {
    let messages: Vec<ChatMessage> = history
        .iter()
        .map(|m| match m.role.as_str() {
            "user" => ChatMessage::user(m.content.clone()),
            "system" => ChatMessage::system(m.content.clone()),
            _ => ChatMessage::assistant(m.content.clone()),
        })
        .collect();

    let ollama = Ollama::default();
    let mut stream = ollama
        .send_chat_messages_stream(ChatMessageRequest::new(model, messages))
        .await
        .map_err(|e| CoreError::Ollama { msg: e.to_string() })?;

    let mut full = String::new();
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
    }
    Ok(full)
}
