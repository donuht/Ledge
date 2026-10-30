import AppKit
import SwiftUI

/// 선반 패널의 생성·위치·표시 상태를 관리한다.
@MainActor
final class ShelfPanelController {
    static let defaultSize = NSSize(width: 168, height: 360)

    let panel: ShelfPanel

    var isVisible: Bool { panel.isVisible }

    init() {
        panel = ShelfPanel(contentRect: NSRect(origin: .zero, size: Self.defaultSize))
        let hosting = NSHostingView(rootView: ShelfView())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        root.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: root.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        panel.contentView = root
    }

    func show() {
        positionAtLeftEdge()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// 마우스가 있는 화면의 왼쪽 가장자리, 세로 중앙.
    private func positionAtLeftEdge() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.minX,
            y: visible.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}
