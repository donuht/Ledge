import Foundation

/// 드래그 중 선반이 나타나는 조건.
enum ShowTrigger: String, CaseIterable, Sendable {
    /// 드래그를 시작하면 바로 나타난다.
    case dragStart
    /// 드래그한 채 선반 쪽 화면 가장자리에 닿아야 나타난다(기본).
    case edge

    var title: String {
        switch self {
        case .dragStart: "드래그 시작하면 바로"
        case .edge: "가장자리에 닿으면"
        }
    }

    static let defaultsKey = "shelf.showTrigger"

    static var saved: ShowTrigger {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey), let value = ShowTrigger(rawValue: raw) else {
            return .edge
        }
        return value
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}
