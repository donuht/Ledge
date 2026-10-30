import Foundation

/// 파일 로그 ~/Library/Logs/Ledge/ledge.log.
/// `write`(동작 추적)는 설정의 "문제 진단 기록"을 켰을 때만 남고, `error`는 항상 남는다.
enum LedgeLog {
    static let enabledKey = "debug.logging"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Ledge")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "ledge.log")
    }()

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        append(message())
    }

    static func error(_ message: String) {
        NSLog("Ledge error: %@", message)
        append("ERROR " + message)
    }

    private static func append(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
