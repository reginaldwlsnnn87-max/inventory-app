import SwiftUI
import CoreData
#if canImport(UIKit)
import UIKit
#endif

private struct RiskSignal: Identifiable {
    let item: InventoryItemEntity
    let onHandUnits: Int64
    let leadTimeDays: Double
    let forecastDailyDemand: Double
    let daysOfCover: Double
    let urgencyScore: Double

    var id: UUID { item.id }
}

private struct DeadStockSignal: Identifiable {
    let item: InventoryItemEntity
    let onHandUnits: Int64
    let staleDays: Int
    let staleScore: Double

    var id: UUID { item.id }
}

private enum DashboardAlert: Identifiable {
    case copied

    var id: String {
        switch self {
        case .copied:
            return "copied"
        }
    }
}

private enum DashboardVisualMode: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case wow = "Wow"

    var id: String { rawValue }
}

struct KPIDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var platformStore: PlatformStore
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.updatedAt, ascending: false)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var editingItem: InventoryItemEntity?
    @State private var isPresentingReplenishment = false
    @State private var alert: DashboardAlert?
    @State private var visualMode: DashboardVisualMode = .wow

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    visualStyleCard
                        .inventoryStaggered(index: 0)
                    if visualMode == .wow {
                        wowHeroCard
                            .inventoryStaggered(index: 1)
                    }
                    headerCard
                        .inventoryStaggered(index: 2)
                    kpiCard
                        .inventoryStaggered(index: 3)
                    countProductivityCard
                        .inventoryStaggered(index: 4)
                    coverageCard
                        .inventoryStaggered(index: 5)
                    riskCard
                        .inventoryStaggered(index: 6)
                    deadStockCard
                        .inventoryStaggered(index: 7)
                }
                .padding(16)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("KPI Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .tint(Theme.accent)
        .alert(item: $alert) { alert in
            switch alert {
            case .copied:
                return Alert(
                    title: Text("Snapshot Copied"),
                    message: Text("Your KPI summary is on the clipboard."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .sheet(item: $editingItem) { item in
            ItemFormView(mode: .edit(item))
        }
        .sheet(isPresented: $isPresentingReplenishment) {
            NavigationStack {
                ReplenishmentPlannerView()
            }
        }
    }

    private var workspaceItems: [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(authStore.activeWorkspaceID) }
    }

    private var coverageReadyCount: Int {
        workspaceItems.filter { item in
            forecastDemand(for: item) > 0 && item.leadTimeDays > 0
        }.count
    }

    private var riskSignals: [RiskSignal] {
        let signals = workspaceItems.compactMap { item -> RiskSignal? in
            let forecast = forecastDemand(for: item)
            let leadTime = max(0, Double(item.leadTimeDays))
            let onHand = max(0, Int64(item.totalUnitsOnHand))
            guard forecast > 0, leadTime > 0 else { return nil }

            let daysOfCover = Double(onHand) / forecast
            let riskThreshold = max(1, leadTime)
            let isAtRisk = onHand == 0 || daysOfCover <= riskThreshold
            guard isAtRisk else { return nil }

            let urgency = daysOfCover - riskThreshold
            return RiskSignal(
                item: item,
                onHandUnits: onHand,
                leadTimeDays: leadTime,
                forecastDailyDemand: forecast,
                daysOfCover: daysOfCover,
                urgencyScore: urgency
            )
        }

        return signals.sorted { lhs, rhs in
            if lhs.urgencyScore != rhs.urgencyScore {
                return lhs.urgencyScore < rhs.urgencyScore
            }
            if lhs.onHandUnits != rhs.onHandUnits {
                return lhs.onHandUnits < rhs.onHandUnits
            }
            return lhs.item.name.localizedCaseInsensitiveCompare(rhs.item.name) == .orderedAscending
        }
    }

    private var deadStockSignals: [DeadStockSignal] {
        let today = Date()
        let signals = workspaceItems.compactMap { item -> DeadStockSignal? in
            let onHand = max(0, Int64(item.totalUnitsOnHand))
            guard onHand > 0 else { return nil }
            let forecast = forecastDemand(for: item)
            guard forecast <= 0 else { return nil }

            let staleDays = max(0, Calendar.current.dateComponents([.day], from: item.updatedAt, to: today).day ?? 0)
            guard staleDays >= 30 else { return nil }

            let staleScore = Double(staleDays) * Double(onHand)
            return DeadStockSignal(item: item, onHandUnits: onHand, staleDays: staleDays, staleScore: staleScore)
        }

        return signals.sorted { lhs, rhs in
            if lhs.staleScore != rhs.staleScore {
                return lhs.staleScore > rhs.staleScore
            }
            return lhs.item.name.localizedCaseInsensitiveCompare(rhs.item.name) == .orderedAscending
        }
    }

    private var averageDaysOfCover: Double? {
        let values = workspaceItems.compactMap { item -> Double? in
            let forecast = forecastDemand(for: item)
            guard forecast > 0 else { return nil }
            return Double(max(0, Int64(item.totalUnitsOnHand))) / forecast
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var stockoutRiskPercent: Double {
        guard coverageReadyCount > 0 else { return 0 }
        return (Double(riskSignals.count) / Double(coverageReadyCount)) * 100
    }

    private var deadStockPercent: Double {
        guard !workspaceItems.isEmpty else { return 0 }
        return (Double(deadStockSignals.count) / Double(workspaceItems.count)) * 100
    }

    private var countSummary: CountProductivitySummary {
        platformStore.countProductivitySummary(
            workspaceID: authStore.activeWorkspaceID,
            windowDays: 14
        )
    }

    private var recentCountSessions: [CountSessionRecord] {
        platformStore.countSessions(
            for: authStore.activeWorkspaceID,
            windowDays: countSummary.windowDays,
            limit: 3
        )
    }

    private var coverageBuckets: (critical: Int, watch: Int, healthy: Int) {
        var critical = 0
        var watch = 0
        var healthy = 0

        for item in workspaceItems {
            let forecast = forecastDemand(for: item)
            guard forecast > 0 else { continue }
            let days = Double(max(0, Int64(item.totalUnitsOnHand))) / forecast
            if days <= 3 {
                critical += 1
            } else if days <= 14 {
                watch += 1
            } else {
                healthy += 1
            }
        }

        return (critical, watch, healthy)
    }

    private var visualStyleCard: some View {
        HStack(spacing: 10) {
            InventoryModuleBadge(module: .reports, symbol: "sparkles.tv.fill", size: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text("Dashboard Look")
                    .font(Theme.sectionFont())
                    .foregroundStyle(Theme.textSecondary)
                Picker("Dashboard Look", selection: $visualMode) {
                    ForEach(DashboardVisualMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            Spacer()
        }
        .padding(14)
        .inventoryCard(cornerRadius: 16, emphasis: 0.52)
    }

    private var wowHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                InventoryModuleBadge(module: .reports, symbol: "chart.xyaxis.line", size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mission Control")
                        .font(Theme.font(17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Live pulse of risk, coverage, and count execution")
                        .font(Theme.font(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("WOW")
                    .font(Theme.font(10, weight: .bold))
                    .foregroundStyle(Theme.moduleVisual(.reports).deepTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Theme.moduleChipGradient(.reports))
                    )
            }

            HStack(spacing: 10) {
                wowChip(
                    module: .shrink,
                    title: "Stockout",
                    value: percentString(stockoutRiskPercent)
                )
                wowChip(
                    module: .replenishment,
                    title: "Coverage",
                    value: averageDaysOfCover.map { "\(valueString($0))d" } ?? "-"
                )
                wowChip(
                    module: .counts,
                    title: "Sessions",
                    value: "\(countSummary.sessionCount)"
                )
            }
        }
        .padding(16)
        .inventoryCard(cornerRadius: 18, emphasis: 0.74)
    }

    private var headerCard: some View {
        HStack(spacing: 10) {
            InventoryModuleBadge(module: .reports, symbol: "chart.bar.doc.horizontal", size: 38)
            VStack(alignment: .leading, spacing: 8) {
                Text("Track inventory health in one place.")
                    .font(Theme.font(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(
                    visualMode == .wow
                        ? "Mission-focused KPI stack for faster operator decisions."
                        : "Use risk, coverage, and dead-stock KPIs to catch stock issues before they cost sales."
                )
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.56)
    }

    private var kpiCard: some View {
        sectionCard(title: "Core KPIs", module: .reports) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                metricTile(title: "Stockout Risk", value: percentString(stockoutRiskPercent), tint: .orange)
                metricTile(title: "Avg Days Cover", value: averageDaysOfCover.map { valueString($0) } ?? "-", tint: Theme.accentDeep)
                metricTile(title: "Dead Stock", value: percentString(deadStockPercent), tint: .red)
                metricTile(title: "Coverage Ready", value: "\(coverageReadyCount)", tint: Theme.textPrimary)
            }

            Button {
                copySnapshot()
            } label: {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("Copy KPI Snapshot")
                        .font(Theme.font(13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .inventorySecondaryAction()
            .disabled(workspaceItems.isEmpty)
            .opacity(workspaceItems.isEmpty ? 0.55 : 1)
        }
    }

    private var countProductivityCard: some View {
        sectionCard(title: "Count Productivity (14 Days)", module: .counts) {
            if countSummary.sessionCount == 0 {
                Text("Run Stock Counts or Zone Mission to start tracking speed, variance load, and execution consistency.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    metricTile(title: "Sessions", value: "\(countSummary.sessionCount)", tint: Theme.textPrimary)
                    metricTile(title: "Items Counted", value: "\(countSummary.totalItemsCounted)", tint: Theme.accentDeep)
                    metricTile(title: "Avg Speed", value: "\(valueString(countSummary.averageItemsPerMinute))/min", tint: Theme.accent)
                    metricTile(title: "Best Speed", value: "\(valueString(countSummary.bestItemsPerMinute))/min", tint: .green)
                    metricTile(title: "Avg Duration", value: "\(valueString(countSummary.averageDurationMinutes))m", tint: Theme.textSecondary)
                    metricTile(
                        title: "Blind Mode",
                        value: percentString(countSummary.blindModeRate * 100),
                        tint: Theme.accentDeep
                    )
                    metricTile(
                        title: "Target Tracked",
                        value: "\(countSummary.targetTrackedSessions)",
                        tint: Theme.textPrimary
                    )
                    metricTile(
                        title: "Target Hit",
                        value: countSummary.targetTrackedSessions > 0
                            ? percentString(countSummary.targetHitRate * 100)
                            : "-",
                        tint: countSummary.targetTrackedSessions == 0
                            ? Theme.textSecondary
                            : (countSummary.targetHitRate >= 0.8 ? .green : .orange)
                    )
                }

                metricTile(
                    title: "High Variance Reviewed",
                    value: "\(countSummary.highVarianceItems)",
                    tint: countSummary.highVarianceItems > 0 ? .orange : Theme.textSecondary
                )

                ForEach(Array(recentCountSessions.enumerated()), id: \.element.id) { index, session in
                    countSessionRow(session)
                        .inventoryStaggered(index: index, baseDelay: 0.03, initialYOffset: 12)
                }
            }
        }
    }

    private var coverageCard: some View {
        let buckets = coverageBuckets
        return sectionCard(title: "Days Of Cover Buckets", module: .replenishment) {
            bucketRow(title: "Critical (0-3 days)", count: buckets.critical, tint: .orange)
            bucketRow(title: "Watch (4-14 days)", count: buckets.watch, tint: Theme.accentDeep)
            bucketRow(title: "Healthy (15+ days)", count: buckets.healthy, tint: .green)

            Text("Coverage uses on-hand units divided by forecast daily demand.")
                .font(Theme.font(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var riskCard: some View {
        sectionCard(title: "Top Stockout Risks", module: .shrink) {
            if riskSignals.isEmpty {
                Text("No immediate stockout risks detected in this workspace.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(Array(riskSignals.prefix(8).enumerated()), id: \.element.id) { index, signal in
                    riskRow(signal)
                        .inventoryStaggered(index: index, baseDelay: 0.03, initialYOffset: 12)
                }

                Button {
                    isPresentingReplenishment = true
                } label: {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                        Text("Open Replenishment Planner")
                            .font(Theme.font(13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .inventoryPrimaryAction()
            }
        }
    }

    private var deadStockCard: some View {
        sectionCard(title: "Dead Stock Watch", module: .shrink) {
            if deadStockSignals.isEmpty {
                Text("No dead stock candidates over 30 stale days.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(Array(deadStockSignals.prefix(8).enumerated()), id: \.element.id) { index, signal in
                    deadStockRow(signal)
                        .inventoryStaggered(index: index, baseDelay: 0.03, initialYOffset: 12)
                }
            }
        }
    }

    private func countSessionRow(_ session: CountSessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(session.type.title)
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let zoneTitle = session.zoneTitle {
                    Text(zoneTitle)
                        .font(Theme.font(10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Theme.accentSoft.opacity(0.22))
                        )
                        .foregroundStyle(Theme.accentDeep)
                }
                Spacer()
                Text("\(valueString(session.itemsPerMinute))/min")
                    .font(Theme.font(10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.green.opacity(0.14))
                    )
                    .foregroundStyle(.green)
            }

            HStack(spacing: 10) {
                detailChip("Items", value: "\(session.itemCount)")
                detailChip("Duration", value: "\(valueString(session.durationMinutes))m")
                detailChip("Variance", value: "\(session.highVarianceCount)")
                detailChip("Mode", value: session.blindModeEnabled ? "Blind" : "Guided")
                if let targetDurationMinutes = session.targetDurationMinutes {
                    detailChip("Target", value: "\(targetDurationMinutes)m")
                    detailChip("Hit", value: session.metTarget == true ? "Yes" : "No")
                }
            }

            Text(session.finishedAt.formatted(date: .abbreviated, time: .shortened))
                .font(Theme.font(10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    visualMode == .wow
                        ? Theme.moduleChipGradient(.counts)
                        : LinearGradient(
                            colors: [Theme.cardBackground.opacity(0.95), Theme.cardBackground.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func riskRow(_ signal: RiskSignal) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(signal.item.name.isEmpty ? "Unnamed Item" : signal.item.name)
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(valueString(signal.daysOfCover))d cover")
                    .font(Theme.font(10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.orange.opacity(0.15))
                    )
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                detailChip("On hand", value: "\(signal.onHandUnits)")
                detailChip("Lead", value: "\(Int(signal.leadTimeDays.rounded()))d")
                detailChip("Forecast/day", value: valueString(signal.forecastDailyDemand))
            }

            HStack(spacing: 8) {
                Button {
                    editingItem = signal.item
                } label: {
                    Label("Edit Inputs", systemImage: "square.and.pencil")
                }
                .inventorySecondaryAction()
                .disabled(!authStore.canManageCatalog)
                .opacity(authStore.canManageCatalog ? 1 : 0.55)

                Spacer()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    visualMode == .wow
                        ? Theme.moduleChipGradient(.shrink)
                        : LinearGradient(
                            colors: [Theme.cardBackground.opacity(0.95), Theme.cardBackground.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func deadStockRow(_ signal: DeadStockSignal) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(signal.item.name.isEmpty ? "Unnamed Item" : signal.item.name)
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(signal.staleDays)d stale")
                    .font(Theme.font(10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.red.opacity(0.14))
                    )
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                detailChip("On hand", value: "\(signal.onHandUnits)")
                detailChip("Category", value: signal.item.category.isEmpty ? "Uncategorized" : signal.item.category)
                detailChip("Location", value: signal.item.location.isEmpty ? "-" : signal.item.location)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    visualMode == .wow
                        ? Theme.moduleChipGradient(.replenishment)
                        : LinearGradient(
                            colors: [Theme.cardBackground.opacity(0.95), Theme.cardBackground.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        module: InventoryModule,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let moduleVisual = Theme.moduleVisual(module)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                InventoryModuleBadge(module: module, size: 24)
                Text(title)
                    .font(Theme.sectionFont())
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if visualMode == .wow {
                    Text(module.rawValue.uppercased())
                        .font(Theme.font(9, weight: .bold))
                        .foregroundStyle(moduleVisual.deepTint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Theme.moduleChipGradient(module))
                        )
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 10) {
                content()
            }
            .padding(12)
            .inventoryCard(cornerRadius: 14, emphasis: visualMode == .wow ? 0.32 : 0.24)
        }
        .padding(14)
        .inventoryCard(cornerRadius: 16, emphasis: visualMode == .wow ? 0.56 : 0.42)
    }

    private func metricTile(title: String, value: String, tint: Color) -> some View {
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
                .fill(
                    visualMode == .wow
                        ? Theme.cardGradient(emphasis: 0.32)
                        : LinearGradient(
                            colors: [Theme.cardBackground.opacity(0.95), Theme.cardBackground.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func wowChip(module: InventoryModule, title: String, value: String) -> some View {
        let moduleVisual = Theme.moduleVisual(module)
        return VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(Theme.font(9, weight: .bold))
                .foregroundStyle(moduleVisual.deepTint)
            Text(value)
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.moduleChipGradient(module))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.strongBorder.opacity(0.5), lineWidth: 0.8)
        )
    }

    private func bucketRow(title: String, count: Int, tint: Color) -> some View {
        HStack {
            Text(title)
                .font(Theme.font(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(count)")
                .font(Theme.font(12, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(.vertical, 4)
    }

    private func detailChip(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.font(10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(Theme.font(11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func forecastDemand(for item: InventoryItemEntity) -> Double {
        max(0, max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0))
    }

    private func percentString(_ value: Double) -> String {
        if value.isNaN || value.isInfinite {
            return "-"
        }
        return String(format: "%.0f%%", value)
    }

    private func valueString(_ value: Double) -> String {
        if value.isNaN || value.isInfinite {
            return "-"
        }
        if abs(value.rounded() - value) < 0.01 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }

    private func copySnapshot() {
        guard !workspaceItems.isEmpty else { return }
        let snapshotLines = [
            "KPI Dashboard • \(Date().formatted(date: .abbreviated, time: .shortened))",
            "Workspace: \(authStore.activeWorkspaceName)",
            "Stockout Risk: \(percentString(stockoutRiskPercent))",
            "Avg Days Cover: \(averageDaysOfCover.map { valueString($0) } ?? "-")",
            "Dead Stock: \(percentString(deadStockPercent))",
            "Coverage Ready SKUs: \(coverageReadyCount)",
            "Count Sessions (14d): \(countSummary.sessionCount)",
            "Count Avg Speed: \(valueString(countSummary.averageItemsPerMinute))/min",
            "Count High Variance Reviewed: \(countSummary.highVarianceItems)",
            "Count Target Sessions: \(countSummary.targetTrackedSessions)",
            "Count Target Hit Rate: \(countSummary.targetTrackedSessions > 0 ? percentString(countSummary.targetHitRate * 100) : "-")"
        ]
        #if canImport(UIKit)
        UIPasteboard.general.string = snapshotLines.joined(separator: "\n")
        #endif
        alert = .copied
    }
}
