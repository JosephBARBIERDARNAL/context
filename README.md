# Context

A 100% local macOS chat app for [Ollama](https://ollama.com) models. Rust core
(chat streaming via [ollama-rs](https://crates.io/crates/ollama-rs), history in
SQLite via rusqlite) exposed to a native SwiftUI frontend through
[UniFFI](https://mozilla.github.io/uniffi-rs/). No network access except
`localhost:11434`.

## Requirements

- macOS 26+ (Liquid Glass UI)
- Xcode Command Line Tools (Swift 6.2+) — full Xcode not required
- Rust (stable)
- [just](https://github.com/casey/just)
- Ollama running locally with at least one model pulled

## Usage

```sh
just setup   # sanity-check the toolchain and that Ollama is up
just run     # build everything and launch Context.app
```

Default model: `gemma4:26b` (falls back to the first installed model).

## Development

| Command | What it does |
| --- | --- |
| `just build` | Rust core → UniFFI bindings → Swift app |
| `just dev` | Build and run in the foreground (logs on stdout) |
| `just test` | Rust unit tests |
| `just bindings` | Regenerate the Swift bindings after changing the Rust API |
| `just fmt` / `just lint` | Format / clippy |
| `just db-reset` | Delete the local chat database |

## Architecture

```
core/   Rust: ollama-rs streaming, rusqlite store, UniFFI exports
app/    SwiftUI: NavigationSplitView, Liquid Glass styling
        Sources/ContextCore*  = generated bindings (gitignored)
```

- Swift calls into Rust through the UniFFI-generated `ContextCore` object
  (linked as a static library — see `app/Package.swift`).
- Token streaming flows Rust → Swift through the `ChatListener` foreign trait;
  a global tokio runtime in the Rust core drives the request.
- Chat history lives in `~/Library/Application Support/Context/context.db`.
