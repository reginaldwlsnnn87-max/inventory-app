import SwiftUI
import CoreData

struct PurchaseOrderReceiveItemsView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var dataController: InventoryDataController
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.name, ascending: true)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var received: [UUID: Int] = [:]
    @State private var hasSeeded = false

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    ForEach(items) { item in
                        receiveRow(for: item)
                    }
                    applyButton
                }
                .padding(16)
            }
        }
        .navigationTitle("Receive Items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .tint(Theme.accent)
        .onAppear { seedIfNeeded() }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log deliveries and update inventory.")
                .font(Theme.font(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Enter received quantities and apply to inventory.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func receiveRow(for item: InventoryItemEntity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(Theme.font(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(item.category.isEmpty ? "Uncategorized" : item.category)
                        .font(Theme.font(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("On hand \(totalUnitsLabel(for: item))")
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            TextField("Received units", value: binding(for: item), format: .number)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .textFieldStyle(.roundedBorder)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private var applyButton: some View {
        Button {
            applyReceipts()
        } label: {
            Text("Apply Receipts")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(items.isEmpty)
    }

    private func seedIfNeeded() {
        guard !hasSeeded else { return }
        hasSeeded = true
        var seed: [UUID: Int] = [:]
        for item in items {
            seed[item.id] = 0
        }
        received = seed
    }

    private func binding(for item: InventoryItemEntity) -> Binding<Int> {
        Binding(
            get: { received[item.id] ?? 0 },
            set: { received[item.id] = max(0, $0) }
        )
    }

    private func totalUnitsLabel(for item: InventoryItemEntity) -> String {
        if item.isLiquid {
            let gallons = Double(item.looseUnits) + item.gallonFraction
            let rounded = (gallons * 100).rounded() / 100
            return "\(rounded) gal"
        }
        let units = item.unitsPerCase > 0
            ? item.quantity * item.unitsPerCase + item.looseUnits
            : item.quantity
        return "\(units) units"
    }

    private func applyReceipts() {
        let now = Date()
        for item in items {
            guard let added = received[item.id], added > 0 else { continue }
            if item.unitsPerCase > 0 {
                let totalUnits = item.quantity * item.unitsPerCase + item.looseUnits + Int64(added)
                item.quantity = totalUnits / item.unitsPerCase
                item.looseUnits = totalUnits % item.unitsPerCase
            } else {
                item.quantity += Int64(added)
            }
            item.updatedAt = now
        }
        dataController.save()
        Haptics.success()
        dismiss()
    }
}
