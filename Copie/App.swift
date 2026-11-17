import AppKit
import SwiftUI

@main
struct CopieMain {
    private static let delegate = AppController()

    static func main() {
        let application = NSApplication.shared
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

final class PickerState: ObservableObject {
    @Published var query = ""
    @Published var selectedIndex = 0
    @Published var keyboardScrollTarget: UUID?

    func filtered(_ entries: [ClipEntry]) -> [ClipEntry] {
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.preview.localizedCaseInsensitiveContains(query) || $0.kind.label.localizedCaseInsensitiveContains(query) }
    }
}

final class AppController: NSObject, NSApplicationDelegate {
    private var history: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var hotKey: HotKeyManager!
    private var statusItem: NSStatusItem!
    private var pickerPopover: NSPopover?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var keyboardMonitor: Any?
    private var captureProcess: Process?
    private let pickerState = PickerState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { history = try HistoryStore() }
        catch {
            let alert = NSAlert()
            alert.messageText = "Copie could not open its history"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        monitor = ClipboardMonitor(history: history)
        hotKey = HotKeyManager()
        hotKey.onOpenHistory = { [weak self] in self?.togglePicker() }
        hotKey.onCaptureArea = { [weak self] in self?.captureArea() }
        setupMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "com.local.Copie.statusItem"
        let menuIcon = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Copie clipboard history")
        menuIcon?.size = NSSize(width: 18, height: 18)
        menuIcon?.isTemplate = true
        statusItem.button?.image = menuIcon
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleProportionallyDown
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.target = self
        statusItem.button?.toolTip = "Copie — clipboard history (Right-click for options)"
        statusItem.isVisible = true
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.button?.needsDisplay = true
            self?.primeStatusItem()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.monitor.start() }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "q" {
                NSApp.terminate(nil)
                return nil
            }
            guard self.pickerPopover?.isShown == true else { return event }
            let visible = self.pickerState.filtered(self.history.entries)
            switch event.keyCode {
            case 125:
                self.pickerState.selectedIndex = min(max(visible.count - 1, 0), self.pickerState.selectedIndex + 1)
                if visible.indices.contains(self.pickerState.selectedIndex) {
                    self.pickerState.keyboardScrollTarget = visible[self.pickerState.selectedIndex].id
                }
                return nil
            case 126:
                self.pickerState.selectedIndex = max(0, self.pickerState.selectedIndex - 1)
                if visible.indices.contains(self.pickerState.selectedIndex) {
                    self.pickerState.keyboardScrollTarget = visible[self.pickerState.selectedIndex].id
                }
                return nil
            case 36, 76:
                if visible.indices.contains(self.pickerState.selectedIndex) { self.select(visible[self.pickerState.selectedIndex]) }
                return nil
            case 53:
                self.pickerPopover?.performClose(nil)
                return nil
            default: return event
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusMenu()
        } else {
            togglePicker()
        }
    }

    @objc private func showStatusMenu() {
        pickerPopover?.performClose(nil)
        let menu = NSMenu()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let header = NSMenuItem(title: "Copie \(version)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: "Open History", action: #selector(openHistoryFromMenu), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let captureItem = NSMenuItem(title: "Capture Screen Area", action: #selector(captureAreaFromMenu), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About Copie", action: #selector(openAboutFromMenu), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Copie", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.popUpMenu(menu)
    }

    @objc private func openHistoryFromMenu() { showPicker() }
    @objc private func captureAreaFromMenu() { captureArea() }
    @objc private func openSettingsFromMenu() { showSettings() }
    @objc private func openAboutFromMenu() { showAbout() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let aboutItem = NSMenuItem(title: "About Copie", action: #selector(openAboutFromMenu), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        appMenu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Copie", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)

        NSApp.mainMenu = mainMenu
    }

    private func primeStatusItem() {
        guard let button = statusItem.button else { return }
        let previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        let warmup = NSPopover()
        warmup.animates = false
        warmup.behavior = .applicationDefined
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        warmup.contentViewController = controller
        warmup.contentSize = NSSize(width: 1, height: 1)
        warmup.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            warmup.performClose(nil)
            guard let self, self.pickerPopover?.isShown != true,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier else { return }
            if previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier,
               previousApp?.activate(options: []) != true {
                NSApp.deactivate()
            }
        }
    }

    private func togglePicker() {
        if pickerPopover?.isShown == true {
            pickerPopover?.performClose(nil)
            return
        }
        showPicker()
    }

    private func showPicker() {
        pickerState.query = ""
        pickerState.selectedIndex = 0
        pickerState.keyboardScrollTarget = nil
        guard let button = statusItem.button else { return }
        let screen = button.window?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let availableHeight = (button.window?.frame.minY ?? visibleFrame.maxY) - visibleFrame.minY - 12
        let size = NSSize(width: min(540, visibleFrame.width - 20), height: min(570, max(1, availableHeight)))
        let popover = pickerPopover ?? NSPopover()
        popover.behavior = .transient
        popover.animates = false
        let content = PickerView(history: history, state: pickerState, stackedFooter: size.width < 510,
                                 onSelect: { [weak self] entry in self?.select(entry) },
                                 onCapture: { [weak self] in self?.captureArea() },
                                 onSettings: { [weak self] in self?.showSettings() },
                                 onAbout: { [weak self] in self?.showAbout() },
                                 onQuit: { NSApp.terminate(nil) })
            .frame(width: size.width, height: size.height)
        let host = NSHostingController(rootView: content)
        host.sizingOptions = []
        popover.contentViewController = host
        popover.contentSize = size
        pickerPopover = popover
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func select(_ entry: ClipEntry) {
        do {
            try monitor.restore(entry)
            pickerPopover?.performClose(nil)
        } catch { history.notice = error.localizedDescription }
    }

    private func captureArea() {
        guard captureProcess?.isRunning != true else { return }
        pickerPopover?.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-c", "-t", "png"]
            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.captureProcess = nil
                    self?.monitor.captureNow()
                }
            }
            self.captureProcess = process
            do { try process.run() }
            catch {
                self.captureProcess = nil
                self.history.notice = "Screen capture could not start: \(error.localizedDescription)"
            }
        }
    }

    private func showSettings() {
        pickerPopover?.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 580), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Copie Settings"
            window.isReleasedWhenClosed = false
            let content = SettingsView(history: history, hotKey: hotKey)
                .frame(width: 590, height: 580)
            let host = NSHostingController(rootView: content)
            host.sizingOptions = []
            window.contentViewController = host
            window.contentMinSize = NSSize(width: 590, height: 580)
            window.setContentSize(NSSize(width: 590, height: 580))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAbout() {
        pickerPopover?.performClose(nil)
        if aboutWindow == nil {
            let size = NSSize(width: 420, height: 400)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "About Copie"
            window.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: AboutView().frame(width: size.width, height: size.height))
            host.sizingOptions = []
            window.contentViewController = host
            window.center()
            aboutWindow = window
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

}
