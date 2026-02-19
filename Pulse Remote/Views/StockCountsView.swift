import SwiftUI
import CoreData

private enum CountSessionStage {
    case firstPass
    case recount

    var title: String {
        switch self {
        case .firstPass:
            return "First Pass"
        case .recount:
            return "Recount"
        }
    }
}

private enum VarianceReasonCode: String, CaseIterable, Identifiable {
    case countError = "Count Error"
    case receivingError = "Receiving Error"
    case damageWaste = "Damage / Waste"
    case theftLoss = "Theft / Loss"
    case transferError = "Transfer Error"
    case other = "Other"

    var id: String { rawValue }
}

private enum CountSessionAlert: Identifiable {
    case missingCounts(count: Int)
    case invalidNumber(itemName: String)
    case recountRequired(count: Int)
    case missingReasons(count: Int)

    var id: String {
        switch self {
        case .missingCounts(let count):
            return "missing-counts-\(count)"
        case .invalidNumber(let itemName):
            return "invalid-number-\(itemName)"
        case .recountRequired(let count):
            return "recount-required-\(count)"
        case .missingReasons(let count):
            return "missing-reasons-\(count)"
        }
    }
}

private enum CountPaceStatus {
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

struct StockCountsView: View {
    @EnvironmentObject private var dataController: InventoryDataController
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var platformStore: PlatformStore
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.name, ascending: true)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var stage: CountSessionStage = .firstPass
    @State private var blindModeEnabled = true
    @State private var revealExpectedCounts = false
    @State private var varianceThresholdPercent = 8.0
    @State private var targetDurationMinutes = 20
    @State private var firstPassInputs: [UUID: String] = [:]
    @State private var recountInputs: [UUID: String] = [:]
    @State private var recountItemIDs: Set<UUID> = []
    @State private var varianceReasons: [UUID: VarianceReasonCode] = [:]
    @State private var hasSeeded = false
    @State private var sessionStartedAt: Date?
    @State private var activeAlert: CountSessionAlert?

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    sessionSettingsCard
                    paceCoachCard

                    if stage == .recount {
                        recountStatusCard
                    }

                    ForEach(displayItems) { item in
                        countRow(for: item)
                    }

                    actionButtons
                }
                .padding(16)
            }
        }
        .navigationTitle("Stock Counts")
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
            seedInputsIfNeeded()
        }
        .onChange(of: blindModeEnabled) { _, _ in
            guard stage == .firstPass else { return }
            seedFirstPassInputsForMode()
        }
        .onChange(of: authStore.activeWorkspaceID) { _, _ in
            resetSession()
        }
        .onChange(of: targetDurationMinutes) { _, newValue in
            platformStore.setDefaultTargetDurationMinutes(
                newValue,
                for: .stockCount,
                workspaceID: authStore.activeWorkspaceID
            )
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .missingCounts(let count):
                return Alert(
                    title: Text("Missing Counts"),
                    message: Text("Please enter counts for \(count) item(s) before continuing."),
                    dismissButton: .default(Text("OK"))
                )
            case .invalidNumber(let itemName):
                return Alert(
                    title: Text("Invalid Number"),
                    message: Text("The count entered for \(itemName) is not valid."),
                    dismissButton: .default(Text("OK"))
                )
            case .recountRequired(let count):
                return Alert(
                    title: Text("Recount Required"),
                    message: Text("\(count) item(s) crossed the variance threshold. Complete recount before finalizing."),
                    dismissButton: .default(Text("Continue"))
                )
            case .missingReasons(let count):
                return Alert(
                    title: Text("Reason Codes Needed"),
                    message: Text("Select variance reasons for \(count) recounted item(s) before finalizing."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var workspaceItems: [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(authStore.activeWorkspaceID) }
    }

    private var recountItems: [InventoryItemEntity] {
        workspaceItems.filter { recountItemIDs.contains($0.id) }
    }

    private var displayItems: [InventoryItemEntity] {
        stage == .firstPass ? workspaceItems : recountItems
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stage == .firstPass ? "Count quickly, then auto-verify variance." : "Recount only flagged items and log reasons.")
                .font(Theme.font(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(blindModeEnabled ? "Blind mode hides expected counts until you choose to reveal them." : "Expected counts are visible for a faster guided count.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.45)
    }

    private var sessionSettingsCard: some View {
        sectionCard(title: "Session Settings") {
            Toggle("Blind count mode", isOn: $blindModeEnabled)
                .font(Theme.font(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .disabled(stage == .recount)

            Stepper(value: $varianceThresholdPercent, in: 3...30, step: 1) {
                Text("Recount trigger: \(Int(varianceThresholdPercent))% variance")
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .disabled(stage == .recount)

            Stepper(value: $targetDurationMinutes, in: 5...180, step: 5) {
                Text("Target session time: \(targetDurationMinutes)m")
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            if stage == .recount {
                Toggle("Reveal expected counts", isOn: $revealExpectedCounts)
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.accent)
            }
        }
    }

    private var recountStatusCard: some View {
        sectionCard(title: "Recount Queue") {
            Text("\(recountItems.count) items need a second count because variance exceeded \(Int(varianceThresholdPercent))%.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var firstPassCompletedCount: Int {
        workspaceItems.filter { item in
            parsedValue(from: firstPassInputs[item.id], for: item) != nil
        }.count
    }

    private var recountCompletedCount: Int {
        recountItems.filter { item in
            parsedValue(from: recountInputs[item.id], for: item) != nil
        }.count
    }

    private var totalEffortCount: Int {
        switch stage {
        case .firstPass:
            return workspaceItems.count
        case .recount:
            return workspaceItems.count + recountItems.count
        }
    }

    private var completedEffortCount: Int {
        switch stage {
        case .firstPass:
            return firstPassCompletedCount
        case .recount:
            return workspaceItems.count + recountCompletedCount
        }
    }

    private var sessionProgressRatio: Double {
        guard totalEffortCount > 0 else { return 0 }
        return min(1, max(0, Double(completedEffortCount) / Double(totalEffortCount)))
    }

    private var elapsedSessionSeconds: TimeInterval {
        guard let sessionStartedAt else { return 0 }
        return max(1, Date().timeIntervalSince(sessionStartedAt))
    }

    private var elapsedSessionMinutes: Double {
        elapsedSessionSeconds / 60
    }

    private var liveItemsPerMinute: Double {
        guard elapsedSessionMinutes > 0 else { return 0 }
        return Double(completedEffortCount) / elapsedSessionMinutes
    }

    private var projectedTotalMinutes: Double? {
        guard completedEffortCount > 0 else { return nil }
        return elapsedSessionMinutes / sessionProgressRatio
    }

    private var projectedFinishTime: Date? {
        guard let sessionStartedAt, let projectedTotalMinutes else { return nil }
        return sessionStartedAt.addingTimeInterval(projectedTotalMinutes * 60)
    }

    private var paceStatus: CountPaceStatus {
        guard let projectedTotalMinutes else { return .preparing }
        let delta = projectedTotalMinutes - Double(targetDurationMinutes)
        if delta <= 0 {
            return .ahead
        }
        if delta <= Double(targetDurationMinutes) * 0.15 {
            return .atRisk
        }
        return .behind
    }

    private var paceCoachCard: some View {
        sectionCard(title: "Live Pace Coach") {
            if workspaceItems.isEmpty {
                Text("Add items to run a pace-tracked counting session.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    paceMetric(title: "Progress", value: "\(completedEffortCount)/\(totalEffortCount)")
                    paceMetric(title: "Elapsed", value: elapsedLabel())
                    paceMetric(title: "Live Speed", value: "\(valueString(liveItemsPerMinute))/min")
                    paceMetric(title: "Target", value: "\(targetDurationMinutes)m")
                    paceMetric(
                        title: "Projection",
                        value: projectedTotalMinutes.map { "\(valueString($0))m" } ?? "-"
                    )
                    paceMetric(
                        title: "ETA",
                        value: projectedFinishTime.map { $0.formatted(date: .omitted, time: .shortened) } ?? "-"
                    )
                }

                HStack {
                    Text("Status")
                        .font(Theme.font(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(paceStatus.title)
                        .font(Theme.font(11, weight: .semibold))
                        .foregroundStyle(paceStatus.tint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(paceStatus.tint.opacity(0.14))
                        )
                }

                Text(paceGuidanceText())
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func countRow(for item: InventoryItemEntity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(Theme.font(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle(for: item))
                        .font(Theme.font(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                actionButtonLabel(for: item)
            }

            TextField(
                item.isLiquid ? "Enter gallons" : "Enter units",
                text: inputBinding(for: item)
            )
            #if os(iOS)
            .keyboardType(item.isLiquid ? .decimalPad : .numberPad)
            #endif
            .inventoryTextInputField()

            if stage == .recount {
                reasonPicker(for: item)
            }
        }
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.22)
    }

    @ViewBuilder
    private func actionButtonLabel(for item: InventoryItemEntity) -> some View {
        switch stage {
        case .firstPass:
            Button(blindModeEnabled ? "Clear" : "Reset") {
                firstPassInputs[item.id] = blindModeEnabled ? "" : formatInput(for: item, value: defaultCount(for: item))
            }
            .font(Theme.font(11, weight: .semibold))
            .buttonStyle(.bordered)
        case .recount:
            Button("Use 1st") {
                recountInputs[item.id] = firstPassInputs[item.id] ?? ""
            }
            .font(Theme.font(11, weight: .semibold))
            .buttonStyle(.bordered)
        }
    }

    private func subtitle(for item: InventoryItemEntity) -> String {
        switch stage {
        case .firstPass:
            if blindModeEnabled {
                return "First pass \(item.isLiquid ? "gallons" : "units")"
            }
            return "Expected: \(formattedExpectedLabel(for: item))"
        case .recount:
            let firstValue = parsedValue(from: firstPassInputs[item.id], for: item)
            let firstLabel = firstValue.map { formatValue($0, for: item) } ?? "-"
            if revealExpectedCounts || !blindModeEnabled {
                return "1st pass: \(firstLabel) • expected: \(formattedExpectedLabel(for: item))"
            }
            return "1st pass: \(firstLabel)"
        }
    }

    private func reasonPicker(for item: InventoryItemEntity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Variance Reason")
                .font(Theme.font(10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            Picker("Variance Reason", selection: reasonBinding(for: item)) {
                Text("Select reason").tag(Optional<VarianceReasonCode>.none)
                ForEach(VarianceReasonCode.allCases) { code in
                    Text(code.rawValue).tag(Optional(code))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                handlePrimaryAction()
            } label: {
                Text(primaryButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(displayItems.isEmpty)

            if stage == .recount {
                Button("Back To First Pass") {
                    stage = .firstPass
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var primaryButtonTitle: String {
        switch stage {
        case .firstPass:
            return blindModeEnabled ? "Run Variance Check" : "Apply Counts"
        case .recount:
            return "Finalize Recount"
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

    private func inputBinding(for item: InventoryItemEntity) -> Binding<String> {
        Binding(
            get: {
                switch stage {
                case .firstPass:
                    return firstPassInputs[item.id] ?? ""
                case .recount:
                    return recountInputs[item.id] ?? ""
                }
            },
            set: { newValue in
                switch stage {
                case .firstPass:
                    firstPassInputs[item.id] = newValue
                case .recount:
                    recountInputs[item.id] = newValue
                }
            }
        )
    }

    private func reasonBinding(for item: InventoryItemEntity) -> Binding<VarianceReasonCode?> {
        Binding(
            get: { varianceReasons[item.id] },
            set: { newValue in
                if let newValue {
                    varianceReasons[item.id] = newValue
                } else {
                    varianceReasons.removeValue(forKey: item.id)
                }
            }
        )
    }

    private func seedInputsIfNeeded() {
        guard !hasSeeded else { return }
        targetDurationMinutes = platformStore.defaultTargetDurationMinutes(
            for: .stockCount,
            workspaceID: authStore.activeWorkspaceID
        )
        hasSeeded = true
        if sessionStartedAt == nil {
            sessionStartedAt = Date()
        }
        seedFirstPassInputsForMode()
    }

    private func resetSession() {
        hasSeeded = false
        stage = .firstPass
        revealExpectedCounts = false
        recountItemIDs = []
        recountInputs = [:]
        varianceReasons = [:]
        firstPassInputs = [:]
        sessionStartedAt = Date()
        seedInputsIfNeeded()
    }

    private func seedFirstPassInputsForMode() {
        recountItemIDs = []
        recountInputs = [:]
        varianceReasons = [:]

        var seeded: [UUID: String] = [:]
        if !blindModeEnabled {
            for item in workspaceItems {
                seeded[item.id] = formatInput(for: item, value: defaultCount(for: item))
            }
        }
        firstPassInputs = seeded
    }

    private func handlePrimaryAction() {
        switch stage {
        case .firstPass:
            handleFirstPass()
        case .recount:
            handleRecountFinalize()
        }
    }

    private func handleFirstPass() {
        guard let parsedFirstPass = parseInputs(from: firstPassInputs, itemsToParse: workspaceItems) else {
            return
        }

        guard blindModeEnabled else {
            applyCounts(finalCounts: parsedFirstPass)
            return
        }

        let flagged = workspaceItems.filter { item in
            guard let counted = parsedFirstPass[item.id] else { return false }
            return shouldRequireRecount(for: item, counted: counted)
        }

        guard !flagged.isEmpty else {
            applyCounts(finalCounts: parsedFirstPass)
            return
        }

        stage = .recount
        recountItemIDs = Set(flagged.map(\.id))
        recountInputs = [:]
        varianceReasons = [:]
        activeAlert = .recountRequired(count: flagged.count)
    }

    private func handleRecountFinalize() {
        guard let parsedFirstPass = parseInputs(from: firstPassInputs, itemsToParse: workspaceItems) else {
            return
        }
        guard let parsedRecounts = parseInputs(from: recountInputs, itemsToParse: recountItems) else {
            return
        }

        var finalCounts = parsedFirstPass
        for item in recountItems {
            if let recounted = parsedRecounts[item.id] {
                finalCounts[item.id] = recounted
            }
        }

        let missingReasons = recountItems.filter { item in
            guard let finalCount = finalCounts[item.id] else { return false }
            let expected = defaultCount(for: item)
            let variance = abs(finalCount - expected)
            guard variance > 0 else { return false }
            return varianceReasons[item.id] == nil
        }

        guard missingReasons.isEmpty else {
            activeAlert = .missingReasons(count: missingReasons.count)
            return
        }

        applyCounts(finalCounts: finalCounts)
    }

    private func applyCounts(finalCounts: [UUID: Double]) {
        let now = Date()
        let source = stage == .recount ? "stock-count-recount" : "stock-count-first-pass"
        let varianceReviewedCount = workspaceItems.filter { item in
            guard let finalCount = finalCounts[item.id] else { return false }
            return shouldRequireRecount(for: item, counted: finalCount)
        }.count

        _ = platformStore.createGuardBackupIfNeeded(
            reason: "Stock count apply",
            from: workspaceItems,
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName,
            cooldownMinutes: 120
        )

        for item in workspaceItems {
            guard let count = finalCounts[item.id] else { continue }
            let previous = defaultCount(for: item)
            let previousUnits = item.totalUnitsOnHand

            if item.isLiquid {
                item.applyTotalGallons(count)
            } else {
                item.applyTotalNonLiquidUnits(
                    Int64(max(0, count.rounded())),
                    resetLooseEaches: true
                )
            }

            if let reason = varianceReasons[item.id], abs(previous - count) > 0 {
                let line = "\(Date().formatted(date: .abbreviated, time: .shortened)) • Count variance \(formatValue(count, for: item)) vs \(formatValue(previous, for: item)) • Reason: \(reason.rawValue)"
                if item.notes.isEmpty {
                    item.notes = line
                } else {
                    item.notes += "\n\(line)"
                }
            }

            item.assignWorkspaceIfNeeded(authStore.activeWorkspaceID)
            item.updatedAt = now
            let reason = varianceReasons[item.id]?.rawValue ?? "Cycle count update"
            platformStore.recordCountCorrection(
                item: item,
                previousUnits: previousUnits,
                newUnits: item.totalUnitsOnHand,
                actorName: authStore.displayName,
                workspaceID: authStore.activeWorkspaceID,
                source: source,
                reason: reason
            )
        }

        dataController.save()
        platformStore.recordCountSession(
            type: .stockCount,
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName,
            startedAt: sessionStartedAt ?? now,
            finishedAt: now,
            itemCount: workspaceItems.count,
            highVarianceCount: varianceReviewedCount,
            blindModeEnabled: blindModeEnabled,
            targetDurationMinutes: targetDurationMinutes,
            note: stage == .recount ? "Stock count finalized after recount." : "Stock count finalized on first pass."
        )
        Haptics.success()
        dismiss()
    }

    private func parseInputs(
        from inputs: [UUID: String],
        itemsToParse: [InventoryItemEntity]
    ) -> [UUID: Double]? {
        var parsed: [UUID: Double] = [:]
        var missingCount = 0

        for item in itemsToParse {
            let raw = (inputs[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                missingCount += 1
                continue
            }

            guard let value = Double(raw), value >= 0 else {
                activeAlert = .invalidNumber(itemName: item.name)
                return nil
            }

            parsed[item.id] = max(0, value)
        }

        guard missingCount == 0 else {
            activeAlert = .missingCounts(count: missingCount)
            return nil
        }

        return parsed
    }

    private func shouldRequireRecount(for item: InventoryItemEntity, counted: Double) -> Bool {
        let expected = defaultCount(for: item)
        let absoluteVariance = abs(counted - expected)
        let percentVariance: Double
        if expected > 0 {
            percentVariance = (absoluteVariance / expected) * 100
        } else {
            percentVariance = counted > 0 ? 100 : 0
        }

        let minimumVariance = item.isLiquid ? 0.25 : 2
        return absoluteVariance >= minimumVariance && percentVariance >= varianceThresholdPercent
    }

    private func defaultCount(for item: InventoryItemEntity) -> Double {
        if item.isLiquid {
            return item.totalGallonsOnHand
        }
        return Double(item.totalUnitsOnHand)
    }

    private func parsedValue(from raw: String?, for item: InventoryItemEntity) -> Double? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed), value >= 0 else { return nil }
        if item.isLiquid {
            return value
        }
        return value.rounded()
    }

    private func formatInput(for item: InventoryItemEntity, value: Double) -> String {
        if item.isLiquid {
            return String(format: "%.2f", value)
        }
        return "\(Int(value.rounded()))"
    }

    private func formatValue(_ value: Double, for item: InventoryItemEntity) -> String {
        if item.isLiquid {
            return "\(formattedGallons(value)) gal"
        }
        return "\(Int(value.rounded())) units"
    }

    private func formattedExpectedLabel(for item: InventoryItemEntity) -> String {
        if item.isLiquid {
            return "\(formattedGallons(defaultCount(for: item))) gal"
        }
        return "\(Int(defaultCount(for: item).rounded())) units"
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

    private func paceMetric(title: String, value: String) -> some View {
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

    private func valueString(_ value: Double) -> String {
        if value.isNaN || value.isInfinite {
            return "-"
        }
        if abs(value.rounded() - value) < 0.01 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }

    private func elapsedLabel() -> String {
        guard sessionStartedAt != nil else { return "0m" }
        let minutes = Int((elapsedSessionSeconds / 60).rounded(.down))
        let seconds = Int(elapsedSessionSeconds.truncatingRemainder(dividingBy: 60))
        if minutes <= 0 {
            return "\(seconds)s"
        }
        return "\(minutes)m \(seconds)s"
    }

    private func paceGuidanceText() -> String {
        switch paceStatus {
        case .preparing:
            return "Enter a few counts to get a live finish projection."
        case .ahead:
            return "On pace to beat the target. Keep flow steady and finalize once complete."
        case .atRisk:
            return "Near target. Use quick-entry rhythm and clear any blanks to stay on time."
        case .behind:
            return "Behind target. Prioritize remaining items and avoid context-switching until session close."
        }
    }
}
