import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 클립보드 기록 창 열기/닫기. 기본값 없음(다른 클립보드 앱과 겹치지 않도록 켜는 사람이 정한다).
    static let showClipboardHistory = Self("showClipboardHistory")
}

/// 클립보드 히스토리 모듈. 설정에서 켜야 동작한다(기본 꺼짐).
@MainActor
final class ClipboardController {
    let store = ClipboardStore()
    private let monitor = ClipboardMonitor()
    private let shelf: ShelfPanelController
    private var windowController: ClipboardWindowController?

    init(shelf: ShelfPanelController) {
        self.shelf = shelf
        monitor.onChange = { [weak self] pb in
            self?.store.capture(from: pb)
        }
        KeyboardShortcuts.onKeyUp(for: .showClipboardHistory) { [weak self] in
            guard let self, AppSettings.shared.clipboardHistoryEnabled else { return }
            toggleWindow()
        }
        observeSetting()
    }

    /// 설정이 바뀌면 감시를 켜고 끈다.
    private func observeSetting() {
        let enabled = withObservationTracking {
            AppSettings.shared.clipboardHistoryEnabled
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSetting() }
        }
        if enabled { monitor.start() } else {
            monitor.stop()
            windowController?.close(returnToPreviousApp: false)
        }
    }

    func toggleWindow() {
        if windowController == nil {
            windowController = ClipboardWindowController { [unowned self] in
                ClipboardHistoryView(
                    store: store,
                    onCopy: { [weak self] in self?.copy($0) },
                    onSendToShelf: { [weak self] in self?.sendToShelf($0) },
                    onClose: { [weak self] in self?.windowController?.close(returnToPreviousApp: true) }
                )
            }
        }
        windowController?.toggle()
    }

    func showWindow() {
        if !(windowController?.isVisible ?? false) { toggleWindow() }
    }

    /// 다시 복사: 페이스트보드에 쓰고 창을 닫은 뒤 이전 앱으로 돌아간다. 자기 쓰기는 기록하지 않는다.
    private func copy(_ entry: ClipboardEntry) {
        store.write(entry)
        monitor.ignoreCurrentChange()
        windowController?.close(returnToPreviousApp: true)
    }

    /// 선반으로 보내기: 텍스트·이미지는 Snippets에 파일로 만들고, 파일은 경로를 그대로 올린다.
    private func sendToShelf(_ entry: ClipboardEntry) {
        var urls: [URL] = []
        switch entry.kind {
        case .text:
            if let url = SnippetWriter.writeText(entry.text ?? "") { urls = [url] }
        case .image:
            if let source = store.imageURL(for: entry), let data = try? Data(contentsOf: source),
               let url = SnippetWriter.write(data: data, name: SnippetWriter.generatedName("이미지"), ext: "png") {
                urls = [url]
            }
        case .files:
            urls = (entry.paths ?? []).map { URL(fileURLWithPath: $0) }
        }
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }
        shelf.store.add(urls: urls)
        if !shelf.isVisible { shelf.toggleByUser() }
        windowController?.close(returnToPreviousApp: true)
    }
}
