import AppKit
import SwiftUI

/// 패널 바닥에 깔리는 드롭 대상.
/// 받는 순서: 파일 URL → 파일 프로미스(브라우저 이미지·메일 첨부) → 이미지 데이터 → 웹 URL → 텍스트.
/// 파일이 아닌 것은 SnippetWriter로 실제 파일을 만든 뒤 선반에 올린다.
final class DropTargetView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onTargetChanged: ((Bool) -> Void)?

    private let fileURLOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    private let promiseQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.jasonhwangfilm.yonk.file-promise"
        q.qualityOfService = .userInitiated
        return q
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        var types: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff, .URL, .string]
        types += NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes(types)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let op = operation(for: sender)
        if !op.isEmpty { onTargetChanged?(true) }
        return op
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        operation(for: sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onTargetChanged?(false)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        onTargetChanged?(false)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        !operation(for: sender).isEmpty
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onTargetChanged?(false)
        guard !isFromOwnWindow(sender) else { return false }
        let pb = sender.draggingPasteboard

        // 1. 실제 파일: 경로만 참조.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: fileURLOptions) as? [URL], !urls.isEmpty {
            onDrop?(urls)
            return true
        }

        // 2. 파일 프로미스: 보내는 쪽이 저장 폴더에 직접 써 준다(브라우저 이미지, 메일 첨부, 사진 앱).
        if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            receivePromises(receivers, fallbackPasteboard: pb)
            return true
        }

        // 3. 이미지 데이터.
        if let url = SnippetWriter.writeImage(from: pb) {
            onDrop?([url])
            return true
        }

        // 4. 웹 링크 → .webloc
        if let web = SnippetWriter.webURL(from: pb), let url = SnippetWriter.writeWebLocation(web) {
            onDrop?([url])
            return true
        }

        // 5. 텍스트 → .txt
        if let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = SnippetWriter.writeText(text) {
            onDrop?([url])
            return true
        }
        return false
    }

    // MARK: - 파일 프로미스

    private func receivePromises(_ receivers: [NSFilePromiseReceiver], fallbackPasteboard pb: NSPasteboard) {
        let destination = SnippetWriter.directory
        // 프로미스가 전부 실패하면(일부 사이트) 이미지 데이터로 대신 저장하기 위해 미리 복사해 둔다.
        let fallback = NSPasteboard(name: NSPasteboard.Name("com.jasonhwangfilm.yonk.promise-fallback"))
        fallback.clearContents()
        fallback.writeObjects(pb.pasteboardItems?.compactMap { copyItem($0) } ?? [])

        var pending = receivers.count
        var received: [URL] = []
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: promiseQueue) { [weak self] url, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        NSLog("Yonk: 파일 프로미스 실패: \(error)")
                    } else {
                        received.append(url)
                    }
                    pending -= 1
                    if pending == 0 {
                        if !received.isEmpty {
                            self.onDrop?(received)
                        } else if let image = SnippetWriter.writeImage(from: fallback) {
                            self.onDrop?([image])
                        }
                        fallback.clearContents()
                    }
                }
            }
        }
    }

    private func copyItem(_ item: NSPasteboardItem) -> NSPasteboardItem? {
        let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes)
        let copy = NSPasteboardItem()
        var any = false
        for type in item.types where !promiseTypes.contains(type.rawValue) {
            if let data = item.data(forType: type) {
                copy.setData(data, forType: type)
                any = true
            }
        }
        return any ? copy : nil
    }

    // MARK: - 판정

    private func isFromOwnWindow(_ sender: any NSDraggingInfo) -> Bool {
        if let source = sender.draggingSource as? NSView, source.window === window { return true }
        return false
    }

    private func hasAcceptableContent(_ pb: NSPasteboard) -> Bool {
        if pb.canReadObject(forClasses: [NSURL.self], options: fileURLOptions) { return true }
        if pb.canReadObject(forClasses: [NSFilePromiseReceiver.self]) { return true }
        if pb.canReadObject(forClasses: [NSImage.self]) { return true }
        if pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: false]) { return true }
        if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }

    /// 파일 드래그는 경로만 참조하므로 배지 없는 .generic, 나머지는 파일을 새로 만드니 .copy.
    private func operation(for sender: any NSDraggingInfo) -> NSDragOperation {
        guard !isFromOwnWindow(sender) else { return [] }
        let pb = sender.draggingPasteboard
        guard hasAcceptableContent(pb) else { return [] }
        let mask = sender.draggingSourceOperationMask
        let isRealFile = pb.canReadObject(forClasses: [NSURL.self], options: fileURLOptions)
        if isRealFile {
            if mask.contains(.generic) { return .generic }
            if mask.contains(.link) { return .link }
        }
        if mask.contains(.copy) { return .copy }
        if mask.contains(.generic) { return .generic }
        return mask.isEmpty ? [] : .copy
    }
}
