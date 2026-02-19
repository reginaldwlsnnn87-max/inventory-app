import SwiftUI

struct TVRemoteAppView: View {
    @StateObject private var viewModel = TVRemoteAppViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            RemoteControlView(viewModel: viewModel)
                .navigationBarHidden(true)
        }
        .sheet(isPresented: $viewModel.isDevicePickerPresented) {
            DevicesListView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isPremiumPaywallPresented) {
            PremiumPaywallView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isSceneComposerPresented) {
            SmartSceneComposerView(viewModel: viewModel)
        }
        .task {
            viewModel.startIfNeeded()
            if viewModel.activeDevice == nil {
                viewModel.isDevicePickerPresented = true
            }
        }
        .onChange(of: viewModel.isPremiumPaywallPresented) { _, isPresented in
            viewModel.handlePremiumPaywallPresentationChanged(isPresented: isPresented)
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhase(newPhase)
        }
        .onOpenURL { url in
            viewModel.handleIncomingURL(url)
        }
        .alert(
            "Connection Error",
            isPresented: Binding(
                get: { viewModel.transientErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        viewModel.clearTransientError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.clearTransientError()
            }
        } message: {
            Text(viewModel.transientErrorMessage ?? "")
        }
        .preferredColorScheme(.dark)
    }
}

struct TVRemoteAppView_Previews: PreviewProvider {
    static var previews: some View {
        TVRemoteAppView()
    }
}
