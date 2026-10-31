import AppKit
import Quartz

/// 앱을 활성화하지 않고 모든 스페이스·전체화면 앱 위에 떠 있는 선반 창.
final class ShelfPanel: NSPanel {
    /// 항목·버튼이 아닌 곳을 누른 채 몇 pt 이상 끌면 호출된다(선반 자체 옮기기).
    var onBackgroundDrag: ((NSEvent) -> Void)?
    private var backgroundDownLocation: NSPoint?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .utilityWindow, .resizable],
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

    // 항목을 클릭하면 키 윈도우가 되어 스페이스(QuickLook)·Delete·⌘V를 받는다. 앱 활성화는 하지 않는다.
    override var canBecomeKey: Bool { true }

    // MARK: - QuickLook (responder chain)

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = QuickLookController.shared
        panel.delegate = QuickLookController.shared
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            let hit = contentView?.hitTest(event.locationInWindow)
            LedgeLog.write("panel mouseDown at \(event.locationInWindow) hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil")")
            // 어디를 클릭하든 키 윈도우가 되고, 키 입력은 DropTargetView가 받는다.
            makeKey()
            if let dropView = contentView as? DropTargetView {
                if firstResponder !== dropView { makeFirstResponder(dropView) }
                // 항목·버튼이 아닌 빈 곳(스크롤 영역 등) 클릭 = 선택 해제.
                let onItem = hit.map { $0 is DraggableItemView || $0 is NSButton || $0 is NSControl } ?? false
                if event.type == .leftMouseDown, !onItem {
                    dropView.backgroundClicked()
                    backgroundDownLocation = event.locationInWindow
                }
            }
        case .leftMouseDragged:
            if let down = backgroundDownLocation,
               hypot(event.locationInWindow.x - down.x, event.locationInWindow.y - down.y) > 4 {
                backgroundDownLocation = nil
                onBackgroundDrag?(event)
                return
            }
        case .leftMouseUp:
            backgroundDownLocation = nil
        case .keyDown:
            LedgeLog.write("panel keyDown code=\(event.keyCode) key=\(isKeyWindow) fr=\(firstResponder.map { String(describing: type(of: $0)) } ?? "nil")")
        default:
            break
        }
        super.sendEvent(event)
    }


    override var canBecomeMain: Bool { false }
}
