import AppKit

/// 선반 위의 항목 하나. 파일은 경로 참조만 하고 복사하지 않는다.
/// `urls`가 2개 이상이면 스택(여러 파일을 한 덩어리로 묶은 것).
struct ShelfItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let urls: [URL]
    /// 잠긴 항목은 드래그해 내보내도 선반에 남고, 전체 비우기에서도 빠진다.
    var isLocked: Bool

    init(id: UUID = UUID(), urls: [URL], isLocked: Bool = false) {
        precondition(!urls.isEmpty)
        self.id = id
        self.urls = urls.map(\.standardizedFileURL)
        self.isLocked = isLocked
    }

    init(id: UUID = UUID(), url: URL, isLocked: Bool = false) {
        self.init(id: id, urls: [url], isLocked: isLocked)
    }

    var url: URL { urls[0] }
    var isStack: Bool { urls.count > 1 }
    var count: Int { urls.count }

    var name: String {
        isStack ? "\(url.lastPathComponent) 외 \(urls.count - 1)개" : url.lastPathComponent
    }
    var path: String { url.path(percentEncoded: false) }
    var paths: [String] { urls.map { $0.path(percentEncoded: false) } }

    /// 원본이 아직 존재하는지. 삭제·이동된 항목은 흐리게 표시한다.
    var exists: Bool {
        urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }
}
