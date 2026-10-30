import AppKit
import Observation

/// 선반 항목의 단일 진실 공급원. 추가·제거·전체 비우기·마지막 제거 되살리기를 담당한다.
@MainActor
@Observable
final class ShelfStore {
    private(set) var items: [ShelfItem] = []

    /// 제거된 항목 묶음(원래 위치 포함). 되살리기는 마지막 묶음부터 되돌린다.
    private(set) var removedBatches: [RemovedBatch] = []

    struct RemovedBatch: Sendable {
        struct Entry: Sendable {
            let index: Int
            let item: ShelfItem
        }
        let entries: [Entry]
    }

    var isEmpty: Bool { items.isEmpty }
    var canRestore: Bool { !removedBatches.isEmpty }

    private let defaultsKey = "shelf.itemPaths"
    private let maxRemovedBatches = 50

    init(loadPersisted: Bool = true) {
        if loadPersisted { load() }
    }

    // MARK: - 변경

    /// 파일 URL들을 선반에 추가한다. 이미 있는 경로는 건너뛴다.
    @discardableResult
    func add(urls: [URL]) -> Int {
        let existing = Set(items.map(\.url))
        var added = 0
        for url in urls where url.isFileURL {
            let item = ShelfItem(url: url)
            guard !existing.contains(item.url),
                  !items.contains(where: { $0.url == item.url }) else { continue }
            items.append(item)
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    func remove(_ item: ShelfItem) {
        guard let index = items.firstIndex(of: item) else { return }
        items.remove(at: index)
        pushRemoved(RemovedBatch(entries: [.init(index: index, item: item)]))
        save()
    }

    func remove(id: ShelfItem.ID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        remove(item)
    }

    func removeAll() {
        guard !items.isEmpty else { return }
        let entries = items.enumerated().map { RemovedBatch.Entry(index: $0.offset, item: $0.element) }
        items.removeAll()
        pushRemoved(RemovedBatch(entries: entries))
        save()
    }

    /// 마지막으로 제거한 항목(또는 전체 비우기 묶음)을 원래 자리에 되돌린다.
    func restoreLastRemoved() {
        guard let batch = removedBatches.popLast() else { return }
        for entry in batch.entries.sorted(by: { $0.index < $1.index }) {
            guard !items.contains(where: { $0.url == entry.item.url }) else { continue }
            let index = min(entry.index, items.count)
            items.insert(entry.item, at: index)
        }
        save()
    }

    private func pushRemoved(_ batch: RemovedBatch) {
        removedBatches.append(batch)
        if removedBatches.count > maxRemovedBatches {
            removedBatches.removeFirst(removedBatches.count - maxRemovedBatches)
        }
    }

    // MARK: - 저장 (경로만, 파일 복사 없음)

    private func save() {
        let paths = items.map(\.path)
        UserDefaults.standard.set(paths, forKey: defaultsKey)
    }

    private func load() {
        guard let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) else { return }
        items = paths.map { ShelfItem(url: URL(fileURLWithPath: $0)) }
    }
}
