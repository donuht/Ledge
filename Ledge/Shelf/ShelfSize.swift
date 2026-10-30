import AppKit

/// 선반 크기 프리셋. 세로(왼쪽·오른쪽)와 가로(위·아래) 치수가 다르다. 모서리를 끌어 바꾸면 `custom`이 된다.
enum ShelfSize: String, CaseIterable, Sendable {
    case small, medium, large, custom

    var title: String {
        switch self {
        case .small: "작게"
        case .medium: "보통"
        case .large: "크게"
        case .custom: "직접 조절"
        }
    }

    func size(vertical: Bool) -> NSSize? {
        switch (self, vertical) {
        case (.small, true): NSSize(width: 150, height: 280)
        case (.medium, true): NSSize(width: 168, height: 360)
        case (.large, true): NSSize(width: 240, height: 560)
        case (.small, false): NSSize(width: 360, height: 110)
        case (.medium, false): NSSize(width: 440, height: 124)
        case (.large, false): NSSize(width: 680, height: 170)
        case (.custom, _): nil
        }
    }

    static let minVertical = NSSize(width: 120, height: 160)
    static let minHorizontal = NSSize(width: 240, height: 100)
}
