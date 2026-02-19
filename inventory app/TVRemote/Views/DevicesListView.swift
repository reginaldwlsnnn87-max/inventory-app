import SwiftUI

struct DevicesListView: View {
    @ObservedObject var viewModel: TVRemoteAppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isAdvancedSettingsVisible {
                    Section("Network Check") {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(viewModel.networkCheckNeedsAttention ? Color.orange : Color.green)
                                .frame(width: 9, height: 9)
                            Text(viewModel.networkStatusText)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 4)

                        Button {
                            viewModel.runManualIPReachabilityCheck()
                        } label: {
                            if viewModel.isProbingManualIP {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Testing TV reachability...")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            } else {
                                Text("Test IP Reachability")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .disabled(viewModel.isProbingManualIP)

                        if let manualIPProbeStatus = viewModel.manualIPProbeStatus {
                            Text(manualIPProbeStatus)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 2)
                        }
                    }
                }

                if viewModel.localNetworkGuidanceVisible {
                    Section("Local Network Access") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Allow Local Network access in iOS Settings.")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Settings > Privacy & Security > Local Network > \(AppBranding.displayName)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section("Nearby LG TVs") {
                    if viewModel.discoveredDevices.isEmpty {
                        ContentUnavailableView(
                            "Searching for TVs",
                            systemImage: "dot.radiowaves.left.and.right",
                            description: Text("Same Wi-Fi subnet required. If still empty, enable LG Connect Apps on TV and check router multicast/client isolation settings.")
                        )
                    } else {
                        ForEach(viewModel.discoveredDevices) { device in
                            DeviceRow(
                                device: device,
                                isActive: viewModel.activeDevice?.id == device.id
                            ) {
                                viewModel.connect(to: device)
                            }
                        }
                    }
                }

                if !viewModel.knownDevices.isEmpty {
                    Section("Known Devices") {
                        ForEach(viewModel.knownDevices) { device in
                            DeviceRow(
                                device: device,
                                isActive: viewModel.activeDevice?.id == device.id
                            ) {
                                viewModel.connect(to: device)
                            }
                        }
                    }
                }

                Section("More Tools") {
                    Toggle(
                        "Show Advanced Tools",
                        isOn: Binding(
                            get: { viewModel.isAdvancedSettingsVisible },
                            set: { viewModel.setAdvancedSettingsVisible($0) }
                        )
                    )

                    if !viewModel.isAdvancedSettingsVisible {
                        Text("Advanced includes manual IP, Wake-on-LAN, Plex metadata, diagnostics, and automations.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.isAdvancedSettingsVisible {
                    Section("Advanced: Enter IP") {
                        TextField("192.168.1.47", text: $viewModel.manualIPAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.numbersAndPunctuation)

                        Button("Connect by IP") {
                            viewModel.connectManualIPAddress()
                        }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    }

                    Section("Wake-On-LAN (Power On)") {
                        TextField("AA:BB:CC:DD:EE:FF", text: $viewModel.wakeMACAddress)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)

                        Button("Save Wake MAC") {
                            viewModel.saveWakeMACAddress()
                        }
                        .font(.system(size: 15, weight: .bold, design: .rounded))

                        if let status = viewModel.wakeMACStatusMessage {
                            Text(status)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Plex Metadata (Optional)") {
                        TextField("http://192.168.1.20:32400", text: $viewModel.plexMetadataServerURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)

                        SecureField("Plex token", text: $viewModel.plexMetadataToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)

                        HStack(spacing: 10) {
                            Button("Save Plex") {
                                viewModel.savePlexMetadataConfiguration()
                            }
                            .font(.system(size: 15, weight: .bold, design: .rounded))

                            Button("Clear") {
                                viewModel.clearPlexMetadataConfiguration()
                            }
                            .font(.system(size: 14, weight: .semibold))
                        }

                        Text(viewModel.isPlexMetadataConfigured
                            ? "Plex metadata is active. Titles can auto-fill when Plex is on-screen."
                            : "Connect Plex to improve \"Now Watching\" title accuracy when Plex is playing.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        if let status = viewModel.plexMetadataStatusMessage {
                            Text(status)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Safety") {
                        Toggle(
                            "Caregiver Mode",
                            isOn: Binding(
                                get: { viewModel.isCaregiverModeEnabled },
                                set: { viewModel.setCaregiverModeEnabled($0) }
                            )
                        )

                        Toggle(
                            "App/Input Locking",
                            isOn: Binding(
                                get: { viewModel.isAppInputLockEnabled },
                                set: { viewModel.setAppInputLockEnabled($0) }
                            )
                        )

                        Text("Locked apps: \(viewModel.quickLaunchCountLocked), locked inputs: \(viewModel.inputCountLocked)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Section("Smart Scenes") {
                        Text(viewModel.smartScenesPlanSummary)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        if viewModel.smartScenes.isEmpty {
                            Text("No scenes yet. Create one-tap routines like \"TV Night\".")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.smartScenes) { scene in
                                SmartSceneRow(
                                    scene: scene,
                                    runAction: {
                                        viewModel.runSmartScene(scene)
                                    },
                                    removeAction: {
                                        viewModel.removeSmartScene(scene.id)
                                    }
                                )
                            }
                        }

                        Button("New Smart Scene") {
                            viewModel.presentSmartSceneComposer()
                        }
                        .buttonStyle(.borderedProminent)

                        if !viewModel.canCreateAdditionalSmartScene {
                            Button("Upgrade to Pro for Unlimited Scenes") {
                                viewModel.presentPremiumPaywall(
                                    source: "smart_scene_count_limit",
                                    dismissDevicePicker: true
                                )
                            }
                            .buttonStyle(.bordered)
                        }

                        if let sceneStatusMessage = viewModel.sceneStatusMessage {
                            Text(sceneStatusMessage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Time Automations") {
                        Text(viewModel.automationRulesSummary)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                    if viewModel.automationRules.isEmpty {
                        Text("No schedules yet. Add one preset below.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.automationRules) { rule in
                            AutomationRuleRow(
                                rule: rule,
                                isEnabled: Binding(
                                    get: { rule.isEnabled },
                                    set: { viewModel.toggleAutomationEnabled(rule.id, isEnabled: $0) }
                                ),
                                time: Binding(
                                    get: { viewModel.automationTimeDate(for: rule) },
                                    set: { viewModel.updateAutomationTime(rule.id, using: $0) }
                                ),
                                removeAction: {
                                    viewModel.removeAutomation(rule.id)
                                },
                                weekdayChoices: viewModel.automationWeekdayChoices,
                                weekdayLabel: { weekday in
                                    viewModel.shortWeekdayLabel(for: weekday)
                                },
                                toggleWeekday: { weekday in
                                    viewModel.toggleAutomationWeekday(rule.id, weekday: weekday)
                                }
                            )
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Add Weekday On") {
                            viewModel.addWeekdayPowerOnAutomation()
                        }
                        .buttonStyle(.bordered)

                        Button("Add Night Off") {
                            viewModel.addNightPowerOffAutomation()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Add YouTube TV Launch") {
                        viewModel.addYouTubeTVAutomation()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Custom Automation") {
                        viewModel.presentAutomationComposer()
                    }
                    .buttonStyle(.bordered)

                        if let automationStatus = viewModel.automationStatusMessage {
                            Text(automationStatus)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Power-On Setup Check") {
                        Toggle(
                            "LG Connect Apps is enabled on TV",
                            isOn: Binding(
                                get: { viewModel.powerSetupLGConnectAppsEnabled },
                                set: { viewModel.setPowerSetupLGConnectAppsEnabled($0) }
                            )
                        )

                        Toggle(
                            "Mobile TV On is enabled on TV",
                            isOn: Binding(
                                get: { viewModel.powerSetupMobileTVOnEnabled },
                                set: { viewModel.setPowerSetupMobileTVOnEnabled($0) }
                            )
                        )

                        Toggle(
                            "Quick Start+ is enabled on TV",
                            isOn: Binding(
                                get: { viewModel.powerSetupQuickStartEnabled },
                                set: { viewModel.setPowerSetupQuickStartEnabled($0) }
                            )
                        )

                    ChecklistStatusRow(
                        title: "Wake MAC configured",
                        detail: viewModel.powerSetupWakeMACConfigured ? "Ready for Wake-on-LAN." : "Save a Wake MAC in the section above.",
                        passed: viewModel.powerSetupWakeMACConfigured
                    )

                    ChecklistStatusRow(
                        title: "Wi-Fi path healthy",
                        detail: viewModel.isWiFiReadyForTVControl ? "iPhone is on Wi-Fi with local IPv4." : "Fix Wi-Fi path first before power-on tests.",
                        passed: viewModel.isWiFiReadyForTVControl
                    )

                    Text(viewModel.powerSetupChecklistSummary)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                        Button("Run Power On Test") {
                            viewModel.powerOnTV()
                        }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .disabled(!viewModel.canRunPowerOnSetupTest)
                    }

                    Section("Diagnostics") {
                        DiagnosticsValueRow(
                            label: "State",
                            value: viewModel.diagnosticsSnapshot.connectionStateLabel
                        )
                        DiagnosticsValueRow(
                            label: "Transport",
                            value: viewModel.diagnosticsSnapshot.commandTransport
                        )
                        DiagnosticsValueRow(
                            label: "Reconnect Attempts",
                            value: "\(viewModel.diagnosticsSnapshot.reconnectAttempts)"
                        )
                        DiagnosticsValueRow(
                            label: "Command Retries",
                            value: "\(viewModel.diagnosticsSnapshot.commandRetryCount)"
                        )
                        DiagnosticsValueRow(
                            label: "Ping Failures",
                            value: "\(viewModel.diagnosticsSnapshot.pingFailureCount)"
                        )
                        DiagnosticsValueRow(
                            label: "Last Auto-Recovery",
                            value: diagnosticsLastAutoRecoveryText
                        )
                        DiagnosticsValueRow(
                            label: "Endpoint",
                            value: diagnosticsEndpointText
                        )
                        DiagnosticsValueRow(
                            label: "Services",
                            value: diagnosticsServicesText
                        )
                        DiagnosticsValueRow(
                            label: "Capabilities",
                            value: diagnosticsCapabilitiesText
                        )
                        DiagnosticsValueRow(
                            label: "Last Error",
                            value: diagnosticsLastErrorText
                        )
                        DiagnosticsValueRow(
                            label: "Cmd Latency",
                            value: diagnosticsCommandLatencyText
                        )
                        DiagnosticsValueRow(
                            label: "Cmd Success",
                            value: diagnosticsCommandSuccessText
                        )
                        DiagnosticsValueRow(
                            label: "Last Cmd RTT",
                            value: diagnosticsLastCommandRTTText
                        )

                        if let copiedStatus = viewModel.diagnosticsStatusMessage {
                            Text(copiedStatus)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            Button("Refresh") {
                                viewModel.refreshDiagnostics()
                            }
                            .buttonStyle(.bordered)

                            Button("Copy") {
                                viewModel.copyDiagnosticsToClipboard()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    Section("Pro") {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(viewModel.premiumSnapshot.tier == .pro ? Color.green : Color.orange)
                                .frame(width: 9, height: 9)

                            Text(viewModel.premiumStatusLabel)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 2)

                        Text("Growth Funnel: \(viewModel.growthFunnelSummary)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)

                        Button(viewModel.premiumCTAButtonTitle) {
                            viewModel.presentPremiumPaywall(
                                source: "devices_sheet",
                                dismissDevicePicker: true
                            )
                        }
                        .font(.system(size: 14, weight: .semibold))

                        if let premiumStatusMessage = viewModel.premiumStatusMessage {
                            Text(premiumStatusMessage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh") {
                        viewModel.refreshDiscovery()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            viewModel.refreshNetworkDiagnostics()
            viewModel.refreshDiagnostics()
        }
        .sheet(isPresented: $viewModel.isAutomationComposerPresented) {
            AutomationComposerView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isSceneComposerPresented) {
            SmartSceneComposerView(viewModel: viewModel)
        }
    }

    private var diagnosticsEndpointText: String {
        let snapshot = viewModel.diagnosticsSnapshot
        if let port = snapshot.endpointPort {
            return "\(snapshot.deviceIP):\(port)"
        }
        return snapshot.deviceIP
    }

    private var diagnosticsServicesText: String {
        let names = viewModel.diagnosticsSnapshot.serviceNames
        if names.isEmpty {
            return "None"
        }
        return "\(names.count): \(names.joined(separator: ", "))"
    }

    private var diagnosticsCapabilitiesText: String {
        let capabilities = viewModel.diagnosticsSnapshot.supportedCapabilities
        if capabilities.isEmpty {
            return "None"
        }
        return capabilities.map(\.rawValue).joined(separator: ", ")
    }

    private var diagnosticsLastErrorText: String {
        let snapshot = viewModel.diagnosticsSnapshot
        guard let message = snapshot.lastErrorMessage, !message.isEmpty else {
            return "None"
        }
        if let code = snapshot.lastErrorCode {
            return "\(code): \(message)"
        }
        return message
    }

    private var diagnosticsLastAutoRecoveryText: String {
        guard let lastAutoRecoveryAt = viewModel.diagnosticsSnapshot.lastAutoRecoveryAt else {
            return "Never"
        }
        return lastAutoRecoveryAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var diagnosticsCommandLatencyText: String {
        let telemetry = viewModel.diagnosticsSnapshot.commandLatencyTelemetry
        guard let average = telemetry.averageLatencyMs,
              let p50 = telemetry.p50LatencyMs,
              let p95 = telemetry.p95LatencyMs else {
            return "N/A"
        }
        return "avg \(average)ms • p50 \(p50)ms • p95 \(p95)ms"
    }

    private var diagnosticsCommandSuccessText: String {
        let telemetry = viewModel.diagnosticsSnapshot.commandLatencyTelemetry
        guard telemetry.windowSampleCount > 0 else {
            return "No samples yet"
        }
        return "\(telemetry.successRatePercentText) success • \(telemetry.timeoutCount) timeout • \(telemetry.windowSampleCount) samples"
    }

    private var diagnosticsLastCommandRTTText: String {
        let telemetry = viewModel.diagnosticsSnapshot.commandLatencyTelemetry
        guard let latency = telemetry.lastLatencyMs else {
            return "N/A"
        }

        let status: String
        if telemetry.lastWasTimeout {
            status = "timeout"
        } else if telemetry.lastWasSuccess {
            status = "ok"
        } else {
            status = "failed"
        }

        let command = telemetry.lastCommandKey ?? "unknown"
        return "\(command) • \(latency)ms • \(status)"
    }
}

private struct DeviceRow: View {
    let device: TVDevice
    let isActive: Bool
    let connectAction: () -> Void

    var body: some View {
        Button(action: connectAction) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: "tv")
                        .font(.system(size: 17, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(device.ip)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let lastConnectedAt = device.lastConnectedAt {
                        Text("Last connected \(lastConnectedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                if isActive {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.green)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name), \(device.ip)")
    }
}

private struct ChecklistStatusRow: View {
    let title: String
    let detail: String
    let passed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: passed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(passed ? Color.green : Color.orange)
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DiagnosticsValueRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
        }
        .padding(.vertical, 2)
    }
}

private struct AutomationRuleRow: View {
    let rule: TVAutomationRule
    @Binding var isEnabled: Bool
    @Binding var time: Date
    let removeAction: () -> Void
    let weekdayChoices: [Int]
    let weekdayLabel: (Int) -> String
    let toggleWeekday: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(rule.action.title) • \(rule.weekdayLabel)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
            }

            DatePicker(
                "Time",
                selection: $time,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(weekdayChoices, id: \.self) { weekday in
                        let selected = rule.weekdays.contains(weekday)
                        Button(weekdayLabel(weekday)) {
                            toggleWeekday(weekday)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.22) : Color.gray.opacity(0.14))
                        )
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    }
                }
            }

            Button(role: .destructive, action: removeAction) {
                Text("Remove Automation")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

private struct SmartSceneRow: View {
    let scene: TVSmartScene
    let runAction: () -> Void
    let removeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: scene.iconSystemName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(scene.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(scene.actionSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button("Run", action: runAction)
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.bordered)
            }

            if let lastRunAt = scene.lastRunAt {
                Text("Last run \(lastRunAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive, action: removeAction) {
                Text("Delete Scene")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

private struct AutomationComposerView: View {
    @ObservedObject var viewModel: TVRemoteAppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Automation name", text: $viewModel.automationDraftName)

                    Picker(
                        "Action",
                        selection: Binding(
                            get: { viewModel.automationDraftAction },
                            set: { viewModel.setAutomationDraftAction($0) }
                        )
                    ) {
                        ForEach(TVAutomationActionKind.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }

                    DatePicker(
                        "Time",
                        selection: $viewModel.automationDraftTime,
                        displayedComponents: .hourAndMinute
                    )
                }

                Section("Days") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(viewModel.automationWeekdayChoices, id: \.self) { weekday in
                            let selected = viewModel.automationDraftSelectedWeekdays.contains(weekday)
                            Button(viewModel.shortWeekdayLabel(for: weekday)) {
                                viewModel.toggleAutomationDraftWeekday(weekday)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(selected ? Color.accentColor.opacity(0.20) : Color.gray.opacity(0.16))
                            )
                            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Action Payload") {
                    switch viewModel.automationDraftAction {
                    case .setVolume:
                        HStack(spacing: 12) {
                            Slider(
                                value: Binding(
                                    get: { Double(Int(viewModel.automationDraftPayload) ?? 20) },
                                    set: { viewModel.automationDraftPayload = String(Int($0.rounded())) }
                                ),
                                in: 0 ... 100,
                                step: 1
                            )
                            Text("\(Int(viewModel.automationDraftPayload) ?? 20)%")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 44, alignment: .trailing)
                        }
                    case .launchApp:
                        Picker("App", selection: $viewModel.automationDraftPayload) {
                            ForEach(viewModel.availableAutomationLaunchApps) { app in
                                Text(app.title).tag(app.appID)
                            }
                        }
                    case .switchInput:
                        Picker("Input", selection: $viewModel.automationDraftPayload) {
                            ForEach(viewModel.availableAutomationInputs) { input in
                                Text(input.title).tag(input.inputID)
                            }
                        }
                    default:
                        Text("No additional payload needed for this action.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if let message = viewModel.automationDraftMessage {
                    Section {
                        Text(message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Custom Automation")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        viewModel.addCustomAutomationFromDraft()
                    }
                }
            }
        }
    }
}
