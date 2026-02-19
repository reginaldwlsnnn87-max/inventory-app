import SwiftUI
import CoreData

struct QuickStockAdjustView: View {
    @EnvironmentObject private var dataController: InventoryDataController
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var platformStore: PlatformStore
    @Environment(\.dismiss) private var dismiss

    let item: InventoryItemEntity

    @State private var mode: AdjustMode = .stockIn
    @State private var amount: Double = 1
    @State private var reasonCode: InventoryAdjustmentReasonCode = .countCorrection
    @State private var reasonDetail = ""
    @State private var needsHighRiskConfirmation = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                VStack(spacing: 16) {
                    headerCard
                    modePicker
                    amountCard
                    reasonCard
                    applyButton
                }
                .padding(16)
            }
            .navigationTitle("Stock In / Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .tint(Theme.accent)
            .confirmationDialog(
                "Confirm high-risk adjustment?",
                isPresented: $needsHighRiskConfirmation,
                titleVisibility: .visible
            ) {
                Button("Apply Adjustment", role: .destructive) {
                    applyAdjustment(highRiskConfirmed: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This change exceeds the high-risk threshold (\(platformStore.highRiskAdjustmentThresholdUnits) units).")
            }
            .alert("Stock Adjustment", isPresented: .init(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK", role: .cancel) {
                    message = nil
                }
            } message: {
                Text(message ?? "")
            }
        }
        .onAppear {
            amount = item.isLiquid ? 0.5 : 1
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name)
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(onHandLabel)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.52)
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(AdjustMode.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.isLiquid ? "Gallons" : "Units")
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)

            if item.isLiquid {
                TextField(
                    "Gallons",
                    value: $amount,
                    format: .number.precision(.fractionLength(0...2))
                )
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .inventoryTextInputField()
            } else {
                Stepper(value: unitsBinding, in: 1...10_000) {
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text("\(Int(unitsBinding.wrappedValue))")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.26)
    }

    private var applyButton: some View {
        Button {
            handleApplyTapped()
        } label: {
            Text(mode == .stockIn ? "Apply Stock In" : "Apply Stock Out")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private var reasonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reason Code")
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)

            Picker("Reason", selection: $reasonCode) {
                ForEach(InventoryAdjustmentReasonCode.allCases) { code in
                    Text(code.rawValue).tag(code)
                }
            }
            .pickerStyle(.menu)

            TextField("", text: $reasonDetail, prompt: Theme.inputPrompt("Details (optional)"))
                .inventoryTextInputField(horizontalPadding: 10, verticalPadding: 10)
        }
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.26)
    }

    private var onHandUnits: Int64 {
        item.totalUnitsOnHand
    }

    private var onHandLabel: String {
        if item.isLiquid {
            return "On hand \(formattedGallons(item.totalGallonsOnHand)) gallons"
        }
        return "On hand \(onHandUnits) units"
    }

    private var unitsBinding: Binding<Int> {
        Binding(
            get: { Int(max(1, amount.rounded())) },
            set: { amount = Double(max(1, $0)) }
        )
    }

    private func handleApplyTapped() {
        guard amount > 0 else {
            message = "Enter an amount greater than zero."
            return
        }
        if platformStore.isHighRiskAdjustment(deltaUnits: proposedDeltaUnits) {
            needsHighRiskConfirmation = true
            return
        }
        applyAdjustment(highRiskConfirmed: false)
    }

    private var proposedDeltaUnits: Int64 {
        let signedAmount = mode == .stockIn ? amount : -amount
        if item.isLiquid {
            return Int64(signedAmount.rounded())
        }
        let roundedMagnitude = Int64(max(1, abs(signedAmount).rounded()))
        return signedAmount >= 0 ? roundedMagnitude : -roundedMagnitude
    }

    private func applyAdjustment(highRiskConfirmed: Bool) {
        let previousUnits = item.totalUnitsOnHand
        let delta = mode == .stockIn ? amount : -amount
        let reason = platformStore.adjustmentReasonSummary(reasonCode: reasonCode, detail: reasonDetail)
        if item.isLiquid {
            _ = platformStore.createGuardBackupIfNeeded(
                reason: "Manual adjustment",
                from: allItemsForBackup(),
                workspaceID: authStore.activeWorkspaceID,
                actorName: authStore.displayName,
                cooldownMinutes: 90
            )
            item.applyTotalGallons(item.totalGallonsOnHand + delta)
            item.assignWorkspaceIfNeeded(authStore.activeWorkspaceID)
            item.updatedAt = Date()
            dataController.save()
            let deltaUnits = item.totalUnitsOnHand - previousUnits
            guard deltaUnits != 0 else {
                message = "No net adjustment was applied."
                return
            }
            platformStore.recordInventoryMovement(
                item: item,
                deltaUnits: deltaUnits,
                actorName: authStore.displayName,
                workspaceID: authStore.activeWorkspaceID,
                type: .adjustment,
                source: "quick-stock-adjust",
                reason: reason
            )
        } else {
            let roundedMagnitude = Int64(max(1, abs(delta).rounded()))
            let roundedDelta = delta >= 0 ? roundedMagnitude : -roundedMagnitude
            let didApply = platformStore.applyAdjustment(
                item: item,
                deltaUnits: roundedDelta,
                reasonCode: reasonCode,
                reasonDetail: reasonDetail,
                highRiskConfirmed: highRiskConfirmed,
                actorName: authStore.displayName,
                workspaceID: authStore.activeWorkspaceID,
                dataController: dataController
            )
            guard didApply else {
                message = "High-risk adjustment confirmation is required."
                return
            }
        }
        Haptics.success()
        dismiss()
    }

    private func allItemsForBackup() -> [InventoryItemEntity] {
        let request: NSFetchRequest<InventoryItemEntity> = InventoryItemEntity.fetchRequest()
        return (try? dataController.container.viewContext.fetch(request)) ?? []
    }

    private func formattedGallons(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        var text = String(format: "%.2f", rounded)
        if text.contains(".") {
            text = text.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        }
        return text
    }
}

private enum AdjustMode: String, CaseIterable, Identifiable {
    case stockIn = "Stock In"
    case stockOut = "Stock Out"

    var id: String { rawValue }

    var label: String { rawValue }
}
