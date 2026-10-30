import AppKit
import SwiftUI

/// 클립보드 기록 창 내용: 검색, 목록(고정 항목 위), Return=다시 복사, ⌘Return=선반으로, Delete=삭제.
struct ClipboardHistoryView: View {
    @Bindable var store: ClipboardStore
    var onCopy: (ClipboardEntry) -> Void
    var onSendToShelf: (ClipboardEntry) -> Void
    var onClose: () -> Void

    @State private var query = ""
    @State private var selection: ClipboardEntry.ID?
    @FocusState private var searchFocused: Bool

    private var filtered: [ClipboardEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? store.entries : store.entries.filter { entry in
            entry.title.lowercased().contains(q) || (entry.text?.lowercased().contains(q) ?? false)
                || (entry.paths?.contains { $0.lowercased().contains(q) } ?? false)
        }
        return base.filter(\.isPinned) + base.filter { !$0.isPinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("검색", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding(10)
                .onSubmit { copySelectedOrFirst() }
            Divider()
            if filtered.isEmpty {
                VStack {
                    Spacer()
                    Text(store.entries.isEmpty ? "아직 기록이 없습니다.\n복사(⌘C)하면 여기에 쌓입니다." : "검색 결과 없음")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(filtered, selection: $selection) { entry in
                    row(entry)
                        .tag(entry.id)
                        .contextMenu { contextMenu(entry) }
                        .onTapGesture(count: 2) { onCopy(entry) }
                }
                .listStyle(.inset)
                .onDeleteCommand { if let id = selection { store.remove(id: id) } }
                .onKeyPress(.return) {
                    guard let entry = selected else { return .ignored }
                    if NSEvent.modifierFlags.contains(.command) { onSendToShelf(entry) } else { onCopy(entry) }
                    return .handled
                }
                .onKeyPress(.escape) { onClose(); return .handled }
            }
            Divider()
            HStack {
                Text("\(store.entries.count)건")
                Spacer()
                Text("Return 다시 복사 · ⌘Return 선반으로 · Delete 삭제")
                Button("고정 외 모두 지우기") { store.removeUnpinned() }
                    .disabled(!store.entries.contains { !$0.isPinned })
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 380, minHeight: 320)
        .onAppear { searchFocused = true }
        .onExitCommand(perform: onClose)
    }

    private var selected: ClipboardEntry? {
        filtered.first { $0.id == selection }
    }

    private func copySelectedOrFirst() {
        if let entry = selected ?? filtered.first { onCopy(entry) }
    }

    @ViewBuilder
    private func row(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 10) {
            if entry.kind == .image, let url = store.imageURL(for: entry), let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: entry.symbolName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).lineLimit(1).truncationMode(.tail)
                Text("\(entry.subtitle) · \(entry.date.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                store.togglePin(id: entry.id)
            } label: {
                Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(entry.isPinned ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help(entry.isPinned ? "고정 해제" : "고정 (지우기에서 제외)")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func contextMenu(_ entry: ClipboardEntry) -> some View {
        Button("다시 복사") { onCopy(entry) }
        Button("선반으로 보내기") { onSendToShelf(entry) }
        Divider()
        Button(entry.isPinned ? "고정 해제" : "고정") { store.togglePin(id: entry.id) }
        Button("삭제") { store.remove(id: entry.id) }
    }
}

/// 기록 창. 열 때 앱을 활성화하고, 복사 후 닫으면 이전 앱으로 돌아가 바로 ⌘V 할 수 있게 한다.
@MainActor
final class ClipboardWindowController {
    private var window: NSWindow?
    private var previousApp: NSRunningApplication?
    private let make: () -> ClipboardHistoryView

    init(make: @escaping () -> ClipboardHistoryView) {
        self.make = make
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: make())
            let window = NSWindow(contentViewController: hosting)
            window.title = "클립보드 기록"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 460, height: 520))
            window.center()
            window.level = .floating
            self.window = window
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func toggle() {
        if isVisible { close(returnToPreviousApp: false) } else { show() }
    }

    func close(returnToPreviousApp: Bool) {
        window?.orderOut(nil)
        if returnToPreviousApp, let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp.activate()
        }
    }
}
