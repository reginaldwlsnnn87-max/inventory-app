import CoreData
import Foundation
import Combine

final class InventoryDataController: ObservableObject {
    let container: NSPersistentContainer

    init() {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "InventoryModel", managedObjectModel: model)
        if let description = container.persistentStoreDescriptions.first {
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }
        container.loadPersistentStores { _, _ in }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
        }
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
        let createdAt = attribute(name: "createdAt", type: .dateAttributeType, optional: false)
        let updatedAt = attribute(name: "updatedAt", type: .dateAttributeType, optional: false)

        entity.properties = [id, name, quantity, notes, category, location, unitsPerCase, looseUnits, eachesPerUnit, looseEaches, isLiquid, gallonFraction, createdAt, updatedAt]
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
