import AppKit

/// 파일 경로를 채팅 앱에 붙여 쓸 수 있는 링크 형식으로 바꾼다.
/// 공백·`%`·`#`·`?`·`()`·`[]`만 퍼센트 인코딩하고 한글 등은 그대로 둔다.
enum LinkFormatter {
    enum Kind { case markdown, path }

    /// `addingPercentEncoding`은 허용 집합과 무관하게 비ASCII를 인코딩하므로, 대상 8개 문자만 직접 바꾼다.
    private static let reserved: [Character: String] = [
        " ": "%20", "%": "%25", "#": "%23", "?": "%3F", "(": "%28", ")": "%29", "[": "%5B", "]": "%5D",
    ]

    static func linkPath(_ url: URL) -> String {
        url.path(percentEncoded: false).map { reserved[$0] ?? String($0) }.joined()
    }

    static func markdownLink(_ url: URL) -> String {
        let name = url.lastPathComponent.replacingOccurrences(of: "]", with: "\\]")
        return "[\(name)](\(linkPath(url)))"
    }

    static func text(_ urls: [URL], as kind: Kind) -> String {
        urls.map { kind == .markdown ? markdownLink($0) : linkPath($0) }.joined(separator: "\n")
    }

    static func copy(_ urls: [URL], as kind: Kind) {
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text(urls, as: kind), forType: .string)
    }
}
