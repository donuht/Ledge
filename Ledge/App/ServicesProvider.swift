import AppKit

/// Finder 우클릭 → 서비스 → "Ledge에 추가" (Info.plist NSServices, D6).
@MainActor
final class ServicesProvider: NSObject {
    private let shelf: ShelfPanelController

    init(shelf: ShelfPanelController) {
        self.shelf = shelf
    }

    @objc func addToShelf(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else {
            error.pointee = String(localized: "선택한 파일이 없습니다.") as NSString
            return
        }
        shelf.store.add(urls: urls)
        if !shelf.isVisible { shelf.toggleByUser() }
    }

    @objc func copyMarkdownLink(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        copyLinks(pboard, as: .markdown, error: error)
    }

    @objc func copyLinkPath(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        copyLinks(pboard, as: .path, error: error)
    }

    @objc func copyVideoInfo(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .filter(MediaInfoProvider.isVideo)
        guard !urls.isEmpty else {
            error.pointee = String(localized: "영상 파일이 없습니다.") as NSString
            return
        }
        // 서비스 호출은 동기라 결과를 기다리지 않고, 다 읽은 뒤 클립보드에 넣는다.
        Task { @MainActor in
            let text = await MediaInfoProvider.lines(for: urls)
            guard !text.isEmpty else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
    }

    private func copyLinks(_ pboard: NSPasteboard, as kind: LinkFormatter.Kind, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else {
            error.pointee = String(localized: "선택한 파일이 없습니다.") as NSString
            return
        }
        LinkFormatter.copy(urls, as: kind)
    }
}
