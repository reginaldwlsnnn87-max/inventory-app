import SwiftUI

struct ItemSelectionView: View {
    let title: String
    let items: [InventoryItemEntity]
    let onSelect: (InventoryItemEntity) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                List(items) { item in
                    Button {
                        onSelect(item)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(Theme.font(16, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            if !item.category.isEmpty {
                                Text(item.category)
                                    .font(Theme.font(12, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .padding(10)
                    .inventoryCard(cornerRadius: 14, emphasis: 0.2)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
    }
}
