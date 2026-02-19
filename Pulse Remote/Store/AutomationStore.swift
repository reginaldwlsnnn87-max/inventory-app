import Foundation
import Combine
#if canImport(UserNotifications)
import UserNotifications
#endif

enum AutomationTaskPriority: String, Codable, CaseIterable {
    case critical
    case high
    case normal

    var title: String {
        switch self {
        case .critical:
            return "Critical"
        case .high:
            return "High"
        case .normal:
            return "Normal"
        }
    }
}

enum AutomationTaskCategory: String, Codable, CaseIterable {
    case counting
    case replenishment
    case shrink
    case dataQuality
    case planning
    case integrations
}

enum AutomationTaskStatus: String, Codable {
    case open
    case done
}

enum AutomationTaskAction: String, Codable, CaseIterable {
    case openAutomationInbox
    case openZoneMission
    case openReplenishment
    case createAutoDraftPO
    case openKPIDashboard
    case openExceptionFeed
    case openDailyOpsBrief
    case openGuidedHelp
    case openIntegrationHub
    case openTrustCenter

    var title: String {
        switch self {
        case .openAutomationInbox:
            return "Open Automation Inbox"
        case .openZoneMission:
            return "Open Zone Mission"
        case .openReplenishment:
            return "Open Replenishment"
        case .createAutoDraftPO:
            return "Create Auto Draft PO"
        case .openKPIDashboard:
            return "Open KPI Dashboard"
        case .openExceptionFeed:
            return "Open Exception Feed"
        case .openDailyOpsBrief:
            return "Open Daily Ops Brief"
        case .openGuidedHelp:
            return "Open Guided Help"
        case .openIntegrationHub:
            return "Open Integration Hub"
        case .openTrustCenter:
            return "Open Trust Center"
        }
    }

    var systemImage: String {
        switch self {
        case .openAutomationInbox:
            return "tray.full"
        case .openZoneMission:
            return "map.fill"
        case .openReplenishment:
            return "chart.line.uptrend.xyaxis"
        case .createAutoDraftPO:
            return "cart.badge.plus"
        case .openKPIDashboard:
            return "chart.bar.doc.horizontal"
        case .openExceptionFeed:
            return "exclamationmark.bubble"
        case .openDailyOpsBrief:
            return "checklist.checked"
        case .openGuidedHelp:
            return "questionmark.bubble"
        case .openIntegrationHub:
            return "arrow.triangle.2.circlepath"
        case .openTrustCenter:
            return "checkmark.shield"
        }
    }
}

private enum AutomationNotificationPayloadKey {
    static let action = "action"
    static let taskID = "taskID"
    static let workspaceKey = "workspaceKey"
    static let summary = "summary"
}

struct AutomationNotificationRoute: Equatable {
    let token: UUID
    let action: AutomationTaskAction
    let workspaceKey: String?
    let taskID: String?
    let isSummary: Bool

    init(
        action: AutomationTaskAction,
        workspaceKey: String?,
        taskID: String?,
        isSummary: Bool,
        token: UUID = UUID()
    ) {
        self.token = token
        self.action = action
        self.workspaceKey = workspaceKey
        self.taskID = taskID
        self.isSummary = isSummary
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let rawAction = userInfo[AutomationNotificationPayloadKey.action] as? String,
              let action = AutomationTaskAction(rawValue: rawAction) else {
            return nil
        }

        let workspaceKey = userInfo[AutomationNotificationPayloadKey.workspaceKey] as? String
        let taskID = userInfo[AutomationNotificationPayloadKey.taskID] as? String
        let summaryValue = userInfo[AutomationNotificationPayloadKey.summary]
        let isSummary: Bool
        if let boolValue = summaryValue as? Bool {
            isSummary = boolValue
        } else if let numberValue = summaryValue as? NSNumber {
            isSummary = numberValue.boolValue
        } else if let stringValue = summaryValue as? String {
            isSummary = (stringValue as NSString).boolValue
        } else {
            isSummary = false
        }

        self.init(
            action: action,
            workspaceKey: workspaceKey,
            taskID: taskID,
            isSummary: isSummary
        )
    }

    var payload: [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = [
            AutomationNotificationPayloadKey.action: action.rawValue,
            AutomationNotificationPayloadKey.summary: isSummary
        ]

        if let workspaceKey {
            userInfo[AutomationNotificationPayloadKey.workspaceKey] = workspaceKey
        }
        if let taskID {
            userInfo[AutomationNotificationPayloadKey.taskID] = taskID
        }
        return userInfo
    }
}

@MainActor
final class AutomationRouteStore: ObservableObject {
    static let shared = AutomationRouteStore()

    @Published private(set) var pendingRoute: AutomationNotificationRoute?

    private init() {}

    func queue(userInfo: [AnyHashable: Any]) {
        guard let route = AutomationNotificationRoute(userInfo: userInfo) else {
            return
        }
        pendingRoute = route
    }

    func queue(route: AutomationNotificationRoute) {
        pendingRoute = route
    }

    func consumeRoute() -> AutomationNotificationRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }
}

enum AutomationReminderWindow: String, Codable, CaseIterable, Identifiable {
    case allDay
    case openShift
    case midShift
    case closeShift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allDay:
            return "All Day"
        case .openShift:
            return "Open"
        case .midShift:
            return "Mid"
        case .closeShift:
            return "Close"
        }
    }

    var description: String {
        switch self {
        case .allDay:
            return "6AM-10PM reminders"
        case .openShift:
            return "6AM-11AM reminders"
        case .midShift:
            return "11AM-4PM reminders"
        case .closeShift:
            return "4PM-10PM reminders"
        }
    }
}

struct AutomationTask: Identifiable, Codable, Hashable {
    let id: String
    let ruleID: String
    let createdAt: Date
    var updatedAt: Date
    var title: String
    var detail: String
    var action: AutomationTaskAction
    var priority: AutomationTaskPriority
    var category: AutomationTaskCategory
    var estimateMinutes: Int
    var dueAt: Date
    var assignedZone: String?
    var status: AutomationTaskStatus
    var snoozedUntil: Date?
    var completedAt: Date?
}

struct AutomationZoneAssignment: Codable, Hashable {
    let zoneKey: String
    let zoneLabel: String
    let staleItemCount: Int
}

struct AutomationSignals {
    let role: WorkspaceRole
    let itemCount: Int
    let staleItemCount: Int
    let staleZoneAssignments: [AutomationZoneAssignment]
    let stockoutRiskCount: Int
    let urgentReplenishmentCount: Int
    let autoDraftCandidateCount: Int
    let autoDraftSuggestedUnits: Int64
    let missingLocationCount: Int
    let missingDemandInputCount: Int
    let missingBarcodeCount: Int
    let pendingLedgerEventCount: Int
    let failedLedgerEventCount: Int
    let lowConfidenceItemCount: Int
    let countTargetTrackedSessions: Int
    let countTargetHitRate: Double
}

@MainActor
final class AutomationStore: ObservableObject {
    static let unassignedZoneKey = "__unassigned__"

    @Published private(set) var tasks: [AutomationTask] = []
    @Published private(set) var lastRunAt: Date?
    @Published private(set) var activeWorkspaceKey = "all"
    @Published var isAutopilotEnabled = true
    @Published var isRemindersEnabled = true
    @Published private(set) var isReminderAuthorizationGranted = false
    @Published var reminderWindow: AutomationReminderWindow = .allDay

    private let defaults: UserDefaults
    private let tasksPrefix = "inventory.automation.tasks."
    private let autopilotPrefix = "inventory.automation.autopilot."
    private let lastRunPrefix = "inventory.automation.lastRun."
    private let remindersPrefix = "inventory.automation.reminders."
    private let reminderWindowPrefix = "inventory.automation.reminderWindow."
    private let proactiveRoutePrefix = "inventory.automation.proactiveRoute."
    private var lastReminderSyncAt: Date?
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadWorkspaceState()
    }

    var openTasks: [AutomationTask] {
        let now = Date()
        return tasks
            .filter { task in
                guard task.status == .open else { return false }
                if let snoozedUntil = task.snoozedUntil, snoozedUntil > now {
                    return false
                }
                return true
            }
            .sorted(by: sortTasks)
    }

    var snoozedTasks: [AutomationTask] {
        let now = Date()
        return tasks
            .filter { task in
                guard task.status == .open else { return false }
                if let snoozedUntil = task.snoozedUntil {
                    return snoozedUntil > now
                }
                return false
            }
            .sorted(by: sortTasks)
    }

    var completedTasks: [AutomationTask] {
        tasks
            .filter { $0.status == .done }
            .sorted {
                ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt)
            }
    }

    func activateWorkspace(_ workspaceID: UUID?) {
        let key = workspaceID?.uuidString ?? "all"
        guard key != activeWorkspaceKey else { return }
        activeWorkspaceKey = key
        loadWorkspaceState()
    }

    func setAutopilotEnabled(_ enabled: Bool, workspaceID: UUID?) {
        activateWorkspace(workspaceID)
        isAutopilotEnabled = enabled
        defaults.set(enabled, forKey: autopilotKey(for: activeWorkspaceKey))
    }

    func setRemindersEnabled(_ enabled: Bool, workspaceID: UUID?) {
        activateWorkspace(workspaceID)
        isRemindersEnabled = enabled
        defaults.set(enabled, forKey: remindersKey(for: activeWorkspaceKey))

        if enabled {
            Task {
                let granted = await requestReminderAuthorizationIfNeeded()
                await MainActor.run {
                    self.isReminderAuthorizationGranted = granted
                    if !granted {
                        self.isRemindersEnabled = false
                        self.defaults.set(false, forKey: self.remindersKey(for: self.activeWorkspaceKey))
                    }
                }
                guard granted else { return }
                await syncTaskReminders(force: true)
            }
        } else {
            Task {
                await removeTaskReminders()
            }
        }
    }

    func setReminderWindow(_ window: AutomationReminderWindow, workspaceID: UUID?) {
        activateWorkspace(workspaceID)
        reminderWindow = window
        defaults.set(window.rawValue, forKey: reminderWindowKey(for: activeWorkspaceKey))
        Task {
            await syncTaskReminders(force: true)
        }
    }

    func runAutomationCycle(
        using signals: AutomationSignals,
        workspaceID: UUID?,
        force: Bool = false
    ) {
        activateWorkspace(workspaceID)

        guard isAutopilotEnabled || force else { return }

        let now = Date()
        if !force, let lastRunAt, now.timeIntervalSince(lastRunAt) < 20 {
            return
        }

        let candidates = buildCandidates(using: signals, now: now)
        guard !candidates.isEmpty || !tasks.isEmpty else {
            lastRunAt = now
            defaults.set(now.timeIntervalSince1970, forKey: lastRunKey(for: activeWorkspaceKey))
            return
        }

        let candidateIDs = Set(candidates.map(\.id))
        let existingByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var merged: [AutomationTask] = []

        for candidate in candidates {
            if var existing = existingByID[candidate.id] {
                existing.title = candidate.title
                existing.detail = candidate.detail
                existing.action = candidate.action
                existing.priority = candidate.priority
                existing.category = candidate.category
                existing.estimateMinutes = candidate.estimateMinutes
                existing.dueAt = candidate.dueAt
                existing.assignedZone = candidate.assignedZone
                existing.updatedAt = now
                merged.append(existing)
            } else {
                merged.append(candidate)
            }
        }

        let retentionCutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let preservedHistory = tasks.filter { task in
            guard !candidateIDs.contains(task.id) else { return false }
            if task.status == .done {
                return (task.completedAt ?? task.updatedAt) >= retentionCutoff
            }
            return task.createdAt >= retentionCutoff
        }

        merged.append(contentsOf: preservedHistory)
        tasks = merged.sorted(by: sortTasks)
        lastRunAt = now
        persistWorkspaceState()
        triggerProactiveRouteIfNeeded(using: signals, now: now)
        Task {
            await syncTaskReminders()
        }
    }

    func markTaskDone(_ taskID: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .done
        tasks[index].completedAt = Date()
        tasks[index].snoozedUntil = nil
        tasks[index].updatedAt = Date()
        persistWorkspaceState()
        Task {
            await syncTaskReminders(force: true)
        }
    }

    func reopenTask(_ taskID: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .open
        tasks[index].completedAt = nil
        tasks[index].updatedAt = Date()
        persistWorkspaceState()
        Task {
            await syncTaskReminders(force: true)
        }
    }

    func snoozeTask(_ taskID: String, hours: Int = 3) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .open
        tasks[index].snoozedUntil = Date().addingTimeInterval(TimeInterval(max(1, hours) * 3600))
        tasks[index].updatedAt = Date()
        persistWorkspaceState()
        Task {
            await syncTaskReminders(force: true)
        }
    }

    func resetWorkspaceTasks() {
        tasks = []
        persistWorkspaceState()
        Task {
            await removeTaskReminders()
        }
    }

    private func buildCandidates(using signals: AutomationSignals, now: Date) -> [AutomationTask] {
        guard signals.itemCount > 0 else { return [] }

        let dayKey = Self.dayFormatter.string(from: now)
        var output: [AutomationTask] = []

        if signals.urgentReplenishmentCount >= 2 {
            let canCreateDraft = (signals.role == .owner || signals.role == .manager)
                && signals.autoDraftCandidateCount > 0
                && signals.autoDraftSuggestedUnits > 0

            if canCreateDraft {
                output.append(
                    makeTask(
                        ruleID: "auto-draft-po",
                        dayKey: dayKey,
                        now: now,
                        title: "Auto: Generate draft PO",
                        detail: "\(signals.autoDraftCandidateCount) SKU(s) need \(signals.autoDraftSuggestedUnits) units. Create a one-tap draft PO now.",
                        action: .createAutoDraftPO,
                        priority: .critical,
                        category: .replenishment,
                        estimateMinutes: 3,
                        dueHour: 9
                    )
                )
            } else {
                output.append(
                    makeTask(
                        ruleID: "urgent-replenishment",
                        dayKey: dayKey,
                        now: now,
                        title: "Auto: Build replenishment draft",
                        detail: "\(signals.urgentReplenishmentCount) SKU(s) are at urgent stockout risk. Prioritize a draft order before next receiving window.",
                        action: .openReplenishment,
                        priority: .critical,
                        category: .replenishment,
                        estimateMinutes: 8,
                        dueHour: 10
                    )
                )
            }
        }

        if signals.countTargetTrackedSessions >= 2 && signals.countTargetHitRate < 0.6 {
            let paceAction = preferredPaceRecoveryAction(using: signals)
            let actionLabel: String
            let category: AutomationTaskCategory
            switch paceAction {
            case .openReplenishment:
                actionLabel = "replenishment queue"
                category = .replenishment
            default:
                actionLabel = "zone mission"
                category = .counting
            }
            output.append(
                makeTask(
                    ruleID: "count-pace-recovery",
                    dayKey: dayKey,
                    now: now,
                    title: "Auto: Recover count pace",
                    detail: "Target hit rate is \(percentString(signals.countTargetHitRate)) across \(signals.countTargetTrackedSessions) tracked sessions. Open \(actionLabel) now to recover execution speed.",
                    action: paceAction,
                    priority: signals.countTargetHitRate < 0.4 ? .critical : .high,
                    category: category,
                    estimateMinutes: 6,
                    dueHour: 10
                )
            )
        }

        let staleThreshold = max(4, signals.itemCount / 4)
        if signals.staleItemCount >= staleThreshold {
            let prioritizedZones = signals.staleZoneAssignments
                .filter { $0.staleItemCount > 0 }
                .sorted { lhs, rhs in
                    if lhs.staleItemCount != rhs.staleItemCount {
                        return lhs.staleItemCount > rhs.staleItemCount
                    }
                    return lhs.zoneLabel.localizedCaseInsensitiveCompare(rhs.zoneLabel) == .orderedAscending
                }

            if prioritizedZones.isEmpty {
                output.append(
                    makeTask(
                        ruleID: "stale-count-recovery",
                        dayKey: dayKey,
                        now: now,
                        title: "Auto: Run cycle count mission",
                        detail: "\(signals.staleItemCount) item(s) are stale. Run a focused zone mission to cut shrink risk.",
                        action: .openZoneMission,
                        priority: .high,
                        category: .counting,
                        estimateMinutes: 10,
                        dueHour: 12
                    )
                )
            } else {
                for (index, zone) in prioritizedZones.prefix(3).enumerated() {
                    let zoneRuleToken = normalizedRuleToken(zone.zoneKey)
                    let zonePriority: AutomationTaskPriority =
                        (zone.staleItemCount >= max(3, staleThreshold) || index == 0) ? .critical : .high
                    let estimateMinutes = min(18, max(6, zone.staleItemCount * 2))
                    output.append(
                        makeTask(
                            ruleID: "stale-count-zone-\(zoneRuleToken)",
                            dayKey: dayKey,
                            now: now,
                            title: "Auto: Count \(zone.zoneLabel)",
                            detail: "\(zone.staleItemCount) stale item(s) assigned to \(zone.zoneLabel). Run Zone Mission on this zone first.",
                            action: .openZoneMission,
                            priority: zonePriority,
                            category: .counting,
                            estimateMinutes: estimateMinutes,
                            dueHour: min(18, 11 + index),
                            assignedZone: zone.zoneKey == Self.unassignedZoneKey ? Self.unassignedZoneKey : zone.zoneLabel
                        )
                    )
                }
            }
        }

        let hygieneLoad = signals.missingLocationCount + signals.missingDemandInputCount + signals.missingBarcodeCount
        if hygieneLoad >= max(5, signals.itemCount / 3) {
            output.append(
                makeTask(
                    ruleID: "data-hygiene-sweep",
                    dayKey: dayKey,
                    now: now,
                    title: "Auto: Fix data quality blockers",
                    detail: "\(hygieneLoad) data gaps are slowing counts and reorder accuracy. Use the brief to clear highest-impact gaps first.",
                    action: .openDailyOpsBrief,
                    priority: .high,
                    category: .dataQuality,
                    estimateMinutes: 7,
                    dueHour: 14
                )
            )
        }

        if signals.failedLedgerEventCount > 0 || signals.pendingLedgerEventCount >= 20 {
            output.append(
                makeTask(
                    ruleID: "offline-ledger-reconnect",
                    dayKey: dayKey,
                    now: now,
                    title: "Auto: Clear sync backlog",
                    detail: "\(signals.pendingLedgerEventCount) ledger event(s) are unsynced (\(signals.failedLedgerEventCount) failed). Reconnect integrations and run auto sync.",
                    action: .openIntegrationHub,
                    priority: signals.failedLedgerEventCount > 0 ? .critical : .high,
                    category: .integrations,
                    estimateMinutes: 6,
                    dueHour: 11
                )
            )
        }

        if signals.lowConfidenceItemCount >= max(2, signals.itemCount / 5) {
            output.append(
                makeTask(
                    ruleID: "confidence-recovery",
                    dayKey: dayKey,
                    now: now,
                    title: "Auto: Recover count confidence",
                    detail: "\(signals.lowConfidenceItemCount) SKU(s) have weak confidence. Use Trust Center to target high-risk items and fix root causes.",
                    action: .openTrustCenter,
                    priority: .high,
                    category: .counting,
                    estimateMinutes: 8,
                    dueHour: 13
                )
            )
        }

        if signals.stockoutRiskCount >= 2 {
            output.append(
                makeTask(
                    ruleID: "shrink-watch",
                    dayKey: dayKey,
                    now: now,
                    title: "Auto: Investigate shrink risk",
                    detail: "Risk signals are elevated across \(signals.stockoutRiskCount) item(s). Review exception feed and close top causes.",
                    action: .openExceptionFeed,
                    priority: .high,
                    category: .shrink,
                    estimateMinutes: 9,
                    dueHour: 16
                )
            )
        }

        if signals.role == .owner || signals.role == .manager {
            output.append(
                makeTask(
                    ruleID: "manager-kpi-check",
                    dayKey: dayKey,
                    now: now,
                    title: "Auto: Manager KPI review",
                    detail: "Run a KPI review to confirm risk, dead stock, and coverage posture before end of day.",
                    action: .openKPIDashboard,
                    priority: .normal,
                    category: .planning,
                    estimateMinutes: 5,
                    dueHour: 18
                )
            )
        } else {
            output.append(
                makeTask(
                    ruleID: "staff-guided-refresh",
                    dayKey: dayKey,
                    now: now,
                    title: "Auto: Skill-up refresh",
                    detail: "Run a quick guided help refresh to keep count quality high during fast shifts.",
                    action: .openGuidedHelp,
                    priority: .normal,
                    category: .counting,
                    estimateMinutes: 4,
                    dueHour: 17
                )
            )
        }

        return output
    }

    private func makeTask(
        ruleID: String,
        dayKey: String,
        now: Date,
        title: String,
        detail: String,
        action: AutomationTaskAction,
        priority: AutomationTaskPriority,
        category: AutomationTaskCategory,
        estimateMinutes: Int,
        dueHour: Int,
        assignedZone: String? = nil
    ) -> AutomationTask {
        let id = "\(dayKey).\(ruleID)"
        return AutomationTask(
            id: id,
            ruleID: ruleID,
            createdAt: now,
            updatedAt: now,
            title: title,
            detail: detail,
            action: action,
            priority: priority,
            category: category,
            estimateMinutes: estimateMinutes,
            dueAt: dueDate(hour: dueHour),
            assignedZone: assignedZone,
            status: .open,
            snoozedUntil: nil,
            completedAt: nil
        )
    }

    private func dueDate(hour: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = min(max(0, hour), 23)
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private func sortTasks(lhs: AutomationTask, rhs: AutomationTask) -> Bool {
        if lhs.status != rhs.status {
            return lhs.status == .open
        }

        let priorityOrder: [AutomationTaskPriority: Int] = [
            .critical: 0,
            .high: 1,
            .normal: 2
        ]
        let lhsPriority = priorityOrder[lhs.priority] ?? 9
        let rhsPriority = priorityOrder[rhs.priority] ?? 9
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        if lhs.dueAt != rhs.dueAt {
            return lhs.dueAt < rhs.dueAt
        }

        return lhs.updatedAt > rhs.updatedAt
    }

    private func preferredPaceRecoveryAction(using signals: AutomationSignals) -> AutomationTaskAction {
        let elevatedStockRisk = signals.urgentReplenishmentCount >= 2 || signals.stockoutRiskCount >= max(2, signals.itemCount / 6)
        if elevatedStockRisk {
            return .openReplenishment
        }
        return .openZoneMission
    }

    private func percentString(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        return String(format: "%.0f%%", max(0, value) * 100)
    }

    private func normalizedRuleToken(_ rawValue: String) -> String {
        let mapped = rawValue.lowercased().map { char -> Character in
            if char.isLetter || char.isNumber {
                return char
            }
            return "-"
        }
        let collapsed = String(mapped)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "zone" : collapsed
    }

    private func triggerProactiveRouteIfNeeded(using signals: AutomationSignals, now: Date) {
        guard isAutopilotEnabled else { return }
        guard signals.countTargetTrackedSessions >= 2, signals.countTargetHitRate < 0.6 else { return }

        let key = proactiveRouteKey(for: activeWorkspaceKey)
        let cooldown: TimeInterval = 60 * 60 * 2
        let lastTriggeredAt = defaults.double(forKey: key)
        if lastTriggeredAt > 0, (now.timeIntervalSince1970 - lastTriggeredAt) < cooldown {
            return
        }

        let action = preferredPaceRecoveryAction(using: signals)
        AutomationRouteStore.shared.queue(
            route: AutomationNotificationRoute(
                action: action,
                workspaceKey: activeWorkspaceKey,
                taskID: "count-pace-recovery",
                isSummary: false
            )
        )
        defaults.set(now.timeIntervalSince1970, forKey: key)
    }

    private func tasksKey(for workspaceKey: String) -> String {
        tasksPrefix + workspaceKey
    }

    private func autopilotKey(for workspaceKey: String) -> String {
        autopilotPrefix + workspaceKey
    }

    private func lastRunKey(for workspaceKey: String) -> String {
        lastRunPrefix + workspaceKey
    }

    private func remindersKey(for workspaceKey: String) -> String {
        remindersPrefix + workspaceKey
    }

    private func reminderWindowKey(for workspaceKey: String) -> String {
        reminderWindowPrefix + workspaceKey
    }

    private func proactiveRouteKey(for workspaceKey: String) -> String {
        proactiveRoutePrefix + workspaceKey
    }

    private func loadWorkspaceState() {
        if defaults.object(forKey: autopilotKey(for: activeWorkspaceKey)) == nil {
            isAutopilotEnabled = true
        } else {
            isAutopilotEnabled = defaults.bool(forKey: autopilotKey(for: activeWorkspaceKey))
        }

        if defaults.object(forKey: remindersKey(for: activeWorkspaceKey)) == nil {
            isRemindersEnabled = true
        } else {
            isRemindersEnabled = defaults.bool(forKey: remindersKey(for: activeWorkspaceKey))
        }

        if let rawValue = defaults.string(forKey: reminderWindowKey(for: activeWorkspaceKey)),
           let window = AutomationReminderWindow(rawValue: rawValue) {
            reminderWindow = window
        } else {
            reminderWindow = .allDay
        }

        if let data = defaults.data(forKey: tasksKey(for: activeWorkspaceKey)),
           let decoded = try? JSONDecoder().decode([AutomationTask].self, from: data) {
            tasks = decoded.sorted(by: sortTasks)
        } else {
            tasks = []
        }

        if defaults.object(forKey: lastRunKey(for: activeWorkspaceKey)) != nil {
            let value = defaults.double(forKey: lastRunKey(for: activeWorkspaceKey))
            if value > 0 {
                lastRunAt = Date(timeIntervalSince1970: value)
            } else {
                lastRunAt = nil
            }
        } else {
            lastRunAt = nil
        }

        Task {
            let granted = await currentReminderAuthorizationState()
            await MainActor.run {
                self.isReminderAuthorizationGranted = granted
            }
            await syncTaskReminders(force: true)
        }
    }

    private func persistWorkspaceState() {
        if let data = try? JSONEncoder().encode(tasks) {
            defaults.set(data, forKey: tasksKey(for: activeWorkspaceKey))
        }
        defaults.set(isAutopilotEnabled, forKey: autopilotKey(for: activeWorkspaceKey))
        defaults.set(isRemindersEnabled, forKey: remindersKey(for: activeWorkspaceKey))
        defaults.set(reminderWindow.rawValue, forKey: reminderWindowKey(for: activeWorkspaceKey))
        if let lastRunAt {
            defaults.set(lastRunAt.timeIntervalSince1970, forKey: lastRunKey(for: activeWorkspaceKey))
        }
    }

    private var reminderIdentifierPrefix: String {
        "inventory.automation.reminder.\(activeWorkspaceKey)."
    }

    private var reminderSummaryIdentifier: String {
        "inventory.automation.reminder.\(activeWorkspaceKey).summary"
    }

    private func reminderIdentifier(for task: AutomationTask) -> String {
        reminderIdentifierPrefix + task.id
    }

    private func shouldNotify(for task: AutomationTask, now: Date) -> Bool {
        guard task.status == .open else { return false }
        if let snoozedUntil = task.snoozedUntil, snoozedUntil > now {
            return false
        }
        guard task.dueAt > now && task.dueAt <= now.addingTimeInterval(18 * 60 * 60) else {
            return false
        }
        let hour = Calendar.current.component(.hour, from: task.dueAt)
        return reminderWindowIncludes(hour: hour)
    }

    private func notificationBody(for task: AutomationTask) -> String {
        "\(task.title) • \(task.action.title)"
    }

    private func reminderUserInfo(
        action: AutomationTaskAction,
        taskID: String?,
        isSummary: Bool = false
    ) -> [AnyHashable: Any] {
        AutomationNotificationRoute(
            action: action,
            workspaceKey: activeWorkspaceKey,
            taskID: taskID,
            isSummary: isSummary
        ).payload
    }

    private func summaryBody(openCount: Int) -> String {
        if openCount == 1 {
            return "1 autopilot task is ready. Start with the highest-priority action."
        }
        return "\(openCount) autopilot tasks are ready. Start with the highest-priority action."
    }

    private func reminderWindowIncludes(hour: Int) -> Bool {
        switch reminderWindow {
        case .allDay:
            return hour >= 6 && hour < 22
        case .openShift:
            return hour >= 6 && hour < 11
        case .midShift:
            return hour >= 11 && hour < 16
        case .closeShift:
            return hour >= 16 && hour < 22
        }
    }

    private func summaryHourForWindow() -> Int {
        switch reminderWindow {
        case .allDay:
            return 9
        case .openShift:
            return 7
        case .midShift:
            return 12
        case .closeShift:
            return 17
        }
    }

    private func nextSummaryDate(from now: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = summaryHourForWindow()
        components.minute = 0
        components.second = 0

        let baseline = calendar.date(from: components) ?? now.addingTimeInterval(5 * 60)
        if baseline > now {
            return baseline
        }
        return calendar.date(byAdding: .day, value: 1, to: baseline) ?? now.addingTimeInterval(5 * 60)
    }

    private func syncTaskReminders(force: Bool = false) async {
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            return
        }

        guard isRemindersEnabled else {
            await removeTaskReminders()
            return
        }

        let now = Date()
        if !force, let lastReminderSyncAt, now.timeIntervalSince(lastReminderSyncAt) < 12 {
            return
        }

        let granted = await requestReminderAuthorizationIfNeeded()
        isReminderAuthorizationGranted = granted
        guard granted else {
            return
        }

        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let existing = await pendingRequests(for: center)
        let ownedIdentifiers = existing
            .map(\.identifier)
            .filter { $0.hasPrefix(reminderIdentifierPrefix) }
        if !ownedIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ownedIdentifiers)
        }

        var requests: [UNNotificationRequest] = []
        for task in openTasks where shouldNotify(for: task, now: now) {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: task.dueAt
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let content = UNMutableNotificationContent()
            content.title = "Inventory Task Due"
            content.body = notificationBody(for: task)
            content.sound = .default
            content.userInfo = reminderUserInfo(action: task.action, taskID: task.id)
            let request = UNNotificationRequest(
                identifier: reminderIdentifier(for: task),
                content: content,
                trigger: trigger
            )
            requests.append(request)
            if requests.count >= 20 {
                break
            }
        }

        if !openTasks.isEmpty {
            let summaryDate = nextSummaryDate(from: now)
            let content = UNMutableNotificationContent()
            content.title = "Autopilot Shift Brief"
            content.body = summaryBody(openCount: openTasks.count)
            content.sound = .default
            content.userInfo = reminderUserInfo(
                action: .openAutomationInbox,
                taskID: nil,
                isSummary: true
            )
            let triggerComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: summaryDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            requests.append(
                UNNotificationRequest(
                    identifier: reminderSummaryIdentifier,
                    content: content,
                    trigger: trigger
                )
            )
        }

        for request in requests {
            await add(request, to: center)
        }
        #endif

        lastReminderSyncAt = now
    }

    private func removeTaskReminders() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let existing = await pendingRequests(for: center)
        let identifiers = existing
            .map(\.identifier)
            .filter { $0.hasPrefix(reminderIdentifierPrefix) }
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        #endif
        lastReminderSyncAt = Date()
    }

    private func requestReminderAuthorizationIfNeeded() async -> Bool {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            return granted
        @unknown default:
            return false
        }
        #else
        return false
        #endif
    }

    private func currentReminderAuthorizationState() async -> Bool {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
        #else
        return false
        #endif
    }

    #if canImport(UserNotifications)
    private func pendingRequests(for center: UNUserNotificationCenter) async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private func add(_ request: UNNotificationRequest, to center: UNUserNotificationCenter) async {
        await withCheckedContinuation { continuation in
            center.add(request) { _ in
                continuation.resume(returning: ())
            }
        }
    }
    #endif
}
