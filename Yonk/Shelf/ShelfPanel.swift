import AppKit

/// 앱을 활성화하지 않고 모든 스페이스·전체화면 앱 위에 떠 있는 선반 창.
final class ShelfPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
    }

    // 드래그 중에도 마우스 이벤트를 받아야 하므로 키 윈도우가 되지 않는다.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
