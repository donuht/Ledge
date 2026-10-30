import AppKit
import SwiftUI

/// 패널 바닥에 깔리는 드롭 대상.
/// 받는 순서: 파일 URL → 파일 프로미스(신형·구형) → 이미지 데이터 → 이미지 URL 다운로드 → HTML → 웹 URL → 텍스트.
/// 파일이 아닌 것은 SnippetWriter로 실제 파일을 만든 뒤 선반에 올린다.
final class DropTargetView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

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
        var types: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff, .URL, .html, .string, WebImporter.legacyPromiseType]
        types += NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes(types)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let op = operation(for: sender)
        YonkLog.write("drop entered types=\(sender.draggingPasteboard.types?.map(\.rawValue).joined(separator: ",") ?? "-") op=\(op.rawValue)")
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
        YonkLog.write("drop perform")
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

        // 3. 구형 파일 프로미스(Chrome·Electron 이미지).
        if WebImporter.hasLegacyPromise(pb) {
            let fallback = snapshot(of: pb)
            let started = WebImporter.receiveLegacyPromise(sender) { [weak self] urls in
                guard let self else { return }
                if !urls.isEmpty { onDrop?(urls) } else { importWebContent(from: fallback) }
            }
            if started { return true }
        }

        importWebContent(from: pb)
        return true
    }

    /// 파일이 아닌 웹 내용: 이미지 데이터 → 이미지 URL 다운로드 → HTML → 링크 → 텍스트 순.
    private func importWebContent(from pb: NSPasteboard) {
        YonkLog.write("web import url=\(SnippetWriter.webURL(from: pb)?.absoluteString.prefix(120) ?? "-") html=\(pb.string(forType: .html)?.prefix(160) ?? "-")")
        if let url = SnippetWriter.writeImage(from: pb) {
            onDrop?([url])
            return
        }
        if let imageURL = WebImporter.imageURL(from: pb) {
            let fallback = snapshot(of: pb)
            WebImporter.downloadImage(imageURL, referer: SnippetWriter.webURL(from: pb)) { [weak self] url in
                guard let self else { return }
                if let url { onDrop?([url]) } else { importNonImageWebContent(from: fallback) }
            }
            return
        }
        importNonImageWebContent(from: pb)
    }

    private func importNonImageWebContent(from pb: NSPasteboard) {
        let text = pb.string(forType: .string)
        if let web = SnippetWriter.webURL(from: pb), let url = SnippetWriter.writeWebLocation(web) {
            onDrop?([url])
        } else if let html = pb.string(forType: .html), !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let url = SnippetWriter.writeHTML(html, plainText: text) {
            onDrop?([url])
        } else if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let url = SnippetWriter.writeText(text) {
            onDrop?([url])
        } else {
            YonkLog.write("web import: nothing usable, types=\(pb.types?.map(\.rawValue) ?? [])")
        }
    }

    /// 드래그 페이스트보드는 드롭이 끝나면 비워지므로, 비동기 처리용으로 프로미스 타입을 뺀 복사본을 만든다.
    private func snapshot(of pb: NSPasteboard) -> NSPasteboard {
        let copy = NSPasteboard(name: NSPasteboard.Name("com.jasonhwangfilm.yonk.snapshot-\(UUID().uuidString)"))
        copy.clearContents()
        copy.writeObjects(pb.pasteboardItems?.compactMap { copyItem($0) } ?? [])
        return copy
    }

    // MARK: - 파일 프로미스

    private func receivePromises(_ receivers: [NSFilePromiseReceiver], fallbackPasteboard pb: NSPasteboard) {
        let destination = SnippetWriter.directory
        // 프로미스가 전부 실패하면(일부 사이트) 이미지 데이터로 대신 저장하기 위해 미리 복사해 둔다.
        let fallback = snapshot(of: pb)

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
                        } else {
                            self.importWebContent(from: fallback)
                        }
                    }
                }
            }
        }
    }

    private func copyItem(_ item: NSPasteboardItem) -> NSPasteboardItem? {
        let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes + [WebImporter.legacyPromiseType.rawValue])
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
        if WebImporter.hasLegacyPromise(pb) { return true }
        if pb.canReadObject(forClasses: [NSImage.self]) { return true }
        if let h = pb.string(forType: .html), !h.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
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
