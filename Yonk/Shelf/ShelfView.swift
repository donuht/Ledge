import SwiftUI

/// 선반 내용: 헤더(되살리기·전체 비우기), 항목 목록 또는 빈 상태.
struct ShelfView: View {
    @Bindable var store: ShelfStore
    var isDropTargeted: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .frame(minWidth: 120, minHeight: 200)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isDropTargeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                              lineWidth: isDropTargeted ? 2 : 1)
        )
        .animation(.easeOut(duration: 0.12), value: isDropTargeted)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down.fill")
                .foregroundStyle(.secondary)
            Text(store.isEmpty ? "Yonk" : "\(store.items.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 0)
            Button {
                store.restoreLastRemoved()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .help("마지막으로 제거한 항목 되살리기")
            .disabled(!store.canRestore)
            Button {
                store.removeAll()
            } label: {
                Image(systemName: "trash")
            }
            .help("전체 비우기")
            .disabled(store.isEmpty)
        }
        .buttonStyle(.borderless)
        .imageScale(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(store.items) { item in
                    DraggableItemRow(
                        item: item,
                        onRemove: { store.remove($0) },
                        onExported: { store.remove($0) }
                    )
                    .frame(height: 44)
                }
            }
            .padding(6)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "arrow.down.to.line")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("파일을 여기에\n떨어뜨리세요")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ShelfView(store: ShelfStore(loadPersisted: false), isDropTargeted: false)
        .frame(width: 168, height: 360)
}
