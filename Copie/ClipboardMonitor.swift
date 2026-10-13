import AppKit
import Foundation

final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private let history: HistoryStore
    private var timer: Timer?
    private var observedChangeCount = -1

    init(history: HistoryStore) { self.history = history }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func captureNow() { poll() }

    func restore(_ entry: ClipEntry) throws {
        let items = try history.pasteboardItems(for: entry)
        pasteboard.clearContents()
        guard pasteboard.writeObjects(items) else { throw HistoryError.invalidContent }
        observedChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != observedChangeCount else { return }
        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else {
            observedChangeCount = changeCount
            return
        }

        var items: [[ClipboardRepresentation]] = []
        for item in pasteboardItems {
            let representations = item.types.compactMap { type -> ClipboardRepresentation? in
                guard let data = item.data(forType: type) else { return nil }
                return ClipboardRepresentation(type: type.rawValue, data: data)
            }
            if !representations.isEmpty { items.append(representations) }
        }
        guard pasteboard.changeCount == changeCount else { return }
        observedChangeCount = changeCount
        guard !items.isEmpty else { return }
        do { try history.add(ClipboardSnapshot(items: items)) }
        catch { history.notice = "Clipboard item could not be saved: \(error.localizedDescription)" }
    }
}
