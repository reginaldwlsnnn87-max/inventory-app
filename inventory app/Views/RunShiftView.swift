import SwiftUI
import CoreData

private enum RunShiftTaskAction {
    case countQueue
    case exceptions
    case replenishment
    case closeShift
}

private struct RunShiftTask: Identifiable {
    let id: String
    let title: String
    let detail: String
    let estimateMinutes: Int
    let actionTitle: String
    let action: RunShiftTaskAction
}

private enum RunShiftAlert: Identifiable {
    case shiftClosed(minutesSaved: Int, counts: Int, shrinkUnits: Int64)
    case message(String)

    var id: String {
        switch self {
        case .shiftClosed(let minutesSaved, let counts, let shrinkUnits):
            return "shift-closed-\(minutesSaved)-\(counts)-\(shrinkUnits)"
        case .message(let text):
            return "message-\(text)"
        }
    }
}

struct RunShiftView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var platformStore: PlatformStore
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.updatedAt, ascending: true)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var completedTaskIDs: Set<String> = []
    @State private var isPresentingCountQueue = false
    @State private var isPresentingExceptions = false
    @State private var isPresentingReplenishment = false
    @State private var activeAlert: RunShiftAlert?
    @State private var pilotExportURL: URL?

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    queueSnapshotCard
                    valueScoreCard
                    tasksCard
                }
                .padding(16)
            }
        }
        .navigationTitle("Run Shift")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .tint(Theme.accent)
        .sheet(isPresented: $isPresentingCountQueue) {
            NavigationStack {
                CycleCountPlannerView()
            }
        }
        .sheet(isPresented: $isPresentingExceptions) {
            NavigationStack {
                ExceptionFeedView()
            }
        }
        .sheet(isPresented: $isPresentingReplenishment) {
            NavigationStack {
                ReplenishmentPlannerView()
            }
        }
        .onAppear {
            loadCompletionState()
        }
        .onChange(of: authStore.activeWorkspaceID) { _, _ in
            loadCompletionState()
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .shiftClosed(let minutesSaved, let counts, let shrinkUnits):
                return Alert(
                    title: Text("Shift Closed"),
                    message: Text("Great run. Shift saved \(minutesSaved)m, completed \(counts) counts, and resolved \(shrinkUnits) shrink-risk units."),
                    dismissButton: .default(Text("Done"))
                )
            case .message(let text):
                return Alert(
                    title: Text("Run Shift"),
                    message: Text(text),
                    dismissButton: .default(Text("OK"))
                )
            }
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

    private var workspaceKey: String {
        authStore.activeWorkspaceID?.uuidString ?? "all"
    }

    private var todayKey: String {
        Self.dayFormatter.string(from: Date())
    }

    private var completionKey: String {
        "inventory.runshift.completed.\(workspaceKey).\(todayKey)"
    }

    private var correctionCountsByItemID: [UUID: Int] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        var output: [UUID: Int] = [:]

        for event in platformStore.inventoryEvents {
            guard event.workspaceKey == workspaceKey else { continue }
            guard event.createdAt >= cutoff else { continue }
            guard let itemID = event.itemID else { continue }
            let isCorrectionLike = event.type == .countCorrection || (event.type == .adjustment && event.deltaUnits < 0)
            guard isCorrectionLike else { continue }
            output[itemID, default: 0] += 1
        }

        return output
    }

    private var countQueueCount: Int {
        let correctionMap = correctionCountsByItemID
        let planInputs = workspaceItems.map { item in
            CountPlanInput(
                id: item.id,
                itemName: item.name.isEmpty ? "Unnamed Item" : item.name,
                locationLabel: item.location,
                onHandUnits: item.totalUnitsOnHand,
                averageDailyUsage: max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0),
                leadTimeDays: max(0, Int(item.leadTimeDays)),
                lastCountedAt: item.safeUpdatedAt,
                missingBarcode: item.barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                missingPlanningInputs: max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0) <= 0 || item.leadTimeDays <= 0,
                recentCorrectionCount: correctionMap[item.id, default: 0]
            )
        }

        return CycleCountPlannerEngine.buildPlan(
            inputs: planInputs,
            mode: .express,
            now: Date(),
            includeRoutine: false
        ).count
    }

    private var exceptionCount: Int {
        let staleCutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        var total = 0

        for item in workspaceItems {
            let demand = max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0)
            let leadTime = max(0, Double(item.leadTimeDays))
            let onHand = Double(max(0, item.totalUnitsOnHand))
            if demand > 0, leadTime > 0 {
                let daysOfCover = onHand / demand
                let threshold = max(1, leadTime * 0.5)
                if onHand == 0 || daysOfCover <= threshold {
                    total += 1
                }
            } else {
                total += 1
            }

            if item.safeUpdatedAt < staleCutoff {
                total += 1
            }

            if item.barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                total += 1
            }
        }

        return total
    }

    private var replenishmentCount: Int {
        workspaceItems.filter { item in
            let demand = max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0)
            let leadTime = max(0, Double(item.leadTimeDays))
            guard demand > 0, leadTime > 0 else { return false }
            let onHand = max(0, item.totalUnitsOnHand)
            let reorderPoint = Int64((demand * leadTime).rounded(.up)) + max(0, item.safetyStockUnits)
            let baseSuggestion = max(0, reorderPoint - onHand)
            let suggested = item.adjustedSuggestedOrderUnits(from: baseSuggestion)
            return suggested > 0
        }.count
    }

    private var shiftValue: ValueTrackingSnapshot {
        platformStore.valueTrackingSnapshot(
            workspaceID: authStore.activeWorkspaceID,
            window: .shift
        )
    }

    private var weekValue: ValueTrackingSnapshot {
        platformStore.valueTrackingSnapshot(
            workspaceID: authStore.activeWorkspaceID,
            window: .week
        )
    }

    private var todayPilotMetrics: PilotDailyMetrics {
        platformStore.pilotDailyMetrics(workspaceID: authStore.activeWorkspaceID)
    }

    private var tasks: [RunShiftTask] {
        [
            RunShiftTask(
                id: "count-queue",
                title: "Count Queue",
                detail: "\(countQueueCount) high-risk items ready to count.",
                estimateMinutes: max(4, min(18, countQueueCount * 2)),
                actionTitle: "Open Count Queue",
                action: .countQueue
            ),
            RunShiftTask(
                id: "exceptions",
                title: "Exception Sweep",
                detail: "\(exceptionCount) issues need cleanup (risk, stale, or data gaps).",
                estimateMinutes: max(5, min(20, max(1, exceptionCount / 2))),
                actionTitle: "Open Exceptions",
                action: .exceptions
            ),
            RunShiftTask(
                id: "replenishment",
                title: "Replenishment Pass",
                detail: "\(replenishmentCount) items are due for reorder planning.",
                estimateMinutes: max(4, min(16, max(1, replenishmentCount / 2))),
                actionTitle: "Open Replenishment",
                action: .replenishment
            ),
            RunShiftTask(
                id: "close-shift",
                title: "Done",
                detail: "Close the shift and lock your progress.",
                estimateMinutes: 1,
                actionTitle: "Complete Shift",
                action: .closeShift
            )
        ]
    }

    private var canCloseShift: Bool {
        completedTaskIDs.contains("count-queue")
            && completedTaskIDs.contains("exceptions")
            && completedTaskIDs.contains("replenishment")
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("One flow for the whole shift.")
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Run count queue, clear exceptions, handle replenishment, then close out with confidence.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.56)
    }

    private var queueSnapshotCard: some View {
        sectionCard(title: "Today Queue") {
            HStack(spacing: 10) {
                metricChip(title: "Count Queue", value: "\(countQueueCount)", tint: Theme.accentDeep)
                metricChip(title: "Exceptions", value: "\(exceptionCount)", tint: .orange)
                metricChip(title: "Replenishment", value: "\(replenishmentCount)", tint: .red)
            }
        }
    }

    private var valueScoreCard: some View {
        sectionCard(title: "Proof Of Value") {
            HStack(spacing: 10) {
                valueColumn(title: "This Shift", snapshot: shiftValue)
                valueColumn(title: "Last 7 Days", snapshot: weekValue)
            }

            Divider()
                .background(Theme.subtleBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Auto Pilot Metrics (Today)")
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                valueLine("Count sessions", "\(todayPilotMetrics.countSessionRuns)")
                valueLine("Items counted", "\(todayPilotMetrics.itemsCounted)")
                valueLine("Exceptions resolved", "\(todayPilotMetrics.exceptionsResolved)")
                valueLine("Adjustments", "\(todayPilotMetrics.adjustmentCount)")

                if let firstStart = todayPilotMetrics.firstCountStartedAt {
                    valueLine("First count start", firstStart.formatted(date: .omitted, time: .shortened))
                }
                if let lastFinish = todayPilotMetrics.lastCountFinishedAt {
                    valueLine("Last count finish", lastFinish.formatted(date: .omitted, time: .shortened))
                }
            }

            Button("Export 14-Day Pilot CSV") {
                exportPilotValidationCSV()
            }
            .buttonStyle(.borderedProminent)

            if let pilotExportURL {
                ShareLink(item: pilotExportURL) {
                    Label("Share latest pilot export", systemImage: "square.and.arrow.up")
                        .font(Theme.font(11, weight: .semibold))
                }
            }
        }
    }

    private var tasksCard: some View {
        sectionCard(title: "Task Flow") {
            ForEach(tasks) { task in
                taskRow(task)
                if task.id != tasks.last?.id {
                    Divider()
                        .background(Theme.subtleBorder)
                        .padding(.leading, 40)
                }
            }
        }
    }

    private func taskRow(_ task: RunShiftTask) -> some View {
        let isDone = completedTaskIDs.contains(task.id)
        let actionDisabled = task.action == .closeShift ? !canCloseShift : false

        return HStack(alignment: .top, spacing: 10) {
            Button {
                toggleDone(task.id)
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isDone ? Theme.accent : Theme.textTertiary)
                    .padding(.top, 2)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(task.title)
                        .font(Theme.font(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(task.estimateMinutes)m")
                        .font(Theme.font(10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }

                Text(task.detail)
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(task.actionTitle) {
                    handleTaskAction(task)
                }
                .buttonStyle(.borderedProminent)
                .disabled(actionDisabled)
                .opacity(actionDisabled ? 0.55 : 1)
            }
        }
        .padding(.vertical, 4)
    }

    private func valueColumn(title: String, snapshot: ValueTrackingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.font(11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            valueLine("Minutes saved", "\(snapshot.minutesSaved)")
            valueLine("Counts completed", "\(snapshot.countsCompleted)")
            valueLine("Shrink-risk resolved", "\(snapshot.shrinkRiskResolved)")
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

    private func valueLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.font(10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(value)
                .font(Theme.font(11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func metricChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.font(10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(Theme.font(14, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
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
            .inventoryCard(cornerRadius: 14, emphasis: 0.28)
        }
        .padding(14)
        .inventoryCard(cornerRadius: 16, emphasis: 0.44)
    }

    private func handleTaskAction(_ task: RunShiftTask) {
        switch task.action {
        case .countQueue:
            isPresentingCountQueue = true
            markDone(task.id)
        case .exceptions:
            isPresentingExceptions = true
            markDone(task.id)
        case .replenishment:
            isPresentingReplenishment = true
            markDone(task.id)
        case .closeShift:
            guard canCloseShift else { return }
            markDone(task.id)
            platformStore.recordShiftRunCompletion(
                workspaceID: authStore.activeWorkspaceID,
                actorName: authStore.displayName,
                countQueueSize: countQueueCount,
                exceptionCount: exceptionCount,
                replenishmentCount: replenishmentCount
            )
            activeAlert = .shiftClosed(
                minutesSaved: shiftValue.minutesSaved,
                counts: shiftValue.countsCompleted,
                shrinkUnits: shiftValue.shrinkRiskResolved
            )
            Haptics.success()
        }
    }

    private func toggleDone(_ taskID: String) {
        if completedTaskIDs.contains(taskID) {
            completedTaskIDs.remove(taskID)
        } else {
            completedTaskIDs.insert(taskID)
        }
        saveCompletionState()
    }

    private func markDone(_ taskID: String) {
        guard !completedTaskIDs.contains(taskID) else { return }
        completedTaskIDs.insert(taskID)
        saveCompletionState()
    }

    private func exportPilotValidationCSV() {
        do {
            let url = try platformStore.exportPilotValidationCSV(
                workspaceID: authStore.activeWorkspaceID,
                actorName: authStore.displayName,
                days: 14
            )
            pilotExportURL = url
            activeAlert = .message("Pilot CSV exported.")
        } catch {
            activeAlert = .message("Pilot CSV export failed.")
        }
    }

    private func loadCompletionState() {
        guard let data = UserDefaults.standard.data(forKey: completionKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            completedTaskIDs = []
            return
        }
        completedTaskIDs = Set(decoded)
    }

    private func saveCompletionState() {
        let ordered = Array(completedTaskIDs).sorted()
        if let data = try? JSONEncoder().encode(ordered) {
            UserDefaults.standard.set(data, forKey: completionKey)
        }
    }
}
