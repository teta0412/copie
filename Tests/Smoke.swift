import AppKit
import Foundation
import SQLite3

@main
struct Smoke {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CopieSmoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lXcAAAAASUVORK5CYII=")!
        let snapshot = ClipboardSnapshot(items: [
            [
                ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data("Hello image".utf8)),
                ClipboardRepresentation(type: NSPasteboard.PasteboardType.html.rawValue, data: Data("<b>Hello image</b>".utf8)),
                ClipboardRepresentation(type: NSPasteboard.PasteboardType.png.rawValue, data: png)
            ],
            [ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data("Second item".utf8))]
        ])

        do {
            let history = try HistoryStore(rootURL: root, limitBytes: 1_000_000)
            try check(history.add(snapshot), "first capture should be stored")
            try check(!history.add(snapshot), "consecutive duplicate should be skipped")
            try check(history.entries.count == 1, "one entry should remain")
            let entry = history.entries[0]
            try check(entry.kind == .image, "image representation should be recognized")
            try check(history.thumbnailURL(for: entry).map { FileManager.default.fileExists(atPath: $0.path) } == true, "image thumbnail should be saved")
            let restored = try history.pasteboardItems(for: entry)
            try check(restored.count == 2, "two pasteboard items should be restored")
            try check(restored[0].data(forType: .png) == png, "PNG bytes should survive storage")
            try check(restored[0].data(forType: .html) == Data("<b>Hello image</b>".utf8), "HTML should survive storage")
            try check(restored[1].string(forType: .string) == "Second item", "second item should survive storage")
            let testPasteboard = NSPasteboard.withUniqueName()
            defer { testPasteboard.releaseGlobally() }
            testPasteboard.clearContents()
            let simple = NSPasteboardItem()
            _ = simple.setString("Test", forType: .string)
            if testPasteboard.writeObjects([simple]) {
                testPasteboard.clearContents()
                try check(testPasteboard.writeObjects(restored), "restored objects should be writable")
                try check(testPasteboard.pasteboardItems?.count == 2, "pasteboard should retain both items")
                try check(testPasteboard.pasteboardItems?.first?.data(forType: .png) == png, "pasteboard should retain image data")
            } else {
                print("Pasteboard server unavailable; storage round trip was verified without server write")
            }
        }

        do {
            let reopened = try HistoryStore(rootURL: root, limitBytes: 1_000_000)
            try check(reopened.entries.count == 1, "history should persist after reopen")
            try check(try reopened.pasteboardItems(for: reopened.entries[0]).count == 2, "persisted entry should restore")
        }

        let fileRoot = root.appendingPathComponent("FilePreview", isDirectory: true)
        let imageFile = root.appendingPathComponent("sample.png")
        try png.write(to: imageFile)
        let fileSnapshot = ClipboardSnapshot(items: [[ClipboardRepresentation(type: NSPasteboard.PasteboardType.fileURL.rawValue, data: Data(imageFile.absoluteString.utf8))]])
        var legacyEntry: ClipEntry!
        do {
            let fileHistory = try HistoryStore(rootURL: fileRoot, limitBytes: 1_000_000)
            try check(fileHistory.add(fileSnapshot), "Finder image file should save")
            legacyEntry = fileHistory.entries[0]
            try check(legacyEntry.kind == .file, "image file should remain a file reference")
            try check(fileHistory.thumbnailURL(for: legacyEntry).map { FileManager.default.fileExists(atPath: $0.path) } == true, "Finder image file should have a thumbnail")
            try check(legacyEntry.manifest.imageBackups?.count == 1, "Finder image file should have a full backup")
            let copiedImage = try fileHistory.pasteboardItems(for: legacyEntry)[0]
            try check(copiedImage.data(forType: .png) == png && copiedImage.data(forType: .fileURL) == nil,
                      "Finder image file with a backup should copy image content")
        }

        let backupFile = root.appendingPathComponent("archived.png")
        try png.write(to: backupFile)
        let backupSnapshot = ClipboardSnapshot(items: [[ClipboardRepresentation(type: NSPasteboard.PasteboardType.fileURL.rawValue, data: Data(backupFile.absoluteString.utf8))]])
        let backupRoot = root.appendingPathComponent("FullImageBackup", isDirectory: true)
        let backed = try HistoryStore(rootURL: backupRoot, limitBytes: 1_000_000)
        try check(backed.add(backupSnapshot), "image file with full backup should save")
        let backedEntry = backed.entries[0]
        try check(try backed.pasteboardItems(for: backedEntry)[0].data(forType: .png) == png,
                  "existing image file with a backup should paste as an image")

        let backupSize = Int64(png.count)
        let limitedRoot = root.appendingPathComponent("ThumbnailFallback", isDirectory: true)
        let limited = try HistoryStore(rootURL: limitedRoot, limitBytes: backedEntry.byteCount - backupSize)
        try check(limited.add(backupSnapshot), "image file should save when full backup is over the limit")
        try check(limited.entries[0].manifest.imageBackups == nil, "oversized image backup should be skipped")
        try check(limited.notice != nil, "skipped full backup should be explained")

        try FileManager.default.removeItem(at: backupFile)
        let backedImage = try backed.pasteboardItems(for: backedEntry)[0]
        try check(backedImage.data(forType: .png) == png && backedImage.data(forType: .fileURL) == nil,
                  "deleted image file should paste its full-quality backup")
        let imagePasteboard = NSPasteboard.withUniqueName()
        defer { imagePasteboard.releaseGlobally() }
        imagePasteboard.clearContents()
        if imagePasteboard.writeObjects([backedImage]) {
            try check(imagePasteboard.pasteboardItems?.first?.data(forType: .png) == png,
                      "deleted image backup should survive a pasteboard write")
        } else {
            print("Pasteboard server unavailable; image backup storage was verified without server write")
        }
        let reopenedBackup = try HistoryStore(rootURL: backupRoot, limitBytes: 1_000_000)
        try check(try reopenedBackup.pasteboardItems(for: reopenedBackup.entries[0])[0].data(forType: .png) == png,
                  "full image backup should survive reopening")
        let thumbnailFallback = try limited.pasteboardItems(for: limited.entries[0])[0]
        try check(thumbnailFallback.data(forType: .png) != nil && thumbnailFallback.data(forType: .fileURL) == nil,
                  "older image file should paste its thumbnail when the original is gone")

        let oldManifest = ClipManifest(items: legacyEntry.manifest.items, thumbnail: nil)
        let oldJSON = String(data: try JSONEncoder().encode(oldManifest), encoding: .utf8)!
        var database: OpaquePointer?
        try check(sqlite3_open(fileRoot.appendingPathComponent("History.sqlite").path, &database) == SQLITE_OK, "legacy database should open")
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(database, "UPDATE clips SET bytes = ?, manifest = ? WHERE id = ?;", -1, &statement, nil) == SQLITE_OK, "legacy update should prepare")
        sqlite3_bind_int64(statement, 1, fileSnapshot.byteCount)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = oldJSON.withCString { sqlite3_bind_text(statement, 2, $0, -1, transient) }
        _ = legacyEntry.id.uuidString.withCString { sqlite3_bind_text(statement, 3, $0, -1, transient) }
        try check(sqlite3_step(statement) == SQLITE_DONE, "legacy update should complete")
        sqlite3_finalize(statement)
        sqlite3_close(database)
        try FileManager.default.removeItem(at: fileRoot.appendingPathComponent("Clips/\(legacyEntry.id.uuidString)/thumbnail.png"))
        let migrated = try HistoryStore(rootURL: fileRoot, limitBytes: 1_000_000)
        try check(migrated.thumbnailURL(for: migrated.entries[0]).map { FileManager.default.fileExists(atPath: $0.path) } == true, "existing Finder image entry should gain a thumbnail")
        try FileManager.default.removeItem(at: imageFile)
        let legacyFallback = try migrated.pasteboardItems(for: migrated.entries[0])[0]
        try check(legacyFallback.data(forType: .png) != nil && legacyFallback.data(forType: .fileURL) == nil,
                  "legacy image file should paste its thumbnail after deletion")

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        let pixelColor = NSColor(calibratedRed: 0.9, green: 0.2, blue: 0.1, alpha: 1)
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(pixelColor, atX: x, y: y) } }
        let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
        let jpegFile = root.appendingPathComponent("finder-image.jpg")
        try jpeg.write(to: jpegFile)
        let finderSnapshot = ClipboardSnapshot(items: [[
            ClipboardRepresentation(type: NSPasteboard.PasteboardType.fileURL.rawValue,
                                    data: Data(jpegFile.absoluteString.utf8)),
            ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue,
                                    data: Data("finder-image.jpg".utf8))
        ]])
        let finderHistory = try HistoryStore(rootURL: root.appendingPathComponent("FinderJPEG"), limitBytes: 1_000_000)
        try check(finderHistory.add(finderSnapshot), "Finder JPEG with a text name should save")
        let referenceURL = (jpegFile as NSURL).fileReferenceURL()!
        let referenceSnapshot = ClipboardSnapshot(items: [[
            ClipboardRepresentation(type: NSPasteboard.PasteboardType.fileURL.rawValue,
                                    data: Data(referenceURL.absoluteString.utf8)),
            ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue,
                                    data: Data("finder-image.jpg".utf8))
        ]])
        let referenceHistory = try HistoryStore(rootURL: root.appendingPathComponent("FinderReference"), limitBytes: 1_000_000)
        try check(referenceHistory.add(referenceSnapshot), "Finder file-reference JPEG should save")
        try check(referenceHistory.entries[0].manifest.imageBackups?.count == 1,
                  "Finder file-reference JPEG should have a backup")
        try FileManager.default.removeItem(at: jpegFile)
        let finderRestore = try finderHistory.pasteboardItems(for: finderHistory.entries[0])[0]
        try check(finderRestore.data(forType: NSPasteboard.PasteboardType("public.jpeg")) == jpeg,
                  "deleted Finder JPEG should restore its full image")
        try check(finderRestore.data(forType: .png) != nil,
                  "deleted Finder JPEG should offer PNG for paste targets that cannot read JPEG")
        try check(finderRestore.data(forType: .string) == nil && finderRestore.data(forType: .fileURL) == nil,
                  "deleted Finder JPEG should not restore its file name or stale URL")
        let finderPasteboard = NSPasteboard.withUniqueName()
        defer { finderPasteboard.releaseGlobally() }
        finderPasteboard.clearContents()
        if finderPasteboard.writeObjects([finderRestore]) {
            let pasted = finderPasteboard.pasteboardItems?.first
            try check(pasted?.data(forType: NSPasteboard.PasteboardType("public.jpeg")) == jpeg &&
                      pasted?.data(forType: .string) == nil,
                      "deleted Finder JPEG should write only image data to the pasteboard")
        } else {
            print("Pasteboard server unavailable; Finder JPEG restore was verified without server write")
        }
        let referenceRestore = try referenceHistory.pasteboardItems(for: referenceHistory.entries[0])[0]
        try check(referenceRestore.data(forType: NSPasteboard.PasteboardType("public.jpeg")) == jpeg &&
                  referenceRestore.data(forType: .string) == nil && referenceRestore.data(forType: .fileURL) == nil,
                  "deleted Finder file-reference JPEG should restore its backup instead of its file name")

        let document = root.appendingPathComponent("Project Notes.txt")
        let documentData = Data("Saved document contents".utf8)
        try documentData.write(to: document)
        let documentSnapshot = ClipboardSnapshot(items: [[
            ClipboardRepresentation(type: NSPasteboard.PasteboardType.fileURL.rawValue,
                                    data: Data(document.absoluteString.utf8)),
            ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue,
                                    data: Data(document.lastPathComponent.utf8))
        ]])
        let documentRoot = root.appendingPathComponent("DocumentBackup")
        let documents = try HistoryStore(rootURL: documentRoot, limitBytes: 1_000_000)
        try check(documents.add(documentSnapshot), "regular Finder file should save")
        let documentEntry = documents.entries[0]
        try check(documentEntry.manifest.fileBackups?.count == 1,
                  "regular Finder file should have a full backup")
        try check(documentEntry.byteCount == documentSnapshot.byteCount + Int64(documentData.count),
                  "regular file backup should count toward history storage")
        let documentBackup = documentRoot.appendingPathComponent("Clips/\(documentEntry.id.uuidString)/\(documentEntry.manifest.fileBackups![0].file)")
        try check(documentBackup.lastPathComponent == document.lastPathComponent &&
                  (try Data(contentsOf: documentBackup)) == documentData,
                  "regular file backup should preserve its name and contents")
        try check(try documents.pasteboardItems(for: documentEntry)[0].string(forType: .fileURL) == documentBackup.absoluteString,
                  "regular file should use its saved copy while the original still exists")
        let limitedDocuments = try HistoryStore(rootURL: root.appendingPathComponent("DocumentWithoutBackup"),
                                                limitBytes: documentSnapshot.byteCount)
        try check(limitedDocuments.add(documentSnapshot), "file reference should save when its backup cannot fit")
        try check(limitedDocuments.entries[0].manifest.fileBackups == nil && limitedDocuments.notice != nil,
                  "skipped regular file backup should be visible")
        let documentReference = (document as NSURL).fileReferenceURL()!
        let referenceDocumentSnapshot = ClipboardSnapshot(items: [[ClipboardRepresentation(
            type: NSPasteboard.PasteboardType.fileURL.rawValue,
            data: Data(documentReference.absoluteString.utf8))]])
        let referencedDocuments = try HistoryStore(rootURL: root.appendingPathComponent("DocumentFileReference"), limitBytes: 1_000_000)
        try check(referencedDocuments.add(referenceDocumentSnapshot), "Finder file-reference document should save")
        try check(referencedDocuments.entries[0].manifest.fileBackups?.count == 1,
                  "Finder file-reference document should have a backup")
        try FileManager.default.removeItem(at: document)
        let documentRestore = try documents.pasteboardItems(for: documentEntry)[0]
        try check(documentRestore.string(forType: .fileURL) == documentBackup.absoluteString &&
                  documentRestore.data(forType: .string) == nil,
                  "deleted regular file should paste its saved copy, not its name")
        let documentPasteboard = NSPasteboard.withUniqueName()
        defer { documentPasteboard.releaseGlobally() }
        documentPasteboard.clearContents()
        if documentPasteboard.writeObjects([documentRestore]) {
            try check(documentPasteboard.pasteboardItems?.first?.string(forType: .fileURL) == documentBackup.absoluteString,
                      "saved regular file should survive a pasteboard write")
            let readableFile = (documentPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first
            try check(readableFile?.path == documentBackup.path,
                      "saved regular file should be recognized as a file URL by paste targets")
        } else {
            print("Pasteboard server unavailable; regular file backup was verified without server write")
        }
        let reopenedDocuments = try HistoryStore(rootURL: documentRoot, limitBytes: 1_000_000)
        try check(try reopenedDocuments.pasteboardItems(for: reopenedDocuments.entries[0])[0].string(forType: .fileURL) == documentBackup.absoluteString,
                  "regular file backup should survive reopening")
        let referencedBackup = root.appendingPathComponent("DocumentFileReference/Clips/\(referencedDocuments.entries[0].id.uuidString)/\(referencedDocuments.entries[0].manifest.fileBackups![0].file)")
        try check(referencedBackup.lastPathComponent == document.lastPathComponent &&
                  (try Data(contentsOf: referencedBackup)) == documentData &&
                  (try referencedDocuments.pasteboardItems(for: referencedDocuments.entries[0])[0].string(forType: .fileURL)) == referencedBackup.absoluteString,
                  "deleted Finder file-reference document should paste a saved file with its original name")
        var missingUnbackedFile = false
        do { _ = try limitedDocuments.pasteboardItems(for: limitedDocuments.entries[0]) }
        catch HistoryError.missingContent { missingUnbackedFile = true }
        try check(missingUnbackedFile, "deleted file without a backup should report missing content")

        let folder = root.appendingPathComponent("NotBackedUp", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let folderSnapshot = ClipboardSnapshot(items: [[ClipboardRepresentation(type: NSPasteboard.PasteboardType.fileURL.rawValue,
                                                                               data: Data(folder.absoluteString.utf8))]])
        let folderHistory = try HistoryStore(rootURL: root.appendingPathComponent("FolderReference"), limitBytes: 1_000_000)
        try check(folderHistory.add(folderSnapshot), "folder reference should save")
        try check(folderHistory.entries[0].manifest.fileBackups == nil,
                  "folder contents should not be backed up")

        let trimRoot = root.appendingPathComponent("Trim", isDirectory: true)
        let trimmed = try HistoryStore(rootURL: trimRoot, limitBytes: 220)
        let first = ClipboardSnapshot(items: [[ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(repeating: 65, count: 150))]])
        let second = ClipboardSnapshot(items: [[ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(repeating: 66, count: 150))]])
        try check(trimmed.add(first), "first trim candidate should save")
        try check(trimmed.add(second), "second trim candidate should save")
        try check(trimmed.entries.count == 1 && trimmed.entries[0].digest == second.digest, "oldest item should be trimmed")
        let oversized = ClipboardSnapshot(items: [[ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(repeating: 67, count: 300))]])
        try check(!trimmed.add(oversized), "oversized item should be skipped")
        try check(trimmed.notice != nil, "oversized skip should have a visible reason")

        let file = ClipboardSnapshot(items: [[ClipboardRepresentation(type: NSPasteboard.PasteboardType.fileURL.rawValue, data: Data("file:///tmp/example.png".utf8))]])
        try check(file.kind == .file, "Finder file URLs should remain files")
        print("Copie smoke tests passed")
    }

    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw NSError(domain: "CopieSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}
