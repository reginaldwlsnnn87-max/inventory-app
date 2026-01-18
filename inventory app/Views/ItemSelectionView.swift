import SwiftUI

struct ItemSelectionView: View {
    let title: String
    let items: [InventoryItemEntity]
    let onSelect: (InventoryItemEntity) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button {
                    onSelect(item)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        if !item.category.isEmpty {
                            Text(item.category)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
