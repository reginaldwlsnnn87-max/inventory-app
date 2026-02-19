import SwiftUI

struct SmartSceneComposerView: View {
    @ObservedObject var viewModel: TVRemoteAppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Scene Details") {
                    TextField("Scene name", text: $viewModel.sceneDraftName)

                    Picker(
                        "Icon",
                        selection: $viewModel.sceneDraftIconSystemName
                    ) {
                        ForEach(viewModel.sceneIconChoices, id: \.self) { icon in
                            Label(iconTitle(for: icon), systemImage: icon)
                                .tag(icon)
                        }
                    }

                    Text(viewModel.smartScenesPlanSummary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Section("Actions") {
                    if viewModel.sceneDraftActions.isEmpty {
                        Text("Add at least one action.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(viewModel.sceneDraftActions.enumerated()), id: \.element.id) { index, action in
                            SmartSceneDraftActionRow(
                                index: index,
                                action: action,
                                viewModel: viewModel
                            )
                        }
                    }

                    Button {
                        viewModel.addSceneDraftAction()
                    } label: {
                        Label("Add Action", systemImage: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .disabled(!viewModel.canAddSceneDraftAction)
                    .opacity(viewModel.canAddSceneDraftAction ? 1 : 0.45)

                    Text(viewModel.smartSceneComposerActionLimitLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    if !viewModel.canAddSceneDraftAction {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Free limit reached. Pro unlocks unlimited scene actions.")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)

                            Button("Upgrade to Pro") {
                                viewModel.presentPremiumPaywall(source: "smart_scene_action_limit")
                            }
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 4)
                    }
                }

                if let sceneDraftMessage = viewModel.sceneDraftMessage {
                    Section {
                        Text(sceneDraftMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Smart Scene")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        viewModel.isSceneComposerPresented = false
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        viewModel.saveSmartSceneFromDraft()
                    }
                }
            }
        }
    }

    private func iconTitle(for icon: String) -> String {
        switch icon {
        case "sparkles.tv.fill":
            return "TV Night"
        case "moon.stars.fill":
            return "Wind Down"
        case "bolt.fill":
            return "Quick Start"
        case "play.rectangle.fill":
            return "Watch Now"
        case "sportscourt.fill":
            return "Sports"
        case "house.fill":
            return "Home"
        case "film.stack.fill":
            return "Movie"
        case "gamecontroller.fill":
            return "Gaming"
        default:
            return "Scene"
        }
    }
}

private struct SmartSceneDraftActionRow: View {
    let index: Int
    let action: TVSceneAction
    @ObservedObject var viewModel: TVRemoteAppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(
                "Step \(index + 1)",
                selection: Binding(
                    get: { action.kind },
                    set: { viewModel.updateSceneDraftActionKind(action.id, kind: $0) }
                )
            ) {
                ForEach(TVSceneActionKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }

            switch action.kind {
            case .setVolume:
                HStack(spacing: 12) {
                    Slider(
                        value: Binding(
                            get: {
                                Double(Int(action.payload ?? "20") ?? 20)
                            },
                            set: {
                                viewModel.updateSceneDraftActionPayload(
                                    action.id,
                                    payload: String(Int($0.rounded()))
                                )
                            }
                        ),
                        in: 0 ... 100,
                        step: 1
                    )

                    Text("\(Int(action.payload ?? "20") ?? 20)%")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 44, alignment: .trailing)
                }
            case .launchApp:
                Picker(
                    "App",
                    selection: Binding(
                        get: { action.payload ?? viewModel.availableAutomationLaunchApps.first?.appID ?? "" },
                        set: { viewModel.updateSceneDraftActionPayload(action.id, payload: $0) }
                    )
                ) {
                    ForEach(viewModel.availableAutomationLaunchApps) { app in
                        Text(app.title).tag(app.appID)
                    }
                }
            case .switchInput:
                Picker(
                    "Input",
                    selection: Binding(
                        get: { action.payload ?? viewModel.availableAutomationInputs.first?.inputID ?? "" },
                        set: { viewModel.updateSceneDraftActionPayload(action.id, payload: $0) }
                    )
                ) {
                    ForEach(viewModel.availableAutomationInputs) { input in
                        Text(input.title).tag(input.inputID)
                    }
                }
            default:
                Text("No additional value needed.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                viewModel.removeSceneDraftAction(action.id)
            } label: {
                Text("Remove Step")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
