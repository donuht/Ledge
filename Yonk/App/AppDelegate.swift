import AppKit

/// 명시적 진입점. `@main`을 NSApplicationDelegate에 직접 붙이면 nib 없는 메뉴바 앱에서
/// delegate가 연결되지 않아 창이 하나도 안 뜨는 문제가 있었다(2026-10-30 확인).
@main
enum YonkMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

/// 메뉴바 전용 앱. Dock 아이콘 없음(LSUIElement), 상태 메뉴와 선반 패널만 가진다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var shelfController: ShelfPanelController?
    private var hotkeyController: HotkeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Yonk: didFinishLaunching")
        let shelf = ShelfPanelController()
        shelfController = shelf
        statusItemController = StatusItemController(shelf: shelf)
        hotkeyController = HotkeyController(shelf: shelf)
        shelf.showAtLaunchIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
