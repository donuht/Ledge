import AppKit
import Quartz

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
        acceptsMouseMovedEvents = true
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
    }

    // 드래그 중에도 마우스 이벤트를 받아야 하므로 키 윈도우가 되지 않는다.
    override var canBecomeKey: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            let hit = contentView?.hitTest(event.locationInWindow)
            YonkLog.write("panel mouseDown at \(event.locationInWindow) hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil")")
            // 어디를 클릭하든 키 윈도우가 되고, 키 입력은 DropTargetView가 받는다.
            makeKey()
            if let dropView = contentView as? DropTargetView {
                if firstResponder !== dropView { makeFirstResponder(dropView) }
                // 항목·버튼이 아닌 빈 곳(스크롤 영역 등) 클릭 = 선택 해제.
                let onItem = hit.map { $0 is DraggableItemView || $0 is NSButton || $0 is NSControl } ?? false
                if event.type == .leftMouseDown, !onItem { dropView.backgroundClicked() }
            }
        case .keyDown:
            YonkLog.write("panel keyDown code=\(event.keyCode) key=\(isKeyWindow) fr=\(firstResponder.map { String(describing: type(of: $0)) } ?? "nil")")
        default:
            break
        }
        super.sendEvent(event)
    }


    override var canBecomeMain: Bool { false }
}
