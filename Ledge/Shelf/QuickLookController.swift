import AppKit
import Quartz

/// 스페이스바 QuickLook. 선반 패널이 responder chain으로 이 객체를 데이터 소스로 넘긴다.
@MainActor
final class QuickLookController: NSObject {
    static let shared = QuickLookController()

    private(set) var urls: [URL] = []

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func toggle(urls: [URL]) {
        if isVisible { close() } else { show(urls: urls) }
    }

    func show(urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.updateController()
        panel.reloadData()
    }

    /// 선택이 바뀌면 열려 있는 미리보기도 따라간다.
    func update(urls: [URL]) {
        guard isVisible else { return }
        self.urls = urls
        if urls.isEmpty { close() } else { QLPreviewPanel.shared().reloadData() }
    }

    func close() {
        guard isVisible else { return }
        QLPreviewPanel.shared().orderOut(nil)
    }
}

extension QuickLookController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let url: URL? = MainActor.assumeIsolated { urls.indices.contains(index) ? urls[index] : nil }
        return url.map { $0 as NSURL }
    }
}
