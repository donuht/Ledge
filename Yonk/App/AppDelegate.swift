import AppKit

/// 메뉴바 전용 앱의 진입점. Dock 아이콘 없음(LSUIElement), 상태 메뉴와 선반 패널만 가진다.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var shelfController: ShelfPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let shelf = ShelfPanelController()
        shelfController = shelf
        statusItemController = StatusItemController(shelf: shelf)
        shelf.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
