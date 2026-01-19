import SwiftUI

@main
struct InventoryApp: App {
    @StateObject private var dataController = InventoryDataController()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ItemsListView()
                    .environment(\.managedObjectContext, dataController.container.viewContext)
                    .environmentObject(dataController)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        showSplash = false
                    }
                }
            }
        }
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            AmbientBackgroundView()
            VStack(spacing: 6) {
                Text("Built by")
                    .font(Theme.font(14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text("Reginald Wilson")
                    .font(Theme.font(22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .ignoresSafeArea()
    }
}
import CoreData
