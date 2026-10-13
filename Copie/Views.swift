import AppKit
import ImageIO
import ServiceManagement
import SwiftUI

private enum Palette {
    static let ink = Color.primary
    static let muted = Color.secondary
    static let accent = Color(red: 0.30, green: 0.42, blue: 0.82)
    static let image = Color(red: 0.20, green: 0.58, blue: 0.68)
    static let file = Color(red: 0.74, green: 0.47, blue: 0.20)

    static func color(for kind: ClipKind) -> Color {
        switch kind {
        case .text, .richText: accent
        case .image: image
        case .file: file
        }
    }
}

struct PickerView: View {
    @ObservedObject var history: HistoryStore
    @ObservedObject var state: PickerState
    let stackedFooter: Bool
    let onSelect: (ClipEntry) -> Void
    let onCapture: () -> Void
    let onSettings: () -> Void
    let onAbout: () -> Void
    let onQuit: () -> Void
    @FocusState private var searchFocused: Bool

    private var visible: [ClipEntry] { state.filtered(history.entries) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Copie").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("Clipboard history").font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text(history.usedBytes.storageLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 17)

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Search text, images, files", text: $state.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 17)
            .padding(.bottom, 12)

            Divider()

            if let notice = history.notice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text(notice).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { history.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss message")
                }
                .padding(10)
                .background(Color.orange.opacity(0.09))
                .padding(.horizontal, 17)
                .padding(.top, 10)
            }

            if visible.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: state.query.isEmpty ? "square.on.square" : "magnifyingglass")
                        .font(.system(size: 30, weight: .ultraLight))
                        .foregroundStyle(Palette.muted)
                    Text(state.query.isEmpty ? "Copy something to start" : "No matching items")
                        .font(.system(size: 15, weight: .medium))
                    Text(state.query.isEmpty ? "Text, images, and files will appear here." : "Try a different search.")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                                Button { onSelect(entry) } label: {
                                    ClipRow(entry: entry, thumbnailURL: history.thumbnailURL(for: entry), selected: index == state.selectedIndex)
                                }
                                .buttonStyle(.plain)
                                .id(entry.id)
                                .contextMenu {
                                    Button("Copy to Clipboard") { onSelect(entry) }
                                    Button("Delete", role: .destructive) {
                                        do { try history.delete(entry) } catch { history.notice = error.localizedDescription }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                    }
                    .onChange(of: state.keyboardScrollTarget) { _, target in
                        if let target { proxy.scrollTo(target, anchor: .center) }
                    }
                }
            }

            Divider()
            Group {
                if stackedFooter {
                    VStack(spacing: 10) {
                        footerHint.frame(maxWidth: .infinity, alignment: .leading)
                        footerActions.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                } else {
                    HStack(spacing: 12) {
                        footerHint
                        Spacer(minLength: 4)
                        footerActions
                    }
                    .frame(height: 50)
                }
            }
            .padding(.horizontal, 19)
        }
        .background(.regularMaterial)
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
        .onChange(of: state.query) { _, _ in
            state.selectedIndex = 0
            state.keyboardScrollTarget = nil
        }
        .onChange(of: history.entries.count) { _, _ in state.selectedIndex = min(state.selectedIndex, max(visible.count - 1, 0)) }
    }

    private var footerHint: some View {
        Text("↩ Copy selected   ·   ⌘V Paste")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var footerActions: some View {
        HStack(spacing: 14) {
                Button(action: onCapture) {
                    Label("Capture Area", systemImage: "camera.viewfinder")
                        .font(.system(size: 11, weight: .medium))
                }
                .help("Select a screen area and copy it to history")
                Button(action: onSettings) { Image(systemName: "gearshape") }.help("Settings")
                Button(action: onAbout) { Image(systemName: "info.circle") }
                    .help("About Copie")
                    .accessibilityLabel("About Copie")
                Button(action: onQuit) { Image(systemName: "power") }.help("Quit Copie")
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private enum AboutDetails {
    // Replace these placeholders with the developer's public contact details.
    static let developerName = "Developer name not configured"
    static let supportEmail = "ducna0412@gmail.com"
    static let coffeeURL = ""

    static var bugReportURL: URL? {
        let email = supportEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
              !email.contains(where: \.isWhitespace) else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: "Copie bug report")]
        return components.url
    }

    static var donationURL: URL? {
        guard let url = URL(string: coffeeURL), url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }
}

struct AboutView: View {
    @State private var linkError: String?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 76, height: 76)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Copie")
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }

            VStack(spacing: 7) {
                Text("DEVELOPER")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.accent)
                Text(AboutDetails.developerName)
                    .foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button("Report a Bug") { open(AboutDetails.bugReportURL) }
                    .disabled(AboutDetails.bugReportURL == nil)
                Button("Buy Me a Coffee ☕") { open(AboutDetails.donationURL) }
                    .disabled(AboutDetails.donationURL == nil)
            }
            if AboutDetails.bugReportURL == nil {
                Text("Bug report email not configured")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            } else {
                Text(AboutDetails.supportEmail)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            if AboutDetails.donationURL == nil {
                Text("Coffee link not configured")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            if let linkError {
                Text(linkError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        linkError = NSWorkspace.shared.open(url) ? nil : "Could not open this link. Check your default app settings."
    }
}

private struct ClipRow: View {
    let entry: ClipEntry
    let thumbnailURL: URL?
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Palette.color(for: entry.kind))
                .frame(width: 3, height: 55)
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Palette.color(for: entry.kind).opacity(0.10))
                if let thumbnailURL {
                    ClipThumbnail(url: thumbnailURL)
                } else {
                    Image(systemName: entry.kind.symbol)
                        .font(.system(size: 21, weight: .light))
                        .foregroundStyle(Palette.color(for: entry.kind))
                }
            }
            .frame(width: 57, height: 55)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.preview.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text(entry.kind == .file && thumbnailURL != nil ? "IMAGE FILE" : entry.kind.label.uppercased())
                        .foregroundStyle(thumbnailURL != nil ? Palette.image : Palette.color(for: entry.kind))
                    Text(entry.createdAt, style: .relative)
                    Text("·")
                    Text(entry.byteCount.storageLabel)
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.muted)
            }
            if selected { Image(systemName: "return").font(.caption).foregroundStyle(Palette.muted) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(selected || hovered ? Palette.accent.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 11))
        .contentShape(RoundedRectangle(cornerRadius: 11))
        .onHover { hovered = $0 }
    }
}

@MainActor
private final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let images = NSCache<NSURL, NSImage>()

    private init() { images.totalCostLimit = 32 * 1024 * 1024 }

    func image(for url: URL) async -> NSImage? {
        if let cached = images.object(forKey: url as NSURL) { return cached }
        let thumbnail = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 160
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        guard let thumbnail else { return nil }
        let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
        images.setObject(image, forKey: url as NSURL, cost: thumbnail.width * thumbnail.height * 4)
        return image
    }
}

private struct ClipThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(4)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(Palette.image)
            }
        }
        .task(id: url) {
            image = nil
            let loaded = await ThumbnailCache.shared.image(for: url)
            if !Task.isCancelled { image = loaded }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var history: HistoryStore
    @ObservedObject var hotKey: HotKeyManager
    @State private var selectedLimit: Int64 = 1_000_000_000
    @State private var launchAtLogin = false
    @State private var loginMessage: String?
    @State private var recordingAction: HotKeyAction?
    @State private var recordingMonitor: Any?
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("Clipboard history stays on this Mac.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "square.on.square").font(.title2).foregroundStyle(Palette.accent)
            }
            .padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    settingsSection("General") {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Open history")
                                Text("Press the shortcut while using another app.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(recordingAction == .openHistory ? "Press shortcut…" : hotKey.shortcut.label) { beginRecording(for: .openHistory) }
                                .frame(minWidth: 120)
                        }
                        if let message = hotKey.statusMessage { Text(message).font(.caption).foregroundStyle(.orange) }
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Capture screen area")
                                Text("Select an area and copy the image to history.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(recordingAction == .captureArea ? "Press shortcut…" : hotKey.captureShortcut.label) { beginRecording(for: .captureArea) }
                                .frame(minWidth: 120)
                        }
                        if let message = hotKey.captureStatusMessage { Text(message).font(.caption).foregroundStyle(.orange) }
                        Divider()
                        Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                        if let loginMessage { Text(loginMessage).font(.caption).foregroundStyle(.orange) }
                    }

                    settingsSection("Storage") {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Used").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(history.usedBytes.storageLabel) / \(history.limitBytes.storageLabel)")
                                .font(.system(.body, design: .monospaced))
                        }
                        ProgressView(value: Double(history.usedBytes), total: Double(max(history.limitBytes, 1)))
                            .tint(Palette.accent)
                        Picker("History limit", selection: $selectedLimit) {
                            Text("250 MB").tag(Int64(250_000_000))
                            Text("1 GB").tag(Int64(1_000_000_000))
                            Text("5 GB").tag(Int64(5_000_000_000))
                        }
                        .onChange(of: selectedLimit) { _, newValue in history.setLimit(newValue) }
                        Text("Oldest entries are removed when history exceeds this limit. Finder files remain at their original locations.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    settingsSection("Manage history") {
                        HStack {
                            Text("\(history.entries.count) saved items").foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear History", role: .destructive) { confirmClear = true }
                                .disabled(history.entries.isEmpty)
                        }
                        LazyVStack(spacing: 12) {
                            ForEach(history.entries) { entry in
                                Divider()
                                HStack(spacing: 8) {
                                    Image(systemName: entry.kind.symbol).foregroundStyle(Palette.color(for: entry.kind)).frame(width: 20)
                                    Text(entry.preview.replacingOccurrences(of: "\n", with: " ")).lineLimit(1)
                                    Spacer()
                                    Text(entry.byteCount.storageLabel).font(.caption).foregroundStyle(.secondary)
                                    Button { do { try history.delete(entry) } catch { history.notice = error.localizedDescription } } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Delete item")
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 500, minHeight: 500)
        .onAppear {
            selectedLimit = history.limitBytes
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onDisappear { stopRecording() }
        .confirmationDialog("Delete all clipboard history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) {
                do { try history.clear() } catch { history.notice = error.localizedDescription }
            }
        } message: { Text("This removes saved text, images, and rich content from Copie.") }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginMessage = enabled && !launchAtLogin ? "Allow Copie in System Settings → Login Items to finish enabling it." : nil
        } catch { loginMessage = error.localizedDescription }
    }

    private func beginRecording(for action: HotKeyAction) {
        stopRecording()
        recordingAction = action
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stopRecording(); return nil }
            guard let shortcut = Shortcut.from(event) else { return nil }
            hotKey.change(to: shortcut, for: action)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor) }
        recordingMonitor = nil
        recordingAction = nil
    }
}
