import AppKit

/// 선반 위의 항목 하나. 파일은 경로 참조만 하고 복사하지 않는다.
struct ShelfItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url.standardizedFileURL
    }

    var name: String { url.lastPathComponent }
    var path: String { url.path(percentEncoded: false) }

    /// 원본이 아직 존재하는지. 삭제·이동된 항목은 흐리게 표시한다.
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}
