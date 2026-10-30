import AppKit
import SwiftUI

/// 패널 바닥에 깔리는 드롭 대상. Finder 등에서 파일 URL을 여러 개 받는다.
final class DropTargetView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onTargetChanged: ((Bool) -> Void)?

    private let readingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isAcceptable(sender) else { return [] }
        onTargetChanged?(true)
        return operation(for: sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isAcceptable(sender) else { return [] }
        return operation(for: sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onTargetChanged?(false)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        onTargetChanged?(false)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isAcceptable(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onTargetChanged?(false)
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: readingOptions) as? [URL],
              !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    /// 선반 자신이 시작한 드래그(내보내기)는 다시 받지 않는다.
    private func isAcceptable(_ sender: any NSDraggingInfo) -> Bool {
        if let source = sender.draggingSource as? NSView, source.window === window { return false }
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: readingOptions)
    }

    /// 파일을 복사하지 않으므로 "+" 배지가 뜨지 않는 .generic을 우선한다.
    private func operation(for sender: any NSDraggingInfo) -> NSDragOperation {
        let mask = sender.draggingSourceOperationMask
        if mask.contains(.generic) { return .generic }
        if mask.contains(.link) { return .link }
        if mask.contains(.copy) { return .copy }
        return mask.isEmpty ? [] : .generic
    }
}
