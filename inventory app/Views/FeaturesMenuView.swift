import SwiftUI

struct FeaturesMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                        ForEach(features) { feature in
                            featureCard(feature)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Features")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .tint(Theme.accent)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Simple and fast inventory.")
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Tap any feature below for a quick reminder on how to use it.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func featureCard(_ feature: FeatureInfo) -> some View {
        let isOpen = expanded == feature.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(feature.title)
                    .font(Theme.font(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(feature.summary)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if isOpen {
                Text(feature.howTo)
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                expanded = isOpen ? nil : feature.id
            }
        }
    }
}

private struct FeatureInfo: Identifiable {
    let id: String
    let title: String
    let summary: String
    let howTo: String
}

private let features: [FeatureInfo] = [
    FeatureInfo(
        id: "shelf-scan",
        title: "Shelf Scan",
        summary: "Snap a shelf photo, let the app detect labels, then confirm counts.",
        howTo: "Tap the camera icon, take a clear photo, then review the detected items. Tap any item to adjust counts and press Apply Counts."
    ),
    FeatureInfo(
        id: "quick-add",
        title: "Quick Add",
        summary: "Add an item fast with basic counts when you're in a hurry.",
        howTo: "Tap the bolt icon, fill in the essentials, and press Save. You can refine details later."
    ),
    FeatureInfo(
        id: "smart-reorder",
        title: "Smart Reorder",
        summary: "Set daily usage, lead time, and safety stock to see reorder suggestions.",
        howTo: "Edit an item, enter usage, lead time, and safety stock under Reorder, then check the item row for the reorder target."
    ),
    FeatureInfo(
        id: "barcode-scan",
        title: "Barcode Scan",
        summary: "Scan a barcode to find an item or create a new one.",
        howTo: "Tap the barcode icon or Quick Actions → Scan Barcode. If it matches, the item opens; if not, a new item is started."
    ),
    FeatureInfo(
        id: "workflows",
        title: "Workflows",
        summary: "Run guided flows for stock counts, pick lists, and purchase orders.",
        howTo: "Open the Menu, tap Workflows, and choose the flow you need."
    ),
    FeatureInfo(
        id: "stock-counts",
        title: "Stock Counts",
        summary: "Count every item quickly and apply updates in one tap.",
        howTo: "In Workflows, open Stock Counts, adjust counts, then tap Apply Counts."
    ),
    FeatureInfo(
        id: "pick-lists",
        title: "Pick Lists",
        summary: "Create lists for items that need to be pulled.",
        howTo: "In Workflows, open Pick Lists and tap New to start a list."
    ),
    FeatureInfo(
        id: "purchase-orders",
        title: "Purchase Orders",
        summary: "Create and receive purchase orders to keep stock aligned.",
        howTo: "In Workflows, open Purchase Orders to add items or receive deliveries."
    ),
    FeatureInfo(
        id: "shift-modes",
        title: "Shift Modes",
        summary: "Open/Mid/Close sorts items to fit your shift workflow.",
        howTo: "Use the Shift control at the top to switch between Open, Mid, or Close sorting styles."
    ),
    FeatureInfo(
        id: "pin-items",
        title: "Pin Items",
        summary: "Pin high-priority items so they stay on top.",
        howTo: "Swipe an item from the left and tap Pin. Pinned items stay at the top of the list."
    ),
    FeatureInfo(
        id: "set-amount",
        title: "Set Amount",
        summary: "Swipe an item and set its exact count.",
        howTo: "Swipe an item to reveal Set, enter the exact count, and confirm."
    ),
    FeatureInfo(
        id: "notes",
        title: "Notes",
        summary: "Swipe an item to add notes for reminders or usage tips.",
        howTo: "Swipe an item, tap Note, type your reminder, and save."
    ),
    FeatureInfo(
        id: "search-filter",
        title: "Search + Filters",
        summary: "Search by name and filter by category to find items fast.",
        howTo: "Use the search bar for names, or tap the filter icon to select a category."
    ),
    FeatureInfo(
        id: "quick-actions",
        title: "Quick Actions",
        summary: "Open a single sheet to jump into common tasks.",
        howTo: "Tap the ellipsis button in the toolbar to open Quick Actions."
    ),
    FeatureInfo(
        id: "menu",
        title: "Menu",
        summary: "Access workflows, labels, reports, and account tools.",
        howTo: "Tap the Menu icon in the toolbar and choose a section."
    )
]
