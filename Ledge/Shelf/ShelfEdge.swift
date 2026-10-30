import AppKit

/// 선반이 붙는 화면 가장자리. 왼쪽·오른쪽은 세로 목록, 위·아래는 가로 목록.
enum ShelfEdge: String, CaseIterable, Sendable {
    case left, right, top, bottom

    static let defaultsKey = "shelf.edge"

    var title: String {
        switch self {
        case .left: "왼쪽"
        case .right: "오른쪽"
        case .top: "위"
        case .bottom: "아래"
        }
    }

    var isVertical: Bool { self == .left || self == .right }

    static var saved: ShelfEdge {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(ShelfEdge.init(rawValue:)) ?? .left
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }

    /// 주어진 화면의 가용 영역에서 이 가장자리에 붙는 프레임.
    func frame(in visible: NSRect, size: NSSize) -> NSRect {
        let origin: NSPoint
        switch self {
        case .left:
            origin = NSPoint(x: visible.minX, y: visible.midY - size.height / 2)
        case .right:
            origin = NSPoint(x: visible.maxX - size.width, y: visible.midY - size.height / 2)
        case .top:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height)
        case .bottom:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY)
        }
        return NSRect(origin: origin, size: size)
    }
}
