import SwiftUI
import CoreData

private enum ZoneFilter: Hashable, Identifiable {
    case all
    case location(String)
    case unassigned

    var id: String {
        switch self {
        case .all:
            return "all"
        case .location(let value):
            return "location-\(value)"
        case .unassigned:
            return "unassigned"
        }
    }

    var title: String {
        switch self {
        case .all:
            return "All Zones"
        case .location(let value):
            return value
        case .unassigned:
            return "No Location"
        }
    }
}

private enum ZoneVarianceReason: String, CaseIterable, Identifiable {
    case countError = "Count Error"
    case receivingError = "Receiving Error"
    case damageWaste = "Damage / Waste"
    case theftLoss = "Theft / Loss"
    case transferError = "Transfer Error"
    case other = "Other"

    var id: String { rawValue }
}

private enum ZoneMissionAlert: Identifiable {
    case invalidCount(itemName: String)
    case missingCounts(count: Int)
    case missingReasons(count: Int)
    case applied(summary: String)

    var id: String {
        switch self {
        case .invalidCount(let itemName):
            return "invalid-\(itemName)"
        case .missingCounts(let count):
            return "missing-counts-\(count)"
        case .missingReasons(let count):
            return "missing-reasons-\(count)"
        case .applied(let summary):
            return "applied-\(summary)"
        }
    }
}

private enum ZoneMissionPaceStatus {
    case preparing
    case ahead
    case atRisk
    case behind

    var title: String {
        switch self {
        case .preparing:
            return "Preparing"
        case .ahead:
            return "Ahead"
        case .atRisk:
            return "At Risk"
        case .behind:
            return "Behind"
        }
    }

    var tint: Color {
        switch self {
        case .preparing:
            return Theme.textSecondary
        case .ahead:
            return .green
        case .atRisk:
            return .orange
        case .behind:
            return .red
        }
    }
}

struct ZoneMissionView: View {
    let preferredZone: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: InventoryDataController
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var guidanceStore: GuidanceStore
    @EnvironmentObject private var platformStore: PlatformStore
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.name, ascending: true)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var selectedZone: ZoneFilter = .all
    @State private var blindModeEnabled = true
    @State private var showExpectedInReview = false
    @State private var varianceThresholdPercent = 8.0
    @State private var targetDurationMinutes = 25
    @State private var missionStartedAt: Date?
    @State private var currentIndex = 0
    @State private var inputs: [UUID: String] = [:]
    @State private var reasonByItemID: [UUID: ZoneVarianceReason] = [:]
    @State private var isReviewMode = false
    @State private var activeAlert: ZoneMissionAlert?
    @State private var hasInitializedZone = false
    @State private var hasAppliedPreferredZone = false
    @State private var isShowingWalkthrough = false

    init(preferredZone: String? = nil) {
        self.preferredZone = preferredZone
    }

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    missionControlsCard

                    if zoneItems.isEmpty {
                        emptyZoneCard
                    } else if isReviewMode {
                        reviewCard
                    } else {
                        missionProgressCard
                        currentItemCard
                    }

                    actionCard
                }
                .padding(16)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("Zone Mission")
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
                .accessibilityLabel("How to use Zone Mission")
            }
        }
        .tint(Theme.accent)
        .sheet(isPresented: $isShowingWalkthrough) {
            ProcessWalkthroughView(
                flow: .zoneMission,
                showLaunchButton: false,
                onCompleted: {
                    guidanceStore.markFlowCompleted(.zoneMission)
                }
            )
        }
        .onAppear {
            initializeZoneIfNeeded()
            applyPreferredZoneIfNeeded()
        }
        .onChange(of: selectedZone) { _, _ in
            resetMission()
        }
        .onChange(of: authStore.activeWorkspaceID) { _, _ in
            hasInitializedZone = false
            hasAppliedPreferredZone = false
            initializeZoneIfNeeded()
            applyPreferredZoneIfNeeded()
        }
        .onChange(of: items.count) { _, _ in
            applyPreferredZoneIfNeeded()
        }
        .onChange(of: targetDurationMinutes) { _, newValue in
            platformStore.setDefaultTargetDurationMinutes(
                newValue,
                for: .zoneMission,
                workspaceID: authStore.activeWorkspaceID
            )
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .invalidCount(let itemName):
                return Alert(
                    title: Text("Invalid Number"),
                    message: Text("The value entered for \(itemName) is not valid."),
                    dismissButton: .default(Text("OK"))
                )
            case .missingCounts(let count):
                return Alert(
                    title: Text("Missing Counts"),
                    message: Text("Enter counts for \(count) remaining item(s) before finishing."),
                    dismissButton: .default(Text("OK"))
                )
            case .missingReasons(let count):
                return Alert(
                    title: Text("Reason Codes Needed"),
                    message: Text("Select reasons for \(count) high-variance item(s) before applying."),
                    dismissButton: .default(Text("OK"))
                )
            case .applied(let summary):
                return Alert(
                    title: Text("Mission Complete"),
                    message: Text(summary),
                    dismissButton: .default(Text("Done"))
                )
            }
        }
    }

    private var workspaceItems: [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(authStore.activeWorkspaceID) }
    }

    private var zoneFilters: [ZoneFilter] {
        var filters: [ZoneFilter] = [.all]
        let locationNames = Set(
            workspaceItems.compactMap { item -> String? in
                let trimmed = item.location.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        )
        .sorted()

        filters.append(contentsOf: locationNames.map { ZoneFilter.location($0) })

        let hasUnassigned = workspaceItems.contains { item in
            item.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if hasUnassigned {
            filters.append(.unassigned)
        }
        return filters
    }

    private var zoneItems: [InventoryItemEntity] {
        workspaceItems.filter { item in
            switch selectedZone {
            case .all:
                return true
            case .location(let value):
                return item.location.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(value) == .orderedSame
            case .unassigned:
                return item.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    private var currentItem: InventoryItemEntity? {
        guard !zoneItems.isEmpty else { return nil }
        let safeIndex = min(max(0, currentIndex), zoneItems.count - 1)
        return zoneItems[safeIndex]
    }

    private var countedItems: Int {
        zoneItems.filter { item in
            parsedCount(from: inputs[item.id], for: item) != nil
        }.count
    }

    private var progressValue: Double {
        guard !zoneItems.isEmpty else { return 0 }
        return Double(countedItems) / Double(zoneItems.count)
    }

    private var missionDurationSeconds: TimeInterval {
        guard let missionStartedAt else { return 0 }
        return max(0, Date().timeIntervalSince(missionStartedAt))
    }

    private var missionDurationMinutes: Double {
        missionDurationSeconds / 60
    }

    private var missionItemsPerMinute: Double {
        guard missionDurationMinutes > 0 else { return 0 }
        return Double(countedItems) / missionDurationMinutes
    }

    private var projectedMissionMinutes: Double? {
        guard countedItems > 0 else { return nil }
        return missionDurationMinutes / max(0.01, progressValue)
    }

    private var projectedMissionFinishAt: Date? {
        guard let missionStartedAt, let projectedMissionMinutes else { return nil }
        return missionStartedAt.addingTimeInterval(projectedMissionMinutes * 60)
    }

    private var missionPaceStatus: ZoneMissionPaceStatus {
        guard let projectedMissionMinutes else { return .preparing }
        let delta = projectedMissionMinutes - Double(targetDurationMinutes)
        if delta <= 0 {
            return .ahead
        }
        if delta <= Double(targetDurationMinutes) * 0.15 {
            return .atRisk
        }
        return .behind
    }

    private var varianceItems: [InventoryItemEntity] {
        zoneItems.filter { item in
            guard let entered = parsedCount(from: inputs[item.id], for: item) else { return false }
            return exceedsVarianceThreshold(for: item, entered: entered)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fast zone counting for teams on the move.")
                .font(Theme.font(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Pick a zone, run a one-by-one mission, then apply with automatic variance controls.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.52)
    }

    private var missionControlsCard: some View {
        sectionCard(title: "Mission Setup") {
            Picker("Zone", selection: $selectedZone) {
                ForEach(zoneFilters) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)

            Toggle("Blind mission mode", isOn: $blindModeEnabled)
                .font(Theme.font(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .disabled(missionStartedAt != nil)

            Stepper(value: $varianceThresholdPercent, in: 3...30, step: 1) {
                Text("Variance trigger: \(Int(varianceThresholdPercent))%")
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .disabled(missionStartedAt != nil)

            Stepper(value: $targetDurationMinutes, in: 5...180, step: 5) {
                Text("Target mission time: \(targetDurationMinutes)m")
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .disabled(missionStartedAt != nil)
        }
    }

    private var emptyZoneCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("No items in this zone")
                .font(Theme.font(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Pick a different zone or add locations to inventory items.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .inventoryCard(cornerRadius: 16, emphasis: 0.28)
    }

    private var missionProgressCard: some View {
        sectionCard(title: "Mission Progress") {
            ProgressView(value: progressValue)
                .tint(Theme.accent)

            HStack {
                metricChip("Counted", value: "\(countedItems)/\(zoneItems.count)")
                metricChip("Elapsed", value: elapsedString())
                metricChip("Stage", value: missionStartedAt == nil ? "Ready" : "Live")
            }

            HStack {
                metricChip("Speed", value: "\(formattedNumber(missionItemsPerMinute))/min")
                metricChip("Target", value: "\(targetDurationMinutes)m")
                metricChip(
                    "Projection",
                    value: projectedMissionMinutes.map { "\(formattedNumber($0))m" } ?? "-"
                )
            }

            HStack(spacing: 8) {
                Text("Status")
                    .font(Theme.font(11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(missionPaceStatus.title)
                    .font(Theme.font(11, weight: .semibold))
                    .foregroundStyle(missionPaceStatus.tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(missionPaceStatus.tint.opacity(0.14))
                    )
            }

            Text(missionPaceGuidance())
                .font(Theme.font(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var currentItemCard: some View {
        sectionCard(title: "Current Item") {
            if let item = currentItem {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.name.isEmpty ? "Unnamed Item" : item.name)
                        .font(Theme.font(17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(item.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No location set" : item.location)
                        .font(Theme.font(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)

                    if !blindModeEnabled {
                        Text("Expected: \(expectedLabel(for: item))")
                            .font(Theme.font(11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    TextField(
                        item.isLiquid ? "Enter gallons" : "Enter units",
                        text: inputBinding(for: item)
                    )
                    #if os(iOS)
                    .keyboardType(item.isLiquid ? .decimalPad : .numberPad)
                    #endif
                    .inventoryTextInputField()

                    HStack(spacing: 10) {
                        Button("Previous") {
                            currentIndex = max(0, currentIndex - 1)
                        }
                        .buttonStyle(.bordered)
                        .disabled(currentIndex == 0)

                        Button("Save & Next") {
                            saveAndAdvance()
                        }
                        .buttonStyle(.borderedProminent)

                        if currentIndex == zoneItems.count - 1 {
                            Button("Review") {
                                openReview()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } else {
                Text("Select a zone to begin.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var reviewCard: some View {
        sectionCard(title: "Mission Review") {
            Toggle("Show expected counts", isOn: $showExpectedInReview)
                .font(Theme.font(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)

            metricChip("High Variance", value: "\(varianceItems.count)")
            metricChip("Counted", value: "\(countedItems)/\(zoneItems.count)")

            if varianceItems.isEmpty {
                Text("No high-variance items detected.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(varianceItems) { item in
                    reviewVarianceRow(for: item)
                }
            }
        }
    }

    private func reviewVarianceRow(for item: InventoryItemEntity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.name.isEmpty ? "Unnamed Item" : item.name)
                .font(Theme.font(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            if showExpectedInReview {
                let expected = expectedLabel(for: item)
                let entered = enteredLabel(for: item)
                Text("Entered: \(entered) • Expected: \(expected)")
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            Picker("Variance Reason", selection: reasonBinding(for: item)) {
                Text("Select reason").tag(Optional<ZoneVarianceReason>.none)
                ForEach(ZoneVarianceReason.allCases) { reason in
                    Text(reason.rawValue).tag(Optional(reason))
                }
            }
            .pickerStyle(.menu)
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

    private var actionCard: some View {
        sectionCard(title: "Actions") {
            if missionStartedAt == nil {
                Button {
                    startMission()
                } label: {
                    Label("Start Mission", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(zoneItems.isEmpty)
                .opacity(zoneItems.isEmpty ? 0.55 : 1)
            } else if isReviewMode {
                Button {
                    finalizeMission()
                } label: {
                    Label("Apply Mission Counts", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(zoneItems.isEmpty)
                .opacity(zoneItems.isEmpty ? 0.55 : 1)

                Button("Back To Mission") {
                    isReviewMode = false
                }
                .buttonStyle(.bordered)
            } else {
                Button("Open Review") {
                    openReview()
                }
                .buttonStyle(.borderedProminent)
                .disabled(zoneItems.isEmpty)
                .opacity(zoneItems.isEmpty ? 0.55 : 1)
            }

            if missionStartedAt != nil {
                Button("Reset Mission") {
                    resetMission()
                }
                .buttonStyle(.bordered)
            }
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
        .inventoryCard(cornerRadius: 16, emphasis: 0.42)
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
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func initializeZoneIfNeeded() {
        guard !hasInitializedZone else { return }
        hasInitializedZone = true
        targetDurationMinutes = platformStore.defaultTargetDurationMinutes(
            for: .zoneMission,
            workspaceID: authStore.activeWorkspaceID
        )
        selectedZone = zoneFilters.first ?? .all
        resetMission()
    }

    private func applyPreferredZoneIfNeeded() {
        guard !hasAppliedPreferredZone else { return }
        guard let preferredZone, !preferredZone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            hasAppliedPreferredZone = true
            return
        }

        if preferredZone == AutomationStore.unassignedZoneKey {
            if zoneFilters.contains(where: { filter in
                if case .unassigned = filter { return true }
                return false
            }) {
                selectedZone = .unassigned
                resetMission()
                hasAppliedPreferredZone = true
            }
            return
        }

        if let matched = zoneFilters.first(where: { filter in
            if case .location(let value) = filter {
                return value.caseInsensitiveCompare(preferredZone) == .orderedSame
            }
            return false
        }) {
            selectedZone = matched
            resetMission()
            hasAppliedPreferredZone = true
        }
    }

    private func startMission() {
        missionStartedAt = Date()
        currentIndex = 0
        isReviewMode = false
        reasonByItemID = [:]
        inputs = [:]
    }

    private func resetMission() {
        missionStartedAt = nil
        currentIndex = 0
        isReviewMode = false
        inputs = [:]
        reasonByItemID = [:]
        showExpectedInReview = false
    }

    private func saveAndAdvance() {
        guard let currentItem else { return }
        guard parsedCount(from: inputs[currentItem.id], for: currentItem) != nil else {
            activeAlert = .invalidCount(itemName: currentItem.name)
            return
        }
        if currentIndex < zoneItems.count - 1 {
            currentIndex += 1
        } else {
            isReviewMode = true
        }
    }

    private func openReview() {
        let missing = zoneItems.filter { parsedCount(from: inputs[$0.id], for: $0) == nil }.count
        guard missing == 0 else {
            activeAlert = .missingCounts(count: missing)
            return
        }
        isReviewMode = true
    }

    private func finalizeMission() {
        var parsedCounts: [UUID: Double] = [:]
        var missing = 0
        for item in zoneItems {
            guard let parsed = parsedCount(from: inputs[item.id], for: item) else {
                missing += 1
                continue
            }
            parsedCounts[item.id] = parsed
        }

        guard missing == 0 else {
            activeAlert = .missingCounts(count: missing)
            return
        }

        let flagged = varianceItems.filter { item in
            guard parsedCounts[item.id] != nil else { return false }
            return reasonByItemID[item.id] == nil
        }
        guard flagged.isEmpty else {
            activeAlert = .missingReasons(count: flagged.count)
            return
        }

        _ = platformStore.createGuardBackupIfNeeded(
            reason: "Zone mission apply",
            from: workspaceItems,
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName,
            cooldownMinutes: 120
        )

        let now = Date()
        for item in zoneItems {
            guard let counted = parsedCounts[item.id] else { continue }
            let previous = defaultCount(for: item)
            let previousUnits = item.totalUnitsOnHand

            if item.isLiquid {
                item.applyTotalGallons(counted)
            } else {
                item.applyTotalNonLiquidUnits(Int64(max(0, counted.rounded())), resetLooseEaches: true)
            }

            if let reason = reasonByItemID[item.id], exceedsVarianceThreshold(for: item, entered: counted) {
                let line = "\(Date().formatted(date: .abbreviated, time: .shortened)) • Zone mission variance \(formattedCount(counted, for: item)) vs \(formattedCount(previous, for: item)) • Reason: \(reason.rawValue)"
                if item.notes.isEmpty {
                    item.notes = line
                } else {
                    item.notes += "\n\(line)"
                }
            }

            item.assignWorkspaceIfNeeded(authStore.activeWorkspaceID)
            item.updatedAt = now
            let reason = reasonByItemID[item.id]?.rawValue ?? "Zone mission count"
            platformStore.recordCountCorrection(
                item: item,
                previousUnits: previousUnits,
                newUnits: item.totalUnitsOnHand,
                actorName: authStore.displayName,
                workspaceID: authStore.activeWorkspaceID,
                source: "zone-mission",
                reason: reason
            )
        }

        dataController.save()
        Haptics.success()

        let sessionStart = missionStartedAt ?? now
        let varianceReviewedCount = varianceItems.count
        let elapsedMinutes = max(1, Int((missionDurationSeconds / 60).rounded()))
        let itemsPerMinute = zoneItems.isEmpty ? 0 : Double(zoneItems.count) / max(1, missionDurationSeconds / 60)
        let summary = "\(zoneItems.count) items counted in \(elapsedMinutes)m (\(String(format: "%.1f", itemsPerMinute))/min). \(varianceReviewedCount) high-variance items reviewed."

        platformStore.recordCountSession(
            type: .zoneMission,
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName,
            startedAt: sessionStart,
            finishedAt: now,
            itemCount: zoneItems.count,
            highVarianceCount: varianceReviewedCount,
            blindModeEnabled: blindModeEnabled,
            targetDurationMinutes: targetDurationMinutes,
            zoneTitle: selectedZone.title,
            note: "Zone mission count finalized."
        )

        resetMission()
        activeAlert = .applied(summary: summary)
    }

    private func defaultCount(for item: InventoryItemEntity) -> Double {
        if item.isLiquid {
            return item.totalGallonsOnHand
        }
        return Double(item.totalUnitsOnHand)
    }

    private func parsedCount(from raw: String?, for item: InventoryItemEntity) -> Double? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed), value >= 0 else { return nil }
        if item.isLiquid {
            return value
        }
        return value.rounded()
    }

    private func exceedsVarianceThreshold(for item: InventoryItemEntity, entered: Double) -> Bool {
        let expected = defaultCount(for: item)
        let absoluteVariance = abs(entered - expected)
        let percentVariance: Double
        if expected > 0 {
            percentVariance = (absoluteVariance / expected) * 100
        } else {
            percentVariance = entered > 0 ? 100 : 0
        }
        let minimumVariance = item.isLiquid ? 0.25 : 2
        return absoluteVariance >= minimumVariance && percentVariance >= varianceThresholdPercent
    }

    private func inputBinding(for item: InventoryItemEntity) -> Binding<String> {
        Binding(
            get: { inputs[item.id] ?? "" },
            set: { inputs[item.id] = $0 }
        )
    }

    private func reasonBinding(for item: InventoryItemEntity) -> Binding<ZoneVarianceReason?> {
        Binding(
            get: { reasonByItemID[item.id] },
            set: { newValue in
                if let newValue {
                    reasonByItemID[item.id] = newValue
                } else {
                    reasonByItemID.removeValue(forKey: item.id)
                }
            }
        )
    }

    private func enteredLabel(for item: InventoryItemEntity) -> String {
        guard let value = parsedCount(from: inputs[item.id], for: item) else { return "-" }
        return formattedCount(value, for: item)
    }

    private func expectedLabel(for item: InventoryItemEntity) -> String {
        formattedCount(defaultCount(for: item), for: item)
    }

    private func formattedCount(_ value: Double, for item: InventoryItemEntity) -> String {
        if item.isLiquid {
            let rounded = (value * 100).rounded() / 100
            var text = String(format: "%.2f", rounded)
            if text.contains(".") {
                text = text.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                text = text.replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
            }
            return "\(text) gal"
        }
        return "\(Int(value.rounded())) units"
    }

    private func elapsedString() -> String {
        guard missionStartedAt != nil else { return "0m" }
        let minutes = Int((missionDurationSeconds / 60).rounded(.down))
        let seconds = Int(missionDurationSeconds.truncatingRemainder(dividingBy: 60))
        if minutes <= 0 {
            return "\(seconds)s"
        }
        return "\(minutes)m \(seconds)s"
    }

    private func formattedNumber(_ value: Double) -> String {
        if value.isNaN || value.isInfinite {
            return "-"
        }
        if abs(value.rounded() - value) < 0.01 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }

    private func missionPaceGuidance() -> String {
        let etaText = projectedMissionFinishAt?.formatted(date: .omitted, time: .shortened) ?? "-"
        switch missionPaceStatus {
        case .preparing:
            return "Capture a few counts to generate a live finish projection."
        case .ahead:
            return "On pace to beat the target. Estimated finish around \(etaText)."
        case .atRisk:
            return "Close to target. Stay in sequence to finish near \(etaText)."
        case .behind:
            return "Behind pace. Prioritize remaining items and tighten transition time."
        }
    }
}
