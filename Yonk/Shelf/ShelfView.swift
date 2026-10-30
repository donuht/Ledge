import SwiftUI

/// 선반 내용: 헤더(되살리기·전체 비우기), 항목 목록 또는 빈 상태.
/// 왼쪽·오른쪽 가장자리는 세로 목록, 위·아래는 가로 카드 목록.
struct ShelfView: View {
    @Bindable var store: ShelfStore
    var edge: ShelfEdge
    var isDropTargeted: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.isEmpty {
                emptyState
            } else if edge.isVertical {
                verticalList
            } else {
                horizontalList
            }
        }
        .frame(minWidth: 120, minHeight: 100)
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
            .help("전체 비우기 (잠긴 항목 제외)")
            .disabled(!store.hasUnlocked)
        }
        .buttonStyle(.borderless)
        .imageScale(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var verticalList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(store.items) { item in
                    DraggableItemRow(
                        item: item,
                        style: .row,
                        store: store,
                        isSelected: store.selectedIDs.contains(item.id)
                    )
                    .frame(height: DraggableItemView.rowHeight)
                }
            }
            .padding(6)
        }
    }

    private var horizontalList: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 2) {
                ForEach(store.items) { item in
                    DraggableItemRow(
                        item: item,
                        style: .card,
                        store: store,
                        isSelected: store.selectedIDs.contains(item.id)
                    )
                    .frame(width: DraggableItemView.cardSize.width, height: DraggableItemView.cardSize.height)
                }
            }
            .padding(6)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            Image(systemName: "arrow.down.to.line")
                .font(edge.isVertical ? .title2 : .body)
                .foregroundStyle(.tertiary)
            Text(edge.isVertical ? "파일을 여기에\n떨어뜨리세요" : "파일을 여기에 떨어뜨리세요")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("세로") {
    ShelfView(store: ShelfStore(loadPersisted: false), edge: .left, isDropTargeted: false)
        .frame(width: 168, height: 360)
}

#Preview("가로") {
    ShelfView(store: ShelfStore(loadPersisted: false), edge: .bottom, isDropTargeted: false)
        .frame(width: 440, height: 124)
}
