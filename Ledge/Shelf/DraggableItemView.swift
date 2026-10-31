import AppKit
import SwiftUI

/// 선반 항목 한 줄(AppKit). 끌면 파일 URL을 페이스트보드에 실어 내보내고, 잠기지 않았으면 선반에서 제거한다.
/// 클릭 = 선택(⌘클릭 = 토글, ⇧클릭 = 범위), 더블클릭 = 열기, 오른쪽 클릭 = 컨텍스트 메뉴. x 버튼은 별도 서브뷰라 드래그를 가로채지 않는다.
final class DraggableItemView: NSView, NSDraggingSource {
    /// row: 세로 목록용(아이콘 왼쪽·이름 오른쪽). card: 가로 목록용(아이콘 위·이름 아래).
    enum Style { case row, card }

    let style: Style
    var item: ShelfItem {
        didSet {
            if item != oldValue { refresh() }
            if item.id != oldValue.id { observeSelection() }
        }
    }
    var isSelected = false {
        didSet { if isSelected != oldValue { updateBackground() } }
    }
    weak var store: ShelfStore? {
        didSet { if store !== oldValue { observeSelection() } }
    }

    /// SwiftUI 재평가에 기대지 않고 스토어의 선택 상태를 직접 관찰한다.
    private func observeSelection() {
        guard let store else { return }
        let id = item.id
        withObservationTracking {
            isSelected = store.selectedIDs.contains(id)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSelection() }
        }
    }

    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let lockBadge = NSImageView()
    private let countBadge = NSTextField(labelWithString: "")
    private var mouseDownPoint: NSPoint?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet {
            closeButton.isHidden = !isHovered
            updateBackground()
        }
    }

    static let rowHeight: CGFloat = 44
    static let cardSize = NSSize(width: 84, height: 84)
    private var iconSize: CGFloat { style == .row ? 32 : 40 }

    init(item: ShelfItem, style: Style = .row) {
        self.item = item
        self.style = style
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: Self.rowHeight))
        wantsLayer = true
        layer?.cornerRadius = 8

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameField.font = .systemFont(ofSize: style == .row ? NSFont.smallSystemFontSize : 10)
        nameField.lineBreakMode = .byTruncatingMiddle
        nameField.maximumNumberOfLines = 2
        nameField.alignment = style == .row ? .natural : .center
        nameField.cell?.truncatesLastVisibleLine = true
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeButton.bezelStyle = .accessoryBarAction
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: String(localized: "제거"))
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = String(localized: "선반에서 제거")
        closeButton.target = self
        closeButton.action = #selector(removeTapped)
        closeButton.isHidden = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        lockBadge.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: String(localized: "잠김"))?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
        lockBadge.contentTintColor = .labelColor
        lockBadge.wantsLayer = true
        lockBadge.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        lockBadge.layer?.cornerRadius = 7
        lockBadge.translatesAutoresizingMaskIntoConstraints = false

        countBadge.font = .systemFont(ofSize: 9, weight: .bold)
        countBadge.textColor = .white
        countBadge.alignment = .center
        countBadge.wantsLayer = true
        countBadge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        countBadge.layer?.cornerRadius = 7
        countBadge.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(nameField)
        addSubview(closeButton)
        addSubview(lockBadge)
        addSubview(countBadge)
        switch style {
        case .row:
            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: iconSize),
                iconView.heightAnchor.constraint(equalToConstant: iconSize),

                nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
                nameField.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
                nameField.centerYAnchor.constraint(equalTo: centerYAnchor),

                closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                closeButton.widthAnchor.constraint(equalToConstant: 18),
                closeButton.heightAnchor.constraint(equalToConstant: 18),
            ])
        case .card:
            NSLayoutConstraint.activate([
                iconView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
                iconView.widthAnchor.constraint(equalToConstant: iconSize),
                iconView.heightAnchor.constraint(equalToConstant: iconSize),

                nameField.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
                nameField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                nameField.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),

                closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 2),
                closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
                closeButton.widthAnchor.constraint(equalToConstant: 18),
                closeButton.heightAnchor.constraint(equalToConstant: 18),
            ])
        }
        NSLayoutConstraint.activate([
            lockBadge.widthAnchor.constraint(equalToConstant: 14),
            lockBadge.heightAnchor.constraint(equalToConstant: 14),
            lockBadge.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 3),
            lockBadge.bottomAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 3),

            countBadge.heightAnchor.constraint(equalToConstant: 14),
            countBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 14),
            countBadge.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 5),
            countBadge.topAnchor.constraint(equalTo: iconView.topAnchor, constant: -5),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        switch style {
        case .row: NSSize(width: NSView.noIntrinsicMetric, height: Self.rowHeight)
        case .card: Self.cardSize
        }
    }

    // 패널이 키 윈도우가 아니어도 첫 클릭부터 드래그를 시작할 수 있어야 한다.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// 불투명하지 않은 뷰는 기본적으로 mouseDown이 창 이동으로 바뀐다. 항목은 끌어내야 하므로 막는다.
    override var mouseDownCanMoveWindow: Bool { false }

    // x 버튼을 제외한 모든 클릭(아이콘·이름 포함)은 줄 전체가 받아서 드래그로 이어간다.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit === closeButton || hit.isDescendant(of: closeButton) { return hit }
        return self
    }

    private func refresh() {
        let current = item
        iconView.image = NSWorkspace.shared.icon(forFile: current.path)
        if !current.isStack {
            ThumbnailProvider.shared.thumbnail(for: current.url, size: iconSize) { [weak self] image in
                guard let self, self.item.id == current.id, self.item.url == current.url else { return }
                self.iconView.image = image
            }
        }
        nameField.stringValue = current.name
        lockBadge.isHidden = !current.isLocked
        countBadge.isHidden = !current.isStack
        countBadge.stringValue = current.isStack ? " \(current.count) " : ""
        let exists = current.exists
        alphaValue = exists ? 1 : 0.45
        let pathList = current.paths.joined(separator: "\n")
        toolTip = exists ? pathList : String(localized: "원본을 찾을 수 없음") + "\n" + pathList
    }

    private func updateBackground() {
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
        } else if isHovered {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        } else {
            layer?.backgroundColor = nil
        }
    }

    @objc private func removeTapped() {
        store?.remove(item)
    }

    // MARK: - 호버

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    // MARK: - 마우스: 선택·열기·드래그

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 {
            mouseDownPoint = nil
            open()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let now = convert(event.locationInWindow, from: nil)
        guard hypot(now.x - start.x, now.y - start.y) >= 4 else { return }
        mouseDownPoint = nil
        LedgeLog.write("item drag begin \(item.name)")
        beginDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownPoint != nil else { return }
        mouseDownPoint = nil
        store?.select(item.id, modifiers: event.modifierFlags)
        LedgeLog.write("item select \(item.name) selected=\(store?.selectedIDs.count ?? -1) key=\(window?.isKeyWindow ?? false) fr=\(window?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")")
        if let store { QuickLookController.shared.update(urls: store.selectedItems.flatMap(\.urls)) }
    }

    override func rightMouseDown(with event: NSEvent) {
        store?.ensureSelected(item.id)
        if let menu = contextMenu() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    // MARK: - 드래그 소스

    /// 이 항목이 선택에 포함돼 있으면 선택된 항목 전부를 함께 끈다.
    private var itemsToDrag: [ShelfItem] {
        if let store, store.selectedIDs.contains(item.id), store.selectedItems.count > 1 {
            return store.selectedItems
        }
        return [item]
    }

    private func beginDrag(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let iconSize = NSSize(width: 48, height: 48)
        var draggingItems: [NSDraggingItem] = []
        var offset: CGFloat = 0
        for shelfItem in itemsToDrag {
            for url in shelfItem.urls {
                let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
                draggingItem.setDraggingFrame(
                    NSRect(x: location.x - iconSize.width / 2 + offset, y: location.y - iconSize.height / 2 - offset,
                           width: iconSize.width, height: iconSize.height),
                    contents: icon
                )
                draggingItems.append(draggingItem)
                offset = min(offset + 4, 24)
            }
        }
        let session = beginDraggingSession(with: draggingItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .stack
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .withinApplication: return []
        case .outsideApplication: return [.copy, .move, .generic]
        @unknown default: return [.copy, .generic]
        }
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { false }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        LedgeLog.write("item session began at \(screenPoint)")
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        LedgeLog.write("item session ended at \(screenPoint) op=\(operation.rawValue)")
        // 어딘가에 실제로 놓였으면(복사·이동 등) 잠기지 않은 항목은 선반에서 내려간다.
        guard !operation.isEmpty, let store else { return }
        for shelfItem in itemsToDrag { store.exported(shelfItem) }
    }

    // MARK: - 컨텍스트 메뉴 (C1~C3, C6)

    private var targetItems: [ShelfItem] {
        guard let store else { return [item] }
        let selected = store.selectedItems
        return selected.isEmpty ? [item] : selected
    }

    private var targetURLs: [URL] { targetItems.flatMap(\.urls) }

    private func contextMenu() -> NSMenu? {
        let menu = NSMenu()
        let targets = targetItems
        let urls = targetURLs
        let plural = urls.count > 1 ? String(localized: " (\(urls.count)개)") : ""

        menu.addItem(withTitle: String(localized: "열기") + plural, action: #selector(open), keyEquivalent: "").target = self
        let openWith = NSMenuItem(title: String(localized: "다음으로 열기"), action: nil, keyEquivalent: "")
        openWith.submenu = openWithMenu(for: urls)
        menu.addItem(openWith)
        menu.addItem(withTitle: String(localized: "미리보기"), action: #selector(showQuickLook), keyEquivalent: " ").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Finder에서 보기"), action: #selector(revealInFinder), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "경로 복사") + plural, action: #selector(copyPaths), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "공유…"), action: #selector(share), keyEquivalent: "").target = self
        menu.addItem(.separator())
        if !item.isStack, targets.count == 1 {
            menu.addItem(withTitle: String(localized: "다른 위치에 복사…"), action: #selector(copyToLocation), keyEquivalent: "").target = self
            menu.addItem(withTitle: String(localized: "다른 위치로 이동…"), action: #selector(moveToLocation), keyEquivalent: "").target = self
            menu.addItem(withTitle: String(localized: "이름 변경…"), action: #selector(rename), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }

        let allLocked = targets.allSatisfy(\.isLocked)
        menu.addItem(withTitle: allLocked ? String(localized: "잠금 해제") : String(localized: "잠금"), action: #selector(toggleLock), keyEquivalent: "").target = self
        if targets.count >= 2 {
            menu.addItem(withTitle: String(localized: "선택 항목 합치기 (\(targets.count)개)"), action: #selector(mergeSelected), keyEquivalent: "").target = self
        } else if item.isStack {
            menu.addItem(withTitle: String(localized: "스택 풀기 (\(item.count)개)"), action: #selector(splitStack), keyEquivalent: "").target = self
        }
        if let store, store.items.count >= 2 {
            menu.addItem(withTitle: String(localized: "전체 합치기"), action: #selector(mergeAll), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "선반에서 제거") + (targets.count > 1 ? String(localized: " (\(targets.count)개)") : ""), action: #selector(removeTargets), keyEquivalent: "").target = self
        return menu
    }

    private func openWithMenu(for urls: [URL]) -> NSMenu {
        let menu = NSMenu()
        guard let first = urls.first else { return menu }
        var apps = NSWorkspace.shared.urlsForApplications(toOpen: first)
        if urls.count > 1 {
            // 모든 파일을 열 수 있는 앱만 남긴다.
            for url in urls.dropFirst() {
                let can = Set(NSWorkspace.shared.urlsForApplications(toOpen: url))
                apps = apps.filter { can.contains($0) }
            }
        }
        if apps.isEmpty {
            let none = NSMenuItem(title: String(localized: "열 수 있는 앱 없음"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
            return menu
        }
        for app in apps.prefix(15) {
            let name = FileManager.default.displayName(atPath: app.path(percentEncoded: false))
                .replacingOccurrences(of: ".app", with: "")
            let menuItem = NSMenuItem(title: name, action: #selector(openWith(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = app
            let icon = NSWorkspace.shared.icon(forFile: app.path(percentEncoded: false))
            icon.size = NSSize(width: 16, height: 16)
            menuItem.image = icon
            menu.addItem(menuItem)
        }
        return menu
    }

    @objc private func open() {
        for url in targetURLs { NSWorkspace.shared.open(url) }
    }

    @objc private func openWith(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(targetURLs, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func showQuickLook() {
        QuickLookController.shared.toggle(urls: targetURLs)
    }

    @objc private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(targetURLs)
    }

    @objc private func copyPaths() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(targetURLs.map { $0.path(percentEncoded: false) }.joined(separator: "\n"), forType: .string)
    }

    // MARK: - 공유 (C4) · 복사/이동/이름 변경 (C5)

    @objc private func share() {
        let picker = NSSharingServicePicker(items: targetURLs)
        picker.show(relativeTo: iconView.frame, of: self, preferredEdge: .maxX)
    }

    private func runSavePanel(title: String, prompt: String, completion: @escaping @MainActor (URL) -> Void) {
        let panel = NSSavePanel()
        panel.title = title
        panel.prompt = prompt
        panel.nameFieldStringValue = item.name
        panel.directoryURL = item.url.deletingLastPathComponent()
        panel.canCreateDirectories = true
        panel.level = .floating
        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }

    @objc private func copyToLocation() {
        let source = item.url
        runSavePanel(title: String(localized: "다른 위치에 복사"), prompt: String(localized: "복사")) { destination in
            do {
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.copyItem(at: source, to: destination)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func moveToLocation() {
        let source = item.url
        let id = item.id
        runSavePanel(title: String(localized: "다른 위치로 이동"), prompt: String(localized: "이동")) { [weak self] destination in
            do {
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.moveItem(at: source, to: destination)
                self?.store?.replace(id: id, url: source, with: destination)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func rename() {
        let source = item.url
        let id = item.id
        let alert = NSAlert()
        alert.messageText = String(localized: "이름 변경")
        alert.informativeText = source.lastPathComponent
        alert.addButton(withTitle: String(localized: "변경"))
        alert.addButton(withTitle: String(localized: "취소"))
        let field = NSTextField(string: source.lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != source.lastPathComponent, !newName.contains("/") else { return }
        let destination = source.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: source, to: destination)
            store?.replace(id: id, url: source, with: destination)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func toggleLock() {
        guard let store else { return }
        let targets = targetItems
        let allLocked = targets.allSatisfy(\.isLocked)
        store.setLock(!allLocked, ids: Set(targets.map(\.id)))
    }

    @objc private func mergeSelected() { store?.mergeSelected() }
    @objc private func mergeAll() { store?.mergeAll() }
    @objc private func splitStack() { store?.split(id: item.id) }

    @objc private func removeTargets() {
        guard let store else { return }
        if store.selectedItems.isEmpty { store.remove(item) } else { store.removeSelected() }
    }
}

/// SwiftUI 목록 안에서 쓰기 위한 래퍼.
struct DraggableItemRow: NSViewRepresentable {
    let item: ShelfItem
    var style: DraggableItemView.Style = .row
    let store: ShelfStore
    let isSelected: Bool

    func makeNSView(context: Context) -> DraggableItemView {
        let view = DraggableItemView(item: item, style: style)
        view.store = store
        view.isSelected = isSelected
        return view
    }

    func updateNSView(_ nsView: DraggableItemView, context: Context) {
        nsView.item = item
        nsView.store = store
        nsView.isSelected = isSelected
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DraggableItemView, context: Context) -> CGSize? {
        switch style {
        case .row: CGSize(width: proposal.width ?? 160, height: DraggableItemView.rowHeight)
        case .card: DraggableItemView.cardSize
        }
    }
}
