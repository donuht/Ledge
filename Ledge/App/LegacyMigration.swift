import AppKit

/// 개명 전(Yonk, com.jasonhwangfilm.yonk) 설정·스니펫 폴더를 한 번만 가져온다.
enum LegacyMigration {
    private static let doneKey = "migration.fromYonk.done"
    private static let oldBundleID = "com.jasonhwangfilm.yonk"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        // 1. UserDefaults: 옛 도메인의 키를 새 도메인에 없는 것만 복사한다(선반 항목·위치·단축키 포함).
        if let old = UserDefaults(suiteName: oldBundleID)?.persistentDomain(forName: oldBundleID) {
            for (key, value) in old where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        // 2. 스니펫 폴더: Application Support/Yonk/Snippets → Ledge/Snippets. 경로가 저장돼 있으므로 항목 경로도 바꾼다.
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldDir = base.appendingPathComponent("Yonk/Snippets", isDirectory: true)
        let newDir = SnippetWriter.directory
        if let names = try? FileManager.default.contentsOfDirectory(atPath: oldDir.path) {
            for name in names where !name.hasPrefix(".") {
                let from = oldDir.appendingPathComponent(name)
                let to = newDir.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: to.path) {
                    try? FileManager.default.moveItem(at: from, to: to)
                }
            }
            try? FileManager.default.removeItem(at: oldDir.deletingLastPathComponent())
        }
        if let records = defaults.array(forKey: "shelf.items.v2") as? [[String: Any]] {
            let oldPrefix = oldDir.path(percentEncoded: false)
            let newPrefix = newDir.path(percentEncoded: false)
            let updated = records.map { record -> [String: Any] in
                var r = record
                if let paths = r["paths"] as? [String] {
                    r["paths"] = paths.map { $0.hasPrefix(oldPrefix) ? newPrefix + $0.dropFirst(oldPrefix.count) : $0 }
                }
                return r
            }
            defaults.set(updated, forKey: "shelf.items.v2")
        }
    }
}
