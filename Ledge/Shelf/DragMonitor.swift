import AppKit

/// 다른 앱에서 드래그가 시작·종료되는 것을 감지한다. 접근성 권한 불필요.
/// 시작: 전역 leftMouseDragged + 드래그 페이스트보드 changeCount 변화.
/// 종료: 0.05초마다 마우스 버튼이 떼어졌는지 확인(드래그 세션 중엔 mouseUp이 전역 모니터에 안 올 수 있음).
@MainActor
final class DragMonitor {
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?
    /// 드래그 중 주기적으로 호출된다(마우스 위치, 화면 좌표).
    var onDragMoved: ((NSPoint) -> Void)?

    private(set) var isDragging = false

    private let dragPasteboard = NSPasteboard(name: .drag)
    private var lastChangeCount: Int
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var endTimer: Timer?

    init() {
        lastChangeCount = dragPasteboard.changeCount
    }

    func start() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleDragged() }
        }
        // 선반 자신이 시작한 드래그(내보내기)는 등장 신호가 아니므로 카운트만 맞춰 둔다.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.syncChangeCount() }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        endTimer?.invalidate()
        endTimer = nil
    }

    private func syncChangeCount() {
        if !isDragging { lastChangeCount = dragPasteboard.changeCount }
    }

    private func handleDragged() {
        guard !isDragging else { return }
        let count = dragPasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        isDragging = true
        onDragBegan?()
        endTimer?.invalidate()
        endTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard NSEvent.pressedMouseButtons & 1 == 0 else {
            onDragMoved?(NSEvent.mouseLocation)
            return
        }
        endTimer?.invalidate()
        endTimer = nil
        isDragging = false
        lastChangeCount = dragPasteboard.changeCount
        onDragEnded?()
    }
}
