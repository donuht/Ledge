import AppKit
import SwiftUI

/// 선반 패널의 생성·위치·표시 상태를 관리한다.
@MainActor
final class ShelfPanelController {
    let panel: ShelfPanel
    let store: ShelfStore

    private let dropView: DropTargetView
    private let hostingView: NSHostingView<ShelfView>
    private let dragMonitor = DragMonitor()
    private var hideWorkItem: DispatchWorkItem?

    /// 사용자가 메뉴바에서 직접 켠 경우. 직접 끌 때까지 자동 숨김을 하지 않는다.
    private var isPinnedByUser = false

    private var isDropTargeted = false {
        didSet { refreshRootView() }
    }

    /// 선반이 붙는 가장자리(AppSettings가 원본). 바뀌면 보이는 중이라도 즉시 옮겨진다.
    private var edge: ShelfEdge { AppSettings.shared.edge }
    private var edgeObserver: (any NSObjectProtocol)?

    var isVisible: Bool { panel.isVisible }

    /// 비었을 때 자동으로 숨기기까지의 지연(초).
    static let autoHideDelay: TimeInterval = 0.5

    init(store: ShelfStore = ShelfStore()) {
        self.store = store
        let edge = ShelfEdge.saved
        panel = ShelfPanel(contentRect: NSRect(origin: .zero, size: edge.panelSize))

        dropView = DropTargetView(frame: panel.contentRect(forFrameRect: panel.frame))
        hostingView = NSHostingView(rootView: ShelfView(store: store, edge: edge, isDropTargeted: false))
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
            // 무시 목록에 있는 앱이 맨 앞이면 나타나지 않는다.
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if AppSettings.shared.isIgnored(bundleID: front) { return }
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

        edgeObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.edgeDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshRootView()
                if self.isVisible { self.position() }
            }
        }
    }

    private func refreshRootView() {
        hostingView.rootView = ShelfView(store: store, edge: edge, isDropTargeted: isDropTargeted)
    }

    /// 실행 직후: 내용이 있으면 보여 주고, 비어 있으면 숨긴 채 드래그를 기다린다.
    func showAtLaunchIfNeeded() {
        if !store.isEmpty { show() }
    }

    func show() {
        hideWorkItem?.cancel()
        position()
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

    /// 마우스가 있는 화면의 설정된 가장자리에 붙인다.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrame(edge.frame(in: visible, size: edge.panelSize), display: true)
    }
}
