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

    private let dragMonitor = DragMonitor()
    private var hideWorkItem: DispatchWorkItem?

    /// 사용자가 메뉴바에서 직접 켠 경우. 직접 끌 때까지 자동 숨김을 하지 않는다.
    private var isPinnedByUser = false

    var isVisible: Bool { panel.isVisible }

    /// 비었을 때 자동으로 숨기기까지의 지연(초).
    static let autoHideDelay: TimeInterval = 0.5

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

        // 평소엔 숨어 있다가, 다른 앱에서 드래그가 시작되면 나타나고 끝난 뒤 비어 있으면 사라진다.
        dragMonitor.onDragBegan = { [weak self] in
            guard let self else { return }
            hideWorkItem?.cancel()
            if !isVisible { show() }
        }
        dragMonitor.onDragEnded = { [weak self] in
            self?.scheduleAutoHideIfEmpty()
        }
        store.onChange = { [weak self] in
            self?.scheduleAutoHideIfEmpty()
        }
        dragMonitor.start()
    }

    /// 실행 직후: 내용이 있으면 보여 주고, 비어 있으면 숨긴 채 드래그를 기다린다.
    func showAtLaunchIfNeeded() {
        if !store.isEmpty { show() }
    }

    func show() {
        hideWorkItem?.cancel()
        positionAtLeftEdge()
        panel.orderFrontRegardless()
    }

    func hide() {
        hideWorkItem?.cancel()
        panel.orderOut(nil)
    }

    /// 메뉴바에서 직접 토글. 직접 켠 선반은 비어도 자동으로 숨기지 않는다.
    func toggleByUser() {
        if isVisible {
            isPinnedByUser = false
            hide()
        } else {
            isPinnedByUser = true
            show()
        }
    }

    private func scheduleAutoHideIfEmpty() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, isVisible, store.isEmpty, !isPinnedByUser, !dragMonitor.isDragging else { return }
            hide()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoHideDelay, execute: work)
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
