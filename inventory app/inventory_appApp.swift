import SwiftUI

@main
struct InventoryApp: App {
    @StateObject private var dataController = InventoryDataController()

    var body: some Scene {
        WindowGroup {
            ItemsListView()
                .environment(\.managedObjectContext, dataController.container.viewContext)
                .environmentObject(dataController)
        }
    }
}
import CoreData

