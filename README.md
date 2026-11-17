# Copie

<p align="center">
  <strong>Fast, lightweight, native macOS clipboard manager built with SwiftUI.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2015%2B%20(Sequoia)-lightgrey.svg" alt="Platform: macOS 15+">
  <img src="https://img.shields.io/badge/Swift-5.0%2B-orange.svg" alt="Swift 5.0+">
  <a href="https://github.com/teta0412/copie/actions/workflows/ci.yml"><img src="https://github.com/teta0412/copie/actions/workflows/ci.yml/badge.svg" alt="CI Status"></a>
  <a href="https://github.com/teta0412/copie/releases"><img src="https://img.shields.io/github/v/release/teta0412/copie?label=latest%20release" alt="Latest Release"></a>
</p>

---

Copie lives in your macOS menu bar and saves readable pasteboard items locally on your Mac. Select any entry to copy it back to your system clipboard, or press **⌘V** in your destination app to paste it.

## ✨ Features

- **Menu Bar Popover:** Instant access via the menu bar icon or the global hotkey (**⌘⇧V**).
- **Fast Search & Keyboard Navigation:** Filter history quickly by typing; navigate with arrow keys and press **Return** to copy.
- **Image Previews & Full Backups:** Shows inline thumbnails for images and Finder image files. Saves a full-quality local copy when within your storage limit, preserving your content even if original files are moved or deleted.
- **Screen Area Capture:** Press **⌃⇧⌘S** (or click *Capture Area* in the popup) to select a screen area; the result is immediately copied to your clipboard and saved in history.
- **100% Offline & Private:** Zero network requests, zero telemetry, zero analytics. All clipboard data remains strictly on your Mac in SQLite.
- **Configurable Storage Limit:** Choose your storage threshold (default: 1 GB) with automatic background pruning of older items.
- **Launch at Login:** Seamlessly start Copie whenever you log in to macOS.

---

## 🚀 Quick Install

### Fast Install via GitHub Releases

1. Go to the [**Latest Releases**](https://github.com/teta0412/copie/releases) page.
2. Download `Copie-<version>-macOS.dmg`.
3. Open the `.dmg` and drag **Copie.app** into your **Applications** folder.
4. Launch Copie from Applications or Spotlight.

> **Note on macOS Permissions:**
> - When first running, macOS may prompt you to grant pasteboard accessibility permissions.
> - Using **Capture Area** (`⌃⇧⌘S`) requires macOS Screen Recording permission so Copie can capture the selected rect.

---

## ⌨️ Shortcuts & Controls

| Shortcut / Action | Action |
| :--- | :--- |
| **⌘⇧V** | Toggle Copie menu bar popover |
| **⌃⇧⌘S** | Capture screen area to clipboard |
| **↑ / ↓** | Navigate history items |
| **Return** | Copy selected item to clipboard |
| **Esc** | Close the popover |
| **⌘Q** | Quit Copie |
| **Right-click icon** | Open quick actions menu (Settings, About, Quit) |

Shortcuts can be customized in **Settings** (click the gear icon in the popover).

### How to Quit Copie
You can quit Copie at any time using any of these convenient methods:
- **Right-click (or Control-click)** the menu bar icon and select **Quit Copie**.
- Press **⌘Q** while the Copie popover, Settings, or About window is focused.
- Click the **Power icon** in the popover footer.
- Open **Settings** and click the **Quit Copie** button.

---

## 🛠️ Building from Source

### Requirements
- macOS 15.0 Sequoia or later
- Xcode 16.0 or later (command-line tools installed)

### Clone & Run

```bash
git clone https://github.com/teta0412/copie.git
cd copie
```

#### Build with Xcode
Open `Copie.xcodeproj` in Xcode and select the **Copie** scheme, then press **⌘R**.

#### Build via Terminal (Debug)
```bash
xcodebuild \
  -project Copie.xcodeproj \
  -scheme Copie \
  -configuration Debug \
  -derivedDataPath /private/tmp/CopieDerived \
  CODE_SIGNING_ALLOWED=NO \
  build

open /private/tmp/CopieDerived/Build/Products/Debug/Copie.app
```

#### Package a Release DMG
To build an optimized Release version and package it into a distributable DMG:
```bash
zsh scripts/build-dmg.sh
# Output created at build/dist/Copie-<version>-macOS.dmg
```

---

## 🧪 Testing

Copie includes a fast standalone smoke test suite for storage, trimming, deduplication, and pasteboard handling:

```bash
zsh scripts/test-smoke.sh
```

---

## 🗄️ Architecture & Storage

- **Data Path:** History and backups live in `~/Library/Application Support/Copie/history.sqlite3`.
- **Database Engine:** Pure native SQLite via `libsqlite3`.
- **UI Framework:** SwiftUI with AppKit integration (`NSStatusItem`, `NSPopover`).
- **Core Components:**
  - `Copie/ClipboardMonitor.swift`: Monitors pasteboard change counts efficiently using polling intervals.
  - `Copie/HistoryStore.swift`: Manages SQLite storage, full-image caching, thumbnail generation, and disk limits.
  - `Copie/HotKeyManager.swift`: Registers global keyboard shortcuts using Carbon APIs.
  - `Copie/Views.swift`: SwiftUI views for popover, history row, settings, and about modal.

---

## 🛡️ Privacy & Security

Copie is designed from the ground up for privacy. Review our [Privacy Policy](PRIVACY_POLICY.md) for details:
- **No telemetry or crash reporting SDKs.**
- **No network sockets or internet calls.**
- **Local storage only.**

If you discover a security vulnerability, please see our [Security Policy](SECURITY.md).

---

## 🤝 Contributing

Contributions, bug reports, and suggestions are welcome!
- Check existing discussions or report a bug via [GitHub Issues](https://github.com/teta0412/copie/issues).
- Please read our [Contributing Guidelines](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md).

---

## 📄 License

Copie is distributed under the [MIT License](LICENSE). Copyright © 2026 teta0412.
