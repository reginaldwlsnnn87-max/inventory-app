import SwiftUI
import CoreData
#if canImport(UIKit)
import UIKit
#endif

private enum PlannerFilter: String, CaseIterable, Identifiable {
    case all
    case urgent
    case dueSoon
    case healthy
    case needsData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .urgent:
            return "Urgent"
        case .dueSoon:
            return "Due Soon"
        case .healthy:
            return "Healthy"
        case .needsData:
            return "Needs Data"
        }
    }
}

private enum ReplenishmentStatus: String {
    case urgent
    case dueSoon
    case healthy
    case needsData

    var title: String {
        switch self {
        case .urgent:
            return "Urgent"
        case .dueSoon:
            return "Due Soon"
        case .healthy:
            return "Healthy"
        case .needsData:
            return "Needs Data"
        }
    }

    var order: Int {
        switch self {
        case .urgent:
            return 0
        case .dueSoon:
            return 1
        case .needsData:
            return 2
        case .healthy:
            return 3
        }
    }

    var tint: Color {
        switch self {
        case .urgent:
            return .orange
        case .dueSoon:
            return Theme.accentDeep
        case .healthy:
            return Theme.textSecondary
        case .needsData:
            return .red
        }
    }

    var icon: String {
        switch self {
        case .urgent:
            return "exclamationmark.triangle.fill"
        case .dueSoon:
            return "clock.badge.exclamationmark"
        case .healthy:
            return "checkmark.seal"
        case .needsData:
            return "questionmark.circle"
        }
    }
}

private struct ReplenishmentSignal: Identifiable {
    let item: InventoryItemEntity
    let status: ReplenishmentStatus
    let onHandUnits: Int64
    let reorderPoint: Int64
    let suggestedOrder: Int64
    let leadTimeDays: Double
    let forecastDailyDemand: Double
    let sampleCount: Int
    let daysOfSupply: Double?

    var id: UUID { item.id }
}

private enum SuggestionConfidence {
    case high
    case medium
    case low

    var title: String {
        switch self {
        case .high:
            return "High confidence"
        case .medium:
            return "Medium confidence"
        case .low:
            return "Low confidence"
        }
    }

    var tint: Color {
        switch self {
        case .high:
            return .green
        case .medium:
            return Theme.accentDeep
        case .low:
            return .orange
        }
    }
}

private struct AutoReorderSuggestion: Identifiable {
    let item: InventoryItemEntity
    let onHandUnits: Int64
    let reorderPoint: Int64
    let targetUnits: Int64
    let recommendedUnits: Int64
    let leadTimeDays: Double
    let reviewWindowDays: Double
    let velocityPerDay: Double
    let safetyStockUnits: Int64
    let sampleCount: Int
    let daysOfCover: Double?
    let riskScore: Double
    let confidence: SuggestionConfidence

    var id: UUID { item.id }
}

private enum PlannerAlert: Identifiable {
    case copiedPlan
    case draftCreated(reference: String)
    case draftBatchCreated(count: Int, totalItems: Int, totalUnits: Int64)
    case error(message: String)

    var id: String {
        switch self {
        case .copiedPlan:
            return "copied-plan"
        case .draftCreated(let reference):
            return "draft-created-\(reference)"
        case .draftBatchCreated(let count, let totalItems, let totalUnits):
            return "draft-batch-\(count)-\(totalItems)-\(totalUnits)"
        case .error(let message):
            return "error-\(message)"
        }
    }
}

struct ReplenishmentPlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: InventoryDataController
    @EnvironmentObject private var purchaseOrderStore: PurchaseOrderStore
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var guidanceStore: GuidanceStore
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.name, ascending: true)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var filter: PlannerFilter = .all
    @State private var searchText = ""
    @State private var activeAlert: PlannerAlert?
    @State private var editingItem: InventoryItemEntity?
    @State private var loggingUsageItem: InventoryItemEntity?
    @State private var usageEntryText = ""
    @State private var isShowingWalkthrough = false

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    summaryCard
                    autoReorderCard
                    filterCard

                    if filteredSignals.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredSignals) { signal in
                            signalCard(signal)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("Replenishment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingWalkthrough = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("How to use Replenishment")
            }
        }
        .searchable(text: $searchText, prompt: "Search items")
        .tint(Theme.accent)
        .sheet(isPresented: $isShowingWalkthrough) {
            ProcessWalkthroughView(
                flow: .replenishment,
                showLaunchButton: false,
                onCompleted: {
                    guidanceStore.markFlowCompleted(.replenishment)
                }
            )
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .copiedPlan:
                return Alert(
                    title: Text("Order Plan Copied"),
                    message: Text("Your draft purchase plan is on the clipboard."),
                    dismissButton: .default(Text("OK"))
                )
            case .draftCreated(let reference):
                return Alert(
                    title: Text("Draft PO Created"),
                    message: Text("\(reference) is ready in Purchase Orders."),
                    dismissButton: .default(Text("Great"))
                )
            case .draftBatchCreated(let count, let totalItems, let totalUnits):
                return Alert(
                    title: Text("Draft POs Created"),
                    message: Text("\(count) supplier-ready drafts were created with \(totalItems) items and \(totalUnits) units total."),
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
        .sheet(item: $editingItem) { item in
            ItemFormView(mode: .edit(item))
        }
        .sheet(item: $loggingUsageItem) { item in
            usageLoggingSheet(item)
        }
    }

    private var allSignals: [ReplenishmentSignal] {
        let signals = workspaceItems.map { item -> ReplenishmentSignal in
            let onHand = max(0, Int64(item.totalUnitsOnHand))
            let averageDemand = max(0, item.averageDailyUsage)
            let forecastDemand = max(averageDemand, item.movingAverageDailyDemand ?? 0)
            let leadTime = max(0, Double(item.leadTimeDays))
            let safetyStock = max(0, item.safetyStockUnits)
            let sampleCount = item.dailyDemandSamples.count

            guard forecastDemand > 0, leadTime > 0 else {
                return ReplenishmentSignal(
                    item: item,
                    status: .needsData,
                    onHandUnits: onHand,
                    reorderPoint: 0,
                    suggestedOrder: 0,
                    leadTimeDays: leadTime,
                    forecastDailyDemand: forecastDemand,
                    sampleCount: sampleCount,
                    daysOfSupply: nil
                )
            }

            let demandDuringLead = Int64((forecastDemand * leadTime).rounded(.up))
            let reorderPoint = max(0, demandDuringLead + safetyStock)
            let baseSuggestedOrder = max(0, reorderPoint - onHand)
            let suggestedOrder = item.adjustedSuggestedOrderUnits(from: baseSuggestedOrder)
            let daysOfSupply = forecastDemand > 0 ? Double(onHand) / forecastDemand : nil

            let status: ReplenishmentStatus
            if suggestedOrder > 0 {
                let urgentCutoff = max(1, leadTime * 0.5)
                if (daysOfSupply ?? 0) <= urgentCutoff || onHand == 0 {
                    status = .urgent
                } else {
                    status = .dueSoon
                }
            } else {
                status = .healthy
            }

            return ReplenishmentSignal(
                item: item,
                status: status,
                onHandUnits: onHand,
                reorderPoint: reorderPoint,
                suggestedOrder: suggestedOrder,
                leadTimeDays: leadTime,
                forecastDailyDemand: forecastDemand,
                sampleCount: sampleCount,
                daysOfSupply: daysOfSupply
            )
        }

        return signals.sorted { lhs, rhs in
            if lhs.status.order != rhs.status.order {
                return lhs.status.order < rhs.status.order
            }
            if lhs.suggestedOrder != rhs.suggestedOrder {
                return lhs.suggestedOrder > rhs.suggestedOrder
            }
            return lhs.item.name.localizedCaseInsensitiveCompare(rhs.item.name) == .orderedAscending
        }
    }

    private var workspaceItems: [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(authStore.activeWorkspaceID) }
    }

    private var actionableSignals: [ReplenishmentSignal] {
        allSignals.filter { signal in
            (signal.status == .urgent || signal.status == .dueSoon) && signal.suggestedOrder > 0
        }
    }

    private var filteredSignals: [ReplenishmentSignal] {
        allSignals.filter { signal in
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .urgent:
                matchesFilter = signal.status == .urgent
            case .dueSoon:
                matchesFilter = signal.status == .dueSoon
            case .healthy:
                matchesFilter = signal.status == .healthy
            case .needsData:
                matchesFilter = signal.status == .needsData
            }

            let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = trimmedSearch.isEmpty
                || signal.item.name.localizedCaseInsensitiveContains(trimmedSearch)
                || signal.item.category.localizedCaseInsensitiveContains(trimmedSearch)
                || signal.item.location.localizedCaseInsensitiveContains(trimmedSearch)

            return matchesFilter && matchesSearch
        }
    }

    private var urgentCount: Int {
        allSignals.filter { $0.status == .urgent }.count
    }

    private var dueSoonCount: Int {
        allSignals.filter { $0.status == .dueSoon }.count
    }

    private var orderUnitsTotal: Int64 {
        actionableSignals.reduce(0) { $0 + $1.suggestedOrder }
    }

    private var forecastBackedCount: Int {
        allSignals.filter { $0.sampleCount > 0 }.count
    }

    private var autoSuggestions: [AutoReorderSuggestion] {
        let suggestions = workspaceItems.compactMap { item -> AutoReorderSuggestion? in
            let onHand = max(0, Int64(item.totalUnitsOnHand))
            let leadTime = max(0, Double(item.leadTimeDays))
            let safetyStock = max(0, item.safetyStockUnits)
            let movingDemand = max(0, item.movingAverageDailyDemand ?? 0)
            let baselineDemand = max(0, item.averageDailyUsage)
            let velocity = blendedVelocity(movingDemand: movingDemand, baselineDemand: baselineDemand)

            guard leadTime > 0, velocity > 0 else { return nil }

            let reviewWindow = max(7, min(21, leadTime * 1.5))
            let reorderPoint = Int64((velocity * leadTime).rounded(.up)) + safetyStock
            let targetUnits = Int64((velocity * (leadTime + reviewWindow)).rounded(.up)) + safetyStock
            let baseRecommended = max(0, targetUnits - onHand)
            let recommended = item.adjustedSuggestedOrderUnits(from: baseRecommended)
            guard recommended > 0 else { return nil }

            let daysOfCover = Double(onHand) / velocity
            let riskScore = (daysOfCover - leadTime) / max(1, leadTime)
            let sampleCount = item.dailyDemandSamples.count
            let confidence = suggestionConfidence(
                sampleCount: sampleCount,
                movingDemand: movingDemand,
                baselineDemand: baselineDemand
            )

            return AutoReorderSuggestion(
                item: item,
                onHandUnits: onHand,
                reorderPoint: max(0, reorderPoint),
                targetUnits: max(0, targetUnits),
                recommendedUnits: recommended,
                leadTimeDays: leadTime,
                reviewWindowDays: reviewWindow,
                velocityPerDay: velocity,
                safetyStockUnits: safetyStock,
                sampleCount: sampleCount,
                daysOfCover: daysOfCover,
                riskScore: riskScore,
                confidence: confidence
            )
        }

        return suggestions.sorted { lhs, rhs in
            if lhs.riskScore != rhs.riskScore {
                return lhs.riskScore < rhs.riskScore
            }
            if lhs.recommendedUnits != rhs.recommendedUnits {
                return lhs.recommendedUnits > rhs.recommendedUnits
            }
            return lhs.item.name.localizedCaseInsensitiveCompare(rhs.item.name) == .orderedAscending
        }
    }

    private var topAutoSuggestions: [AutoReorderSuggestion] {
        Array(autoSuggestions.prefix(6))
    }

    private var autoSuggestedUnitsTotal: Int64 {
        autoSuggestions.reduce(0) { $0 + $1.recommendedUnits }
    }

    private var autoCriticalCount: Int {
        autoSuggestions.filter { suggestion in
            guard let daysOfCover = suggestion.daysOfCover else { return false }
            return daysOfCover <= suggestion.leadTimeDays
        }.count
    }

    private var autoHighConfidenceCount: Int {
        autoSuggestions.filter { $0.confidence == .high }.count
    }

    private var autoPlanLines: [String] {
        autoSuggestions.prefix(20).map { suggestion in
            let lead = Int(suggestion.leadTimeDays.rounded())
            let review = Int(suggestion.reviewWindowDays.rounded())
            let velocity = formatted(suggestion.velocityPerDay)
            return "• \(suggestion.item.name): order \(suggestion.recommendedUnits) units (lead \(lead)d + review \(review)d, target \(suggestion.targetUnits), velocity \(velocity)/day)"
        }
    }

    private var planLines: [String] {
        actionableSignals.map { signal in
            let lead = signal.leadTimeDays > 0 ? "LT \(Int(signal.leadTimeDays))d" : "LT -"
            let forecast = formatted(signal.forecastDailyDemand)
            return "• \(signal.item.name): order \(signal.suggestedOrder) units (\(lead), target \(signal.reorderPoint), forecast \(forecast)/day)"
        }
    }

    private var summaryCard: some View {
        sectionCard(title: "Action Summary") {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                summaryTile(title: "Urgent", value: "\(urgentCount)", tint: .orange)
                summaryTile(title: "Due Soon", value: "\(dueSoonCount)", tint: Theme.accentDeep)
                summaryTile(title: "Suggested Units", value: "\(orderUnitsTotal)", tint: Theme.accent)
                summaryTile(title: "Forecasted", value: "\(forecastBackedCount)", tint: Theme.textSecondary)
            }

            Button {
                createDraftPurchaseOrder()
            } label: {
                HStack {
                    Image(systemName: "cart.badge.plus")
                    Text("Create Draft PO")
                        .font(Theme.font(13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(actionableSignals.isEmpty || !authStore.canManagePurchasing)
            .opacity((actionableSignals.isEmpty || !authStore.canManagePurchasing) ? 0.55 : 1)

            Button {
                copyPlan()
            } label: {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("Copy Order Plan")
                        .font(Theme.font(13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(planLines.isEmpty)
            .opacity(planLines.isEmpty ? 0.55 : 1)
        }
    }

    private var autoReorderCard: some View {
        sectionCard(title: "Auto-Reorder Suggestions") {
            if autoSuggestions.isEmpty {
                Text("No reorder suggestions yet. Add lead time and usage data to generate velocity-based recommendations.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    summaryTile(title: "Suggestions", value: "\(autoSuggestions.count)", tint: Theme.accent)
                    summaryTile(title: "Critical", value: "\(autoCriticalCount)", tint: .orange)
                    summaryTile(title: "Auto Units", value: "\(autoSuggestedUnitsTotal)", tint: Theme.accentDeep)
                    summaryTile(title: "High Confidence", value: "\(autoHighConfidenceCount)", tint: .green)
                }

                Button {
                    createAutoDraftPurchaseOrder()
                } label: {
                    HStack {
                        Image(systemName: "cart.badge.plus")
                        Text("Create Auto Draft PO")
                            .font(Theme.font(13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(autoSuggestions.isEmpty || !authStore.canManagePurchasing)
                .opacity((autoSuggestions.isEmpty || !authStore.canManagePurchasing) ? 0.55 : 1)

                Button {
                    copyAutoPlan()
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Auto-Reorder Plan")
                            .font(Theme.font(13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(autoPlanLines.isEmpty)
                .opacity(autoPlanLines.isEmpty ? 0.55 : 1)

                ForEach(topAutoSuggestions) { suggestion in
                    autoSuggestionRow(suggestion)
                }

                if autoSuggestions.count > topAutoSuggestions.count {
                    Text("Showing top \(topAutoSuggestions.count) of \(autoSuggestions.count) suggestions.")
                        .font(Theme.font(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var filterCard: some View {
        sectionCard(title: "Filter") {
            Picker("Filter", selection: $filter) {
                ForEach(PlannerFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text("Tip: log daily usage on each SKU to build a moving-average demand forecast.")
                .font(Theme.font(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func autoSuggestionRow(_ suggestion: AutoReorderSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(suggestion.item.name.isEmpty ? "Unnamed Item" : suggestion.item.name)
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                confidenceBadge(suggestion.confidence)
            }

            Text("Order \(suggestion.recommendedUnits) units to cover lead + review window.")
                .font(Theme.font(12, weight: .semibold))
                .foregroundStyle(Theme.accent)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                metricChip("Velocity/day", value: formatted(suggestion.velocityPerDay))
                metricChip("On hand", value: "\(suggestion.onHandUnits)")
                metricChip("Reorder point", value: "\(suggestion.reorderPoint)")
                metricChip("Target units", value: "\(suggestion.targetUnits)")
                metricChip("Lead + review", value: "\(Int(suggestion.leadTimeDays.rounded()))d + \(Int(suggestion.reviewWindowDays.rounded()))d")
                metricChip("Safety stock", value: "\(suggestion.safetyStockUnits)")
                metricChip("Days cover", value: suggestion.daysOfCover.map { formatted($0) } ?? "-")
                metricChip("Samples", value: "\(suggestion.sampleCount)")
            }

            HStack(spacing: 10) {
                Button {
                    usageEntryText = ""
                    loggingUsageItem = suggestion.item
                } label: {
                    Label("Log Usage", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    editingItem = suggestion.item
                } label: {
                    Label("Edit Inputs", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                .disabled(!authStore.canManageCatalog)

                Spacer()
            }
        }
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

    private func signalCard(_ signal: ReplenishmentSignal) -> some View {
        sectionCard(title: signal.item.name.isEmpty ? "Unnamed Item" : signal.item.name) {
            HStack(spacing: 8) {
                Label(signal.status.title, systemImage: signal.status.icon)
                    .font(Theme.font(11, weight: .semibold))
                    .foregroundStyle(signal.status.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(signal.status.tint.opacity(0.12))
                    )

                if !signal.item.category.isEmpty {
                    Text(signal.item.category)
                        .font(Theme.font(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Theme.accentSoft.opacity(0.22))
                        )
                }

                Spacer()
            }

            metricsRow(signal)

            if signal.status == .needsData {
                Text("Add average demand and lead time, then log usage to enable forecast-based planning.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(.red)
            } else if signal.sampleCount > 0 {
                Text("Forecast is based on a \(signal.sampleCount)-day moving average.")
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Forecast currently uses avg daily usage. Log usage to improve accuracy.")
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 10) {
                Button {
                    usageEntryText = ""
                    loggingUsageItem = signal.item
                } label: {
                    Label("Log Usage", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    editingItem = signal.item
                } label: {
                    Label("Edit Inputs", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                .disabled(!authStore.canManageCatalog)

                Spacer()
            }
        }
    }

    private func metricsRow(_ signal: ReplenishmentSignal) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            spacing: 8
        ) {
            metricChip("On hand", value: "\(signal.onHandUnits)")
            metricChip("Reorder point", value: "\(signal.reorderPoint)")
            metricChip("Order now", value: "\(signal.suggestedOrder)")
            metricChip("Forecast/day", value: formatted(signal.forecastDailyDemand))
            metricChip(
                "Days supply",
                value: signal.daysOfSupply.map { formatted($0) } ?? "-"
            )
            metricChip("Samples", value: "\(signal.sampleCount)")
        }
    }

    private func confidenceBadge(_ confidence: SuggestionConfidence) -> some View {
        Text(confidence.title)
            .font(Theme.font(10, weight: .semibold))
            .foregroundStyle(confidence.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(confidence.tint.opacity(0.12))
            )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("No items in this view")
                .font(Theme.font(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Try another filter or search term.")
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

    private func metricChip(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.font(10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(Theme.font(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
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

    private func usageLoggingSheet(_ item: InventoryItemEntity) -> some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                VStack(spacing: 16) {
                    sectionCard(title: item.name.isEmpty ? "Log Usage" : item.name) {
                        Text("Enter units used or sold today. The app stores a rolling 14-day demand history.")
                            .font(Theme.font(12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)

                        TextField("", text: $usageEntryText, prompt: Theme.inputPrompt("Today usage"))
                            .keyboardType(.decimalPad)
                            .inventoryTextInputField()
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("Log Daily Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        loggingUsageItem = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveUsageSample(for: item)
                    }
                }
            }
        }
    }

    private func createDraftPurchaseOrder() {
        let lines = actionableSignals.compactMap { signal -> PurchaseOrderLine? in
            let adjustedUnits = signal.item.adjustedSuggestedOrderUnits(from: signal.suggestedOrder)
            guard adjustedUnits > 0 else { return nil }
            let preferredSupplier = signal.item.normalizedPreferredSupplier
            let supplierSKU = signal.item.normalizedSupplierSKU
            return PurchaseOrderLine(
                itemID: signal.item.id,
                itemName: signal.item.name,
                category: signal.item.category,
                suggestedUnits: adjustedUnits,
                reorderPoint: signal.reorderPoint,
                onHandUnits: signal.onHandUnits,
                leadTimeDays: Int64(max(0, Int(signal.leadTimeDays.rounded()))),
                forecastDailyDemand: signal.forecastDailyDemand,
                preferredSupplier: preferredSupplier.isEmpty ? nil : preferredSupplier,
                supplierSKU: supplierSKU.isEmpty ? nil : supplierSKU,
                minimumOrderQuantity: signal.item.minimumOrderQuantity > 0 ? signal.item.minimumOrderQuantity : nil,
                reorderCasePack: signal.item.reorderCasePack > 0 ? signal.item.reorderCasePack : nil,
                leadTimeVarianceDays: signal.item.leadTimeVarianceDays > 0 ? signal.item.leadTimeVarianceDays : nil
            )
        }

        guard authStore.canManagePurchasing else {
            activeAlert = .error(message: "Only owners and managers can create purchase orders.")
            return
        }

        let notes = "Generated from Replenishment Planner on \(Date().formatted(date: .abbreviated, time: .shortened))."
        let drafts = purchaseOrderStore.createDraftsGroupedBySupplier(
            lines: lines,
            workspaceID: authStore.activeWorkspaceID,
            source: "replenishment",
            notes: notes
        )
        guard !drafts.isEmpty else {
            activeAlert = .error(message: "No actionable items are ready for a purchase order.")
            return
        }

        Haptics.success()
        if drafts.count == 1, let draft = drafts.first {
            activeAlert = .draftCreated(reference: draft.reference)
        } else {
            let totalItems = drafts.reduce(0) { $0 + $1.itemCount }
            let totalUnits = drafts.reduce(Int64(0)) { $0 + $1.totalSuggestedUnits }
            activeAlert = .draftBatchCreated(
                count: drafts.count,
                totalItems: totalItems,
                totalUnits: totalUnits
            )
        }
    }

    private func createAutoDraftPurchaseOrder() {
        guard authStore.canManagePurchasing else {
            activeAlert = .error(message: "Only owners and managers can create purchase orders.")
            return
        }

        let lines = autoSuggestions.compactMap { suggestion -> PurchaseOrderLine? in
            let adjustedUnits = suggestion.item.adjustedSuggestedOrderUnits(from: suggestion.recommendedUnits)
            guard adjustedUnits > 0 else { return nil }
            let preferredSupplier = suggestion.item.normalizedPreferredSupplier
            let supplierSKU = suggestion.item.normalizedSupplierSKU
            return PurchaseOrderLine(
                itemID: suggestion.item.id,
                itemName: suggestion.item.name,
                category: suggestion.item.category,
                suggestedUnits: adjustedUnits,
                reorderPoint: suggestion.reorderPoint,
                onHandUnits: suggestion.onHandUnits,
                leadTimeDays: Int64(max(0, Int(suggestion.leadTimeDays.rounded()))),
                forecastDailyDemand: suggestion.velocityPerDay,
                preferredSupplier: preferredSupplier.isEmpty ? nil : preferredSupplier,
                supplierSKU: supplierSKU.isEmpty ? nil : supplierSKU,
                minimumOrderQuantity: suggestion.item.minimumOrderQuantity > 0 ? suggestion.item.minimumOrderQuantity : nil,
                reorderCasePack: suggestion.item.reorderCasePack > 0 ? suggestion.item.reorderCasePack : nil,
                leadTimeVarianceDays: suggestion.item.leadTimeVarianceDays > 0 ? suggestion.item.leadTimeVarianceDays : nil
            )
        }

        let notes = "Generated from Auto-Reorder Suggestions on \(Date().formatted(date: .abbreviated, time: .shortened))."
        let drafts = purchaseOrderStore.createDraftsGroupedBySupplier(
            lines: lines,
            workspaceID: authStore.activeWorkspaceID,
            source: "auto-reorder",
            notes: notes
        )
        guard !drafts.isEmpty else {
            activeAlert = .error(message: "No auto reorder suggestions are ready for a draft purchase order.")
            return
        }

        Haptics.success()
        if drafts.count == 1, let draft = drafts.first {
            activeAlert = .draftCreated(reference: draft.reference)
        } else {
            let totalItems = drafts.reduce(0) { $0 + $1.itemCount }
            let totalUnits = drafts.reduce(Int64(0)) { $0 + $1.totalSuggestedUnits }
            activeAlert = .draftBatchCreated(
                count: drafts.count,
                totalItems: totalItems,
                totalUnits: totalUnits
            )
        }
    }

    private func copyAutoPlan() {
        guard !autoPlanLines.isEmpty else { return }
        let header = "Auto-Reorder Plan • \(Date().formatted(date: .abbreviated, time: .shortened))"
        let body = autoPlanLines.joined(separator: "\n")
        let text = "\(header)\n\n\(body)"
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
        activeAlert = .copiedPlan
    }

    private func copyPlan() {
        guard !planLines.isEmpty else { return }
        let header = "Inventory Replenishment Plan • \(Date().formatted(date: .abbreviated, time: .shortened))"
        let body = planLines.joined(separator: "\n")
        let text = "\(header)\n\n\(body)"
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
        activeAlert = .copiedPlan
    }

    private func saveUsageSample(for item: InventoryItemEntity) {
        let trimmed = usageEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value >= 0 else {
            activeAlert = .error(message: "Enter a valid usage number such as 18 or 18.5.")
            return
        }

        item.appendDailyDemandSample(value)
        if item.averageDailyUsage <= 0 {
            item.averageDailyUsage = value
        }
        item.assignWorkspaceIfNeeded(authStore.activeWorkspaceID)
        item.updatedAt = Date()
        dataController.save()

        usageEntryText = ""
        loggingUsageItem = nil
        Haptics.success()
    }

    private func blendedVelocity(movingDemand: Double, baselineDemand: Double) -> Double {
        if movingDemand > 0, baselineDemand > 0 {
            return movingDemand * 0.65 + baselineDemand * 0.35
        }
        return max(movingDemand, baselineDemand)
    }

    private func suggestionConfidence(
        sampleCount: Int,
        movingDemand: Double,
        baselineDemand: Double
    ) -> SuggestionConfidence {
        if sampleCount >= 10, movingDemand > 0 {
            return .high
        }
        if sampleCount >= 4 || (movingDemand > 0 && baselineDemand > 0) {
            return .medium
        }
        return .low
    }

    private func formatted(_ value: Double) -> String {
        if value.isNaN || value.isInfinite {
            return "-"
        }
        if abs(value.rounded() - value) < 0.01 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}
