import AppKit
import Observation
import ServiceManagement

/// 앱 설정의 단일 진실 공급원. UserDefaults에 저장한다.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    static let edgeDidChange = Notification.Name("com.jasonhwangfilm.ledge.edgeDidChange")

    /// 선반이 붙는 가장자리.
    var edge: ShelfEdge {
        didSet {
            guard edge != oldValue else { return }
            edge.save()
            NotificationCenter.default.post(name: Self.edgeDidChange, object: nil)
        }
    }

    /// 드래그 중 선반이 나타나는 조건.
    var showTrigger: ShowTrigger {
        didSet {
            guard showTrigger != oldValue else { return }
            showTrigger.save()
        }
    }

    /// 이 앱들이 맨 앞일 때는 드래그해도 선반이 나타나지 않는다(번들 ID).
    var ignoredBundleIDs: [String] {
        didSet { UserDefaults.standard.set(ignoredBundleIDs, forKey: Keys.ignoredBundleIDs) }
    }

    /// 클립보드 기록 모듈. 기본 꺼짐(다른 클립보드 앱과 겹치지 않도록).
    var clipboardHistoryEnabled: Bool {
        didSet { UserDefaults.standard.set(clipboardHistoryEnabled, forKey: Keys.clipboardEnabled) }
    }

    /// 이 앱들이 맨 앞일 때 복사한 것은 기록하지 않는다(비밀번호 관리자 등).
    var clipboardIgnoredBundleIDs: [String] {
        didSet { UserDefaults.standard.set(clipboardIgnoredBundleIDs, forKey: Keys.clipboardIgnored) }
    }

    static let defaultClipboardIgnored = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx",
        "com.apple.keychainaccess", "com.apple.Passwords", "com.bitwarden.desktop",
        "com.lastpass.LastPass", "com.dashlane.Dashlane", "com.keepassxc.keepassxc",
    ]

    /// 로그인 시 실행. SMAppService 상태를 그대로 반영한다.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Ledge: 로그인 항목 변경 실패: \(error)")
            }
            launchAtLoginVersion += 1
        }
    }
    /// launchAtLogin이 계산 속성이라 SwiftUI가 변화를 알 수 있도록 두는 카운터.
    private(set) var launchAtLoginVersion = 0

    private enum Keys {
        static let ignoredBundleIDs = "behavior.ignoredBundleIDs"
        static let clipboardEnabled = "clipboard.enabled"
        static let clipboardIgnored = "clipboard.ignoredBundleIDs"
    }

    private init() {
        edge = ShelfEdge.saved
        showTrigger = ShowTrigger.saved
        ignoredBundleIDs = UserDefaults.standard.stringArray(forKey: Keys.ignoredBundleIDs) ?? []
        clipboardHistoryEnabled = UserDefaults.standard.bool(forKey: Keys.clipboardEnabled)
        clipboardIgnoredBundleIDs = UserDefaults.standard.stringArray(forKey: Keys.clipboardIgnored) ?? Self.defaultClipboardIgnored
    }

    func isIgnored(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return ignoredBundleIDs.contains(bundleID)
    }

    func addIgnored(bundleID: String) {
        guard !ignoredBundleIDs.contains(bundleID) else { return }
        ignoredBundleIDs.append(bundleID)
    }

    func removeIgnored(bundleID: String) {
        ignoredBundleIDs.removeAll { $0 == bundleID }
    }

    func isClipboardIgnored(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return clipboardIgnoredBundleIDs.contains(bundleID)
    }

    func addClipboardIgnored(bundleID: String) {
        guard !clipboardIgnoredBundleIDs.contains(bundleID) else { return }
        clipboardIgnoredBundleIDs.append(bundleID)
    }

    func removeClipboardIgnored(bundleID: String) {
        clipboardIgnoredBundleIDs.removeAll { $0 == bundleID }
    }
}
