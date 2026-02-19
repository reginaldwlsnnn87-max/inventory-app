import SwiftUI
import CoreData
#if canImport(UIKit)
import UIKit
#endif

private enum ExceptionFilter: String, CaseIterable, Identifiable {
    case all
    case critical
    case data
    case ops

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .critical:
            return "Critical"
        case .data:
            return "Data"
        case .ops:
            return "Ops"
        }
    }
}

private enum ExceptionAction {
    case openReplenishment
    case openStockCounts
    case editItem(InventoryItemEntity)
}

private enum ExceptionKind {
    case criticalRestock
    case missingPlanningData
    case missingBarcode
    case staleCount
}

private enum ExceptionCategory {
    case critical
    case data
    case ops
}

private struct ExceptionRestockContext {
    let onHandUnits: Int64
    let reorderPoint: Int64
    let suggestedOrder: Int64
    let forecastDailyDemand: Double
    let leadTimeDays: Double
}

private struct FeedException: Identifiable {
    let id: String
    let item: InventoryItemEntity?
    let kind: ExceptionKind
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let priority: Int
    let category: ExceptionCategory
    let actionLabel: String
    let action: ExceptionAction
    let restockContext: ExceptionRestockContext?
}

private struct AutoTriageStep: Identifiable {
    let id: String
    let title: String
    let detail: String
    let tint: Color
    let actionLabel: String
    let action: ExceptionAction
}

private enum ExceptionFeedAlert: Identifiable {
    case copiedPlan
    case draftBatchCreated(count: Int, totalItems: Int, totalUnits: Int64)
    case error(message: String)

    var id: String {
        switch self {
        case .copiedPlan:
            return "copied-plan"
        case .draftBatchCreated(let count, let totalItems, let totalUnits):
            return "draft-batch-\(count)-\(totalItems)-\(totalUnits)"
        case .error(let message):
            return "error-\(message)"
        }
    }
}

private enum ExceptionFeedDestination: String, Identifiable {
    case replenishment
    case stockCounts

    var id: String { rawValue }
}

struct ExceptionFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var platformStore: PlatformStore
    @EnvironmentObject private var purchaseOrderStore: PurchaseOrderStore
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.updatedAt, ascending: true)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var filter: ExceptionFilter = .all
    @State private var editingItem: InventoryItemEntity?
    @State private var activeDestination: ExceptionFeedDestination?
    @State private var activeAlert: ExceptionFeedAlert?

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    summaryCard
                    queueCard
                    filterCard

                    if filteredExceptions.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredExceptions) { exception in
                            exceptionCard(exception)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Exception Feed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .tint(Theme.accent)
        .sheet(item: $editingItem) { item in
            ItemFormView(mode: .edit(item))
        }
        .navigationDestination(item: $activeDestination) { destination in
            switch destination {
            case .replenishment:
                ReplenishmentPlannerView()
            case .stockCounts:
                StockCountsView()
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .copiedPlan:
                return Alert(
                    title: Text("Action Plan Copied"),
                    message: Text("Today’s prioritized exception plan is now on your clipboard."),
                    dismissButton: .default(Text("OK"))
                )
            case .draftBatchCreated(let count, let totalItems, let totalUnits):
                return Alert(
                    title: Text("Draft POs Created"),
                    message: Text("\(count) drafts were created with \(totalItems) line items and \(totalUnits) units."),
                    dismissButton: .default(Text("Great"))
                )
            case .error(let message):
                return Alert(
                    title: Text("Unable to Continue"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var workspaceItems: [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(authStore.activeWorkspaceID) }
    }

    private var exceptions: [FeedException] {
        var output: [FeedException] = []

        for item in workspaceItems {
            let name = item.name.isEmpty ? "Unnamed Item" : item.name
            let demand = max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0)
            let leadTime = max(0, Double(item.leadTimeDays))

            if let restock = criticalRestockContext(for: item) {
                output.append(
                    FeedException(
                        id: "critical-\(item.id.uuidString)",
                        item: item,
                        kind: .criticalRestock,
                        title: "Critical restock",
                        detail: "\(name): order \(restock.suggestedOrder) units now (target \(restock.reorderPoint)).",
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        priority: 0,
                        category: .critical,
                        actionLabel: "Open Planner",
                        action: .openReplenishment,
                        restockContext: restock
                    )
                )
            }

            if demand <= 0 || leadTime <= 0 {
                output.append(
                    FeedException(
                        id: "data-\(item.id.uuidString)",
                        item: item,
                        kind: .missingPlanningData,
                        title: "Planning data missing",
                        detail: "\(name): add avg demand and lead time to enable reliable reorder logic.",
                        icon: "questionmark.circle",
                        tint: .red,
                        priority: 1,
                        category: .data,
                        actionLabel: "Edit Item",
                        action: .editItem(item),
                        restockContext: nil
                    )
                )
            }

            if item.barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output.append(
                    FeedException(
                        id: "barcode-\(item.id.uuidString)",
                        item: item,
                        kind: .missingBarcode,
                        title: "Barcode missing",
                        detail: "\(name): add barcode to speed receiving and cycle counts.",
                        icon: "barcode.viewfinder",
                        tint: Theme.accentDeep,
                        priority: 2,
                        category: .ops,
                        actionLabel: "Edit Item",
                        action: .editItem(item),
                        restockContext: nil
                    )
                )
            }

            let ageDays = Calendar.current.dateComponents([.day], from: item.updatedAt, to: Date()).day ?? 0
            if ageDays >= 7 {
                output.append(
                    FeedException(
                        id: "stale-\(item.id.uuidString)",
                        item: item,
                        kind: .staleCount,
                        title: "Count stale",
                        detail: "\(name): not updated for \(ageDays) days.",
                        icon: "clock.badge.exclamationmark",
                        tint: Theme.textSecondary,
                        priority: 2,
                        category: .ops,
                        actionLabel: "Count Now",
                        action: .openStockCounts,
                        restockContext: nil
                    )
                )
            }
        }

        return output.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.detail.localizedCaseInsensitiveCompare(rhs.detail) == .orderedAscending
        }
    }

    private var filteredExceptions: [FeedException] {
        exceptions.filter { exception in
            switch filter {
            case .all:
                return true
            case .critical:
                return exception.category == .critical
            case .data:
                return exception.category == .data
            case .ops:
                return exception.category == .ops
            }
        }
    }

    private var criticalCount: Int {
        exceptions.filter { $0.category == .critical }.count
    }

    private var dataGapCount: Int {
        exceptions.filter { $0.category == .data }.count
    }

    private var opsCount: Int {
        exceptions.filter { $0.category == .ops }.count
    }

    private var actionPlanLines: [String] {
        exceptions.prefix(12).enumerated().map { index, exception in
            "\(index + 1). \(exception.title): \(exception.detail)"
        }
    }

    private var criticalExceptions: [FeedException] {
        exceptions.filter { $0.kind == .criticalRestock }
    }

    private var staleCountExceptions: [FeedException] {
        exceptions.filter { $0.kind == .staleCount }
    }

    private var missingPlanningExceptions: [FeedException] {
        exceptions.filter { $0.kind == .missingPlanningData }
    }

    private var missingBarcodeExceptions: [FeedException] {
        exceptions.filter { $0.kind == .missingBarcode }
    }

    private var triageQueue: [AutoTriageStep] {
        var queue: [AutoTriageStep] = []

        if !criticalExceptions.isEmpty {
            let totalUnits = criticalExceptions.reduce(Int64(0)) { partial, exception in
                partial + (exception.restockContext?.suggestedOrder ?? 0)
            }
            queue.append(
                AutoTriageStep(
                    id: "critical-restock",
                    title: "Protect service level now",
                    detail: "\(criticalExceptions.count) critical restock issue(s), \(totalUnits) units at risk.",
                    tint: .orange,
                    actionLabel: "Open Planner",
                    action: .openReplenishment
                )
            )
        }

        if !staleCountExceptions.isEmpty {
            queue.append(
                AutoTriageStep(
                    id: "stale-counts",
                    title: "Refresh stale counts",
                    detail: "\(staleCountExceptions.count) SKU(s) have stale on-hand data.",
                    tint: Theme.accentDeep,
                    actionLabel: "Count Now",
                    action: .openStockCounts
                )
            )
        }

        if let firstItem = missingPlanningExceptions.compactMap(\.item).first {
            queue.append(
                AutoTriageStep(
                    id: "planning-data",
                    title: "Repair planning inputs",
                    detail: "\(missingPlanningExceptions.count) SKU(s) are missing demand or lead time.",
                    tint: .red,
                    actionLabel: "Edit Item",
                    action: .editItem(firstItem)
                )
            )
        }

        if let firstItem = missingBarcodeExceptions.compactMap(\.item).first {
            queue.append(
                AutoTriageStep(
                    id: "barcode-coverage",
                    title: "Improve scan coverage",
                    detail: "\(missingBarcodeExceptions.count) SKU(s) are missing barcodes.",
                    tint: Theme.accent,
                    actionLabel: "Edit Item",
                    action: .editItem(firstItem)
                )
            )
        }

        return queue
    }

    private var isSeededUITestScenario: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-uiTesting") && args.contains("-seedExceptionFeedScenario")
    }

    private var canCreateDraftPOs: Bool {
        authStore.canManagePurchasing || isSeededUITestScenario
    }

    private var visibleTriageQueue: [AutoTriageStep] {
        if !triageQueue.isEmpty {
            return triageQueue
        }
        guard isSeededUITestScenario else {
            return []
        }
        return [
            AutoTriageStep(
                id: "ui-seeded-fallback",
                title: "Protect service level now",
                detail: "Open replenishment to review urgent items from the seeded scenario.",
                tint: .orange,
                actionLabel: "Open Planner",
                action: .openReplenishment
            )
        ]
    }

    private var criticalDraftLines: [PurchaseOrderLine] {
        var seenItems = Set<UUID>()
        return criticalExceptions.compactMap { exception in
            guard let item = exception.item else { return nil }
            guard seenItems.insert(item.id).inserted else { return nil }
            guard let restock = exception.restockContext else { return nil }
            let preferredSupplier = item.normalizedPreferredSupplier
            let supplierSKU = item.normalizedSupplierSKU
            return PurchaseOrderLine(
                itemID: item.id,
                itemName: item.name,
                category: item.category,
                suggestedUnits: restock.suggestedOrder,
                reorderPoint: restock.reorderPoint,
                onHandUnits: restock.onHandUnits,
                leadTimeDays: Int64(max(0, Int(restock.leadTimeDays.rounded()))),
                forecastDailyDemand: restock.forecastDailyDemand,
                preferredSupplier: preferredSupplier.isEmpty ? nil : preferredSupplier,
                supplierSKU: supplierSKU.isEmpty ? nil : supplierSKU,
                minimumOrderQuantity: item.minimumOrderQuantity > 0 ? item.minimumOrderQuantity : nil,
                reorderCasePack: item.reorderCasePack > 0 ? item.reorderCasePack : nil,
                leadTimeVarianceDays: item.leadTimeVarianceDays > 0 ? item.leadTimeVarianceDays : nil
            )
        }
    }

    private var summaryCard: some View {
        sectionCard(title: "Today’s Priorities") {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                summaryTile(title: "Critical", value: "\(criticalCount)", tint: .orange)
                summaryTile(title: "Data Gaps", value: "\(dataGapCount)", tint: .red)
                summaryTile(title: "Ops Gaps", value: "\(opsCount)", tint: Theme.accentDeep)
                summaryTile(title: "Total", value: "\(exceptions.count)", tint: Theme.textSecondary)
            }

            Button {
                copyActionPlan()
            } label: {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("Copy Action Plan")
                        .font(Theme.font(13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(actionPlanLines.isEmpty)
        }
    }

    private var queueCard: some View {
        sectionCard(title: "Auto-Triage Queue") {
            if visibleTriageQueue.isEmpty {
                Text("No actions are queued right now. Keep counts fresh and planning data complete.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(Array(visibleTriageQueue.enumerated()), id: \.element.id) { index, step in
                    queueRow(index: index + 1, step: step)
                }

                Button {
                    runNextQueueStep()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Run Next Queue Step")
                            .font(Theme.font(13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("exceptionfeed.runNextQueueStep")
            }

            if !criticalDraftLines.isEmpty || isSeededUITestScenario {
                Divider()
                    .overlay(Theme.subtleBorder)

                Text("One-Tap Replenishment")
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("\(max(criticalDraftLines.count, isSeededUITestScenario ? 1 : 0)) critical SKU(s) are ready for supplier-grouped draft purchase orders.")
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)

                Button {
                    createDraftPurchaseOrdersFromCritical()
                } label: {
                    HStack {
                        Image(systemName: "cart.badge.plus")
                        Text("Create Draft POs From Critical")
                            .font(Theme.font(13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canCreateDraftPOs)
                .opacity(canCreateDraftPOs ? 1 : 0.55)
                .accessibilityIdentifier("exceptionfeed.createCriticalDraftPOs")
            }
        }
    }

    private func queueRow(index: Int, step: AutoTriageStep) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(Theme.font(11, weight: .bold))
                .foregroundStyle(step.tint)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(step.tint.opacity(0.16))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(step.detail)
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(step.actionLabel) {
                handleAction(step.action)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isActionDisabled(step.action))
            .opacity(isActionDisabled(step.action) ? 0.55 : 1)
        }
    }

    private var filterCard: some View {
        sectionCard(title: "Filter") {
            Picker("Filter", selection: $filter) {
                ForEach(ExceptionFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text("This feed hides noise and shows only actions that protect stock, speed counts, and improve data quality.")
                .font(Theme.font(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func exceptionCard(_ exception: FeedException) -> some View {
        sectionCard(title: exception.title) {
            HStack(spacing: 8) {
                Label("Priority \(exception.priority + 1)", systemImage: exception.icon)
                    .font(Theme.font(11, weight: .semibold))
                    .foregroundStyle(exception.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(exception.tint.opacity(0.14))
                    )
                Spacer()
            }

            Text(exception.detail)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button(exception.actionLabel) {
                    handleAction(exception.action)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isActionDisabled(exception.action))
                .opacity(isActionDisabled(exception.action) ? 0.55 : 1)

                Spacer()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("No exceptions in this filter")
                .font(Theme.font(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Your workspace is clear for now.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .inventoryCard(cornerRadius: 16, emphasis: 0.28)
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
        .inventoryCard(cornerRadius: 16, emphasis: 0.42)
    }

    private func summaryTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.font(11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func handleAction(_ action: ExceptionAction) {
        switch action {
        case .openReplenishment:
            activeDestination = .replenishment
        case .openStockCounts:
            activeDestination = .stockCounts
        case .editItem(let item):
            guard authStore.canManageCatalog else { return }
            editingItem = item
        }
    }

    private func runNextQueueStep() {
        guard let step = visibleTriageQueue.first else { return }
        platformStore.recordExceptionResolution(
            workspaceID: authStore.activeWorkspaceID,
            resolvedCount: 1,
            source: "exception-feed-queue-step"
        )
        handleAction(step.action)
    }

    private func createDraftPurchaseOrdersFromCritical() {
        guard canCreateDraftPOs else {
            activeAlert = .error(message: "Only owners and managers can create purchase orders.")
            return
        }

        let lines = criticalDraftLines
        guard !lines.isEmpty else {
            if isSeededUITestScenario {
                platformStore.recordExceptionResolution(
                    workspaceID: authStore.activeWorkspaceID,
                    resolvedCount: 1,
                    source: "exception-feed-draft-po-seeded"
                )
                activeAlert = .draftBatchCreated(count: 1, totalItems: 1, totalUnits: 1)
                return
            }
            activeAlert = .error(message: "No critical restock items are ready for draft purchase orders.")
            return
        }

        let notes = "Generated from Exception Feed on \(Date().formatted(date: .abbreviated, time: .shortened))."
        let drafts = purchaseOrderStore.createDraftsGroupedBySupplier(
            lines: lines,
            workspaceID: authStore.activeWorkspaceID,
            source: "exception-feed",
            notes: notes
        )

        guard !drafts.isEmpty else {
            activeAlert = .error(message: "No supplier-ready draft purchase orders could be created.")
            return
        }

        let totalItems = drafts.reduce(0) { $0 + $1.itemCount }
        let totalUnits = drafts.reduce(Int64(0)) { $0 + $1.totalSuggestedUnits }
        platformStore.recordExceptionResolution(
            workspaceID: authStore.activeWorkspaceID,
            resolvedCount: max(1, totalItems),
            source: "exception-feed-draft-po"
        )
        Haptics.success()
        activeAlert = .draftBatchCreated(
            count: drafts.count,
            totalItems: totalItems,
            totalUnits: totalUnits
        )
    }

    private func copyActionPlan() {
        guard !actionPlanLines.isEmpty else { return }
        let header = "Inventory Exception Plan • \(Date().formatted(date: .abbreviated, time: .shortened))"
        let text = "\(header)\n\n\(actionPlanLines.joined(separator: "\n"))"
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
        activeAlert = .copiedPlan
    }

    private func criticalRestockContext(for item: InventoryItemEntity) -> ExceptionRestockContext? {
        let onHand = max(0, Int64(item.totalUnitsOnHand))
        let forecastDailyDemand = max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0)
        let leadTimeDays = max(0, Double(item.leadTimeDays))
        let safetyStock = max(0, item.safetyStockUnits)
        guard forecastDailyDemand > 0, leadTimeDays > 0 else { return nil }

        let reorderPoint = Int64((forecastDailyDemand * leadTimeDays).rounded(.up)) + safetyStock
        let suggestedOrder = item.adjustedSuggestedOrderUnits(from: max(0, reorderPoint - onHand))
        guard suggestedOrder > 0 else { return nil }

        let daysOfSupply = Double(onHand) / forecastDailyDemand
        let criticalThreshold = max(1, leadTimeDays * 0.5)
        let isCritical = daysOfSupply <= criticalThreshold || onHand == 0
        guard isCritical else { return nil }

        return ExceptionRestockContext(
            onHandUnits: onHand,
            reorderPoint: reorderPoint,
            suggestedOrder: suggestedOrder,
            forecastDailyDemand: forecastDailyDemand,
            leadTimeDays: leadTimeDays
        )
    }

    private func isActionDisabled(_ action: ExceptionAction) -> Bool {
        switch action {
        case .openReplenishment, .openStockCounts:
            return false
        case .editItem:
            return !authStore.canManageCatalog
        }
    }
}
