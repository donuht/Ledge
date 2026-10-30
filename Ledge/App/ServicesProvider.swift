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
}
