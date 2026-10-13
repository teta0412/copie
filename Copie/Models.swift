import AppKit
import CryptoKit
import Foundation

struct ClipboardRepresentation {
    let type: String
    let data: Data
}

struct ClipboardSnapshot {
    let items: [[ClipboardRepresentation]]

    var byteCount: Int64 {
        items.flatMap { $0 }.reduce(0) { $0 + Int64($1.data.count) }
    }

    var digest: String {
        var hasher = SHA256()
        for item in items {
            hasher.update(data: Data([0x01]))
            for representation in item {
                hasher.update(data: Data(representation.type.utf8))
                hasher.update(data: Data([0x00]))
                var length = UInt64(representation.data.count).bigEndian
                withUnsafeBytes(of: &length) { hasher.update(data: Data($0)) }
                hasher.update(data: representation.data)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    var kind: ClipKind {
        let types = items.flatMap { $0.map(\.type) }
        if types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) { return .file }
        if types.contains(where: { $0 == NSPasteboard.PasteboardType.png.rawValue || $0 == NSPasteboard.PasteboardType.tiff.rawValue || $0.hasPrefix("public.jpeg") || $0.hasPrefix("public.heic") }) { return .image }
        if types.contains(NSPasteboard.PasteboardType.html.rawValue) || types.contains(NSPasteboard.PasteboardType.rtf.rawValue) { return .richText }
        return .text
    }

    var preview: String {
        for item in items {
            if let plain = item.first(where: { $0.type == NSPasteboard.PasteboardType.string.rawValue }), let value = String(data: plain.data, encoding: .utf8) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return String(trimmed.prefix(240)) }
            }
            if let file = item.first(where: { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue }), let value = String(data: file.data, encoding: .utf8), let url = URL(string: value) {
                return url.lastPathComponent
            }
        }
        switch kind {
        case .image: return "Image"
        case .file: return "Copied file"
        case .richText: return "Formatted text"
        case .text: return "Clipboard item"
        }
    }
}

enum ClipKind: String, Codable {
    case text, richText, image, file

    var label: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich text"
        case .image: return "Image"
        case .file: return "File"
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}

struct StoredRepresentation: Codable {
    let type: String
    let file: String
}

struct StoredImageBackup: Codable {
    let itemIndex: Int
    let file: String
    let type: String
}

struct StoredFileBackup: Codable {
    let itemIndex: Int
    let file: String
}

struct ClipManifest: Codable {
    let items: [[StoredRepresentation]]
    let thumbnail: String?
    let imageBackups: [StoredImageBackup]?
    let fileBackups: [StoredFileBackup]?

    init(items: [[StoredRepresentation]], thumbnail: String?, imageBackups: [StoredImageBackup]? = nil,
         fileBackups: [StoredFileBackup]? = nil) {
        self.items = items
        self.thumbnail = thumbnail
        self.imageBackups = imageBackups
        self.fileBackups = fileBackups
    }
}

struct ClipEntry: Identifiable {
    let id: UUID
    let createdAt: Date
    let kind: ClipKind
    let preview: String
    let byteCount: Int64
    let digest: String
    let manifest: ClipManifest
}

extension Int64 {
    var storageLabel: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
