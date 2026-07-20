# context

A native SwiftUI macOS chat app for local AI models. It talks directly to Ollama and stores chat history locally in SQLite.

<br>

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/JosephBARBIERDARNAL/context/main/scripts/install.sh | sh
```

This drops the latest release into `/Applications`. If you'd rather download manually, grab `Context-arm64.zip` from the [releases page](https://github.com/y-sunflower/context/releases), unzip into `/Applications`, and on first launch approve it under System Settings → Privacy & Security (the app is ad-hoc signed, not notarized).

<br>

## Ollama

`context` requires macOS 26 or newer and needs [Ollama](https://ollama.com) running locally. Install and start Ollama with the official installer:

```sh
curl -fsSL https://ollama.com/install.sh | sh
```

Verify that the daemon is reachable:

```sh
ollama list
```

On macOS, if Ollama is installed but not running, start it with `open -a Ollama`. See [Ollama's documentation](https://docs.ollama.com/) for system requirements and troubleshooting.
