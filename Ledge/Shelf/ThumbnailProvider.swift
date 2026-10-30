import AppKit
import QuickLookThumbnailing

/// QuickLook 썸네일을 비동기로 만들고 경로·크기별로 캐시한다. 썸네일이 없는 파일은 호출하지 않는다(아이콘 유지).
@MainActor
final class ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private var cache: [String: NSImage] = [:]
    private var waiters: [String: [@MainActor (NSImage) -> Void]] = [:]

    func thumbnail(for url: URL, size: CGFloat, completion: @escaping @MainActor (NSImage) -> Void) {
        let key = "\(url.path)@\(Int(size))"
        if let image = cache[key] {
            completion(image)
            return
        }
        let alreadyRequested = waiters[key] != nil
        waiters[key, default: []].append(completion)
        guard !alreadyRequested else { return }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: size, height: size), scale: scale, representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            nonisolated(unsafe) let image = representation?.nsImage
            Task { @MainActor in
                let callbacks = self.waiters.removeValue(forKey: key) ?? []
                guard let image else { return }
                self.cache[key] = image
                for callback in callbacks { callback(image) }
            }
        }
    }
}
