import AppKit
import CryptoKit
import Observation

/// 클립보드 기록 저장소. `~/Library/Application Support/Ledge/Clipboard/` 에 JSON + 이미지 파일로 보관한다.
@MainActor
@Observable
final class ClipboardStore {
    private(set) var entries: [ClipboardEntry] = []

    static let maxTextLength = 200_000

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Ledge/Clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private static var indexURL: URL { directory.appendingPathComponent("history.json") }

    private var saveWorkItem: DispatchWorkItem?

    init(loadPersisted: Bool = true) {
        if loadPersisted { load() }
    }

    // MARK: - 기록

    /// 페이스트보드 내용을 한 건 기록한다. 직전 항목과 같으면 맨 위로만 올린다.
    func capture(from pb: NSPasteboard) {
        guard let entry = makeEntry(from: pb) else { return }
        if let index = entries.firstIndex(where: { $0.digest == entry.digest }) {
            var existing = entries.remove(at: index)
            existing.date = Date()
            entries.insert(existing, at: 0)
            if entry.kind == .image, let file = entry.imageFile {
                try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(file))
            }
        } else {
            entries.insert(entry, at: 0)
            trim()
        }
        scheduleSave()
    }

    private func makeEntry(from pb: NSPasteboard) -> ClipboardEntry? {
        // 파일
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let paths = urls.map { $0.path(percentEncoded: false) }
            return ClipboardEntry(id: UUID(), kind: .files, date: Date(), isPinned: false, text: nil, imageFile: nil,
                                  paths: paths, digest: Self.digest(of: Data(paths.joined(separator: "\n").utf8)))
        }
        // 이미지 (텍스트보다 먼저: 이미지 복사 시 설명 텍스트가 같이 실리는 앱이 있다)
        if SnippetWriter.hasImageData(pb), let png = Self.pngData(from: pb) {
            let digest = Self.digest(of: png)
            let file = "\(UUID().uuidString).png"
            do {
                try png.write(to: Self.directory.appendingPathComponent(file), options: .atomic)
            } catch {
                LedgeLog.write("clipboard: 이미지 저장 실패 \(error)")
                return nil
            }
            return ClipboardEntry(id: UUID(), kind: .image, date: Date(), isPinned: false, text: nil, imageFile: file,
                                  paths: nil, digest: digest)
        }
        // 텍스트
        if let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let clipped = String(text.prefix(Self.maxTextLength))
            return ClipboardEntry(id: UUID(), kind: .text, date: Date(), isPinned: false, text: clipped, imageFile: nil,
                                  paths: nil, digest: Self.digest(of: Data(clipped.utf8)))
        }
        return nil
    }

    private static func pngData(from pb: NSPasteboard) -> Data? {
        if let png = pb.data(forType: .png), !png.isEmpty { return png }
        guard let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 조작

    func togglePin(id: ClipboardEntry.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isPinned.toggle()
        scheduleSave()
    }

    func remove(id: ClipboardEntry.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        if let file = entry.imageFile {
            try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(file))
        }
        scheduleSave()
    }

    /// 고정 항목은 남기고 전부 지운다.
    func removeUnpinned() {
        for entry in entries where !entry.isPinned {
            if let file = entry.imageFile {
                try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(file))
            }
        }
        entries.removeAll { !$0.isPinned }
        scheduleSave()
    }

    func imageURL(for entry: ClipboardEntry) -> URL? {
        entry.imageFile.map { Self.directory.appendingPathComponent($0) }
    }

    /// 기록을 다시 일반 페이스트보드에 쓴다.
    func write(_ entry: ClipboardEntry, to pb: NSPasteboard = .general) {
        pb.clearContents()
        switch entry.kind {
        case .text:
            pb.setString(entry.text ?? "", forType: .string)
        case .image:
            if let url = imageURL(for: entry), let data = try? Data(contentsOf: url) {
                pb.setData(data, forType: .png)
            }
        case .files:
            let urls = (entry.paths ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            pb.writeObjects(urls)
        }
    }

    /// 설정의 보관 개수·기간을 넘는 고정되지 않은 항목을 버린다.
    func trim() {
        let maxItems = AppSettings.shared.clipboardMaxItems
        let maxAge = AppSettings.shared.clipboardMaxAgeDays
        let cutoff = maxAge > 0 ? Date().addingTimeInterval(-Double(maxAge) * 86_400) : Date.distantPast
        var unpinned = 0
        var kept: [ClipboardEntry] = []
        for entry in entries {
            if entry.isPinned {
                kept.append(entry)
            } else if (maxItems == 0 || unpinned < maxItems), entry.date >= cutoff {
                unpinned += 1
                kept.append(entry)
            } else if let file = entry.imageFile {
                try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(file))
            }
        }
        if kept.count != entries.count {
            entries = kept
            scheduleSave()
        }
    }

    // MARK: - 저장

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = entries
        let work = DispatchWorkItem {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: Self.indexURL, options: .atomic)
            }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([ClipboardEntry].self, from: data)) ?? []
        trim()
    }
}
