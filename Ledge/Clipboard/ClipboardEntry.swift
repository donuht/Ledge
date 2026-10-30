import AppKit

/// 클립보드 기록 한 건. 텍스트는 그대로, 이미지는 PNG 파일, 파일은 경로만 보관한다.
struct ClipboardEntry: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case text, image, files }

    let id: UUID
    let kind: Kind
    var date: Date
    var isPinned: Bool
    let text: String?
    /// Clipboard 폴더 안의 파일 이름(이미지).
    let imageFile: String?
    let paths: [String]?
    /// 같은 내용인지 판별하는 요약값(SHA256).
    let digest: String

    var title: String {
        switch kind {
        case .text:
            let line = (text ?? "").split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? ""
            return line.isEmpty ? "(빈 텍스트)" : String(line.prefix(120))
        case .image:
            return "이미지"
        case .files:
            let names = (paths ?? []).map { ($0 as NSString).lastPathComponent }
            return names.count > 3 ? "\(names.prefix(3).joined(separator: ", ")) 외 \(names.count - 3)개" : names.joined(separator: ", ")
        }
    }

    var subtitle: String {
        switch kind {
        case .text:
            let count = text?.count ?? 0
            let lines = text?.split(whereSeparator: \.isNewline).count ?? 0
            return lines > 1 ? "\(count)자 · \(lines)줄" : "\(count)자"
        case .image: return "PNG"
        case .files: return "파일 \(paths?.count ?? 0)개"
        }
    }

    var symbolName: String {
        switch kind {
        case .text: "text.alignleft"
        case .image: "photo"
        case .files: "doc.on.doc"
        }
    }
}
