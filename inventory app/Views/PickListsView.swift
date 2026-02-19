import SwiftUI

struct PickListsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lists: [PickList] = [
        PickList(name: "Front Counter", itemCount: 12, status: "Open"),
        PickList(name: "Kitchen Restock", itemCount: 8, status: "In Progress")
    ]

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    ForEach(lists) { list in
                        listCard(list)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Pick Lists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("New") { addList() }
            }
        }
        .tint(Theme.accent)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assign pick lists and track what gets pulled.")
                .font(Theme.font(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Create a list, add items, and mark progress as items are picked.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.44)
    }

    private func listCard(_ list: PickList) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(list.name)
                    .font(Theme.font(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(list.status)
                    .font(Theme.font(11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Theme.accentSoft.opacity(0.45))
                    )
                    .foregroundStyle(Theme.accentDeep)
            }
            Text("\(list.itemCount) items")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.26)
    }

    private func addList() {
        let newList = PickList(
            name: "New Pick List",
            itemCount: 0,
            status: "Draft"
        )
        lists.insert(newList, at: 0)
        Haptics.tap()
    }
}

private struct PickList: Identifiable {
    let id = UUID()
    let name: String
    let itemCount: Int
    let status: String
}
