import SwiftUI

struct QuickActionsView: View {
    let onAction: (QuickAction) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                ScrollView {
                    VStack(spacing: 16) {
                        sectionCard(
                            title: "Quick Quantity",
                            rows: [
                                ActionRowData(
                                    title: "Stock In / Out",
                                    subtitle: "Tap an item, then use the quick buttons",
                                    systemImage: "plusminus",
                                    action: { onAction(.stockInOut) }
                                ),
                                ActionRowData(
                                    title: "Set Amount",
                                    subtitle: "Choose an item and set its exact count",
                                    systemImage: "pencil",
                                    action: {
                                        onAction(.setAmount)
                                    }
                                )
                            ]
                        )

                        sectionCard(
                            title: "Quick Add",
                            rows: [
                                ActionRowData(
                                    title: "Add Item",
                                    subtitle: "Full item details",
                                    systemImage: "plus.circle",
                                    action: {
                                        onAction(.addItem)
                                    }
                                ),
                                ActionRowData(
                                    title: "Quick Add",
                                    subtitle: "Faster add with essentials",
                                    systemImage: "bolt.fill",
                                    action: {
                                        onAction(.quickAdd)
                                    }
                                )
                            ]
                        )

                        sectionCard(
                            title: "Smart Tools",
                            rows: [
                                ActionRowData(
                                    title: "Scan Barcode",
                                    subtitle: "Find or create items by barcode",
                                    systemImage: "barcode.viewfinder",
                                    action: {
                                        onAction(.barcodeScan)
                                    }
                                ),
                                ActionRowData(
                                    title: "Shelf Scan",
                                    subtitle: "Capture a shelf photo and confirm counts",
                                    systemImage: "camera.viewfinder",
                                    action: {
                                        onAction(.shelfScan)
                                    }
                                ),
                                ActionRowData(
                                    title: "Add Note",
                                    subtitle: "Attach a quick reminder to an item",
                                    systemImage: "note.text",
                                    action: {
                                        onAction(.addNote)
                                    }
                                )
                            ]
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Quick Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onAction(.close) }
                }
            }
            .tint(Theme.accent)
        }
    }

    private func sectionCard(title: String, rows: [ActionRowData]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    Button(action: row.action) {
                        actionRow(row)
                    }
                    .buttonStyle(.plain)

                    if row.id != rows.last?.id {
                        Divider()
                            .background(Theme.subtleBorder)
                            .padding(.leading, 44)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.cardBackground.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.subtleBorder, lineWidth: 1)
            )
        }
    }

    private func actionRow(_ row: ActionRowData) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(Theme.font(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(row.subtitle)
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

private struct ActionRowData: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void
}

enum QuickAction {
    case stockInOut
    case setAmount
    case addItem
    case quickAdd
    case shelfScan
    case barcodeScan
    case addNote
    case close
}
