import SwiftUI

/// 선반 내용. P0에서는 빈 상태만 보여준다.
struct ShelfView: View {
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            emptyState
        }
        .frame(minWidth: 120, minHeight: 200)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Image(systemName: "tray.and.arrow.down.fill")
                .foregroundStyle(.secondary)
            Text("Yonk")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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
    ShelfView()
        .frame(width: 168, height: 360)
}
