import AppKit
import Observation
import ServiceManagement

/// 앱 설정의 단일 진실 공급원. UserDefaults에 저장한다.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    static let edgeDidChange = Notification.Name("com.jasonhwangfilm.yonk.edgeDidChange")

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

    /// 로그인 시 실행. SMAppService 상태를 그대로 반영한다.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Yonk: 로그인 항목 변경 실패: \(error)")
            }
            launchAtLoginVersion += 1
        }
    }
    /// launchAtLogin이 계산 속성이라 SwiftUI가 변화를 알 수 있도록 두는 카운터.
    private(set) var launchAtLoginVersion = 0

    private enum Keys {
        static let ignoredBundleIDs = "behavior.ignoredBundleIDs"
    }

    private init() {
        edge = ShelfEdge.saved
        showTrigger = ShowTrigger.saved
        ignoredBundleIDs = UserDefaults.standard.stringArray(forKey: Keys.ignoredBundleIDs) ?? []
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
}
