import AppKit
import UniformTypeIdentifiers

/// 파일이 아닌 드롭(브라우저 이미지·파일 프로미스·URL·텍스트)을
/// `~/Library/Application Support/Yonk/Snippets/` 안의 실제 파일로 만든다.
/// 그래야 선반에서 다시 드래그해 어디로든 내보낼 수 있다.
enum SnippetWriter {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Yonk/Snippets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - 이미지

    /// 페이스트보드의 이미지 데이터를 파일로 저장한다. 원본 포맷(PNG/JPEG/GIF…)이 있으면 그대로, 없으면 PNG.
    static func writeImage(from pasteboard: NSPasteboard) -> URL? {
        let preferred: [(NSPasteboard.PasteboardType, String)] = [
            (.png, "png"),
            (NSPasteboard.PasteboardType("public.jpeg"), "jpg"),
            (NSPasteboard.PasteboardType("com.compuserve.gif"), "gif"),
            (NSPasteboard.PasteboardType("org.webmproject.webp"), "webp"),
        ]
        let baseName = suggestedImageName(from: pasteboard)
        for (type, ext) in preferred {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                return write(data: data, name: baseName, ext: ext)
            }
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return write(data: png, name: baseName, ext: "png")
        }
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return write(data: png, name: baseName, ext: "png")
        }
        return nil
    }

    /// 이미지 URL이 같이 실려 있으면 그 파일명을, 없으면 날짜 이름을 쓴다.
    private static func suggestedImageName(from pasteboard: NSPasteboard) -> String {
        if let url = webURL(from: pasteboard) {
            let stem = url.deletingPathExtension().lastPathComponent
            if !stem.isEmpty, stem != "/" { return sanitize(stem) }
        }
        return "이미지 \(timestamp())"
    }

    // MARK: - URL (.webloc)

    static func writeWebLocation(_ url: URL) -> URL? {
        let plist: [String: String] = ["URL": url.absoluteString]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            return nil
        }
        let name = url.host().map(sanitize) ?? "링크 \(timestamp())"
        return write(data: data, name: name, ext: "webloc")
    }

    static func webURL(from pasteboard: NSPasteboard) -> URL? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: false]) as? [URL] else {
            return nil
        }
        return urls.first { !$0.isFileURL }
    }

    // MARK: - 텍스트 (.txt)

    static func writeText(_ text: String) -> URL? {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let stem = String(firstLine.trimmingCharacters(in: .whitespaces).prefix(40))
        let name = stem.isEmpty ? "텍스트 \(timestamp())" : sanitize(stem)
        return write(data: Data(text.utf8), name: name, ext: "txt")
    }

    // MARK: - 공통

    private static func write(data: Data, name: String, ext: String) -> URL? {
        let url = uniqueURL(name: name, ext: ext)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            NSLog("Yonk: 스니펫 저장 실패 \(url.path): \(error)")
            return nil
        }
    }

    static func uniqueURL(name: String, ext: String) -> URL {
        let dir = directory
        var candidate = dir.appendingPathComponent(name).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(name) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    private static func sanitize(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = s.components(separatedBy: bad).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "항목 \(timestamp())" : String(trimmed.prefix(80))
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }
}
