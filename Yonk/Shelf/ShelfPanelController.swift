import AppKit
import SwiftUI

/// 선반 패널의 생성·위치·표시 상태를 관리한다.
@MainActor
final class ShelfPanelController {
    static let defaultSize = NSSize(width: 168, height: 360)

    let panel: ShelfPanel
    let store: ShelfStore

    private let dropView: DropTargetView
    private let hostingView: NSHostingView<ShelfView>
    private var isDropTargeted = false {
        didSet { hostingView.rootView = ShelfView(store: store, isDropTargeted: isDropTargeted) }
    }

    var isVisible: Bool { panel.isVisible }

    init(store: ShelfStore = ShelfStore()) {
        self.store = store
        panel = ShelfPanel(contentRect: NSRect(origin: .zero, size: Self.defaultSize))

        dropView = DropTargetView(frame: panel.contentRect(forFrameRect: panel.frame))
        hostingView = NSHostingView(rootView: ShelfView(store: store, isDropTargeted: false))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        dropView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: dropView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: dropView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: dropView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: dropView.bottomAnchor),
        ])
        panel.contentView = dropView

        dropView.onDrop = { [weak self] urls in
            self?.store.add(urls: urls)
        }
        dropView.onTargetChanged = { [weak self] targeted in
            self?.isDropTargeted = targeted
        }
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
