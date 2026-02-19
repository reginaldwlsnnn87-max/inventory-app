import SwiftUI
import CoreData

struct OpsIntelligenceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var dataController: InventoryDataController
    @EnvironmentObject private var platformStore: PlatformStore
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.name, ascending: true)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var returnItemID: UUID?
    @State private var adjustmentItemID: UUID?
    @State private var returnUnits = 1
    @State private var returnReason = ""
    @State private var adjustmentDelta = 0
    @State private var adjustmentReasonCode: InventoryAdjustmentReasonCode = .countCorrection
    @State private var adjustmentReasonDetail = ""
    @State private var isShowingReceiveFlow = false
    @State private var isConfirmingHighRiskAdjustment = false
    @State private var message: String?

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    receiveCard
                    returnsCard
                    adjustmentsCard
                    ownerReportCard
                }
                .padding(16)
            }
        }
        .navigationTitle("Ops Intelligence")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .tint(Theme.accent)
        .sheet(isPresented: $isShowingReceiveFlow) {
            NavigationStack {
                PurchaseOrderReceiveItemsView()
            }
        }
        .confirmationDialog(
            "Confirm high-risk adjustment?",
            isPresented: $isConfirmingHighRiskAdjustment,
            titleVisibility: .visible
        ) {
            Button("Apply Adjustment", role: .destructive) {
                performAdjustment(highRiskConfirmed: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This change exceeds the high-risk threshold (\(platformStore.highRiskAdjustmentThresholdUnits) units).")
        }
        .onAppear {
            seedSelectionsIfNeeded()
        }
        .onChange(of: workspaceItems.count) { _, _ in
            seedSelectionsIfNeeded()
        }
        .alert("Operations", isPresented: .init(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var workspaceItems: [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(authStore.activeWorkspaceID) }
    }

    private var returnItem: InventoryItemEntity? {
        guard let returnItemID else { return workspaceItems.first }
        return workspaceItems.first(where: { $0.id == returnItemID })
    }

    private var adjustmentItem: InventoryItemEntity? {
        guard let adjustmentItemID else { return workspaceItems.first }
        return workspaceItems.first(where: { $0.id == adjustmentItemID })
    }

    private var report: OwnerImpactReport {
        platformStore.ownerImpactReport(
            for: Array(items),
            workspaceID: authStore.activeWorkspaceID,
            windowDays: 30
        )
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run receiving, returns, and adjustments with measurable owner-level outcomes.")
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("This closes the loop between operations and profitability by logging every high-impact move.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.56)
    }

    private var receiveCard: some View {
        sectionCard(title: "Receiving Workflow") {
            Text("Use the receive flow to post deliveries quickly. Every received line updates inventory and audit history.")
                .font(Theme.font(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Open Receive Items") {
                isShowingReceiveFlow = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(!authStore.canManageCatalog)
            .opacity(authStore.canManageCatalog ? 1 : 0.55)
        }
    }

    private var returnsCard: some View {
        sectionCard(title: "Returns") {
            if workspaceItems.isEmpty {
                Text("No items available.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("Item", selection: Binding(
                    get: { returnItemID ?? workspaceItems.first?.id ?? UUID() },
                    set: { returnItemID = $0 }
                )) {
                    ForEach(workspaceItems) { item in
                        Text(item.name).tag(item.id)
                    }
                }
                .pickerStyle(.menu)

                Stepper("Units: \(returnUnits)", value: $returnUnits, in: 1...500)

                TextField(
                    "",
                    text: $returnReason,
                    prompt: Theme.inputPrompt("Reason (damaged, expired, vendor defect...)")
                )
                    .inventoryTextInputField(horizontalPadding: 10, verticalPadding: 10)

                Button("Apply Return") {
                    applyReturn()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!authStore.canManageCatalog)
                .opacity(authStore.canManageCatalog ? 1 : 0.55)
            }
        }
    }

    private var adjustmentsCard: some View {
        sectionCard(title: "Adjustments") {
            if workspaceItems.isEmpty {
                Text("No items available.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("Item", selection: Binding(
                    get: { adjustmentItemID ?? workspaceItems.first?.id ?? UUID() },
                    set: { adjustmentItemID = $0 }
                )) {
                    ForEach(workspaceItems) { item in
                        Text(item.name).tag(item.id)
                    }
                }
                .pickerStyle(.menu)

                Stepper("Delta: \(adjustmentDelta)", value: $adjustmentDelta, in: -500...500)

                Picker("Reason Code", selection: $adjustmentReasonCode) {
                    ForEach(InventoryAdjustmentReasonCode.allCases) { code in
                        Text(code.rawValue).tag(code)
                    }
                }
                .pickerStyle(.menu)

                TextField("", text: $adjustmentReasonDetail, prompt: Theme.inputPrompt("Details (optional)"))
                    .inventoryTextInputField(horizontalPadding: 10, verticalPadding: 10)

                Button("Apply Adjustment") {
                    applyAdjustment()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!authStore.canManageCatalog || adjustmentDelta == 0)
                .opacity(authStore.canManageCatalog ? 1 : 0.55)
            }
        }
    }

    @ViewBuilder
    private var ownerReportCard: some View {
        sectionCard(title: "Owner Impact (30 Days)") {
            if !authStore.canManageWorkspace {
                Text("Owner-level impact reporting is visible to workspace owners.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                metricRow("Total logged actions", "\(report.totalEvents)")
                metricRow("Units received", "\(report.unitsReceived)")
                metricRow("Units returned", "\(report.unitsReturned)")
                metricRow("Net adjustments", "\(report.netAdjustments)")
                metricRow("Estimated labor time saved", "\(report.estimatedMinutesSaved) min")
                metricRow("Shrink impact addressed", "\(report.shrinkPreventedUnits) units")
                metricRow("Current stockout risk rate", "\(Int((report.shrinkRiskRate * 100).rounded()))%")
            }
        }
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.font(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 2)

            VStack(spacing: 10) {
                content()
            }
            .padding(12)
            .inventoryCard(cornerRadius: 14, emphasis: 0.24)
        }
        .padding(14)
        .inventoryCard(cornerRadius: 16, emphasis: 0.44)
    }

    private func seedSelectionsIfNeeded() {
        if returnItemID == nil {
            returnItemID = workspaceItems.first?.id
        }
        if adjustmentItemID == nil {
            adjustmentItemID = workspaceItems.first?.id
        }
    }

    private func applyReturn() {
        guard authStore.canManageCatalog else {
            message = "Only owners and managers can process returns."
            return
        }
        guard let item = returnItem else {
            message = "Select an item first."
            return
        }
        let reason = returnReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else {
            message = "Enter a return reason."
            return
        }
        let didApply = platformStore.applyReturn(
            item: item,
            units: Int64(returnUnits),
            reason: reason,
            actorName: authStore.displayName,
            workspaceID: authStore.activeWorkspaceID,
            dataController: dataController
        )
        if didApply {
            returnUnits = 1
            returnReason = ""
            Haptics.success()
            message = "Return posted."
        }
    }

    private func applyAdjustment() {
        guard authStore.canManageCatalog else {
            message = "Only owners and managers can apply adjustments."
            return
        }
        guard adjustmentItem != nil else {
            message = "Select an item first."
            return
        }
        guard adjustmentDelta != 0 else {
            message = "Adjustment delta must be non-zero."
            return
        }
        let detail = adjustmentReasonDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        if adjustmentReasonCode == .other && detail.isEmpty {
            message = "Add details when reason code is Other."
            return
        }
        if platformStore.isHighRiskAdjustment(deltaUnits: Int64(adjustmentDelta)) {
            isConfirmingHighRiskAdjustment = true
            return
        }
        performAdjustment(highRiskConfirmed: false)
    }

    private func performAdjustment(highRiskConfirmed: Bool) {
        guard let item = adjustmentItem else {
            message = "Select an item first."
            return
        }
        guard adjustmentDelta != 0 else {
            message = "Adjustment delta must be non-zero."
            return
        }
        let didApply = platformStore.applyAdjustment(
            item: item,
            deltaUnits: Int64(adjustmentDelta),
            reasonCode: adjustmentReasonCode,
            reasonDetail: adjustmentReasonDetail,
            highRiskConfirmed: highRiskConfirmed,
            actorName: authStore.displayName,
            workspaceID: authStore.activeWorkspaceID,
            dataController: dataController
        )
        if didApply {
            adjustmentDelta = 0
            adjustmentReasonCode = .countCorrection
            adjustmentReasonDetail = ""
            Haptics.success()
            message = "Adjustment posted."
        } else {
            message = "High-risk adjustment confirmation is required."
        }
    }
}
