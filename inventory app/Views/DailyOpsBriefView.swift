import SwiftUI
import CoreData

private enum OpsTaskImpact {
    case high
    case medium
    case foundation

    var title: String {
        switch self {
        case .high:
            return "High"
        case .medium:
            return "Medium"
        case .foundation:
            return "Foundation"
        }
    }

    var tint: Color {
        switch self {
        case .high:
            return .orange
        case .medium:
            return Theme.accentDeep
        case .foundation:
            return Theme.textSecondary
        }
    }
}

private enum OpsTaskAction {
    case replenishment
    case zoneMission
    case kpiDashboard
    case guidedHelp
    case integrationHub
}

private struct OpsTask: Identifiable {
    let id: String
    let title: String
    let detail: String
    let actionTitle: String
    let action: OpsTaskAction
    let impact: OpsTaskImpact
    let estimate: String
}

private struct OpsCompletionEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let taskID: String
    let taskTitle: String
    let actorName: String
    let actorRole: String
    let completedAt: Date
}

private struct OpsTrendPoint: Identifiable {
    let id: String
    let label: String
    let count: Int
    let isToday: Bool
}

struct DailyOpsBriefView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var guidanceStore: GuidanceStore
    @EnvironmentObject private var platformStore: PlatformStore
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.updatedAt, ascending: false)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var completedTaskIDs: Set<String> = []
    @State private var auditEntries: [OpsCompletionEvent] = []
    @State private var isPresentingReplenishment = false
    @State private var isPresentingZoneMission = false
    @State private var isPresentingKPI = false
    @State private var isPresentingIntegrationHub = false

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    scorecard
                    progressCard
                    accountabilityCard
                    trendCard
                    tasksCard
                    activityCard
                }
                .padding(16)
                .padding(.bottom, 10)
            }
        }
        .navigationTitle("Daily Ops Brief")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .tint(Theme.accent)
        .sheet(isPresented: $isPresentingReplenishment) {
            NavigationStack {
                ReplenishmentPlannerView()
            }
        }
        .sheet(isPresented: $isPresentingZoneMission) {
            NavigationStack {
                ZoneMissionView()
            }
        }
        .sheet(isPresented: $isPresentingKPI) {
            NavigationStack {
                KPIDashboardView()
            }
        }
        .sheet(isPresented: $isPresentingIntegrationHub) {
            NavigationStack {
                IntegrationHubView()
            }
        }
        .onAppear {
            loadCompletionState()
            loadAuditEntries()
        }
        .onChange(of: authStore.activeWorkspaceID) { _, _ in
            loadCompletionState()
            loadAuditEntries()
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    private var workspaceItems: [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(authStore.activeWorkspaceID) }
    }

    private var staleItemCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return workspaceItems.filter { $0.updatedAt < cutoff }.count
    }

    private var missingLocationCount: Int {
        workspaceItems.filter { item in
            item.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private var missingDemandDataCount: Int {
        workspaceItems.filter { item in
            let demand = max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0)
            return demand <= 0 || item.leadTimeDays <= 0
        }.count
    }

    private var urgentReplenishmentCount: Int {
        workspaceItems.filter { item in
            let demand = max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0)
            let leadTime = max(0, Double(item.leadTimeDays))
            guard demand > 0, leadTime > 0 else { return false }
            let onHand = Double(max(0, item.totalUnitsOnHand))
            let daysOfCover = onHand / demand
            let threshold = max(1, leadTime * 0.5)
            return onHand == 0 || daysOfCover <= threshold
        }.count
    }

    private var reconnectBrief: InventoryReconnectBrief {
        platformStore.inventoryReconnectBrief(workspaceID: authStore.activeWorkspaceID)
    }

    private var confidenceOverview: InventoryConfidenceOverview {
        platformStore.inventoryConfidenceOverview(
            for: workspaceItems,
            workspaceID: authStore.activeWorkspaceID,
            weakestLimit: 5
        )
    }

    private var tasks: [OpsTask] {
        guard !workspaceItems.isEmpty else { return [] }

        var output: [OpsTask] = []

        if urgentReplenishmentCount > 0 {
            output.append(
                OpsTask(
                    id: "urgent-replenishment",
                    title: "Build Today's Replenishment Plan",
                    detail: "\(urgentReplenishmentCount) SKU(s) are at urgent stockout risk. Generate an order plan before next receiving cut-off.",
                    actionTitle: "Open Replenishment",
                    action: .replenishment,
                    impact: .high,
                    estimate: "8 min"
                )
            )
        }

        if staleItemCount > 0 {
            output.append(
                OpsTask(
                    id: "stale-counts",
                    title: "Run A Zone Mission",
                    detail: "\(staleItemCount) item(s) have stale counts (7+ days). Knock out a focused zone mission this shift.",
                    actionTitle: "Open Zone Mission",
                    action: .zoneMission,
                    impact: .high,
                    estimate: "10 min"
                )
            )
        }

        if reconnectBrief.failedCount > 0 || reconnectBrief.pendingCount >= 20 {
            output.append(
                OpsTask(
                    id: "ledger-reconnect",
                    title: "Clear Offline Sync Backlog",
                    detail: "\(reconnectBrief.unsyncedCount) ledger event(s) need sync (\(reconnectBrief.failedCount) failed). Reconnect providers and run auto sync.",
                    actionTitle: "Open Integration Hub",
                    action: .integrationHub,
                    impact: .high,
                    estimate: "6 min"
                )
            )
        }

        if confidenceOverview.criticalCount > 0 {
            output.append(
                OpsTask(
                    id: "confidence-recovery",
                    title: "Recover Critical Count Confidence",
                    detail: "\(confidenceOverview.criticalCount) SKU(s) have critical confidence signals. Run a focused mission and close root-cause data gaps.",
                    actionTitle: "Open Zone Mission",
                    action: .zoneMission,
                    impact: .high,
                    estimate: "9 min"
                )
            )
        }

        if missingDemandDataCount > 0 {
            output.append(
                OpsTask(
                    id: "demand-data",
                    title: "Fix Planning Inputs",
                    detail: "\(missingDemandDataCount) item(s) are missing demand or lead time. Tighten this data to improve reorder accuracy.",
                    actionTitle: "Open Guided Help",
                    action: .guidedHelp,
                    impact: .medium,
                    estimate: "6 min"
                )
            )
        }

        if missingLocationCount > 0 {
            output.append(
                OpsTask(
                    id: "location-cleanup",
                    title: "Clean Up Location Data",
                    detail: "\(missingLocationCount) item(s) have no location. Fixing this reduces count time and mis-picks.",
                    actionTitle: "Open Zone Mission",
                    action: .zoneMission,
                    impact: .medium,
                    estimate: "5 min"
                )
            )
        }

        output.append(
            OpsTask(
                id: "kpi-review",
                title: "Check KPI Health",
                detail: "Review stockout risk, dead stock, and days of cover before closing out the day.",
                actionTitle: "Open KPI Dashboard",
                action: .kpiDashboard,
                impact: .foundation,
                estimate: "4 min"
            )
        )

        return output
    }

    private var completedCount: Int {
        tasks.filter { completedTaskIDs.contains($0.id) }.count
    }

    private var progressValue: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(completedCount) / Double(tasks.count)
    }

    private var workspaceKey: String {
        authStore.activeWorkspaceID?.uuidString ?? "all"
    }

    private var todayKey: String {
        Self.dayFormatter.string(from: Date())
    }

    private var completionKey: String {
        "inventory.opsbrief.completed.\(workspaceKey).\(todayKey)"
    }

    private var auditKey: String {
        "inventory.opsbrief.audit.\(workspaceKey)"
    }

    private var entriesLast7Days: [OpsCompletionEvent] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        return auditEntries.filter { $0.completedAt >= start }
    }

    private var contributorCountsLast7Days: [(name: String, count: Int)] {
        let grouped = Dictionary(grouping: entriesLast7Days, by: { $0.actorName })
        return grouped
            .map { key, value in
                (name: key, count: value.count)
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var topContributorLast7Days: (name: String, count: Int)? {
        contributorCountsLast7Days.first
    }

    private var trendPoints: [OpsTrendPoint] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        var points: [OpsTrendPoint] = []

        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday) else { continue }
            let dayKey = Self.dayFormatter.string(from: day)
            let count = auditEntries.filter { Self.dayFormatter.string(from: $0.completedAt) == dayKey }.count
            let label: String
            if offset == 0 {
                label = "Today"
            } else {
                label = day.formatted(.dateTime.weekday(.abbreviated))
            }
            points.append(
                OpsTrendPoint(
                    id: dayKey,
                    label: label,
                    count: count,
                    isToday: offset == 0
                )
            )
        }

        return points
    }

    private var maxTrendCount: Int {
        max(1, trendPoints.map(\.count).max() ?? 1)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("One screen. Highest-impact actions first.")
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Use this brief at shift start to reduce stockouts, tighten count freshness, and keep planning data clean.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.56)
    }

    private var scorecard: some View {
        sectionCard(title: "Signal Snapshot") {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                metricTile(title: "Urgent Risks", value: "\(urgentReplenishmentCount)", tint: .orange)
                metricTile(title: "Stale Counts", value: "\(staleItemCount)", tint: Theme.accentDeep)
                metricTile(title: "Data Gaps", value: "\(missingDemandDataCount)", tint: .red)
                metricTile(title: "No Location", value: "\(missingLocationCount)", tint: Theme.textSecondary)
                metricTile(title: "Sync Backlog", value: "\(reconnectBrief.unsyncedCount)", tint: reconnectBrief.failedCount > 0 ? .red : .orange)
                metricTile(title: "Critical Confidence", value: "\(confidenceOverview.criticalCount)", tint: confidenceOverview.criticalCount > 0 ? .red : Theme.accentDeep)
            }
        }
    }

    private var progressCard: some View {
        sectionCard(title: "Today's Progress") {
            ProgressView(value: progressValue)
                .tint(Theme.accent)

            HStack {
                Text("\(completedCount)/\(tasks.count) tasks complete")
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Reset Today") {
                    resetToday()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var accountabilityCard: some View {
        sectionCard(title: "Team Accountability") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Completions (7d)")
                        .font(Theme.font(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(entriesLast7Days.count)")
                        .font(Theme.font(22, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Contributors")
                        .font(Theme.font(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(contributorCountsLast7Days.count)")
                        .font(Theme.font(22, weight: .semibold))
                        .foregroundStyle(Theme.accentDeep)
                }
            }

            if let leader = topContributorLast7Days {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Top contributor: \(leader.name) (\(leader.count))")
                        .font(Theme.font(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No completions logged in the last 7 days.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var trendCard: some View {
        sectionCard(title: "7-Day Completion Trend") {
            ForEach(trendPoints) { point in
                HStack(spacing: 10) {
                    Text(point.label)
                        .font(Theme.font(11, weight: .semibold))
                        .foregroundStyle(point.isToday ? Theme.textPrimary : Theme.textSecondary)
                        .frame(width: 48, alignment: .leading)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.subtleBorder.opacity(0.45))
                            .frame(height: 8)

                        let widthFraction = CGFloat(point.count) / CGFloat(maxTrendCount)
                        Capsule()
                            .fill(point.isToday ? Theme.accent : Theme.accentDeep.opacity(0.7))
                            .frame(width: max(8, widthFraction * 150), height: 8)
                    }

                    Text("\(point.count)")
                        .font(Theme.font(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private var tasksCard: some View {
        sectionCard(title: "Action Queue") {
            if tasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No active actions yet.")
                        .font(Theme.font(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Add starter inventory or update item activity to generate a daily operations queue.")
                        .font(Theme.font(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .inventoryCard(cornerRadius: 12, emphasis: 0.24)
            } else {
                ForEach(tasks) { task in
                    taskRow(task)
                }
            }
        }
    }

    private var activityCard: some View {
        sectionCard(title: "Recent Activity") {
            if auditEntries.isEmpty {
                Text("Task completions will appear here with user and timestamp.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(auditEntries.prefix(8))) { entry in
                    activityRow(entry)
                }
            }
        }
    }

    private func activityRow(_ entry: OpsCompletionEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.taskTitle)
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(entry.completedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.font(10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            Text("\(entry.actorName) • \(entry.actorRole)")
                .font(Theme.font(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func taskRow(_ task: OpsTask) -> some View {
        let isDone = completedTaskIDs.contains(task.id)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Button {
                    toggleTaskCompletion(task)
                } label: {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isDone ? Theme.accent : Theme.textTertiary)
                }
                .buttonStyle(.plain)

                Text(task.title)
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Text(task.impact.title.uppercased())
                    .font(Theme.font(9, weight: .bold))
                    .foregroundStyle(task.impact.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(task.impact.tint.opacity(0.16))
                    )
            }

            Text(task.detail)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            HStack {
                Text("Est: \(task.estimate)")
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button(task.actionTitle) {
                    startTask(task)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
        .opacity(isDone ? 0.7 : 1)
    }

    private func metricTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.font(11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.font(22, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inventoryCard(cornerRadius: 14, emphasis: 0.2)
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

    private func toggleTaskCompletion(_ task: OpsTask) {
        if completedTaskIDs.contains(task.id) {
            completedTaskIDs.remove(task.id)
        } else {
            completedTaskIDs.insert(task.id)
            recordCompletionIfNeeded(for: task)
        }
        persistCompletionState()
    }

    private func markTaskCompleted(_ task: OpsTask) {
        guard !completedTaskIDs.contains(task.id) else { return }
        completedTaskIDs.insert(task.id)
        recordCompletionIfNeeded(for: task)
        persistCompletionState()
    }

    private func startTask(_ task: OpsTask) {
        markTaskCompleted(task)

        switch task.action {
        case .replenishment:
            guidanceStore.markFlowEngaged(.replenishment)
            isPresentingReplenishment = true
        case .zoneMission:
            guidanceStore.markFlowEngaged(.zoneMission)
            isPresentingZoneMission = true
        case .kpiDashboard:
            isPresentingKPI = true
        case .guidedHelp:
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guidanceStore.openGuideCenter()
            }
        case .integrationHub:
            isPresentingIntegrationHub = true
        }
    }

    private func recordCompletionIfNeeded(for task: OpsTask) {
        let actorName = authStore.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "User"
            : authStore.displayName
        if hasLoggedCompletionToday(taskID: task.id, actorName: actorName) {
            return
        }

        let entry = OpsCompletionEvent(
            id: UUID(),
            taskID: task.id,
            taskTitle: task.title,
            actorName: actorName,
            actorRole: authStore.currentRole.title,
            completedAt: Date()
        )
        auditEntries.insert(entry, at: 0)
        trimAndPersistAuditEntries()
    }

    private func hasLoggedCompletionToday(taskID: String, actorName: String) -> Bool {
        let key = todayKey
        return auditEntries.contains { entry in
            entry.taskID == taskID
                && entry.actorName == actorName
                && Self.dayFormatter.string(from: entry.completedAt) == key
        }
    }

    private func loadCompletionState() {
        let stored = UserDefaults.standard.stringArray(forKey: completionKey) ?? []
        completedTaskIDs = Set(stored)
    }

    private func persistCompletionState() {
        UserDefaults.standard.set(Array(completedTaskIDs), forKey: completionKey)
    }

    private func loadAuditEntries() {
        guard let data = UserDefaults.standard.data(forKey: auditKey),
              let decoded = try? JSONDecoder().decode([OpsCompletionEvent].self, from: data) else {
            auditEntries = []
            return
        }
        auditEntries = decoded.sorted { $0.completedAt > $1.completedAt }
    }

    private func trimAndPersistAuditEntries() {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -90, to: Date()) ?? Date.distantPast
        auditEntries = auditEntries
            .filter { $0.completedAt >= cutoff }
            .sorted { $0.completedAt > $1.completedAt }

        if auditEntries.count > 400 {
            auditEntries = Array(auditEntries.prefix(400))
        }

        guard let data = try? JSONEncoder().encode(auditEntries) else { return }
        UserDefaults.standard.set(data, forKey: auditKey)
    }

    private func resetToday() {
        completedTaskIDs.removeAll()
        persistCompletionState()
    }
}
