import AppKit
import SwiftUI

/// 선반 항목 한 줄(AppKit). 줄을 끌면 파일 URL을 페이스트보드에 실어 내보내고,
/// 내보내기가 성공하면 선반에서 제거한다. x 버튼은 별도 서브뷰라 드래그를 가로채지 않는다.
final class DraggableItemView: NSView, NSDraggingSource {
    /// row: 세로 목록용(아이콘 왼쪽·이름 오른쪽). card: 가로 목록용(아이콘 위·이름 아래).
    enum Style { case row, card }

    let style: Style
    var item: ShelfItem {
        didSet { if item != oldValue { refresh() } }
    }
    var onRemove: ((ShelfItem) -> Void)?
    var onExported: ((ShelfItem) -> Void)?

    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var mouseDownPoint: NSPoint?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { closeButton.isHidden = !isHovered } }

    static let rowHeight: CGFloat = 44
    static let cardSize = NSSize(width: 84, height: 84)

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
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "제거")
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "선반에서 제거"
        closeButton.target = self
        closeButton.action = #selector(removeTapped)
        closeButton.isHidden = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(nameField)
        addSubview(closeButton)
        switch style {
        case .row:
            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 32),
                iconView.heightAnchor.constraint(equalToConstant: 32),

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
                iconView.widthAnchor.constraint(equalToConstant: 40),
                iconView.heightAnchor.constraint(equalToConstant: 40),

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
        iconView.image = NSWorkspace.shared.icon(forFile: item.path)
        nameField.stringValue = item.name
        let exists = item.exists
        alphaValue = exists ? 1 : 0.45
        toolTip = exists ? item.path : "원본을 찾을 수 없음\n\(item.path)"
    }

    @objc private func removeTapped() {
        onRemove?(item)
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

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = nil
    }

    // MARK: - 드래그 소스

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        YonkLog.write("item mouseDown \(item.name)")
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let now = convert(event.locationInWindow, from: nil)
        guard hypot(now.x - start.x, now.y - start.y) >= 4 else { return }
        mouseDownPoint = nil
        YonkLog.write("item drag begin \(item.name)")
        beginDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
    }

    private func beginDrag(with event: NSEvent) {
        let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: item.path)
        let iconSize = NSSize(width: 48, height: 48)
        let location = convert(event.locationInWindow, from: nil)
        draggingItem.setDraggingFrame(
            NSRect(x: location.x - iconSize.width / 2, y: location.y - iconSize.height / 2,
                   width: iconSize.width, height: iconSize.height),
            contents: icon
        )
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
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
        YonkLog.write("item session began at \(screenPoint)")
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        YonkLog.write("item session ended at \(screenPoint) op=\(operation.rawValue)")
        // 어딘가에 실제로 놓였으면(복사·이동·링크 등) 선반에서 내려간다.
        if !operation.isEmpty {
            onExported?(item)
        }
    }
}

/// SwiftUI 목록 안에서 쓰기 위한 래퍼.
struct DraggableItemRow: NSViewRepresentable {
    let item: ShelfItem
    var style: DraggableItemView.Style = .row
    let onRemove: (ShelfItem) -> Void
    let onExported: (ShelfItem) -> Void

    func makeNSView(context: Context) -> DraggableItemView {
        let view = DraggableItemView(item: item, style: style)
        view.onRemove = onRemove
        view.onExported = onExported
        return view
    }

    func updateNSView(_ nsView: DraggableItemView, context: Context) {
        nsView.item = item
        nsView.onRemove = onRemove
        nsView.onExported = onExported
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DraggableItemView, context: Context) -> CGSize? {
        switch style {
        case .row: CGSize(width: proposal.width ?? 160, height: DraggableItemView.rowHeight)
        case .card: DraggableItemView.cardSize
        }
    }
}
