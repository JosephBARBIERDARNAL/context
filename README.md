<p align="center">
  <img src="assets/logo.png" alt="Context" width="640">
</p>

# Context

A 100% local macOS chat app for [Ollama](https://ollama.com) models. Rust core
(chat streaming via [ollama-rs](https://crates.io/crates/ollama-rs), history in
SQLite via rusqlite) exposed to a native SwiftUI frontend through
[UniFFI](https://mozilla.github.io/uniffi-rs/). No network access except
`localhost:11434`.

<br>

## Install

Apple Silicon, macOS 26+, with [Ollama](https://ollama.com) running locally:

```sh
curl -fsSL https://raw.githubusercontent.com/JosephBARBIERDARNAL/context/main/scripts/install.sh | sh
```

This drops the latest release into `/Applications`. If you'd rather download
manually, grab `Context-arm64.zip` from the
[releases page](https://github.com/JosephBARBIERDARNAL/context/releases),
unzip into `/Applications`, and on first launch approve it under
System Settings → Privacy & Security (the app is ad-hoc signed, not notarized).

<br>

## Requirements (building from source)

- macOS 26+ (Liquid Glass UI)
- Xcode Command Line Tools (Swift 6.2+) — full Xcode not required
- Rust (stable)
- [just](https://github.com/casey/just)
- Ollama running locally with at least one model pulled

