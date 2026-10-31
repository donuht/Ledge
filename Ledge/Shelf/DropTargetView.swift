import AppKit
import SwiftUI

/// 패널 바닥에 깔리는 드롭 대상.
/// 받는 순서: 파일 URL → 파일 프로미스(신형·구형) → 이미지 데이터 → 이미지 URL 다운로드 → HTML → 웹 URL → 텍스트.
/// 파일이 아닌 것은 SnippetWriter로 실제 파일을 만든 뒤 선반에 올린다.
final class DropTargetView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    var onDrop: (([URL]) -> Void)?
    var onTargetChanged: ((Bool) -> Void)?
    /// ⌘V: 클립보드 내용을 선반에 추가.
    var onPaste: (() -> Void)?
    weak var store: ShelfStore?

    // MARK: - 키보드 (패널이 키 윈도우일 때)

    override var acceptsFirstResponder: Bool { true }

    /// 빈 곳 클릭 = 선택 해제(패널의 sendEvent에서 호출).
    func backgroundClicked() {
        store?.clearSelection()
        QuickLookController.shared.close()
    }

    /// ⌘A·⌘V·⌘Z. 이 앱은 메인 메뉴가 없고 SwiftUI 호스팅 뷰가 키 이퀴밸런트를 먼저 가로챌 수 있어
    /// keyDown에 기대지 않고 패널의 sendEvent에서 바로 부른다.
    func handleCommandKey(_ event: NSEvent) -> Bool {
        guard let store, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else { return false }
        switch event.charactersIgnoringModifiers {
        case "a": store.selectAll()
        case "v": onPaste?()
        case "z": store.restoreLastRemoved()
        default: return false
        }
        LedgeLog.write("dropView command key \(event.charactersIgnoringModifiers ?? "")")
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleCommandKey(event) || super.performKeyEquivalent(with: event)
    }

    override func selectAll(_ sender: Any?) {
        store?.selectAll()
    }

    override func keyDown(with event: NSEvent) {
        LedgeLog.write("dropView keyDown code=\(event.keyCode)")
        guard let store else { return super.keyDown(with: event) }
        if handleCommandKey(event) { return }
        switch event.keyCode {
        case 49: // space
            let selected = store.selectedItems
            let urls = (selected.isEmpty ? store.items : selected).flatMap(\.urls)
            QuickLookController.shared.toggle(urls: urls)
        case 51, 117: // delete, forward delete
            if !store.selectedItems.isEmpty { store.removeSelected() }
        case 53: // esc
            QuickLookController.shared.close()
            store.clearSelection()
        case 36, 76: // return
            for url in store.selectedItems.flatMap(\.urls) { NSWorkspace.shared.open(url) }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - 고무줄 선택 (목록 빈 곳을 끌어서)

    private var rubberBandOrigin: NSPoint?
    private var rubberBandBase: Set<ShelfItem.ID> = []
    private let rubberBandView: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        v.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        v.layer?.borderWidth = 1
        v.layer?.cornerRadius = 2
        return v
    }()

    var isRubberBanding: Bool { rubberBandOrigin != nil }

    /// 목록(스크롤 영역) 안의 점인지. 머리 부분과 빈 상태는 false → 거기를 끌면 창 옮기기.
    func isInList(_ pointInWindow: NSPoint) -> Bool {
        guard let scroll = firstDescendant(NSScrollView.self, in: self) else { return false }
        return scroll.bounds.contains(scroll.convert(pointInWindow, from: nil))
    }

    func beginRubberBand(at pointInWindow: NSPoint, modifiers: NSEvent.ModifierFlags) {
        rubberBandOrigin = convert(pointInWindow, from: nil)
        let keep = !modifiers.intersection([.command, .shift]).isEmpty
        rubberBandBase = keep ? (store?.selectedIDs ?? []) : []
    }

    func updateRubberBand(to pointInWindow: NSPoint) {
        guard let origin = rubberBandOrigin, let store else { return }
        let p = convert(pointInWindow, from: nil)
        let rect = NSRect(x: min(origin.x, p.x), y: min(origin.y, p.y),
                          width: abs(p.x - origin.x), height: abs(p.y - origin.y))
        if rubberBandView.superview == nil { addSubview(rubberBandView, positioned: .above, relativeTo: nil) }
        rubberBandView.frame = rect
        // 스크롤로 가려진 줄은 고르지 않도록 목록의 보이는 영역 안에서만 겹침을 본다.
        var hitRect = rect
        if let scroll = firstDescendant(NSScrollView.self, in: self) {
            hitRect = rect.intersection(scroll.convert(scroll.bounds, to: self))
        }
        var ids = rubberBandBase
        for row in descendants(DraggableItemView.self, in: self)
        where row.convert(row.bounds, to: self).intersects(hitRect) {
            ids.insert(row.item.id)
        }
        store.setSelection(ids)
    }

    func endRubberBand() {
        rubberBandOrigin = nil
        rubberBandView.removeFromSuperview()
        if let store { QuickLookController.shared.update(urls: store.selectedItems.flatMap(\.urls)) }
    }

    private func firstDescendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        for sub in view.subviews {
            if let hit = sub as? T { return hit }
            if let hit = firstDescendant(type, in: sub) { return hit }
        }
        return nil
    }

    private func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        view.subviews.flatMap { sub -> [T] in
            (sub as? T).map { [$0] } ?? descendants(type, in: sub)
        }
    }

    private let fileURLOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    private let promiseQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.jasonhwangfilm.ledge.file-promise"
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
        LedgeLog.write("drop entered types=\(sender.draggingPasteboard.types?.map(\.rawValue).joined(separator: ",") ?? "-") op=\(op.rawValue)")
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
        LedgeLog.write("drop perform")
        onTargetChanged?(false)
        guard !isFromOwnWindow(sender) else { return false }
        let pb = sender.draggingPasteboard

        // 1. 실제 파일: 경로만 참조.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: fileURLOptions) as? [URL], !urls.isEmpty {
            onDrop?(urls)
            return true
        }

        // 2. 이미지 데이터가 바로 실려 있으면(Chrome은 jpeg/tiff를 같이 보낸다) 프로미스를 기다리지 않고 저장한다.
        if SnippetWriter.hasImageData(pb), let url = SnippetWriter.writeImage(from: pb) {
            LedgeLog.write("drop: image data → \(url.lastPathComponent)")
            onDrop?([url])
            return true
        }

        // 3. 파일 프로미스: 보내는 쪽이 저장 폴더에 직접 써 준다(메일 첨부, 사진 앱).
        if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            receivePromises(receivers, fallbackPasteboard: pb)
            return true
        }

        // 4. 구형 파일 프로미스(Chrome·Electron 이미지).
        if WebImporter.hasLegacyPromise(pb) {
            let fallback = WebImporter.snapshot(of: pb)
            let started = WebImporter.receiveLegacyPromise(sender) { [weak self] urls in
                guard let self else { return }
                if !urls.isEmpty { onDrop?(urls) } else { WebImporter.importWebContent(from: fallback) { [weak self] urls in self?.onDrop?(urls) } }
            }
            if started { return true }
        }

        WebImporter.importWebContent(from: pb) { [weak self] urls in self?.onDrop?(urls) }
        return true
    }

    // MARK: - 파일 프로미스

    private func receivePromises(_ receivers: [NSFilePromiseReceiver], fallbackPasteboard pb: NSPasteboard) {
        let destination = SnippetWriter.directory
        // 프로미스가 전부 실패하면(일부 사이트) 이미지 데이터로 대신 저장하기 위해 미리 복사해 둔다.
        let fallback = WebImporter.snapshot(of: pb)

        LedgeLog.write("promise: waiting for \(receivers.count)")
        var pending = receivers.count
        var received: [URL] = []
        var finished = false
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self, !finished else { return }
            finished = true
            LedgeLog.write("promise: done received=\(received.map(\.lastPathComponent))")
            if !received.isEmpty {
                self.onDrop?(received)
            } else {
                WebImporter.importWebContent(from: fallback) { [weak self] urls in self?.onDrop?(urls) }
            }
        }
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: promiseQueue) { url, error in
                Task { @MainActor in
                    if let error {
                        LedgeLog.error("promise: failed \(error)")
                    } else {
                        received.append(url)
                    }
                    pending -= 1
                    if pending == 0 { finish() }
                }
            }
        }
        // 일부 앱은 프로미스를 끝내 이행하지 않는다. 10초 지나면 페이스트보드 내용으로 대신 처리한다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if !finished { LedgeLog.error("promise: timeout") }
            finish()
        }
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
