import AppKit
import Observation

/// 선반 항목의 단일 진실 공급원. 추가·제거·전체 비우기·되살리기·선택·잠금·스택을 담당한다.
@MainActor
@Observable
final class ShelfStore {
    private(set) var items: [ShelfItem] = []

    /// 현재 선택된 항목(클릭·⌘클릭). 저장하지 않는다.
    private(set) var selectedIDs: Set<ShelfItem.ID> = []

    /// 제거된 항목 묶음(원래 위치 포함). 되살리기는 마지막 묶음부터 되돌린다.
    private(set) var removedBatches: [RemovedBatch] = []

    struct RemovedBatch: Sendable {
        struct Entry: Sendable {
            let index: Int
            let item: ShelfItem
            /// 휴지통으로 보낸 스니펫 파일(원래 경로 → 휴지통 안 경로). 되살리면 다시 가져온다.
            var trashed: [URL: URL] = [:]
        }
        var entries: [Entry]
    }

    var isEmpty: Bool { items.isEmpty }
    var canRestore: Bool { !removedBatches.isEmpty }
    var selectedItems: [ShelfItem] { items.filter { selectedIDs.contains($0.id) } }
    var hasUnlocked: Bool { items.contains { !$0.isLocked } }

    /// 항목이 바뀔 때마다 호출된다(자동 숨김 판단용).
    var onChange: (() -> Void)?

    private let defaultsKey = "shelf.items.v2"
    private let legacyDefaultsKey = "shelf.itemPaths"
    private let maxRemovedBatches = 50
    /// 드래그로 내보낸 스니펫을 휴지통으로 보내기까지 기다리는 시간.
    /// 받는 앱(클로드·슬랙 같은 Electron 앱)은 드롭이 끝난 뒤에 비동기로 파일을 읽으므로 바로 지우면 "파일 없음"이 난다.
    static let exportTrashDelay: TimeInterval = 60

    init(loadPersisted: Bool = true) {
        if loadPersisted {
            load()
            sweepOrphanSnippets()
        }
    }

    // MARK: - 추가·제거

    /// 파일 URL들을 선반에 각각 추가한다. 이미 있는 경로는 건너뛴다.
    @discardableResult
    func add(urls: [URL]) -> Int {
        var existing = Set(items.flatMap(\.urls))
        var added = 0
        for url in urls where url.isFileURL {
            let item = ShelfItem(url: url)
            guard !existing.contains(item.url) else { continue }
            existing.insert(item.url)
            items.append(item)
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    func remove(_ item: ShelfItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items.remove(at: index)
        selectedIDs.remove(item.id)
        pushRemoved(RemovedBatch(entries: [.init(index: index, item: item)]))
        save()
    }

    func remove(id: ShelfItem.ID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        remove(item)
    }

    func removeSelected() {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        let entries = items.enumerated().filter { selectedIDs.contains($0.element.id) }
            .map { RemovedBatch.Entry(index: $0.offset, item: $0.element) }
        items.removeAll { selectedIDs.contains($0.id) }
        selectedIDs.removeAll()
        pushRemoved(RemovedBatch(entries: entries))
        save()
    }

    /// 잠긴 항목은 남기고 전부 비운다.
    func removeAll() {
        let entries = items.enumerated().filter { !$0.element.isLocked }
            .map { RemovedBatch.Entry(index: $0.offset, item: $0.element) }
        guard !entries.isEmpty else { return }
        items.removeAll { !$0.isLocked }
        selectedIDs = selectedIDs.filter { id in items.contains { $0.id == id } }
        pushRemoved(RemovedBatch(entries: entries))
        save()
    }

    /// 드래그해 내보낸 뒤: 잠기지 않은 항목만 선반에서 내려간다.
    /// 스니펫 파일은 받는 앱이 다 읽을 시간을 주고 나서(`exportTrashDelay`) 휴지통으로 보낸다.
    func exported(_ item: ShelfItem) {
        guard !item.isLocked else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items.remove(at: index)
        selectedIDs.remove(item.id)
        appendRemoved(RemovedBatch(entries: [.init(index: index, item: item)]))
        save()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.exportTrashDelay) { [weak self] in
            self?.trashExportedSnippets(of: item)
        }
    }

    /// 지연 삭제: 그 사이 되살려졌으면 두고, 아니면 휴지통으로 보내고 되살리기 기록에 경로를 남긴다.
    private func trashExportedSnippets(of item: ShelfItem) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        let trashed = trashSnippets(of: item)
        guard !trashed.isEmpty else { return }
        for b in removedBatches.indices {
            for e in removedBatches[b].entries.indices where removedBatches[b].entries[e].item.id == item.id {
                removedBatches[b].entries[e].trashed = trashed
            }
        }
    }

    /// 마지막으로 제거한 항목(또는 전체 비우기 묶음)을 원래 자리에 되돌린다.
    func restoreLastRemoved() {
        guard let batch = removedBatches.popLast() else { return }
        let existing = Set(items.flatMap(\.urls))
        for entry in batch.entries.sorted(by: { $0.index < $1.index }) {
            guard !entry.item.urls.contains(where: { existing.contains($0) }) else { continue }
            for (original, inTrash) in entry.trashed where !FileManager.default.fileExists(atPath: original.path(percentEncoded: false)) {
                try? FileManager.default.moveItem(at: inTrash, to: original)
            }
            let index = min(entry.index, items.count)
            items.insert(entry.item, at: index)
        }
        save()
    }

    /// 선반에서 빠진 항목 중 Ledge가 만든 스니펫 파일(웹 이미지·글·링크)은 휴지통으로 보낸다. 원본 파일은 건드리지 않는다.
    private func trashSnippets(of item: ShelfItem) -> [URL: URL] {
        let snippetDir = SnippetWriter.directory.standardizedFileURL.path(percentEncoded: false)
        var trashed: [URL: URL] = [:]
        for url in item.urls where url.path(percentEncoded: false).hasPrefix(snippetDir) {
            var result: NSURL?
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: &result)) != nil, let result {
                trashed[url] = result as URL
            }
        }
        return trashed
    }

    /// 지연 삭제 전에 앱이 끝나 남은 스니펫(선반에 없고, 만든 지 10분 넘은 것)을 시작할 때 휴지통으로 보낸다.
    private func sweepOrphanSnippets() {
        let fm = FileManager.default
        let dir = SnippetWriter.directory
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path(percentEncoded: false)) else { return }
        let onShelf = Set(items.flatMap(\.urls).map { $0.path(percentEncoded: false) })
        for name in names where !name.hasPrefix(".") {
            let url = dir.appendingPathComponent(name).standardizedFileURL
            guard !onShelf.contains(url.path(percentEncoded: false)),
                  let attrs = try? fm.attributesOfItem(atPath: url.path(percentEncoded: false)),
                  let created = attrs[.creationDate] as? Date, Date().timeIntervalSince(created) > 600 else { continue }
            try? fm.trashItem(at: url, resultingItemURL: nil)
        }
    }

    private func pushRemoved(_ batch: RemovedBatch) {
        let batch = RemovedBatch(entries: batch.entries.map { entry in
            var entry = entry
            entry.trashed = trashSnippets(of: entry.item)
            return entry
        })
        appendRemoved(batch)
    }

    private func appendRemoved(_ batch: RemovedBatch) {
        removedBatches.append(batch)
        if removedBatches.count > maxRemovedBatches {
            removedBatches.removeFirst(removedBatches.count - maxRemovedBatches)
        }
    }

    // MARK: - 선택

    /// 범위 선택(⇧클릭)의 기준점: 마지막으로 ⇧ 없이 클릭한 항목.
    private var anchorID: ShelfItem.ID?

    /// 클릭 = 그것만, ⌘클릭 = 토글, ⇧클릭 = 기준점부터 범위(⌘⇧ = 범위를 기존 선택에 더함).
    func select(_ id: ShelfItem.ID, modifiers: NSEvent.ModifierFlags) {
        let flags = modifiers.intersection([.command, .shift])
        if flags.contains(.shift), let anchor = anchorID,
           let a = items.firstIndex(where: { $0.id == anchor }),
           let b = items.firstIndex(where: { $0.id == id }) {
            let range = Set(items[min(a, b)...max(a, b)].map(\.id))
            if flags.contains(.command) { selectedIDs.formUnion(range) } else { selectedIDs = range }
            return
        }
        if flags.contains(.command) {
            if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
        } else {
            selectedIDs = [id]
        }
        anchorID = id
    }

    /// 고무줄 선택 등 바깥에서 계산한 선택을 통째로 적용한다. 선반에 없는 id는 버린다.
    func setSelection(_ ids: Set<ShelfItem.ID>) {
        let valid = Set(items.map(\.id))
        let next = ids.intersection(valid)
        if next != selectedIDs { selectedIDs = next }
    }

    /// 컨텍스트 메뉴용: 이미 선택에 포함돼 있으면 그대로, 아니면 이 항목만 선택.
    func ensureSelected(_ id: ShelfItem.ID) {
        if !selectedIDs.contains(id) { selectedIDs = [id] }
    }

    func selectAll() { selectedIDs = Set(items.map(\.id)) }
    func clearSelection() { selectedIDs.removeAll() }

    // MARK: - 경로 바꾸기 (이동·이름 변경 뒤)

    func replace(id: ShelfItem.ID, url old: URL, with new: URL) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]
        let urls = item.urls.map { $0 == old.standardizedFileURL ? new : $0 }
        items[index] = ShelfItem(id: item.id, urls: urls, isLocked: item.isLocked)
        save()
    }

    // MARK: - 잠금

    func toggleLock(id: ShelfItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isLocked.toggle()
        save()
    }

    func setLock(_ locked: Bool, ids: Set<ShelfItem.ID>) {
        for index in items.indices where ids.contains(items[index].id) {
            items[index].isLocked = locked
        }
        save()
    }

    // MARK: - 스택

    /// 여러 항목을 하나의 스택으로 합친다(첫 항목 자리에). 하나라도 잠겨 있으면 스택도 잠긴다.
    func merge(ids: Set<ShelfItem.ID>) {
        let targets = items.enumerated().filter { ids.contains($0.element.id) }
        guard targets.count >= 2 else { return }
        var seen = Set<URL>()
        var urls: [URL] = []
        for url in targets.flatMap({ $0.element.urls }) where !seen.contains(url) {
            seen.insert(url)
            urls.append(url)
        }
        let locked = targets.contains { $0.element.isLocked }
        let first = targets[0].offset
        items.removeAll { ids.contains($0.id) }
        let stack = ShelfItem(urls: urls, isLocked: locked)
        items.insert(stack, at: min(first, items.count))
        selectedIDs = [stack.id]
        save()
    }

    func mergeSelected() { merge(ids: selectedIDs) }
    func mergeAll() { merge(ids: Set(items.map(\.id))) }

    /// 스택을 낱개 항목으로 푼다(같은 자리에 순서대로).
    func split(id: ShelfItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].isStack else { return }
        let stack = items.remove(at: index)
        let singles = stack.urls.map { ShelfItem(url: $0, isLocked: stack.isLocked) }
        items.insert(contentsOf: singles, at: index)
        selectedIDs = Set(singles.map(\.id))
        save()
    }

    // MARK: - 저장 (경로만, 파일 복사 없음)

    private func save() {
        let records: [[String: Any]] = items.map { ["paths": $0.paths, "locked": $0.isLocked] }
        UserDefaults.standard.set(records, forKey: defaultsKey)
        onChange?()
    }

    private func load() {
        if let records = UserDefaults.standard.array(forKey: defaultsKey) as? [[String: Any]] {
            items = records.compactMap { record in
                guard let paths = record["paths"] as? [String], !paths.isEmpty else { return nil }
                return ShelfItem(urls: paths.map { URL(fileURLWithPath: $0) }, isLocked: record["locked"] as? Bool ?? false)
            }
        } else if let paths = UserDefaults.standard.stringArray(forKey: legacyDefaultsKey) {
            items = paths.map { ShelfItem(url: URL(fileURLWithPath: $0)) }
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            save()
        }
    }
}
