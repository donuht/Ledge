import Foundation

/// 감독 환경에서 동작을 추적하기 위한 파일 로그. ~/Library/Logs/Ledge/ledge.log
enum LedgeLog {
    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Ledge")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "ledge.log")
    }()

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)\n"
        NSLog("Ledge: %@", message)
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
