import AppKit

/// 선반이 붙는 화면 가장자리. 왼쪽·오른쪽은 세로 목록, 위·아래는 가로 목록.
enum ShelfEdge: String, CaseIterable, Sendable {
    case left, right, top, bottom

    static let defaultsKey = "shelf.edge"

    var title: String {
        switch self {
        case .left: String(localized: "왼쪽")
        case .right: String(localized: "오른쪽")
        case .top: String(localized: "위")
        case .bottom: String(localized: "아래")
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
    /// `offset`은 변을 따라가는 위치(0 = 왼쪽/아래 끝, 0.5 = 가운데, 1 = 오른쪽/위 끝).
    func frame(in visible: NSRect, size: NSSize, offset: CGFloat = 0.5) -> NSRect {
        let t = min(max(offset, 0), 1)
        let origin: NSPoint
        switch self {
        case .left:
            origin = NSPoint(x: visible.minX, y: visible.minY + (visible.height - size.height) * t)
        case .right:
            origin = NSPoint(x: visible.maxX - size.width, y: visible.minY + (visible.height - size.height) * t)
        case .top:
            origin = NSPoint(x: visible.minX + (visible.width - size.width) * t, y: visible.maxY - size.height)
        case .bottom:
            origin = NSPoint(x: visible.minX + (visible.width - size.width) * t, y: visible.minY)
        }
        return NSRect(origin: origin, size: size)
    }

    /// 사용자가 끌어다 놓은 프레임을 이 가장자리에 다시 붙인다. 벽에서 떨어진 축은 벽으로, 변을 따라가는 축은
    /// 화면 안으로만 당긴다. 돌려주는 값은 (붙인 프레임, 변을 따라가는 위치 비율 0...1).
    func snapped(_ frame: NSRect, in visible: NSRect) -> (frame: NSRect, offset: CGFloat) {
        var f = frame
        let offset: CGFloat
        if isVertical {
            f.origin.x = self == .left ? visible.minX : visible.maxX - f.width
            let room = visible.height - f.height
            f.origin.y = min(max(f.origin.y, visible.minY), visible.minY + max(room, 0))
            offset = room > 0 ? (f.origin.y - visible.minY) / room : 0.5
        } else {
            f.origin.y = self == .bottom ? visible.minY : visible.maxY - f.height
            let room = visible.width - f.width
            f.origin.x = min(max(f.origin.x, visible.minX), visible.minX + max(room, 0))
            offset = room > 0 ? (f.origin.x - visible.minX) / room : 0.5
        }
        return (f, offset)
    }
}
