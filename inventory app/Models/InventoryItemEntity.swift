import CoreData
import Foundation

@objc(InventoryItemEntity)
final class InventoryItemEntity: NSManagedObject {}

extension InventoryItemEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<InventoryItemEntity> {
        NSFetchRequest<InventoryItemEntity>(entityName: "InventoryItemEntity")
    }

    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var quantity: Int64
    @NSManaged var notes: String
    @NSManaged var category: String
    @NSManaged var location: String
    @NSManaged var unitsPerCase: Int64
    @NSManaged var looseUnits: Int64
    @NSManaged var eachesPerUnit: Int64
    @NSManaged var looseEaches: Int64
    @NSManaged var isLiquid: Bool
    @NSManaged var gallonFraction: Double
    @NSManaged var isPinned: Bool
    @NSManaged var barcode: String
    @NSManaged var averageDailyUsage: Double
    @NSManaged var leadTimeDays: Int64
    @NSManaged var safetyStockUnits: Int64
    @NSManaged var preferredSupplier: String
    @NSManaged var supplierSKU: String
    @NSManaged var minimumOrderQuantity: Int64
    @NSManaged var reorderCasePack: Int64
    @NSManaged var leadTimeVarianceDays: Int64
    @NSManaged var workspaceID: String
    @NSManaged var recentDemandSamples: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
}

extension InventoryItemEntity {
    var safeUpdatedAt: Date {
        if let date = primitiveValue(forKey: "updatedAt") as? Date {
            return date
        }
        if let created = primitiveValue(forKey: "createdAt") as? Date {
            return created
        }
        return .distantPast
    }

    var totalGallonsOnHand: Double {
        max(0, Double(looseUnits) + gallonFraction)
    }

    var totalUnitsOnHand: Int64 {
        if isLiquid {
            return Int64((totalGallonsOnHand * 128).rounded())
        }
        if unitsPerCase > 0 {
            return max(0, quantity * unitsPerCase + looseUnits)
        }
        return max(0, quantity + looseUnits)
    }

    func applyTotalNonLiquidUnits(_ totalUnits: Int64, resetLooseEaches: Bool = false) {
        let clamped = max(0, totalUnits)
        if unitsPerCase > 0 {
            quantity = clamped / unitsPerCase
            looseUnits = clamped % unitsPerCase
        } else {
            quantity = clamped
            looseUnits = 0
        }
        if resetLooseEaches {
            looseEaches = 0
        }
    }

    func applyTotalGallons(_ gallons: Double) {
        let clamped = max(0, gallons)
        let whole = floor(clamped)
        looseUnits = Int64(whole)
        gallonFraction = clamped - whole
    }

    func applyTotalUnits(_ totalUnits: Int64) {
        let clamped = max(0, totalUnits)
        if isLiquid {
            applyTotalGallons(Double(clamped) / 128.0)
        } else {
            applyTotalNonLiquidUnits(clamped)
        }
    }

    var dailyDemandSamples: [Double] {
        recentDemandSamples
            .split(separator: ",")
            .compactMap { token in
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value = Double(trimmed), value >= 0 else { return nil }
                return value
            }
    }

    var movingAverageDailyDemand: Double? {
        let samples = dailyDemandSamples
        guard !samples.isEmpty else { return nil }
        let total = samples.reduce(0, +)
        return total / Double(samples.count)
    }

    func setDailyDemandSamples(_ samples: [Double], limit: Int = 14) {
        let boundedLimit = max(1, limit)
        let normalized = samples
            .map { max(0, $0) }
            .suffix(boundedLimit)
        recentDemandSamples = normalized
            .map { String(format: "%.3f", $0) }
            .joined(separator: ",")
    }

    func appendDailyDemandSample(_ value: Double, limit: Int = 14) {
        var samples = dailyDemandSamples
        samples.append(max(0, value))
        let boundedLimit = max(1, limit)
        samples = Array(samples.suffix(boundedLimit))
        recentDemandSamples = samples
            .map { String(format: "%.3f", $0) }
            .joined(separator: ",")
    }

    func isInWorkspace(_ activeWorkspaceID: UUID?) -> Bool {
        guard let activeWorkspaceID else { return true }
        let trimmed = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        return trimmed == activeWorkspaceID.uuidString
    }

    func assignWorkspaceIfNeeded(_ activeWorkspaceID: UUID?) {
        guard let activeWorkspaceID else { return }
        if workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            workspaceID = activeWorkspaceID.uuidString
        }
    }

    var normalizedPreferredSupplier: String {
        preferredSupplier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedSupplierSKU: String {
        supplierSKU.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func adjustedSuggestedOrderUnits(from baseUnits: Int64) -> Int64 {
        var units = max(0, baseUnits)
        guard units > 0 else { return 0 }

        let moq = max(0, minimumOrderQuantity)
        if moq > 0 && units < moq {
            units = moq
        }

        let casePack = max(0, reorderCasePack)
        if casePack > 1 {
            let remainder = units % casePack
            if remainder != 0 {
                units += casePack - remainder
            }
        }

        return units
    }
}

extension InventoryItemEntity: Identifiable {}
