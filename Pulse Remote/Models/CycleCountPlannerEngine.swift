import Foundation

enum CountPlanMode: String, CaseIterable, Identifiable {
    case express
    case balanced
    case deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .express:
            return "Express"
        case .balanced:
            return "Balanced"
        case .deep:
            return "Deep"
        }
    }

    var subtitle: String {
        switch self {
        case .express:
            return "Fast top risks"
        case .balanced:
            return "Most locations"
        case .deep:
            return "Full sweep"
        }
    }

    var itemLimit: Int {
        switch self {
        case .express:
            return 12
        case .balanced:
            return 24
        case .deep:
            return 40
        }
    }

    var targetDurationMinutes: Int {
        switch self {
        case .express:
            return 15
        case .balanced:
            return 30
        case .deep:
            return 60
        }
    }
}

enum CountPriorityBand: Int, CaseIterable, Hashable, Comparable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3

    static func < (lhs: CountPriorityBand, rhs: CountPriorityBand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .low:
            return "Routine"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .critical:
            return "Critical"
        }
    }
}

struct CountPlanInput: Identifiable, Hashable {
    let id: UUID
    let itemName: String
    let locationLabel: String
    let onHandUnits: Int64
    let averageDailyUsage: Double
    let leadTimeDays: Int
    let lastCountedAt: Date
    let missingBarcode: Bool
    let missingPlanningInputs: Bool
    let recentCorrectionCount: Int
}

struct CountPlanCandidate: Identifiable, Hashable {
    let id: UUID
    let itemName: String
    let locationLabel: String
    let zoneKey: String
    let onHandUnits: Int64
    let daysSinceCount: Int
    let score: Int
    let band: CountPriorityBand
    let reasons: [String]
    let estimatedSeconds: Int
}

struct CountPlanSummary: Hashable {
    let candidateCount: Int
    let criticalCount: Int
    let highCount: Int
    let mediumCount: Int
    let routineCount: Int
    let estimatedMinutes: Int
    let recommendedZoneLabel: String?
}

enum CycleCountPlannerEngine {
    static func buildPlan(
        inputs: [CountPlanInput],
        mode: CountPlanMode,
        now: Date = Date(),
        includeRoutine: Bool
    ) -> [CountPlanCandidate] {
        let evaluated = inputs.map { evaluate($0, now: now) }
        let filtered: [CountPlanCandidate]
        if includeRoutine {
            filtered = evaluated
        } else {
            filtered = evaluated.filter { $0.band != .low }
        }

        let sorted = filtered.sorted { lhs, rhs in
            if lhs.band != rhs.band {
                return lhs.band > rhs.band
            }
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.daysSinceCount != rhs.daysSinceCount {
                return lhs.daysSinceCount > rhs.daysSinceCount
            }
            return lhs.itemName.localizedCaseInsensitiveCompare(rhs.itemName) == .orderedAscending
        }

        return Array(sorted.prefix(mode.itemLimit))
    }

    static func summarize(candidates: [CountPlanCandidate]) -> CountPlanSummary {
        var criticalCount = 0
        var highCount = 0
        var mediumCount = 0
        var routineCount = 0
        var estimatedSeconds = 0
        var zoneScores: [String: Int] = [:]
        var zoneLabels: [String: String] = [:]

        for candidate in candidates {
            switch candidate.band {
            case .critical:
                criticalCount += 1
            case .high:
                highCount += 1
            case .medium:
                mediumCount += 1
            case .low:
                routineCount += 1
            }
            estimatedSeconds += candidate.estimatedSeconds
            zoneScores[candidate.zoneKey, default: 0] += candidate.score
            zoneLabels[candidate.zoneKey] = candidate.locationLabel
        }

        let recommendedZoneKey = zoneScores.max { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value < rhs.value
            }
            return lhs.key > rhs.key
        }?.key

        let recommendedZoneLabel = recommendedZoneKey.flatMap { zoneLabels[$0] }
        let estimatedMinutes = Int(ceil(Double(estimatedSeconds) / 60.0))

        return CountPlanSummary(
            candidateCount: candidates.count,
            criticalCount: criticalCount,
            highCount: highCount,
            mediumCount: mediumCount,
            routineCount: routineCount,
            estimatedMinutes: estimatedMinutes,
            recommendedZoneLabel: recommendedZoneLabel
        )
    }

    private static func evaluate(_ input: CountPlanInput, now: Date) -> CountPlanCandidate {
        let trimmedLocation = input.locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let locationLabel = trimmedLocation.isEmpty ? "No Location" : trimmedLocation
        let zoneKey = trimmedLocation.isEmpty ? "no-location" : trimmedLocation.lowercased()
        let onHandUnits = max(0, input.onHandUnits)
        let dailyDemand = max(0, input.averageDailyUsage)
        let leadTime = max(0, input.leadTimeDays)
        let corrections = max(0, input.recentCorrectionCount)
        let daysSinceCount = max(0, Calendar.current.dateComponents([.day], from: input.lastCountedAt, to: now).day ?? 0)

        var score = 0
        var reasons: [String] = []

        if daysSinceCount >= 21 {
            score += 28
            reasons.append("Count age is \(daysSinceCount)d.")
        } else if daysSinceCount >= 14 {
            score += 22
            reasons.append("Count age is \(daysSinceCount)d.")
        } else if daysSinceCount >= 7 {
            score += 15
            reasons.append("Count age is \(daysSinceCount)d.")
        } else if daysSinceCount >= 3 {
            score += 8
        }

        if input.missingPlanningInputs {
            score += 10
            reasons.append("Missing demand or lead-time inputs.")
        } else if dailyDemand > 0, leadTime > 0 {
            let daysOfCover = Double(onHandUnits) / dailyDemand
            let urgentThreshold = max(1, Double(leadTime) * 0.5)
            let riskThreshold = max(1, Double(leadTime))

            if onHandUnits == 0 {
                score += 24
                reasons.append("Out of stock with active demand.")
            } else if daysOfCover <= urgentThreshold {
                score += 18
                reasons.append("Cover is \(formatDays(daysOfCover))d vs urgent \(formatDays(urgentThreshold))d.")
            } else if daysOfCover <= riskThreshold {
                score += 11
                reasons.append("Cover is \(formatDays(daysOfCover))d vs lead \(formatDays(riskThreshold))d.")
            }
        }

        if input.missingBarcode {
            score += 7
            reasons.append("Barcode missing.")
        }

        if trimmedLocation.isEmpty {
            score += 6
            reasons.append("No zone assigned.")
        }

        if corrections >= 3 {
            score += 12
            reasons.append("\(corrections) corrections in last 30 days.")
        } else if corrections > 0 {
            score += 6
            reasons.append("\(corrections) recent correction(s).")
        }

        if reasons.isEmpty {
            reasons.append("Routine verification opportunity.")
        }

        let band: CountPriorityBand
        switch score {
        case 58...:
            band = .critical
        case 40...:
            band = .high
        case 24...:
            band = .medium
        default:
            band = .low
        }

        var estimatedSeconds: Int
        switch band {
        case .critical:
            estimatedSeconds = 155
        case .high:
            estimatedSeconds = 120
        case .medium:
            estimatedSeconds = 90
        case .low:
            estimatedSeconds = 70
        }
        if input.missingBarcode {
            estimatedSeconds += 16
        }
        if trimmedLocation.isEmpty {
            estimatedSeconds += 14
        }

        return CountPlanCandidate(
            id: input.id,
            itemName: input.itemName,
            locationLabel: locationLabel,
            zoneKey: zoneKey,
            onHandUnits: onHandUnits,
            daysSinceCount: daysSinceCount,
            score: score,
            band: band,
            reasons: reasons,
            estimatedSeconds: estimatedSeconds
        )
    }

    private static func formatDays(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
