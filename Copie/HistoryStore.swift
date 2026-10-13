import AppKit
import CoreImage
import Foundation
import ImageIO
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum HistoryError: LocalizedError {
    case database(String)
    case missingContent
    case invalidContent

    var errorDescription: String? {
        switch self {
        case .database(let message): return "History database error: \(message)"
        case .missingContent: return "This item is missing saved content and cannot be copied."
        case .invalidContent: return "This item could not be restored to the clipboard."
        }
    }
}

final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [ClipEntry] = []
    @Published private(set) var usedBytes: Int64 = 0
    @Published var notice: String?
    @Published private(set) var limitBytes: Int64

    let rootURL: URL
    private let clipsURL: URL
    private let persistsLimit: Bool
    private var database: OpaquePointer?

    init(rootURL overrideRoot: URL? = nil, limitBytes overrideLimit: Int64? = nil) throws {
        let savedLimit = UserDefaults.standard.object(forKey: "historyLimitBytes") as? Int64
        limitBytes = overrideLimit ?? savedLimit ?? 1_000_000_000
        persistsLimit = overrideRoot == nil
        if let overrideRoot {
            rootURL = overrideRoot
        } else {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            rootURL = support.appendingPathComponent("Copie", isDirectory: true)
        }
        clipsURL = rootURL.appendingPathComponent("Clips", isDirectory: true)
        try FileManager.default.createDirectory(at: clipsURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let dbURL = rootURL.appendingPathComponent("History.sqlite")
        guard sqlite3_open(dbURL.path, &database) == SQLITE_OK else {
            throw HistoryError.database(String(cString: sqlite3_errmsg(database)))
        }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("CREATE TABLE IF NOT EXISTS clips (id TEXT PRIMARY KEY, created REAL NOT NULL, kind TEXT NOT NULL, preview TEXT NOT NULL, bytes INTEGER NOT NULL, digest TEXT NOT NULL, manifest TEXT NOT NULL);")
        try load()
        enrichFileThumbnails()
        try trimToLimit()
    }

    deinit { sqlite3_close(database) }

    func setLimit(_ bytes: Int64) {
        limitBytes = bytes
        if persistsLimit { UserDefaults.standard.set(bytes, forKey: "historyLimitBytes") }
        do { try trimToLimit() } catch { notice = error.localizedDescription }
    }

    @discardableResult
    func add(_ snapshot: ClipboardSnapshot) throws -> Bool {
        guard !snapshot.items.isEmpty else { return false }
        let digest = snapshot.digest
        if entries.first?.digest == digest { return false }
        if snapshot.byteCount > limitBytes {
            notice = "Clipboard item was not saved because it exceeds the \(limitBytes.storageLabel) history limit."
            return false
        }

        let id = UUID()
        let destination = clipsURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let temporary = clipsURL.appendingPathComponent(id.uuidString + ".tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        do {
            var storedItems: [[StoredRepresentation]] = []
            for (itemIndex, item) in snapshot.items.enumerated() {
                var stored: [StoredRepresentation] = []
                for (typeIndex, representation) in item.enumerated() {
                    let name = "\(itemIndex)-\(typeIndex).bin"
                    try representation.data.write(to: temporary.appendingPathComponent(name), options: .atomic)
                    stored.append(StoredRepresentation(type: representation.type, file: name))
                }
                storedItems.append(stored)
            }
            let thumbnail = makeThumbnail(from: snapshot)
            let thumbnailName: String? = thumbnail == nil ? nil : "thumbnail.png"
            if let thumbnail { try thumbnail.write(to: temporary.appendingPathComponent("thumbnail.png"), options: .atomic) }
            let baseSize = snapshot.byteCount + Int64(thumbnail?.count ?? 0)
            let (imageBackups, imageBytes, imageSkipped) = copyImageBackups(from: snapshot, to: temporary,
                                                                             availableBytes: max(0, limitBytes - baseSize))
            let (fileBackups, fileBytes, fileSkipped) = copyFileBackups(from: snapshot, to: temporary,
                                                                        availableBytes: max(0, limitBytes - baseSize - imageBytes))
            let actualSize = baseSize + imageBytes + fileBytes
            if actualSize > limitBytes {
                try? FileManager.default.removeItem(at: temporary)
                notice = "Clipboard item was not saved because it exceeds the \(limitBytes.storageLabel) history limit."
                return false
            }
            let entry = ClipEntry(id: id, createdAt: Date(), kind: snapshot.kind, preview: snapshot.preview,
                                  byteCount: actualSize, digest: digest,
                                  manifest: ClipManifest(items: storedItems, thumbnail: thumbnailName,
                                                         imageBackups: imageBackups.isEmpty ? nil : imageBackups,
                                                         fileBackups: fileBackups.isEmpty ? nil : fileBackups))
            try FileManager.default.moveItem(at: temporary, to: destination)
            do { try insert(entry) } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
            entries.insert(entry, at: 0)
            usedBytes += actualSize
            try trimToLimit()
            notice = imageSkipped || fileSkipped
                ? "A copied file was saved without a full backup because it could not fit in history or could not be read. Keep the original file to paste it later."
                : nil
            return true
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    func pasteboardItems(for entry: ClipEntry) throws -> [NSPasteboardItem] {
        let directory = clipsURL.appendingPathComponent(entry.id.uuidString, isDirectory: true)
        var result: [NSPasteboardItem] = []
        for (itemIndex, representations) in entry.manifest.items.enumerated() {
            if entry.manifest.imageBackups?.contains(where: { $0.itemIndex == itemIndex }) == true {
                result.append(try savedImageItem(for: entry, itemIndex: itemIndex,
                                                 representations: representations, directory: directory))
                continue
            }
            if let backup = entry.manifest.fileBackups?.first(where: { $0.itemIndex == itemIndex }) {
                let url = directory.appendingPathComponent(backup.file)
                guard FileManager.default.fileExists(atPath: url.path) else { throw HistoryError.missingContent }
                let item = NSPasteboardItem()
                guard item.setString(url.absoluteString, forType: .fileURL) else { throw HistoryError.invalidContent }
                result.append(item)
                continue
            }
            if let fileRepresentation = representations.first(where: { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue }),
               let fileData = try? Data(contentsOf: directory.appendingPathComponent(fileRepresentation.file)),
               !fileURLStillExists(fileData) {
                result.append(try savedImageItem(for: entry, itemIndex: itemIndex,
                                                 representations: representations, directory: directory))
                continue
            }
            let item = NSPasteboardItem()
            for representation in representations {
                let url = directory.appendingPathComponent(representation.file)
                guard let data = try? Data(contentsOf: url) else { throw HistoryError.missingContent }
                guard item.setData(data, forType: NSPasteboard.PasteboardType(representation.type)) else { throw HistoryError.invalidContent }
            }
            if !representations.isEmpty { result.append(item) }
        }
        guard !result.isEmpty else { throw HistoryError.invalidContent }
        return result
    }

    private func fileURLStillExists(_ data: Data) -> Bool {
        guard let url = imageFileURL(from: data) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func savedImageItem(for entry: ClipEntry, itemIndex: Int,
                                representations: [StoredRepresentation], directory: URL) throws -> NSPasteboardItem {
        for representation in representations where isImageType(representation.type) {
            if let data = try? Data(contentsOf: directory.appendingPathComponent(representation.file)) {
                return try imagePasteboardItem(data: data, type: representation.type)
            }
        }
        if let backup = entry.manifest.imageBackups?.first(where: { $0.itemIndex == itemIndex }),
           let data = try? Data(contentsOf: directory.appendingPathComponent(backup.file)) {
            return try imagePasteboardItem(data: data, type: backup.type)
        }
        if entry.manifest.items.count == 1,
           let thumbnailURL = thumbnailURL(for: entry),
           let data = try? Data(contentsOf: thumbnailURL) {
            return try imagePasteboardItem(data: data, type: NSPasteboard.PasteboardType.png.rawValue)
        }
        throw HistoryError.missingContent
    }

    private func imagePasteboardItem(data: Data, type: String) throws -> NSPasteboardItem {
        let item = NSPasteboardItem()
        guard item.setData(data, forType: NSPasteboard.PasteboardType(type)) else { throw HistoryError.invalidContent }
        if type != NSPasteboard.PasteboardType.png.rawValue,
           let png = fullSizePNG(from: data) {
            _ = item.setData(png, forType: .png)
        }
        return item
    }

    private func fullSizePNG(from data: Data) -> Data? {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        if let png = CIContext().pngRepresentation(of: image, format: .RGBA8, colorSpace: colorSpace) {
            return png
        }
        if let png = CIContext(options: [.useSoftwareRenderer: true])
            .pngRepresentation(of: image, format: .RGBA8, colorSpace: colorSpace) {
            return png
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: decoded).representation(using: .png, properties: [:])
    }

    private func isImageType(_ type: String) -> Bool {
        type == NSPasteboard.PasteboardType.png.rawValue || type == NSPasteboard.PasteboardType.tiff.rawValue ||
        type.hasPrefix("public.jpeg") || type.hasPrefix("public.heic")
    }

    func thumbnailURL(for entry: ClipEntry) -> URL? {
        guard let name = entry.manifest.thumbnail else { return nil }
        return clipsURL.appendingPathComponent(entry.id.uuidString, isDirectory: true).appendingPathComponent(name)
    }

    func delete(_ entry: ClipEntry) throws {
        try deleteID(entry.id)
        entries.removeAll { $0.id == entry.id }
        usedBytes -= entry.byteCount
    }

    func clear() throws {
        try execute("DELETE FROM clips;")
        for entry in entries {
            try? FileManager.default.removeItem(at: clipsURL.appendingPathComponent(entry.id.uuidString, isDirectory: true))
        }
        entries = []
        usedBytes = 0
        notice = nil
    }

    private func trimToLimit() throws {
        while usedBytes > limitBytes, let oldest = entries.last {
            try delete(oldest)
        }
    }

    private func makeThumbnail(from snapshot: ClipboardSnapshot) -> Data? {
        for representation in snapshot.items.flatMap({ $0 }) {
            if representation.type == NSPasteboard.PasteboardType.fileURL.rawValue,
               let url = imageFileURL(from: representation.data),
               let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let thumbnail = thumbnailData(from: source) {
                return thumbnail
            }
        }
        for representation in snapshot.items.flatMap({ $0 }) {
            guard representation.type == NSPasteboard.PasteboardType.png.rawValue || representation.type == NSPasteboard.PasteboardType.tiff.rawValue || representation.type.hasPrefix("public.jpeg") || representation.type.hasPrefix("public.heic") else { continue }
            if let source = CGImageSourceCreateWithData(representation.data as CFData, nil), let thumbnail = thumbnailData(from: source) {
                return thumbnail
            }
        }
        return nil
    }

    private func copyImageBackups(from snapshot: ClipboardSnapshot, to directory: URL,
                                  availableBytes: Int64) -> ([StoredImageBackup], Int64, Bool) {
        var backups: [StoredImageBackup] = []
        var copiedBytes: Int64 = 0
        var skipped = false
        for (itemIndex, representations) in snapshot.items.enumerated() {
            guard let representation = representations.first(where: { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue }),
                  let url = imageFileURL(from: representation.data),
                  let imageType = backedImageType(for: url),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let fileSize = attributes[.size] as? NSNumber else { continue }
            let size = fileSize.int64Value
            guard size > 0, size <= availableBytes - copiedBytes else {
                skipped = true
                continue
            }
            let name = "image-backup-\(itemIndex).bin"
            let destination = directory.appendingPathComponent(name)
            do {
                try FileManager.default.copyItem(at: url, to: destination)
                let copiedAttributes = try FileManager.default.attributesOfItem(atPath: destination.path)
                let copiedSize = (copiedAttributes[.size] as? NSNumber)?.int64Value ?? 0
                guard copiedSize > 0, copiedSize <= availableBytes - copiedBytes else {
                    try? FileManager.default.removeItem(at: destination)
                    skipped = true
                    continue
                }
                copiedBytes += copiedSize
                backups.append(StoredImageBackup(itemIndex: itemIndex, file: name, type: imageType))
            } catch {
                try? FileManager.default.removeItem(at: destination)
                skipped = true
            }
        }
        return (backups, copiedBytes, skipped)
    }

    private func copyFileBackups(from snapshot: ClipboardSnapshot, to directory: URL,
                                 availableBytes: Int64) -> ([StoredFileBackup], Int64, Bool) {
        var backups: [StoredFileBackup] = []
        var copiedBytes: Int64 = 0
        var skipped = false
        for (itemIndex, representations) in snapshot.items.enumerated() {
            guard let representation = representations.first(where: { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue }),
                  let url = imageFileURL(from: representation.data),
                  backedImageType(for: url) == nil,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let fileSize = attributes[.size] as? NSNumber else { continue }
            let size = fileSize.int64Value
            guard size >= 0, size <= availableBytes - copiedBytes else {
                skipped = true
                continue
            }
            let folder = "file-backup-\(itemIndex)"
            let name = "\(folder)/\(url.lastPathComponent)"
            let destination = directory.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: directory.appendingPathComponent(folder), withIntermediateDirectories: false)
                try FileManager.default.copyItem(at: url, to: destination)
                let copiedAttributes = try FileManager.default.attributesOfItem(atPath: destination.path)
                let copiedSize = (copiedAttributes[.size] as? NSNumber)?.int64Value ?? -1
                guard copiedSize >= 0, copiedSize <= availableBytes - copiedBytes else {
                    try? FileManager.default.removeItem(at: destination)
                    skipped = true
                    continue
                }
                copiedBytes += copiedSize
                backups.append(StoredFileBackup(itemIndex: itemIndex, file: name))
            } catch {
                try? FileManager.default.removeItem(at: destination)
                skipped = true
            }
        }
        return (backups, copiedBytes, skipped)
    }

    private func backedImageType(for url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) as String?,
              type != "com.adobe.pdf" else { return nil }
        return type
    }

    private func imageFileURL(from data: Data) -> URL? {
        guard let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)),
              let url = URL(string: value), url.isFileURL else { return nil }
        return url
    }

    private func thumbnailData(from source: CGImageSource) -> Data? {
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 480, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private func enrichFileThumbnails() {
        var updated = entries
        var addedBytes: Int64 = 0
        for index in updated.indices {
            let entry = updated[index]
            guard entry.kind == .file, entry.manifest.thumbnail == nil else { continue }
            let directory = clipsURL.appendingPathComponent(entry.id.uuidString, isDirectory: true)
            let fileRepresentation = entry.manifest.items.flatMap { $0 }.first { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue }
            guard let fileRepresentation,
                  let data = try? Data(contentsOf: directory.appendingPathComponent(fileRepresentation.file)),
                  let url = imageFileURL(from: data),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumbnail = thumbnailData(from: source) else { continue }
            let thumbnailURL = directory.appendingPathComponent("thumbnail.png")
            do {
                try thumbnail.write(to: thumbnailURL, options: .atomic)
                let manifest = ClipManifest(items: entry.manifest.items, thumbnail: "thumbnail.png",
                                            imageBackups: entry.manifest.imageBackups,
                                            fileBackups: entry.manifest.fileBackups)
                let enriched = ClipEntry(id: entry.id, createdAt: entry.createdAt, kind: entry.kind, preview: entry.preview, byteCount: entry.byteCount + Int64(thumbnail.count), digest: entry.digest, manifest: manifest)
                try update(enriched)
                updated[index] = enriched
                addedBytes += Int64(thumbnail.count)
            } catch {
                try? FileManager.default.removeItem(at: thumbnailURL)
            }
        }
        entries = updated
        usedBytes += addedBytes
    }

    private func update(_ entry: ClipEntry) throws {
        let statement = try prepare("UPDATE clips SET bytes = ?, manifest = ? WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, entry.byteCount)
        let manifest = String(data: try JSONEncoder().encode(entry.manifest), encoding: .utf8)!
        bind(manifest, to: statement, at: 2)
        bind(entry.id.uuidString, to: statement, at: 3)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw HistoryError.database(String(cString: sqlite3_errmsg(database))) }
    }

    private func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorPointer)
            throw HistoryError.database(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw HistoryError.database(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private func insert(_ entry: ClipEntry) throws {
        let statement = try prepare("INSERT INTO clips (id, created, kind, preview, bytes, digest, manifest) VALUES (?, ?, ?, ?, ?, ?, ?);")
        defer { sqlite3_finalize(statement) }
        let manifest = String(data: try JSONEncoder().encode(entry.manifest), encoding: .utf8)!
        bind(entry.id.uuidString, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, entry.createdAt.timeIntervalSince1970)
        bind(entry.kind.rawValue, to: statement, at: 3)
        bind(entry.preview, to: statement, at: 4)
        sqlite3_bind_int64(statement, 5, entry.byteCount)
        bind(entry.digest, to: statement, at: 6)
        bind(manifest, to: statement, at: 7)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw HistoryError.database(String(cString: sqlite3_errmsg(database))) }
    }

    private func deleteID(_ id: UUID) throws {
        let statement = try prepare("DELETE FROM clips WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw HistoryError.database(String(cString: sqlite3_errmsg(database))) }
        try? FileManager.default.removeItem(at: clipsURL.appendingPathComponent(id.uuidString, isDirectory: true))
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, sqliteTransient) }
    }

    private func load() throws {
        let statement = try prepare("SELECT id, created, kind, preview, bytes, digest, manifest FROM clips ORDER BY created DESC;")
        defer { sqlite3_finalize(statement) }
        var loaded: [ClipEntry] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw HistoryError.database(String(cString: sqlite3_errmsg(database))) }
            guard let id = UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))),
                  let kind = ClipKind(rawValue: String(cString: sqlite3_column_text(statement, 2))),
                  let manifestData = String(cString: sqlite3_column_text(statement, 6)).data(using: .utf8),
                  let manifest = try? JSONDecoder().decode(ClipManifest.self, from: manifestData) else { continue }
            loaded.append(ClipEntry(id: id, createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)), kind: kind, preview: String(cString: sqlite3_column_text(statement, 3)), byteCount: sqlite3_column_int64(statement, 4), digest: String(cString: sqlite3_column_text(statement, 5)), manifest: manifest))
        }
        entries = loaded
        usedBytes = loaded.reduce(0) { $0 + $1.byteCount }
    }
}
