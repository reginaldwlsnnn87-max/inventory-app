import CoreData
import Foundation
import Combine

final class InventoryDataController: ObservableObject {
    let container: NSPersistentContainer
    @Published private(set) var storageErrorMessage: String?

    init() {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "InventoryModel", managedObjectModel: model)
        if let description = container.persistentStoreDescriptions.first {
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }
        container.loadPersistentStores { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.storageErrorMessage = "Storage unavailable. Restart the app and verify local disk access. (\(error.localizedDescription))"
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
            storageErrorMessage = nil
        } catch {
            context.rollback()
            storageErrorMessage = "Could not save inventory changes. Your last edit was not written. (\(error.localizedDescription))"
        }
    }

    func deleteAllItems() {
        let context = container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "InventoryItemEntity")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        do {
            _ = try context.execute(deleteRequest)
            storageErrorMessage = nil
        } catch {
            storageErrorMessage = "Could not clear inventory items. (\(error.localizedDescription))"
        }
        context.reset()
    }

    func clearStorageError() {
        storageErrorMessage = nil
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "InventoryItemEntity"
        entity.managedObjectClassName = NSStringFromClass(InventoryItemEntity.self)

        let id = attribute(name: "id", type: .UUIDAttributeType, optional: false)
        let name = attribute(name: "name", type: .stringAttributeType, optional: false, defaultValue: "")
        let quantity = attribute(name: "quantity", type: .integer64AttributeType, optional: false, defaultValue: 0)
        let notes = attribute(name: "notes", type: .stringAttributeType, optional: false, defaultValue: "")
        let category = attribute(name: "category", type: .stringAttributeType, optional: false, defaultValue: "")
        let location = attribute(name: "location", type: .stringAttributeType, optional: false, defaultValue: "")
        let unitsPerCase = attribute(name: "unitsPerCase", type: .integer64AttributeType, optional: false, defaultValue: 0)
        let looseUnits = attribute(name: "looseUnits", type: .integer64AttributeType, optional: false, defaultValue: 0)
        let eachesPerUnit = attribute(name: "eachesPerUnit", type: .integer64AttributeType, optional: false, defaultValue: 0)
        let looseEaches = attribute(name: "looseEaches", type: .integer64AttributeType, optional: false, defaultValue: 0)
        let isLiquid = attribute(name: "isLiquid", type: .booleanAttributeType, optional: false, defaultValue: false)
        let gallonFraction = attribute(name: "gallonFraction", type: .doubleAttributeType, optional: false, defaultValue: 0.0)
        let isPinned = attribute(name: "isPinned", type: .booleanAttributeType, optional: false, defaultValue: false)
        let barcode = attribute(name: "barcode", type: .stringAttributeType, optional: false, defaultValue: "")
        let averageDailyUsage = attribute(name: "averageDailyUsage", type: .doubleAttributeType, optional: false, defaultValue: 0.0)
        let leadTimeDays = attribute(name: "leadTimeDays", type: .integer64AttributeType, optional: false, defaultValue: 0)
        let safetyStockUnits = attribute(name: "safetyStockUnits", type: .integer64AttributeType, optional: false, defaultValue: 0)
        let preferredSupplier = attribute(name: "preferredSupplier", type: .stringAttributeType, optional: false, defaultValue: "")
        let supplierSKU = attribute(name: "supplierSKU", type: .stringAttributeType, optional: false, defaultValue: "")
        let minimumOrderQuantity = attribute(name: "minimumOrderQuantity", type: .integer64AttributeType, optional: false, defaultValue: 0)
        let reorderCasePack = attribute(name: "reorderCasePack", type: .integer64AttributeType, optional: false, defaultValue: 0)
        let leadTimeVarianceDays = attribute(name: "leadTimeVarianceDays", type: .integer64AttributeType, optional: false, defaultValue: 0)
        let workspaceID = attribute(name: "workspaceID", type: .stringAttributeType, optional: false, defaultValue: "")
        let recentDemandSamples = attribute(name: "recentDemandSamples", type: .stringAttributeType, optional: false, defaultValue: "")
        let createdAt = attribute(name: "createdAt", type: .dateAttributeType, optional: false)
        let updatedAt = attribute(name: "updatedAt", type: .dateAttributeType, optional: false)

        entity.properties = [
            id,
            name,
            quantity,
            notes,
            category,
            location,
            unitsPerCase,
            looseUnits,
            eachesPerUnit,
            looseEaches,
            isLiquid,
            gallonFraction,
            isPinned,
            barcode,
            averageDailyUsage,
            leadTimeDays,
            safetyStockUnits,
            preferredSupplier,
            supplierSKU,
            minimumOrderQuantity,
            reorderCasePack,
            leadTimeVarianceDays,
            workspaceID,
            recentDemandSamples,
            createdAt,
            updatedAt
        ]
        model.entities = [entity]
        return model
    }

    private static func attribute(
        name: String,
        type: NSAttributeType,
        optional: Bool,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        attribute.defaultValue = defaultValue
        return attribute
    }
}
