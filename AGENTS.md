# Repository Guidelines

## Project Structure & Module Organization

Context is a native SwiftUI macOS application. UI, Ollama streaming, and SQLite persistence live under `app/Sources/Context/`; `app/Info.plist` and `app/AppIcon.icns` define bundle metadata and branding. Source artwork is in `assets/`, automation in `scripts/`, and assembled applications in the ignored `dist/` directory.

## Build, Test, and Development Commands

Use the repository `justfile` as the main task interface:

- `just setup` checks for Swift and a reachable local Ollama server.
- `just build` compiles the Swift app.
- `just dev` bundles the app and runs it in the foreground with logs visible.
- `just test` runs the Swift test suite.
- `just lint` checks Swift formatting and treats compiler warnings as errors.
- `just fmt` formats the Swift sources and tests.
- `just bundle` creates and ad-hoc signs `dist/Context.app`.

Building requires macOS 26+, Swift 6.2+, `just`, and Ollama.

## Coding Style & Naming Conventions

Accept `swift format` output and use four-space indentation. Follow Swift conventions: `UpperCamelCase` for types and `lowerCamelCase` for properties and methods. Keep UI responsibilities in focused SwiftUI view files, isolate SQLite access in the database actor, and keep Ollama HTTP behavior in its client.

## Testing Guidelines

Swift tests live under `app/Tests/ContextTests/` and use Swift Testing. Add regression tests for changed database, streaming, and state behavior, then run `just test`. There is no stated coverage threshold. For UI changes, also run `just bundle` and manually verify the relevant flow with Ollama running.

## Commit & Pull Request Guidelines

Recent commits use short, lowercase, action-oriented summaries such as `update readme` and `move release script`. Keep each commit focused and use a similarly concise subject. Pull requests should explain the user-visible effect, identify validation performed, and link relevant issues. Include screenshots or a short recording for SwiftUI changes. Ensure the CI-equivalent checks—formatting, `just lint`, `just test`, and `just bundle`—pass before requesting review.
