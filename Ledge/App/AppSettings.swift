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

    static let sizeDidChange = Notification.Name("com.jasonhwangfilm.ledge.sizeDidChange")

    /// 선반 크기 프리셋.
    var size: ShelfSize {
        didSet {
            guard size != oldValue else { return }
            UserDefaults.standard.set(size.rawValue, forKey: Keys.size)
            NotificationCenter.default.post(name: Self.sizeDidChange, object: nil)
        }
    }
    /// 모서리를 끌어 정한 치수(세로·가로 따로). 프리셋이 `custom`일 때 쓴다.
    private var customVertical: NSSize
    private var customHorizontal: NSSize

    func panelSize(for edge: ShelfEdge) -> NSSize {
        if let preset = size.size(vertical: edge.isVertical) { return preset }
        return edge.isVertical ? customVertical : customHorizontal
    }

    /// 사용자가 끌어서 바꾼 크기를 기억하고 프리셋을 `custom`으로 바꾼다.
    func setCustomSize(_ newSize: NSSize, for edge: ShelfEdge) {
        if edge.isVertical {
            customVertical = newSize
            UserDefaults.standard.set([newSize.width, newSize.height], forKey: Keys.customVertical)
        } else {
            customHorizontal = newSize
            UserDefaults.standard.set([newSize.width, newSize.height], forKey: Keys.customHorizontal)
        }
        size = .custom
    }

    /// 커서 옆 모드: 끌다가 이만큼 멈춰 있으면 나타난다(초). 0이면 집는 즉시.
    var cursorPauseDelay: Double {
        didSet { UserDefaults.standard.set(cursorPauseDelay, forKey: Keys.cursorPauseDelay) }
    }

    /// 비었을 때 사라지기까지의 지연(초).
    var autoHideDelay: Double {
        didSet { UserDefaults.standard.set(autoHideDelay, forKey: Keys.autoHideDelay) }
    }

    /// 클립보드 보관 개수(0 = 무제한)와 기간(일, 0 = 무제한).
    var clipboardMaxItems: Int {
        didSet { UserDefaults.standard.set(clipboardMaxItems, forKey: Keys.clipboardMaxItems) }
    }
    var clipboardMaxAgeDays: Int {
        didSet { UserDefaults.standard.set(clipboardMaxAgeDays, forKey: Keys.clipboardMaxAgeDays) }
    }

    /// 앱 언어 강제("" = 시스템 따름, "ko", "en"). 바꾸면 다시 실행해야 적용된다.
    var appLanguage: String {
        didSet {
            guard appLanguage != oldValue else { return }
            if appLanguage.isEmpty {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([appLanguage], forKey: "AppleLanguages")
            }
        }
    }

    /// 문제 진단용 동작 기록(~/Library/Logs/Ledge/ledge.log). 기본 꺼짐.
    var diagnosticLogging: Bool {
        didSet { UserDefaults.standard.set(diagnosticLogging, forKey: LedgeLog.enabledKey) }
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
        static let size = "shelf.size"
        static let customVertical = "shelf.customSize.vertical"
        static let customHorizontal = "shelf.customSize.horizontal"
        static let autoHideDelay = "behavior.autoHideDelay"
        static let cursorPauseDelay = "behavior.cursorPauseDelay"
        static let clipboardMaxItems = "clipboard.maxItems"
        static let clipboardMaxAgeDays = "clipboard.maxAgeDays"
    }

    private init() {
        edge = ShelfEdge.saved
        showTrigger = ShowTrigger.saved
        let d = UserDefaults.standard
        let overridden = Bundle.main.bundleIdentifier.flatMap { d.persistentDomain(forName: $0)?["AppleLanguages"] as? [String] }
        appLanguage = overridden?.first ?? ""
        size = d.string(forKey: Keys.size).flatMap(ShelfSize.init(rawValue:)) ?? .medium
        func loadSize(_ key: String, fallback: NSSize) -> NSSize {
            guard let arr = d.array(forKey: key) as? [Double], arr.count == 2 else { return fallback }
            return NSSize(width: arr[0], height: arr[1])
        }
        customVertical = loadSize(Keys.customVertical, fallback: ShelfSize.medium.size(vertical: true)!)
        customHorizontal = loadSize(Keys.customHorizontal, fallback: ShelfSize.medium.size(vertical: false)!)
        autoHideDelay = d.object(forKey: Keys.autoHideDelay) as? Double ?? 0.5
        cursorPauseDelay = d.object(forKey: Keys.cursorPauseDelay) as? Double ?? 0.5
        diagnosticLogging = d.bool(forKey: LedgeLog.enabledKey)
        clipboardMaxItems = d.object(forKey: Keys.clipboardMaxItems) as? Int ?? 500
        clipboardMaxAgeDays = d.object(forKey: Keys.clipboardMaxAgeDays) as? Int ?? 30
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
