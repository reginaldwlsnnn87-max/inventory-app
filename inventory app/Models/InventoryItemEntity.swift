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
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
}

extension InventoryItemEntity: Identifiable {}

