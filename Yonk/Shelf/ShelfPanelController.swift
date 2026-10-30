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

    /// 지금 진행 중인 드래그가 무시 앱에서 시작됐는지.
    private var isCurrentDragIgnored = false

    /// 가장자리 감지 두께(pt). 포인터는 화면 밖으로 못 나가므로 가장자리에 닿으면 좌표가 경계값이 된다.
    static let edgeThreshold: CGFloat = 6

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
        dropView.store = store
        dropView.onPaste = { [weak self] in
            self?.addFromClipboard()
        }

        // 평소엔 숨어 있다가, 다른 앱에서 드래그하는 동안 나타나고(설정에 따라 시작 즉시 또는
        // 가장자리에 닿았을 때), 끝난 뒤 비어 있으면 사라진다.
        dragMonitor.onDragBegan = { [weak self] in
            guard let self else { return }
            // 무시 목록에 있는 앱이 맨 앞이면 이번 드래그에서는 나타나지 않는다.
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            isCurrentDragIgnored = AppSettings.shared.isIgnored(bundleID: front)
            if isCurrentDragIgnored { return }
            hideWorkItem?.cancel()
            if AppSettings.shared.showTrigger == .dragStart, !isVisible { show() }
        }
        dragMonitor.onDragMoved = { [weak self] mouse in
            guard let self, !isCurrentDragIgnored, !isVisible else { return }
            guard AppSettings.shared.showTrigger == .edge, Self.isAtEdge(mouse, edge: edge) else { return }
            hideWorkItem?.cancel()
            show()
        }
        dragMonitor.onDragEnded = { [weak self] in
            guard let self else { return }
            isCurrentDragIgnored = false
            scheduleAutoHideIfEmpty()
        }
        store.onChange = { [weak self] in
            guard let self else { return }
            // 드롭 뒤 비동기로(다운로드·프로미스) 항목이 들어오면 숨어 있던 선반을 다시 보여 준다.
            if !store.isEmpty, !isVisible { show() }
            scheduleAutoHideIfEmpty()
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

    /// 클립보드 내용(파일·이미지·링크·글)을 선반에 추가한다(B7).
    func addFromClipboard() {
        WebImporter.importContent(from: .general) { [weak self] urls in
            guard let self else { return }
            guard !urls.isEmpty else {
                NSSound.beep()
                return
            }
            store.add(urls: urls)
            if !isVisible { show() }
        }
    }

    /// 실행 직후: 내용이 있으면 보여 주고, 비어 있으면 숨긴 채 드래그를 기다린다.
    func showAtLaunchIfNeeded() {
        if !store.isEmpty { show() }
    }

    func show() {
        YonkLog.write("shelf show")
        hideWorkItem?.cancel()
        position()
        panel.orderFrontRegardless()
    }

    func hide() {
        YonkLog.write("shelf hide")
        hideWorkItem?.cancel()
        QuickLookController.shared.close()
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

    /// 마우스가 있는 화면의 `edge` 쪽 경계에 닿았는지. 메뉴바·독까지 포함한 전체 프레임 기준.
    static func isAtEdge(_ mouse: NSPoint, edge: ShelfEdge) -> Bool {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return false }
        let f = screen.frame
        switch edge {
        case .left: return mouse.x <= f.minX + edgeThreshold
        case .right: return mouse.x >= f.maxX - edgeThreshold
        case .top: return mouse.y >= f.maxY - edgeThreshold
        case .bottom: return mouse.y <= f.minY + edgeThreshold
        }
    }

    /// 마우스가 있는 화면의 설정된 가장자리에 붙인다.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrame(edge.frame(in: visible, size: edge.panelSize), display: true)
    }
}
