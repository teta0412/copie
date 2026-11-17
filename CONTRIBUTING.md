# Contributing to Copie

Thank you for your interest in contributing to Copie! As an open-source project, contributions of all forms—bug reports, feature ideas, documentation improvements, and code changes—are welcome.

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Getting Started

### Prerequisites
- macOS 15.0 Sequoia or later
- Xcode 16.0 or later (with macOS SDK 15+)
- Git

### Building Locally

Clone the repository:
```bash
git clone https://github.com/teta0412/copie.git
cd copie
```

Open `Copie.xcodeproj` in Xcode and press **⌘R** to build and run, or build via the terminal:

```bash
# Debug build
xcodebuild -project Copie.xcodeproj -scheme Copie -configuration Debug -derivedDataPath /private/tmp/CopieDerived CODE_SIGNING_ALLOWED=NO build

# Package release DMG
zsh scripts/build-dmg.sh
```

### Running Tests

We maintain a fast, focused smoke test suite testing SQLite storage, item trimming, deduplication, and pasteboard type handling:

```bash
zsh scripts/test-smoke.sh
```

Make sure all tests pass before submitting changes.

## Development Principles

1. **100% Offline & Private:** Copie must never introduce network requests, analytics, or external telemetry.
2. **Minimal External Dependencies:** Rely on native macOS frameworks (`AppKit`, `SwiftUI`, `ImageIO`, `UniformTypeIdentifiers`, `sqlite3`).
3. **Performance First:** Clipboard operations occur frequently; avoid heavy disk operations on the main thread and keep menu bar popover response snappy.

## Submitting Pull Requests

1. Fork the repository and create your branch from `main`:
   ```bash
   git checkout -b feature/my-new-feature
   ```
2. Commit your changes with clear, descriptive commit messages.
3. Verify that `zsh scripts/test-smoke.sh` passes.
4. Push to your fork and submit a Pull Request against `main`.
5. Link any related issues in the PR description.
