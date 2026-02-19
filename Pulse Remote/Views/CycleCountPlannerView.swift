import SwiftUI
import CoreData

private enum CycleCountPlannerAlert: Identifiable {
    case applied(itemCount: Int, estimatedMinutes: Int)

    var id: String {
        switch self {
        case .applied(let itemCount, let estimatedMinutes):
            return "applied-\(itemCount)-\(estimatedMinutes)"
        }
    }
}

struct CycleCountPlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var dataController: InventoryDataController
    @EnvironmentObject private var platformStore: PlatformStore
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.name, ascending: true)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var mode: CountPlanMode = .balanced
    @State private var includeRoutine = false
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var sessionStartedAt = Date()
    @State private var activeAlert: CycleCountPlannerAlert?

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    planningControlsCard
                    summaryCard
                    queueCard
                    actionCard
                }
                .padding(16)
            }
        }
        .navigationTitle("Cycle Count Planner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .tint(Theme.accent)
        .onAppear {
            seedSelection(force: true)
        }
        .onChange(of: mode) { _, _ in
            seedSelection(force: true)
        }
        .onChange(of: includeRoutine) { _, _ in
            seedSelection(force: true)
        }
        .onChange(of: workspaceItems.count) { _, _ in
            seedSelection()
        }
        .onChange(of: authStore.activeWorkspaceID) { _, _ in
            sessionStartedAt = Date()
            seedSelection(force: true)
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .applied(let itemCount, let estimatedMinutes):
                return Alert(
                    title: Text("Cycle Count Logged"),
                    message: Text("\(itemCount) item(s) marked counted. Estimated floor time: \(estimatedMinutes)m."),
                    dismissButton: .default(Text("Great"))
                )
            }
        }
    }

    private var workspaceItems: [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(authStore.activeWorkspaceID) }
    }

    private var activeWorkspaceKey: String {
        authStore.activeWorkspaceID?.uuidString ?? "all"
    }

    private var correctionCountsByItemID: [UUID: Int] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        var output: [UUID: Int] = [:]
        for event in platformStore.inventoryEvents {
            guard event.workspaceKey == activeWorkspaceKey else { continue }
            guard event.createdAt >= cutoff else { continue }
            guard let itemID = event.itemID else { continue }
            let isCorrectionLike = event.type == .countCorrection || (event.type == .adjustment && event.deltaUnits < 0)
            guard isCorrectionLike else { continue }
            output[itemID, default: 0] += 1
        }
        return output
    }

    private var planInputs: [CountPlanInput] {
        let correctionMap = correctionCountsByItemID
        return workspaceItems.map { item in
            let demand = max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0)
            let leadTime = max(0, Int(item.leadTimeDays))
            return CountPlanInput(
                id: item.id,
                itemName: item.name.isEmpty ? "Unnamed Item" : item.name,
                locationLabel: item.location,
                onHandUnits: item.totalUnitsOnHand,
                averageDailyUsage: demand,
                leadTimeDays: leadTime,
                lastCountedAt: item.safeUpdatedAt,
                missingBarcode: item.barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                missingPlanningInputs: demand <= 0 || leadTime <= 0,
                recentCorrectionCount: correctionMap[item.id, default: 0]
            )
        }
    }

    private var planCandidates: [CountPlanCandidate] {
        CycleCountPlannerEngine.buildPlan(
            inputs: planInputs,
            mode: mode,
            now: Date(),
            includeRoutine: includeRoutine
        )
    }

    private var summary: CountPlanSummary {
        CycleCountPlannerEngine.summarize(candidates: planCandidates)
    }

    private var selectedCandidates: [CountPlanCandidate] {
        planCandidates.filter { selectedItemIDs.contains($0.id) }
    }

    private var selectedEstimatedMinutes: Int {
        let seconds = selectedCandidates.reduce(0) { $0 + $1.estimatedSeconds }
        return Int(ceil(Double(seconds) / 60.0))
    }

    private var highRiskSelectedCount: Int {
        selectedCandidates.filter { $0.band == .critical || $0.band == .high }.count
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shrink-safe counts with less walking.")
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Queue the highest-risk SKUs first, batch your cycle count, and log a session in one tap.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.54)
    }

    private var planningControlsCard: some View {
        sectionCard(title: "Planning Controls") {
            Picker("Mode", selection: $mode) {
                ForEach(CountPlanMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("cycleplanner.modePicker")

            HStack {
                Text(mode.subtitle)
                    .font(Theme.font(11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("Target \(mode.targetDurationMinutes)m")
                    .font(Theme.font(11, weight: .semibold))
                    .foregroundStyle(Theme.accentDeep)
            }

            Toggle("Include routine checks", isOn: $includeRoutine)
                .font(Theme.font(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)

            HStack(spacing: 10) {
                Button("Select All") {
                    selectedItemIDs = Set(planCandidates.map(\.id))
                }
                .buttonStyle(.bordered)

                Button("Clear") {
                    selectedItemIDs.removeAll()
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("\(selectedItemIDs.count) selected")
                    .font(Theme.font(11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var summaryCard: some View {
        sectionCard(title: "Plan Snapshot") {
            HStack(spacing: 8) {
                metricPill(title: "Critical", value: "\(summary.criticalCount)", tint: .red)
                metricPill(title: "High", value: "\(summary.highCount)", tint: .orange)
                metricPill(title: "Medium", value: "\(summary.mediumCount)", tint: .blue)
                metricPill(title: "Routine", value: "\(summary.routineCount)", tint: Theme.textTertiary)
            }

            HStack(spacing: 10) {
                Label("\(summary.candidateCount) queued", systemImage: "checklist")
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Label("\(summary.estimatedMinutes)m est", systemImage: "clock")
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Theme.accentDeep)
            }

            if let zone = summary.recommendedZoneLabel {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Focus zone: \(zone)")
                        .font(Theme.font(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var queueCard: some View {
        sectionCard(title: "Recommended Queue") {
            if planCandidates.isEmpty {
                Text(workspaceItems.isEmpty ? "Add items to build your first cycle count queue." : "No items matched your current mode.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(planCandidates) { candidate in
                    queueRow(candidate)

                    if candidate.id != planCandidates.last?.id {
                        Divider()
                            .background(Theme.subtleBorder)
                            .padding(.leading, 40)
                    }
                }
            }
        }
    }

    private var actionCard: some View {
        sectionCard(title: "Apply Session") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected queue")
                        .font(Theme.font(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(selectedCandidates.count) items • \(selectedEstimatedMinutes)m • \(highRiskSelectedCount) high risk")
                        .font(Theme.font(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
            }

            Button {
                markSelectedAsCounted()
            } label: {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Mark Selected Counted")
                        .font(Theme.font(13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCandidates.isEmpty)
            .accessibilityIdentifier("cycleplanner.markCounted")
        }
    }

    private func queueRow(_ candidate: CountPlanCandidate) -> some View {
        Button {
            toggleSelection(candidate.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selectedItemIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selectedItemIDs.contains(candidate.id) ? Theme.accent : Theme.textTertiary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(candidate.itemName)
                            .font(Theme.font(13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text(candidate.band.title.uppercased())
                            .font(Theme.font(9, weight: .bold))
                            .foregroundStyle(priorityTextColor(candidate.band))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(priorityFillColor(candidate.band))
                            )
                    }

                    HStack(spacing: 10) {
                        Label(candidate.locationLabel, systemImage: "location")
                            .font(Theme.font(11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)

                        Label("\(candidate.onHandUnits) units", systemImage: "shippingbox")
                            .font(Theme.font(11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Text(candidate.reasons.prefix(2).joined(separator: " • "))
                        .font(Theme.font(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        Text("Score \(candidate.score)")
                            .font(Theme.font(10, weight: .semibold))
                            .foregroundStyle(Theme.accentDeep)
                        Text("\(candidate.daysSinceCount)d since count")
                            .font(Theme.font(10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                        Spacer()
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(12)
            .inventoryCard(cornerRadius: 14, emphasis: 0.30)
        }
        .padding(14)
        .inventoryCard(cornerRadius: 16, emphasis: 0.46)
    }

    private func metricPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.font(13, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(Theme.font(10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.subtleBorder, lineWidth: 1)
                )
        )
    }

    private func priorityFillColor(_ band: CountPriorityBand) -> Color {
        switch band {
        case .critical:
            return Color.red.opacity(0.16)
        case .high:
            return Color.orange.opacity(0.18)
        case .medium:
            return Color.blue.opacity(0.16)
        case .low:
            return Theme.accentSoft.opacity(0.30)
        }
    }

    private func priorityTextColor(_ band: CountPriorityBand) -> Color {
        switch band {
        case .critical:
            return .red
        case .high:
            return .orange
        case .medium:
            return .blue
        case .low:
            return Theme.accentDeep
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    private func seedSelection(force: Bool = false) {
        let currentIDs = Set(planCandidates.map(\.id))
        guard force || selectedItemIDs.isEmpty else {
            selectedItemIDs = selectedItemIDs.intersection(currentIDs)
            return
        }
        selectedItemIDs = currentIDs
    }

    private func markSelectedAsCounted() {
        let selectedItems = workspaceItems.filter { selectedItemIDs.contains($0.id) }
        guard !selectedItems.isEmpty else { return }

        _ = platformStore.createGuardBackupIfNeeded(
            reason: "Cycle planner apply",
            from: workspaceItems,
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName,
            cooldownMinutes: 120
        )

        let now = Date()
        for item in selectedItems {
            item.updatedAt = now
        }
        dataController.save()

        platformStore.recordCountSession(
            type: .stockCount,
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName,
            startedAt: sessionStartedAt,
            finishedAt: now,
            itemCount: selectedItems.count,
            highVarianceCount: min(highRiskSelectedCount, selectedItems.count),
            blindModeEnabled: true,
            targetDurationMinutes: mode.targetDurationMinutes,
            zoneTitle: summary.recommendedZoneLabel,
            note: "Cycle Count Planner quick session."
        )

        sessionStartedAt = Date()
        Haptics.success()
        activeAlert = .applied(itemCount: selectedItems.count, estimatedMinutes: selectedEstimatedMinutes)
        seedSelection(force: true)
    }
}
