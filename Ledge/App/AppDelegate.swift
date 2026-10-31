import AppKit

/// 명시적 진입점. `@main`을 NSApplicationDelegate에 직접 붙이면 nib 없는 메뉴바 앱에서
/// delegate가 연결되지 않아 창이 하나도 안 뜨는 문제가 있었다(2026-10-30 확인).
@main
enum LedgeMain {
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
    private var clipboardController: ClipboardController?
    private var servicesProvider: ServicesProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Ledge: didFinishLaunching")
        LegacyMigration.runIfNeeded()
        applyLaunchArguments()
        LedgeLog.write("language=\(Locale.preferredLanguages.first ?? "-") sample=\(String(localized: "Ledge 종료"))")
        let shelf = ShelfPanelController()
        shelfController = shelf
        statusItemController = StatusItemController(shelf: shelf)
        hotkeyController = HotkeyController(shelf: shelf)
        let clipboard = ClipboardController(shelf: shelf)
        clipboardController = clipboard
        statusItemController?.clipboard = clipboard
        let services = ServicesProvider(shelf: shelf)
        servicesProvider = services
        NSApp.servicesProvider = services
        shelf.showAtLaunchIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 설치 스크립트용 실행 인자. `--launch-at-login=on|off`로 로그인 항목을 UI 없이 켜고 끈다.
    private func applyLaunchArguments() {
        for arg in ProcessInfo.processInfo.arguments {
            guard arg.hasPrefix("--launch-at-login=") else { continue }
            let value = arg.dropFirst("--launch-at-login=".count)
            switch value {
            case "on": AppSettings.shared.launchAtLogin = true
            case "off": AppSettings.shared.launchAtLogin = false
            default: continue
            }
            NSLog("Ledge: 실행 인자로 로그인 항목 \(value) → \(AppSettings.shared.launchAtLogin ? "enabled" : "disabled")")
        }
    }
}
