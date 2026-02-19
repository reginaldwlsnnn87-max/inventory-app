import Foundation

enum TVAnalyticsEventName: String, Codable, CaseIterable {
    case appLaunch = "app_launch"
    case discoveryStarted = "discovery_started"
    case discoveryFinished = "discovery_finished"
    case connectAttempt = "connect_attempt"
    case connectResult = "connect_result"
    case commandAttempt = "command_attempt"
    case commandResult = "command_result"
    case paywallShown = "paywall_shown"
    case paywallDismissed = "paywall_dismissed"
    case paywallUpgradeTapped = "paywall_upgrade_tapped"
    case paywallRestoreTapped = "paywall_restore_tapped"
    case premiumUnlocked = "premium_unlocked"
    case automationCreated = "automation_created"
    case voiceSessionStarted = "voice_session_started"
}

struct TVAnalyticsSnapshot: Equatable {
    let generatedAt: Date
    let windowDays: Int
    let totalEvents: Int
    let appLaunches: Int
    let discoveryAttempts: Int
    let discoverySuccesses: Int
    let connectAttempts: Int
    let connectSuccesses: Int
    let commandAttempts: Int
    let commandSuccesses: Int
    let paywallImpressions: Int
    let paywallUpgradeTaps: Int
    let premiumUnlocks: Int

    var discoveryRateText: String {
        Self.percentText(successes: discoverySuccesses, attempts: discoveryAttempts)
    }

    var connectRateText: String {
        Self.percentText(successes: connectSuccesses, attempts: connectAttempts)
    }

    var commandRateText: String {
        Self.percentText(successes: commandSuccesses, attempts: commandAttempts)
    }

    var paywallConversionText: String {
        Self.percentText(successes: premiumUnlocks, attempts: paywallImpressions)
    }

    var funnelSummary: String {
        "Discover \(discoveryRateText) • Connect \(connectRateText) • Cmd \(commandRateText) • Paywall \(paywallConversionText)"
    }

    private static func percentText(successes: Int, attempts: Int) -> String {
        guard attempts > 0 else { return "N/A" }
        let rate = (Double(successes) / Double(attempts)) * 100
        return "\(Int(rate.rounded()))%"
    }
}

extension TVAnalyticsSnapshot {
    static let empty = TVAnalyticsSnapshot(
        generatedAt: Date(),
        windowDays: 30,
        totalEvents: 0,
        appLaunches: 0,
        discoveryAttempts: 0,
        discoverySuccesses: 0,
        connectAttempts: 0,
        connectSuccesses: 0,
        commandAttempts: 0,
        commandSuccesses: 0,
        paywallImpressions: 0,
        paywallUpgradeTaps: 0,
        premiumUnlocks: 0
    )
}

enum TVPremiumTier: String, Codable, Equatable {
    case free
    case pro
}

enum TVPremiumFeature: String, CaseIterable, Codable {
    case customAutomations
    case talkToTV
    case advancedInsights
    case macroShortcuts

    var title: String {
        switch self {
        case .customAutomations:
            return "Custom Automations"
        case .talkToTV:
            return "Talk to TV"
        case .advancedInsights:
            return "Reliability Insights"
        case .macroShortcuts:
            return "AI Scenes + Voice Macros"
        }
    }
}

struct TVPremiumSnapshot: Equatable {
    let tier: TVPremiumTier
    let isTrialActive: Bool
    let trialEndsAt: Date?
    let trialDaysRemaining: Int

    var statusLabel: String {
        if tier == .pro {
            return "Pro active"
        }
        if isTrialActive {
            return "Trial active • \(trialDaysRemaining)d left"
        }
        return "Free plan"
    }
}

extension TVPremiumSnapshot {
    static let empty = TVPremiumSnapshot(
        tier: .free,
        isTrialActive: false,
        trialEndsAt: nil,
        trialDaysRemaining: 0
    )
}

@MainActor
final class TVAnalyticsTracker {
    private struct Event: Codable {
        let name: TVAnalyticsEventName
        let timestamp: Date
        let metadata: [String: String]
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let windowDays: Int
    private let maxEvents: Int
    private var events: [Event]

    init(
        defaults: UserDefaults,
        storageKey: String,
        windowDays: Int = 30,
        maxEvents: Int = 4_000
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.windowDays = max(7, windowDays)
        self.maxEvents = max(500, maxEvents)
        events = Self.loadEvents(defaults: defaults, key: storageKey)
        pruneOldEvents(referenceDate: Date(), saveIfChanged: true)
    }

    func record(
        _ eventName: TVAnalyticsEventName,
        metadata: [String: String] = [:],
        at timestamp: Date = Date()
    ) {
        events.append(
            Event(
                name: eventName,
                timestamp: timestamp,
                metadata: metadata
            )
        )

        pruneOldEvents(referenceDate: timestamp, saveIfChanged: false)
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
        save()
    }

    func snapshot(referenceDate: Date = Date()) -> TVAnalyticsSnapshot {
        pruneOldEvents(referenceDate: referenceDate, saveIfChanged: true)

        func count(_ name: TVAnalyticsEventName) -> Int {
            events.filter { $0.name == name }.count
        }

        func countSuccess(_ name: TVAnalyticsEventName) -> Int {
            events.filter {
                $0.name == name && $0.metadata["success"] == "1"
            }.count
        }

        return TVAnalyticsSnapshot(
            generatedAt: referenceDate,
            windowDays: windowDays,
            totalEvents: events.count,
            appLaunches: count(.appLaunch),
            discoveryAttempts: count(.discoveryStarted),
            discoverySuccesses: countSuccess(.discoveryFinished),
            connectAttempts: count(.connectAttempt),
            connectSuccesses: countSuccess(.connectResult),
            commandAttempts: count(.commandAttempt),
            commandSuccesses: countSuccess(.commandResult),
            paywallImpressions: count(.paywallShown),
            paywallUpgradeTaps: count(.paywallUpgradeTapped),
            premiumUnlocks: count(.premiumUnlocked)
        )
    }

    private func pruneOldEvents(referenceDate: Date, saveIfChanged: Bool) {
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -windowDays, to: referenceDate) else {
            return
        }

        let previousCount = events.count
        events.removeAll { $0.timestamp < cutoffDate }
        if saveIfChanged, previousCount != events.count {
            save()
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(events)
            defaults.set(data, forKey: storageKey)
        } catch {
            // Best-effort persistence only.
        }
    }

    private static func loadEvents(defaults: UserDefaults, key: String) -> [Event] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        do {
            return try JSONDecoder().decode([Event].self, from: data)
        } catch {
            return []
        }
    }
}

@MainActor
final class TVPremiumAccessStore {
    private enum TierSource: String, Codable {
        case trial
        case legacyDeviceUnlock
        case storeKit
    }

    private let defaults: UserDefaults
    private let trialDays: Int
    private let tierKey = "tvremote.premium.tier.v1"
    private let tierSourceKey = "tvremote.premium.tier_source.v1"
    private let installDateKey = "tvremote.premium.install_date.v1"
    private let entitlementProductIDsKey = "tvremote.premium.entitlement_products.v1"

    init(defaults: UserDefaults, trialDays: Int = 7) {
        self.defaults = defaults
        self.trialDays = max(0, trialDays)

        if defaults.object(forKey: installDateKey) == nil {
            defaults.set(Date(), forKey: installDateKey)
        }

        if defaults.string(forKey: tierSourceKey) == nil {
            defaults.set(TierSource.trial.rawValue, forKey: tierSourceKey)
        }
    }

    func snapshot(referenceDate: Date = Date()) -> TVPremiumSnapshot {
        let tier = currentTier()
        guard tier == .free else {
            return TVPremiumSnapshot(
                tier: .pro,
                isTrialActive: false,
                trialEndsAt: nil,
                trialDaysRemaining: 0
            )
        }

        guard let installDate = defaults.object(forKey: installDateKey) as? Date,
              let trialEndsAt = Calendar.current.date(byAdding: .day, value: trialDays, to: installDate) else {
            return .empty
        }

        if referenceDate >= trialEndsAt {
            return TVPremiumSnapshot(
                tier: .free,
                isTrialActive: false,
                trialEndsAt: trialEndsAt,
                trialDaysRemaining: 0
            )
        }

        let remaining = max(Calendar.current.dateComponents([.day], from: referenceDate, to: trialEndsAt).day ?? 0, 0)
        return TVPremiumSnapshot(
            tier: .free,
            isTrialActive: true,
            trialEndsAt: trialEndsAt,
            trialDaysRemaining: remaining + 1
        )
    }

    func hasAccess(to feature: TVPremiumFeature, referenceDate: Date = Date()) -> Bool {
        switch feature {
        case .customAutomations, .talkToTV, .advancedInsights, .macroShortcuts:
            let state = snapshot(referenceDate: referenceDate)
            return state.tier == .pro || state.isTrialActive
        }
    }

    func unlockProForDevice() {
        defaults.set(TVPremiumTier.pro.rawValue, forKey: tierKey)
        defaults.set(TierSource.legacyDeviceUnlock.rawValue, forKey: tierSourceKey)
    }

    func restorePurchases() -> Bool {
        if !entitlementProductIDs().isEmpty {
            defaults.set(TVPremiumTier.pro.rawValue, forKey: tierKey)
            defaults.set(TierSource.storeKit.rawValue, forKey: tierSourceKey)
            return true
        }
        return currentTier() == .pro
    }

    @discardableResult
    func syncEntitlements(productIDs: Set<String>) -> Bool {
        let normalized = Set(
            productIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        defaults.set(Array(normalized).sorted(), forKey: entitlementProductIDsKey)

        if !normalized.isEmpty {
            defaults.set(TVPremiumTier.pro.rawValue, forKey: tierKey)
            defaults.set(TierSource.storeKit.rawValue, forKey: tierSourceKey)
            return true
        }

        if currentTierSource() == .storeKit {
            defaults.set(TVPremiumTier.free.rawValue, forKey: tierKey)
            defaults.set(TierSource.trial.rawValue, forKey: tierSourceKey)
            return false
        }

        return currentTier() == .pro
    }

    func entitlementProductIDs() -> Set<String> {
        let raw = defaults.array(forKey: entitlementProductIDsKey) as? [String] ?? []
        return Set(raw)
    }

    private func currentTier() -> TVPremiumTier {
        guard let rawValue = defaults.string(forKey: tierKey),
              let tier = TVPremiumTier(rawValue: rawValue) else {
            return .free
        }
        return tier
    }

    private func currentTierSource() -> TierSource {
        guard let rawValue = defaults.string(forKey: tierSourceKey),
              let source = TierSource(rawValue: rawValue) else {
            return .trial
        }
        return source
    }
}
