import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// 영상 파일 한 개의 기본 정보(길이·해상도·fps·코덱·소리·크기). 해상도는 회전을 반영한 표시 기준.
struct MediaInfo: Sendable, Equatable {
    var duration: Double
    var width: Int
    var height: Int
    var fps: Double
    var videoCodec: String
    var hasAudio: Bool
    var fileSize: Int64

    /// `12.00s · 1920×1080 · 24.00fps · H.264 · 소리 있음 · 24.3 MB`
    var summary: String {
        let size = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        return [
            String(format: "%.2fs", duration),
            "\(width)×\(height)",
            String(format: "%.2ffps", fps),
            videoCodec,
            hasAudio ? String(localized: "소리 있음") : String(localized: "무음"),
            size,
        ].joined(separator: " · ")
    }
}

enum MediaInfoProvider {
    /// 파일 URL이 영상(`.movie`/`.video`)인지. 메타데이터만 보므로 가볍다.
    static func isVideo(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }

    /// 영상이 아니거나 읽지 못하면 nil. 결과는 URL+수정 시각 기준으로 메모리에 캐시한다.
    static func info(for url: URL) async -> MediaInfo? {
        guard isVideo(url) else { return nil }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(url.standardizedFileURL.path(percentEncoded: false))|\(modified)"
        if let cached = await cache.get(key) { return cached }
        guard let info = await load(url, fileSize: Int64(values?.fileSize ?? 0)) else { return nil }
        await cache.set(key, info)
        return info
    }

    /// 영상 URL마다 `파일명: 요약` 한 줄씩, `\n`으로 잇는다. 영상이 아닌 파일은 건너뛰고, 읽지 못한 영상은 `?`로 둔다.
    static func lines(for urls: [URL]) async -> String {
        var lines: [String] = []
        for url in urls where isVideo(url) {
            let summary = await info(for: url)?.summary ?? "?"
            lines.append("\(url.lastPathComponent): \(summary)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 내부

    private actor Cache {
        private var storage: [String: MediaInfo] = [:]
        func get(_ key: String) -> MediaInfo? { storage[key] }
        func set(_ key: String, _ value: MediaInfo) {
            if storage.count > 500 { storage.removeAll() }
            storage[key] = value
        }
    }

    private static let cache = Cache()

    private static func load(_ url: URL, fileSize: Int64) async -> MediaInfo? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
            let (naturalSize, transform, frameRate, formats) = try await track.load(
                .naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions
            )
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)

            // 90°/270° 회전이면 표시 기준으로 폭·높이를 바꾼다.
            let rotated = naturalSize.applying(transform)
            let width = Int(abs(rotated.width).rounded())
            let height = Int(abs(rotated.height).rounded())

            let codec = formats.first.map { codecName(CMFormatDescriptionGetMediaSubType($0)) } ?? "?"
            return MediaInfo(
                duration: duration.isNumeric ? duration.seconds : 0,
                width: width,
                height: height,
                fps: Double(frameRate),
                videoCodec: codec,
                hasAudio: !audioTracks.isEmpty,
                fileSize: fileSize
            )
        } catch {
            return nil
        }
    }

    private static let codecNames: [String: String] = [
        "avc1": "H.264", "avc3": "H.264",
        "hvc1": "HEVC", "hev1": "HEVC",
        "apcn": "ProRes 422", "apch": "ProRes 422 HQ", "apcs": "ProRes 422 LT", "apco": "ProRes 422 Proxy",
        "ap4h": "ProRes 4444", "ap4x": "ProRes 4444 XQ",
        "jpeg": "MJPEG",
    ]

    private static func codecName(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        let fourcc = String(bytes: bytes, encoding: .macOSRoman)?.trimmingCharacters(in: .whitespaces) ?? "\(code)"
        return codecNames[fourcc] ?? fourcc
    }
}
