import AppKit
import UniformTypeIdentifiers

/// 브라우저·웹 앱에서 끌어온 것(이미지·링크·HTML 선택·텍스트)을 Snippets 폴더의 파일로 만든다.
/// 이미지는 (1) 구형 파일 프로미스(Chrome 계열) (2) 페이스트보드 이미지 데이터 (3) 이미지 URL 다운로드 순으로 받는다.
@MainActor
enum WebImporter {
    /// Chrome·Electron이 쓰는 구형 파일 프로미스 타입. NSFilePromiseReceiver는 이 타입을 읽지 못한다.
    static let legacyPromiseType = NSPasteboard.PasteboardType("Apple files promise pasteboard type")

    static func hasLegacyPromise(_ pb: NSPasteboard) -> Bool {
        pb.types?.contains(legacyPromiseType) ?? false
    }

    // MARK: - 페이스트보드 → 파일 (드롭·클립보드 공용)

    /// 파일 URL이면 그대로, 아니면 웹 내용으로 처리한다.
    static func importContent(from pb: NSPasteboard, completion: @escaping @MainActor ([URL]) -> Void) {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            completion(urls)
            return
        }
        importWebContent(from: pb, completion: completion)
    }

    /// 파일이 아닌 웹 내용: 이미지 데이터 → 이미지 URL 다운로드 → 링크 → HTML → 텍스트 순.
    static func importWebContent(from pb: NSPasteboard, completion: @escaping @MainActor ([URL]) -> Void) {
        YonkLog.write("web import url=\(SnippetWriter.webURL(from: pb)?.absoluteString.prefix(120) ?? "-") html=\(pb.string(forType: .html)?.prefix(160) ?? "-")")
        if let url = SnippetWriter.writeImage(from: pb) {
            completion([url])
            return
        }
        if let imageURL = imageURL(from: pb) {
            let fallback = snapshot(of: pb)
            downloadImage(imageURL, referer: SnippetWriter.webURL(from: pb)) { url in
                if let url { completion([url]) } else { importNonImageWebContent(from: fallback, completion: completion) }
            }
            return
        }
        importNonImageWebContent(from: pb, completion: completion)
    }

    private static func importNonImageWebContent(from pb: NSPasteboard, completion: @MainActor ([URL]) -> Void) {
        let text = pb.string(forType: .string)
        if let web = SnippetWriter.webURL(from: pb), let url = SnippetWriter.writeWebLocation(web) {
            completion([url])
        } else if let html = pb.string(forType: .html), !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let url = SnippetWriter.writeHTML(html, plainText: text) {
            completion([url])
        } else if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let url = SnippetWriter.writeText(text) {
            completion([url])
        } else {
            YonkLog.write("web import: nothing usable, types=\(pb.types?.map(\.rawValue) ?? [])")
            completion([])
        }
    }

    /// 드래그 페이스트보드는 드롭이 끝나면 비워지므로, 비동기 처리용으로 프로미스 타입을 뺀 복사본을 만든다.
    static func snapshot(of pb: NSPasteboard) -> NSPasteboard {
        let copy = NSPasteboard(name: NSPasteboard.Name("com.jasonhwangfilm.yonk.snapshot-\(UUID().uuidString)"))
        copy.clearContents()
        copy.writeObjects(pb.pasteboardItems?.compactMap { copyItem($0) } ?? [])
        return copy
    }

    private static func copyItem(_ item: NSPasteboardItem) -> NSPasteboardItem? {
        let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes + [legacyPromiseType.rawValue])
        let copy = NSPasteboardItem()
        var any = false
        for type in item.types where !promiseTypes.contains(type.rawValue) {
            if let data = item.data(forType: type) {
                copy.setData(data, forType: type)
                any = true
            }
        }
        return any ? copy : nil
    }

    // MARK: - 구형 파일 프로미스

    /// 보내는 쪽이 임시 폴더에 파일을 써 주면, 다 써질 때까지 기다렸다가 Snippets로 옮긴다.
    /// performDragOperation 안에서(동기) 불러야 한다.
    @available(macOS, deprecated: 10.13)
    static func receiveLegacyPromise(_ sender: any NSDraggingInfo, completion: @escaping @MainActor ([URL]) -> Void) -> Bool {
        let incoming = SnippetWriter.directory.appendingPathComponent(".incoming-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        guard let names = sender.namesOfPromisedFilesDropped(atDestination: incoming), !names.isEmpty else {
            try? FileManager.default.removeItem(at: incoming)
            return false
        }
        YonkLog.write("legacy promise names=\(names)")
        let expected = names.map { incoming.appendingPathComponent($0) }
        waitForFiles(expected, previousSizes: [:], attempts: 0) { ready in
            var moved: [URL] = []
            for url in ready {
                let dest = SnippetWriter.uniqueURL(name: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension)
                if (try? FileManager.default.moveItem(at: url, to: dest)) != nil { moved.append(dest) }
            }
            try? FileManager.default.removeItem(at: incoming)
            YonkLog.write("legacy promise received=\(moved.map(\.lastPathComponent))")
            completion(moved)
        }
        return true
    }

    /// 0.2초 간격으로 파일이 생기고 크기가 멈출 때까지(최대 20초) 기다린다.
    private static func waitForFiles(_ urls: [URL], previousSizes: [URL: Int], attempts: Int, completion: @escaping @MainActor ([URL]) -> Void) {
        var sizes: [URL: Int] = [:]
        for url in urls {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), let size = attrs[.size] as? Int, size > 0 {
                sizes[url] = size
            }
        }
        let allStable = urls.allSatisfy { sizes[$0] != nil && sizes[$0] == previousSizes[$0] }
        if allStable || attempts >= 100 {
            completion(urls.filter { sizes[$0] != nil })
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            waitForFiles(urls, previousSizes: sizes, attempts: attempts + 1, completion: completion)
        }
    }

    // MARK: - 이미지 URL

    /// HTML의 <img src> 또는 URL 자체가 이미지를 가리키면 그 URL.
    static func imageURL(from pb: NSPasteboard) -> URL? {
        if let html = pb.string(forType: .html), let src = firstImageSource(in: html) {
            if let url = URL(string: src) { return url }
        }
        if let url = SnippetWriter.webURL(from: pb), looksLikeImage(url) { return url }
        return nil
    }

    private static func firstImageSource(in html: String) -> String? {
        guard let range = html.range(of: #"<img[^>]+src\s*=\s*["']([^"']+)["']"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let tag = String(html[range])
        guard let q = tag.range(of: #"src\s*=\s*["']"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let rest = tag[q.upperBound...]
        guard let end = rest.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        let src = String(rest[..<end]).replacingOccurrences(of: "&amp;", with: "&")
        return src.isEmpty ? nil : src
    }

    private static func looksLikeImage(_ url: URL) -> Bool {
        if url.scheme == "data" { return url.absoluteString.hasPrefix("data:image/") }
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "avif", "svg", "bmp", "tiff", "tif", "heic"].contains(ext)
    }

    /// 이미지 URL을 내려받아 파일로 저장한다. 실패하면 nil.
    static func downloadImage(_ url: URL, referer: URL?, completion: @escaping @MainActor (URL?) -> Void) {
        if url.scheme == "data" {
            completion(decodeDataURI(url))
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let mime = (response as? HTTPURLResponse)?.mimeType ?? response?.mimeType
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            Task { @MainActor in
                guard let data, !data.isEmpty, error == nil, status < 400, let mime, mime.hasPrefix("image/") else {
                    YonkLog.write("image download failed \(url) status=\(status) mime=\(mime ?? "-") err=\(error.map { "\($0)" } ?? "-")")
                    completion(nil)
                    return
                }
                let ext = extensionFor(mime: mime, url: url)
                let stem = url.deletingPathExtension().lastPathComponent
                let name = (stem.isEmpty || stem == "/") ? "이미지 \(SnippetWriter.timestamp())" : SnippetWriter.sanitize(stem)
                completion(SnippetWriter.write(data: data, name: name, ext: ext))
            }
        }
        task.resume()
    }

    private static func decodeDataURI(_ url: URL) -> URL? {
        let s = url.absoluteString
        guard let comma = s.firstIndex(of: ",") else { return nil }
        let header = s[s.index(s.startIndex, offsetBy: 5)..<comma]  // "image/png;base64"
        let payload = String(s[s.index(after: comma)...])
        let mime = header.split(separator: ";").first.map(String.init) ?? "image/png"
        let data: Data?
        if header.contains("base64") {
            data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
        } else {
            data = payload.removingPercentEncoding.flatMap { Data($0.utf8) }
        }
        guard let data, !data.isEmpty else { return nil }
        return SnippetWriter.write(data: data, name: "이미지 \(SnippetWriter.timestamp())", ext: extensionFor(mime: mime, url: nil))
    }

    private static func extensionFor(mime: String, url: URL?) -> String {
        if let url, looksLikeImage(url), url.scheme != "data" { return url.pathExtension.lowercased() }
        if let type = UTType(mimeType: mime), let ext = type.preferredFilenameExtension { return ext }
        switch mime {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/webp": return "webp"
        case "image/avif": return "avif"
        case "image/svg+xml": return "svg"
        default: return "png"
        }
    }
}
