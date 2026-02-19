import Foundation
import Combine

enum GuidedFlow: String, CaseIterable, Identifiable {
    case addItem
    case zoneMission
    case replenishment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addItem:
            return "Add Item Fast"
        case .zoneMission:
            return "Zone Mission"
        case .replenishment:
            return "Replenishment"
        }
    }

    var subtitle: String {
        switch self {
        case .addItem:
            return "Build clean item records in under a minute."
        case .zoneMission:
            return "Run fast on-floor counts by location."
        case .replenishment:
            return "Turn demand into clear order actions."
        }
    }

    var systemImage: String {
        switch self {
        case .addItem:
            return "plus.circle.fill"
        case .zoneMission:
            return "map.fill"
        case .replenishment:
            return "chart.line.uptrend.xyaxis"
        }
    }
}

enum CoachMarkTarget: String, CaseIterable, Identifiable {
    case quickAddButton
    case quickActionsButton
    case menuButton
    case shiftMode
    case quickCountBar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickAddButton:
            return "Quick Add Button"
        case .quickActionsButton:
            return "Quick Actions"
        case .menuButton:
            return "Main Menu"
        case .shiftMode:
            return "Shift Sort"
        case .quickCountBar:
            return "Quick Count Bar"
        }
    }

    var detail: String {
        switch self {
        case .quickAddButton:
            return "Tap this bolt to add items fast when you are moving quickly."
        case .quickActionsButton:
            return "Use this for one-tap access to high-impact tools like Zone Mission and KPI Dashboard."
        case .menuButton:
            return "Open Menu for Guided Help, workspace settings, and advanced workflows."
        case .shiftMode:
            return "Open, Mid, and Close sorting helps teams focus on what matters this shift."
        case .quickCountBar:
            return "Use this bottom bar for quick add, set amount, and note updates without leaving the list."
        }
    }

    var icon: String {
        switch self {
        case .quickAddButton:
            return "bolt.fill"
        case .quickActionsButton:
            return "ellipsis.circle"
        case .menuButton:
            return "line.3.horizontal"
        case .shiftMode:
            return "line.3.horizontal.decrease.circle"
        case .quickCountBar:
            return "slider.horizontal.3"
        }
    }
}

enum GuidanceNudgeAction {
    case openZoneMission
    case openReplenishment
    case openKPIDashboard
    case openGuidedHelp
}

private enum GuidanceNudgeKind: String {
    case zoneMissionCadence
    case replenishmentRisk
    case kpiReview
    case locationHygiene
    case demandDataHygiene
    case guidedKickoff
    case guidedRecoveryZoneMission
    case guidedRecoveryReplenishment

    var repeatInterval: TimeInterval {
        switch self {
        case .replenishmentRisk:
            return 3 * 60 * 60
        case .zoneMissionCadence:
            return 4 * 60 * 60
        case .kpiReview:
            return 8 * 60 * 60
        case .locationHygiene, .demandDataHygiene:
            return 12 * 60 * 60
        case .guidedKickoff:
            return 24 * 60 * 60
        case .guidedRecoveryZoneMission, .guidedRecoveryReplenishment:
            return 24 * 60 * 60
        }
    }

    var dismissCooldown: TimeInterval {
        switch self {
        case .replenishmentRisk, .zoneMissionCadence:
            return 2 * 60 * 60
        case .kpiReview:
            return 4 * 60 * 60
        case .locationHygiene, .demandDataHygiene:
            return 8 * 60 * 60
        case .guidedKickoff, .guidedRecoveryZoneMission, .guidedRecoveryReplenishment:
            return 12 * 60 * 60
        }
    }
}

struct GuidanceNudge: Identifiable, Equatable {
    fileprivate let kind: GuidanceNudgeKind
    let title: String
    let message: String
    let actionTitle: String
    let action: GuidanceNudgeAction
    let systemImage: String
    let badge: String?

    var id: String {
        kind.rawValue
    }
}

struct GuidanceSignals: Equatable {
    let isAuthenticated: Bool
    let role: WorkspaceRole
    let itemCount: Int
    let staleItemCount: Int
    let missingLocationCount: Int
    let stockoutRiskCount: Int
    let urgentReplenishmentCount: Int
    let coverageReadyCount: Int
    let missingDemandInputCount: Int
}

@MainActor
final class GuidanceStore: ObservableObject {
    @Published var isShowingGuideCenter = false
    @Published var isFirstRunGuideContext = false
    @Published var isShowingCoachMarks = false
    @Published private(set) var coachStepIndex = 0
    @Published private(set) var activeNudge: GuidanceNudge?

    private let defaults: UserDefaults
    private let hasSeenGuideKey = "inventory.guidance.seen.v1"
    private let hasSeenCoachMarksKey = "inventory.guidance.coachmarks.seen.v1"
    private let completedPrefix = "inventory.guidance.completed."
    private let engagedPrefix = "inventory.guidance.engaged."
    private let nudgeShownPrefix = "inventory.guidance.nudge.shown."
    private let nudgeDismissedPrefix = "inventory.guidance.nudge.dismissed."
    private let nudgeDismissCountPrefix = "inventory.guidance.nudge.dismissCount."
    private let nudgeActionPrefix = "inventory.guidance.nudge.action."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shouldShowFirstRunGuide: Bool {
        !defaults.bool(forKey: hasSeenGuideKey)
    }

    func presentFirstRunGuideIfNeeded(isAuthenticated: Bool) {
        guard isAuthenticated, shouldShowFirstRunGuide else { return }
        activeNudge = nil
        isFirstRunGuideContext = true
        isShowingGuideCenter = true
    }

    func openGuideCenter() {
        activeNudge = nil
        isShowingCoachMarks = false
        isFirstRunGuideContext = false
        isShowingGuideCenter = true
    }

    func closeGuideCenter(markSeen: Bool = true) {
        if markSeen {
            defaults.set(true, forKey: hasSeenGuideKey)
        }
        isShowingGuideCenter = false
        isFirstRunGuideContext = false
    }

    func markFlowCompleted(_ flow: GuidedFlow) {
        defaults.set(true, forKey: completionKey(for: flow))
        markFlowEngaged(flow)
    }

    func isFlowCompleted(_ flow: GuidedFlow) -> Bool {
        defaults.bool(forKey: completionKey(for: flow))
    }

    func markFlowEngaged(_ flow: GuidedFlow) {
        defaults.set(true, forKey: engagementKey(for: flow))
    }

    func isFlowEngaged(_ flow: GuidedFlow) -> Bool {
        defaults.bool(forKey: engagementKey(for: flow))
    }

    var shouldShowCoachMarks: Bool {
        !defaults.bool(forKey: hasSeenCoachMarksKey)
    }

    var activeCoachTarget: CoachMarkTarget? {
        guard isShowingCoachMarks else { return nil }
        let all = CoachMarkTarget.allCases
        guard all.indices.contains(coachStepIndex) else { return nil }
        return all[coachStepIndex]
    }

    var isLastCoachStep: Bool {
        coachStepIndex >= CoachMarkTarget.allCases.count - 1
    }

    func startCoachMarksIfNeeded(isAuthenticated: Bool) {
        guard isAuthenticated,
              !isShowingGuideCenter,
              shouldShowCoachMarks,
              !isShowingCoachMarks else { return }
        activeNudge = nil
        coachStepIndex = 0
        isShowingCoachMarks = true
    }

    func restartCoachMarks() {
        activeNudge = nil
        coachStepIndex = 0
        isShowingCoachMarks = true
    }

    func advanceCoachMark() {
        if isLastCoachStep {
            completeCoachMarks(markSeen: true)
        } else {
            coachStepIndex += 1
        }
    }

    func skipCoachMarks() {
        completeCoachMarks(markSeen: true)
    }

    func refreshNudge(using signals: GuidanceSignals) {
        guard signals.isAuthenticated,
              !isShowingGuideCenter,
              !isShowingCoachMarks else {
            activeNudge = nil
            return
        }

        let candidates = nudgeCandidates(for: signals)
        guard !candidates.isEmpty else {
            activeNudge = nil
            return
        }

        let now = Date()
        for candidate in candidates {
            if let activeNudge, activeNudge.id == candidate.id {
                self.activeNudge = candidate
                return
            }
            if shouldPresentNudge(ofKind: candidate.kind, at: now) {
                recordNudgeShown(candidate.kind, at: now)
                activeNudge = candidate
                return
            }
        }

        activeNudge = nil
    }

    func dismissActiveNudge() {
        guard let activeNudge else { return }
        recordNudgeDismissed(activeNudge.kind, at: Date())
        self.activeNudge = nil
    }

    func acknowledgeActiveNudgeAction() {
        guard let activeNudge else { return }
        recordNudgeAction(activeNudge.kind, at: Date())
        defaults.set(0, forKey: dismissCountKey(for: activeNudge.kind))
        self.activeNudge = nil
    }

    private func completeCoachMarks(markSeen: Bool) {
        if markSeen {
            defaults.set(true, forKey: hasSeenCoachMarksKey)
        }
        isShowingCoachMarks = false
        coachStepIndex = 0
    }

    private func completionKey(for flow: GuidedFlow) -> String {
        completedPrefix + flow.rawValue
    }

    private func engagementKey(for flow: GuidedFlow) -> String {
        engagedPrefix + flow.rawValue
    }

    private var hasGuidedProgress: Bool {
        GuidedFlow.allCases.contains { flow in
            isFlowCompleted(flow) || isFlowEngaged(flow)
        }
    }

    private func nudgeCandidates(for signals: GuidanceSignals) -> [GuidanceNudge] {
        guard signals.itemCount > 0 else {
            return []
        }

        var nudges: [GuidanceNudge] = []

        switch signals.role {
        case .owner, .manager:
            if shouldOfferRecoveryNudge(for: .replenishmentRisk, flow: .replenishment) {
                nudges.append(
                    GuidanceNudge(
                        kind: .guidedRecoveryReplenishment,
                        title: "Need help setting reorder logic?",
                        message: "You skipped replenishment suggestions a few times. Run Guided Help to set this up once and speed up every week.",
                        actionTitle: "Open Guided Help",
                        action: .openGuidedHelp,
                        systemImage: "questionmark.bubble",
                        badge: "Recovery"
                    )
                )
            }

            if signals.urgentReplenishmentCount >= 3 {
                nudges.append(
                    GuidanceNudge(
                        kind: .replenishmentRisk,
                        title: "Urgent stockout risk detected",
                        message: "\(signals.urgentReplenishmentCount) item(s) are at urgent replenishment risk. Build a draft order plan now.",
                        actionTitle: "Open Replenishment",
                        action: .openReplenishment,
                        systemImage: "chart.line.uptrend.xyaxis",
                        badge: "High Impact"
                    )
                )
            }

            if signals.stockoutRiskCount >= 2 && signals.coverageReadyCount >= 4 {
                nudges.append(
                    GuidanceNudge(
                        kind: .kpiReview,
                        title: "Run a KPI health check",
                        message: "\(signals.stockoutRiskCount) coverage-ready item(s) are at risk. Review dashboard signals before the next ordering cycle.",
                        actionTitle: "Open KPI Dashboard",
                        action: .openKPIDashboard,
                        systemImage: "chart.bar.doc.horizontal",
                        badge: "Manager Focus"
                    )
                )
            }

            if signals.missingLocationCount >= max(6, signals.itemCount / 2) {
                nudges.append(
                    GuidanceNudge(
                        kind: .locationHygiene,
                        title: "Location data is thin",
                        message: "\(signals.missingLocationCount) item(s) are missing a location. Run Zone Mission to prioritize cleanup and faster counts.",
                        actionTitle: "Open Zone Mission",
                        action: .openZoneMission,
                        systemImage: "map.fill",
                        badge: "Data Quality"
                    )
                )
            }

            if signals.missingDemandInputCount >= max(5, signals.itemCount / 2) {
                nudges.append(
                    GuidanceNudge(
                        kind: .demandDataHygiene,
                        title: "Demand inputs need setup",
                        message: "\(signals.missingDemandInputCount) item(s) are missing demand or lead-time data. Guided Help can walk your team through setup.",
                        actionTitle: "Open Guided Help",
                        action: .openGuidedHelp,
                        systemImage: "slider.horizontal.3",
                        badge: "Setup"
                    )
                )
            }
        case .staff:
            if shouldOfferRecoveryNudge(for: .zoneMissionCadence, flow: .zoneMission) {
                nudges.append(
                    GuidanceNudge(
                        kind: .guidedRecoveryZoneMission,
                        title: "Need a faster counting flow?",
                        message: "You skipped Zone Mission reminders a few times. Run the short walkthrough once to speed up shift counts.",
                        actionTitle: "Open Guided Help",
                        action: .openGuidedHelp,
                        systemImage: "questionmark.bubble",
                        badge: "Recovery"
                    )
                )
            }

            if signals.staleItemCount >= max(4, signals.itemCount / 3) {
                nudges.append(
                    GuidanceNudge(
                        kind: .zoneMissionCadence,
                        title: "Count freshness is slipping",
                        message: "\(signals.staleItemCount) item(s) have not been touched in 7+ days. Run a quick Zone Mission this shift.",
                        actionTitle: "Open Zone Mission",
                        action: .openZoneMission,
                        systemImage: "map.fill",
                        badge: "Shift Focus"
                    )
                )
            }
        }

        if !hasGuidedProgress && signals.itemCount >= 5 {
            nudges.append(
                GuidanceNudge(
                    kind: .guidedKickoff,
                    title: "Start with a guided workflow",
                    message: "Your team will move faster with one short tour. Learn a core flow, then run it live right away.",
                    actionTitle: "Open Guided Help",
                    action: .openGuidedHelp,
                    systemImage: "sparkles",
                    badge: "New"
                )
            )
        }

        return nudges
    }

    private func shouldOfferRecoveryNudge(for kind: GuidanceNudgeKind, flow: GuidedFlow) -> Bool {
        dismissCount(for: kind) >= 2 && !isFlowCompleted(flow) && !isFlowEngaged(flow)
    }

    private func shouldPresentNudge(ofKind kind: GuidanceNudgeKind, at now: Date) -> Bool {
        if let lastShown = storedDate(forKey: shownKey(for: kind)),
           now.timeIntervalSince(lastShown) < kind.repeatInterval {
            return false
        }

        if let lastDismissed = storedDate(forKey: dismissedKey(for: kind)),
           now.timeIntervalSince(lastDismissed) < kind.dismissCooldown {
            return false
        }

        return true
    }

    private func dismissCount(for kind: GuidanceNudgeKind) -> Int {
        defaults.integer(forKey: dismissCountKey(for: kind))
    }

    private func recordNudgeShown(_ kind: GuidanceNudgeKind, at date: Date) {
        storeDate(date, forKey: shownKey(for: kind))
    }

    private func recordNudgeDismissed(_ kind: GuidanceNudgeKind, at date: Date) {
        storeDate(date, forKey: dismissedKey(for: kind))
        let count = dismissCount(for: kind)
        defaults.set(count + 1, forKey: dismissCountKey(for: kind))
    }

    private func recordNudgeAction(_ kind: GuidanceNudgeKind, at date: Date) {
        storeDate(date, forKey: actionKey(for: kind))
    }

    private func shownKey(for kind: GuidanceNudgeKind) -> String {
        nudgeShownPrefix + kind.rawValue
    }

    private func dismissedKey(for kind: GuidanceNudgeKind) -> String {
        nudgeDismissedPrefix + kind.rawValue
    }

    private func dismissCountKey(for kind: GuidanceNudgeKind) -> String {
        nudgeDismissCountPrefix + kind.rawValue
    }

    private func actionKey(for kind: GuidanceNudgeKind) -> String {
        nudgeActionPrefix + kind.rawValue
    }

    private func storeDate(_ date: Date, forKey key: String) {
        defaults.set(date.timeIntervalSince1970, forKey: key)
    }

    private func storedDate(forKey key: String) -> Date? {
        guard defaults.object(forKey: key) != nil else { return nil }
        let value = defaults.double(forKey: key)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }
}
