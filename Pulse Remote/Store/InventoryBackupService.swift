import Foundation
import CoreData

struct InventoryBackupService {
    func makeSnapshot(
        title: String,
        from allItems: [InventoryItemEntity],
        workspaceID: UUID?,
        createdAt: Date = Date()
    ) -> InventoryBackupSnapshot {
        let workspaceKey = workspaceKey(for: workspaceID)
        let snapshotItems = scopedItems(allItems, workspaceID: workspaceID)
            .map { InventoryBackupItem(item: $0) }
        return InventoryBackupSnapshot(
            id: UUID(),
            workspaceKey: workspaceKey,
            title: title,
            createdAt: createdAt,
            itemCount: snapshotItems.count,
            items: snapshotItems
        )
    }

    @discardableResult
    func restore(
        snapshot: InventoryBackupSnapshot,
        existingItems: [InventoryItemEntity],
        context: NSManagedObjectContext
    ) -> Int {
        let workspaceID = workspaceID(from: snapshot.workspaceKey)
        for item in scopedItems(existingItems, workspaceID: workspaceID) {
            context.delete(item)
        }

        for payload in snapshot.items {
            let item = InventoryItemEntity(context: context)
            apply(payload, to: item)
        }

        return snapshot.itemCount
    }

    func payloadRoundTripValid(_ snapshot: InventoryBackupSnapshot) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        guard let data = try? encoder.encode(snapshot),
              let decoded = try? decoder.decode(InventoryBackupSnapshot.self, from: data) else {
            return false
        }

        return decoded.id == snapshot.id
            && decoded.itemCount == snapshot.itemCount
            && decoded.items.count == snapshot.items.count
    }

    func scopedItemCount(in allItems: [InventoryItemEntity], workspaceID: UUID?) -> Int {
        scopedItems(allItems, workspaceID: workspaceID).count
    }

    private func scopedItems(_ items: [InventoryItemEntity], workspaceID: UUID?) -> [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(workspaceID) }
    }

    private func workspaceKey(for workspaceID: UUID?) -> String {
        workspaceID?.uuidString ?? "all"
    }

    private func workspaceID(from workspaceKey: String) -> UUID? {
        workspaceKey == "all" ? nil : UUID(uuidString: workspaceKey)
    }

    private func apply(_ backupItem: InventoryBackupItem, to item: InventoryItemEntity) {
        item.id = backupItem.id
        item.name = backupItem.name
        item.quantity = backupItem.quantity
        item.notes = backupItem.notes
        item.category = backupItem.category
        item.location = backupItem.location
        item.unitsPerCase = backupItem.unitsPerCase
        item.looseUnits = backupItem.looseUnits
        item.eachesPerUnit = backupItem.eachesPerUnit
        item.looseEaches = backupItem.looseEaches
        item.isLiquid = backupItem.isLiquid
        item.gallonFraction = backupItem.gallonFraction
        item.isPinned = backupItem.isPinned
        item.barcode = backupItem.barcode
        item.averageDailyUsage = backupItem.averageDailyUsage
        item.leadTimeDays = backupItem.leadTimeDays
        item.safetyStockUnits = backupItem.safetyStockUnits
        item.preferredSupplier = backupItem.preferredSupplier
        item.supplierSKU = backupItem.supplierSKU
        item.minimumOrderQuantity = backupItem.minimumOrderQuantity
        item.reorderCasePack = backupItem.reorderCasePack
        item.leadTimeVarianceDays = backupItem.leadTimeVarianceDays
        item.workspaceID = backupItem.workspaceID
        item.recentDemandSamples = backupItem.recentDemandSamples
        item.createdAt = backupItem.createdAt
        item.updatedAt = backupItem.updatedAt
    }
}
