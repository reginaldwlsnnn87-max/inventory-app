import SwiftUI
import CoreData

struct PurchaseOrderAddItemsView: View {
    @EnvironmentObject private var purchaseOrderStore: PurchaseOrderStore
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.name, ascending: true)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var selections: Set<UUID> = []

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    ForEach(workspaceItems) { item in
                        selectionRow(for: item)
                    }
                    applyButton
                }
                .padding(16)
            }
        }
        .navigationTitle("Add Items")
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

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select items to add to a new purchase order.")
                .font(Theme.font(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Suggested quantities use lead time demand plus supplier rules (MOQ and case pack increments).")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.44)
    }

    private func selectionRow(for item: InventoryItemEntity) -> some View {
        let isSelected = selections.contains(item.id)
        return Button {
            if isSelected {
                selections.remove(item.id)
            } else {
                selections.insert(item.id)
            }
        } label: {
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
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
            }
            .padding(16)
            .inventoryCard(cornerRadius: 16, emphasis: isSelected ? 0.62 : 0.2)
        }
        .buttonStyle(.plain)
    }

    private var applyButton: some View {
        Button {
            createDraftOrder()
        } label: {
            Text("Create Draft Order (\(selections.count) items)")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(selections.isEmpty || !authStore.canManagePurchasing)
    }

    private func createDraftOrder() {
        guard authStore.canManagePurchasing else { return }
        let selected = workspaceItems.filter { selections.contains($0.id) }
        guard !selected.isEmpty else { return }

        let lines = selected.map { item in
            let preferredSupplier = item.normalizedPreferredSupplier
            let supplierSKU = item.normalizedSupplierSKU
            return PurchaseOrderLine(
                itemID: item.id,
                itemName: item.name,
                category: item.category,
                suggestedUnits: suggestedUnits(for: item),
                reorderPoint: reorderPoint(for: item),
                onHandUnits: item.totalUnitsOnHand,
                leadTimeDays: item.leadTimeDays,
                forecastDailyDemand: max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0),
                preferredSupplier: preferredSupplier.isEmpty ? nil : preferredSupplier,
                supplierSKU: supplierSKU.isEmpty ? nil : supplierSKU,
                minimumOrderQuantity: item.minimumOrderQuantity > 0 ? item.minimumOrderQuantity : nil,
                reorderCasePack: item.reorderCasePack > 0 ? item.reorderCasePack : nil,
                leadTimeVarianceDays: item.leadTimeVarianceDays > 0 ? item.leadTimeVarianceDays : nil
            )
        }

        _ = purchaseOrderStore.createDraftsGroupedBySupplier(
            lines: lines,
            workspaceID: authStore.activeWorkspaceID,
            source: "manual selection",
            notes: "Created from Add Items on \(Date().formatted(date: .abbreviated, time: .shortened))."
        )
        Haptics.success()
        dismiss()
    }

    private var workspaceItems: [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(authStore.activeWorkspaceID) }
    }

    private func reorderPoint(for item: InventoryItemEntity) -> Int64 {
        let demand = max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0)
        let lead = max(0, Double(item.leadTimeDays))
        guard demand > 0, lead > 0 else { return max(1, item.safetyStockUnits) }
        let demandDuringLead = Int64((demand * lead).rounded(.up))
        return max(1, demandDuringLead + max(0, item.safetyStockUnits))
    }

    private func suggestedUnits(for item: InventoryItemEntity) -> Int64 {
        let reorder = reorderPoint(for: item)
        let baseUnits = max(1, reorder - max(0, item.totalUnitsOnHand))
        return item.adjustedSuggestedOrderUnits(from: baseUnits)
    }
}
