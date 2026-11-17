# Copie Privacy Policy

**Publisher / Maintainer:** teta0412  
**Contact:** ducna0412@gmail.com  
**Last updated:** November 2026

Copie is an open-source clipboard history application for macOS.

### 1. Data Storage & Local Processing
While running, Copie monitors the system pasteboard for changes and saves readable copies locally on your Mac to enable search and reuse. Saved content may include text, formatted rich text, images, file references, generated thumbnails, and local backups of copied images and regular files that fit within your chosen history storage limit.

All data remains exclusively on your device in your local Application Support directory:
`~/Library/Application Support/Copie`

### 2. Zero Network Connectivity & Telemetry
- Copie contains **no network communication code**.
- Copie collects **no analytics, telemetry, crash reports, or user tracking data**.
- No clipboard data or metadata is ever transmitted over the internet or sent to any server.

### 3. Screen Recording Access
The **Capture Area** feature is strictly user-initiated (`⌃⇧⌘S` or via the menu). macOS requests Screen Recording permission so Copie can capture only the rectangular area you select. The captured snippet is placed on your system clipboard and stored locally in clipboard history.

### 4. Data Control & Retention
- You can clear individual items or your entire clipboard history at any time in **Settings → Delete History**.
- You can adjust the maximum storage limit (default: 1 GB) in Settings.
- Quitting the application immediately stops all clipboard monitoring.
- Deleting the app does not automatically delete your local Application Support files; you can manually remove `~/Library/Application Support/Copie` at any time.

For questions or security concerns, please open an issue at [https://github.com/teta0412/copie/issues](https://github.com/teta0412/copie/issues) or contact `ducna0412@gmail.com`.
