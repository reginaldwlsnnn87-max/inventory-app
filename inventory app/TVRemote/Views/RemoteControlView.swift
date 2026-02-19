import SwiftUI
import UIKit

struct RemoteControlView: View {
    @ObservedObject var viewModel: TVRemoteAppViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isAdvancedControlsPresented = false
    @State private var advancedInitialSection: AdvancedSection = .watching
    @State private var isPowerToolsExpanded = false
    @State private var isQuickScenesExpanded = false
    @State private var compactPanelSelection: CompactPanel = .volume
    @State private var isNowPlayingTitleEditorPresented = false
    @State private var nowPlayingTitleDraft = ""
    @State private var isStatusExpanded = false
    @State private var rttPulsePhase = false
    @State private var isEssentialsExpanded = false
    @State private var containerWidth: CGFloat = 0

    private enum AdvancedSection: Hashable {
        case watching
        case inputs
        case talk
        case copilot
        case commands
        case macros
    }

    private enum CompactPanel: String, CaseIterable, Identifiable {
        case volume
        case power
        case apps
        case scenes

        var id: String { rawValue }

        var title: String {
            switch self {
            case .volume:
                return "Sound"
            case .power:
                return "Power"
            case .apps:
                return "Apps"
            case .scenes:
                return "Scenes"
            }
        }
    }

    private enum SmartControlMode: String {
        case streaming
        case liveTV
        case system

        var label: String {
            switch self {
            case .streaming:
                return "Streaming"
            case .liveTV:
                return "Live TV"
            case .system:
                return "System"
            }
        }
    }

    private struct DockShortcut: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let accented: Bool
        let accessibilityLabel: String
        let action: () -> Void
    }

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad
    }

    private var isNarrowPhone: Bool {
        !isPadLayout && containerWidth > 0 && containerWidth <= 390
    }

    private var contentMaxWidth: CGFloat? {
        isPadLayout ? 920 : nil
    }

    private var contentHorizontalPadding: CGFloat {
        if isPadLayout { return 24 }
        return isNarrowPhone ? 12 : 16
    }

    private var contentTopPadding: CGFloat {
        isNarrowPhone ? 10 : 14
    }

    private var contentSectionSpacing: CGFloat {
        isNarrowPhone ? 8 : 10
    }

    private var actionRingDiameter: CGFloat {
        if isPadLayout { return 300 }
        return isNarrowPhone ? 228 : 256
    }

    private var actionRingOffset: CGFloat {
        if isPadLayout { return 98 }
        return isNarrowPhone ? 74 : 84
    }

    private var actionRingDirectionButtonSize: CGFloat {
        if isPadLayout { return 74 }
        return isNarrowPhone ? 60 : 68
    }

    private var actionRingCenterButtonSize: CGFloat {
        if isPadLayout { return 112 }
        return isNarrowPhone ? 88 : 100
    }

    private var essentialsButtonHeight: CGFloat {
        if isPadLayout { return 56 }
        return isNarrowPhone ? 46 : 52
    }

    private var cardCornerRadius: CGFloat {
        if isPadLayout { return 28 }
        return isNarrowPhone ? 22 : 24
    }

    var body: some View {
        ZStack {
            background

            ScrollView(showsIndicators: false) {
                Group {
                    if viewModel.isCaregiverModeEnabled {
                        caregiverHome
                    } else {
                        standardHome
                    }
                }
                .frame(maxWidth: contentMaxWidth)
                .padding(.horizontal, contentHorizontalPadding)
                .padding(.top, contentTopPadding)
                .padding(.bottom, 16)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        containerWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        containerWidth = newWidth
                    }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !viewModel.isCaregiverModeEnabled {
                proDock
            }
        }
        .sheet(isPresented: $viewModel.isQuickLaunchSheetPresented) {
            QuickLaunchSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isInputPickerPresented) {
            InputSwitcherSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isAdvancedControlsPresented) {
            advancedControlsSheet
        }
        .alert("What Are You Watching?", isPresented: $isNowPlayingTitleEditorPresented) {
            TextField("e.g. Madea", text: $nowPlayingTitleDraft)
            Button("Save") {
                viewModel.saveManualNowPlayingTitle(nowPlayingTitleDraft)
            }
            Button("Clear", role: .destructive) {
                viewModel.clearManualNowPlayingTitleOverride()
            }
            .disabled(!viewModel.hasManualNowPlayingTitleOverride)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.nowPlayingManualCaptureHint)
        }
    }

    private var standardHome: some View {
        VStack(spacing: contentSectionSpacing) {
            headerCard
            if viewModel.supportsControls {
                connectedPrimaryDeck
            } else {
                disconnectedRecoveryDeck
                disconnectedControlPlaceholder
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: smartControlMode.rawValue)
        .onAppear {
            applySmartModePreferredControlSurface(smartControlMode)
        }
        .onChange(of: smartControlMode) { _, mode in
            applySmartModePreferredControlSurface(mode)
        }
    }

    @ViewBuilder
    private var connectedPrimaryDeck: some View {
        if isPadLayout {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: contentSectionSpacing) {
                    smartControlHero
                    controlSurface
                }
                .frame(maxWidth: .infinity)

                focusedEssentialsDeck
                    .frame(maxWidth: 360)
            }
        } else {
            VStack(spacing: contentSectionSpacing) {
                smartControlHero
                controlSurface
                focusedEssentialsDeck
            }
        }
    }

    private var caregiverHome: some View {
        VStack(spacing: isNarrowPhone ? 10 : 14) {
            headerCard
            watchingHistoryDeck
            caregiverIntroDeck
            caregiverPowerDeck
            caregiverNavigationDeck
            caregiverVolumeDeck
            caregiverAppsDeck
        }
    }

    @ViewBuilder
    private var controlSurface: some View {
        if activeControlSurfaceUsesSwipePad {
            swipePad
        } else {
            dPad
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [RemoteTheme.backgroundTop, RemoteTheme.backgroundMid, RemoteTheme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [RemoteTheme.accentGlow.opacity(0.25), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 250
                    )
                )
                .blur(radius: 32)
                .offset(x: 120, y: -260)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.47, green: 0.80, blue: 0.73).opacity(0.14), .clear],
                        center: .center,
                        startRadius: 16,
                        endRadius: 260
                    )
                )
                .blur(radius: 34)
                .offset(x: -130, y: 280)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.14)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .ignoresSafeArea()
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: isStatusExpanded ? 11 : 7) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.activeDeviceName)
                        .font(.system(size: isNarrowPhone ? 17 : 18, weight: .bold, design: .rounded))
                        .foregroundStyle(RemoteTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.connectionState.statusColor)
                            .frame(width: 8, height: 8)

                        Text(viewModel.statusText)
                            .font(.system(size: isNarrowPhone ? 10 : 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(RemoteTheme.textPrimary)
                            .lineLimit(1)

                        if let headerLatencyText {
                            headerLatencyTag(text: headerLatencyText)
                                .accessibilityLabel(headerLatencyAccessibilityLabel)
                        }
                    }
                }

                Spacer(minLength: 0)

                if let app = currentNowPlayingShortcut {
                    TVAppIconView(app: app, size: 28)
                }

                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        isStatusExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isStatusExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(RemoteTheme.accentSoft)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isStatusExpanded ? "Collapse TV status" : "Expand TV status")
            }

            if isStatusExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 10) {
                        statusInfoPill(
                            title: "IP",
                            value: viewModel.activeDevice?.ip ?? "N/A",
                            systemImage: "network"
                        )
                        statusInfoPill(
                            title: "Mode",
                            value: smartModeStatusLabel,
                            systemImage: "bolt.horizontal.circle"
                        )
                    }

                    HStack(spacing: 8) {
                        rttMiniGraph
                        Text(viewModel.connectionState.detailCopy)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(RemoteTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if viewModel.supportsControls {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nowPlayingInsightLine)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(RemoteTheme.textPrimary)
                                .lineLimit(1)
                            Text(viewModel.nowPlayingDetail)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(RemoteTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    if viewModel.supportsControls {
                        HStack(spacing: 8) {
                            statusQuickAction("Restart App", systemImage: "arrow.clockwise.circle.fill") {
                                viewModel.restartCurrentApp()
                            }
                            statusQuickAction("Reconnect", systemImage: "dot.radiowaves.left.and.right") {
                                viewModel.reconnectCurrentTV()
                            }
                            statusQuickAction("Power Off", systemImage: "power") {
                                viewModel.powerOffTV()
                            }
                            statusQuickAction("TVs", systemImage: "tv") {
                                viewModel.isDevicePickerPresented = true
                            }
                            .accessibilityLabel("Switch TV")
                        }
                    } else {
                        HStack(spacing: 8) {
                            statusQuickAction("Reconnect", systemImage: "dot.radiowaves.left.and.right") {
                                viewModel.reconnectCurrentTV()
                            }
                            statusQuickAction("Choose TV", systemImage: "tv") {
                                viewModel.isDevicePickerPresented = true
                            }
                            .accessibilityLabel("Switch TV")
                            statusQuickAction("Troubleshoot", systemImage: "wrench.and.screwdriver") {
                                viewModel.runFixMyTVWorkflow()
                            }
                        }
                    }

                    if viewModel.shouldShowNowPlayingManualCapture {
                        HStack(spacing: 6) {
                            Button {
                                Haptics.tap()
                                nowPlayingTitleDraft = viewModel.currentNowPlayingManualTitleDraft()
                                isNowPlayingTitleEditorPresented = true
                            } label: {
                                nowPlayingTag(
                                    text: viewModel.nowPlayingManualCaptureButtonTitle,
                                    tint: RemoteTheme.accentSoft,
                                    fill: RemoteTheme.accent.opacity(0.14)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Set now playing title manually")

                            if viewModel.hasManualNowPlayingTitleOverride {
                                nowPlayingTag(
                                    text: "Manual",
                                    tint: RemoteTheme.textSecondary,
                                    fill: Color.white.opacity(0.08)
                                )
                                .accessibilityLabel("Manual title override active")
                            }
                        }
                    }

                    if let fixStatus = viewModel.fixMyTVStatusMessage {
                        Text(fixStatus)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(RemoteTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(isNarrowPhone ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [RemoteTheme.cardStrong, RemoteTheme.card],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .strokeBorder(RemoteTheme.stroke, lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [RemoteTheme.glassTop, .clear, RemoteTheme.glassBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 8)
        )
        .gesture(
            DragGesture(minimumDistance: 14)
                .onEnded { value in
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        if value.translation.height > 0 {
                            isStatusExpanded = true
                        } else if value.translation.height < 0 {
                            isStatusExpanded = false
                        }
                    }
                }
        )
        .onAppear {
            guard !rttPulsePhase else { return }
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                rttPulsePhase = true
            }
        }
    }

    private var smartControlMode: SmartControlMode {
        guard let state = viewModel.nowPlayingState else { return .system }
        let token = "\(state.appName) \(state.appID ?? "")".lowercased()
        if state.source == .liveTV || token.contains("live tv") || token.contains("lg channels") || token.contains("broadcast") {
            return .liveTV
        }
        let streamingHints = [
            "netflix", "youtube", "prime", "disney", "hulu", "max", "plex", "apple tv", "amazon"
        ]
        if streamingHints.contains(where: { token.contains($0) }) {
            return .streaming
        }
        return .system
    }

    private func applySmartModePreferredControlSurface(_ mode: SmartControlMode) {
        // Streaming defaults to swipe for easier seek/navigation, but user can switch back.
        guard mode == .streaming else { return }
        guard !viewModel.usesSwipePad else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            viewModel.usesSwipePad = true
        }
    }

    private var activeControlSurfaceUsesSwipePad: Bool {
        viewModel.usesSwipePad
    }

    private var smartModeStatusLabel: String {
        let app = viewModel.nowPlayingState?.appName ?? "TV"
        return "\(smartControlMode.label) · \(app)"
    }

    private var nowPlayingInsightLine: String {
        guard let state = viewModel.nowPlayingState else {
            return "Ready to control your TV."
        }
        let app = state.appName
        if app.lowercased().contains("netflix"), state.title != nil {
            return "Watching \(app) · Next episode in ~12 min"
        }
        if let title = state.title, !title.isEmpty {
            return "Watching \(app) · \(title)"
        }
        if state.isProviderMetadataRestricted {
            return "Watching \(app) · Title hidden by provider"
        }
        return "Watching \(app) · Smart controls ready"
    }

    private var currentNowPlayingShortcut: TVAppShortcut? {
        guard let state = viewModel.nowPlayingState else { return nil }

        if let appID = state.appID?.lowercased(),
           let existing = viewModel.quickLaunchApps.first(where: { $0.appID.lowercased() == appID }) {
            return existing
        }

        let normalizedName = state.appName.lowercased()
        if let existing = viewModel.quickLaunchApps.first(where: { $0.title.lowercased() == normalizedName }) {
            return existing
        }

        let fallbackID = "active-\(normalizedName.replacingOccurrences(of: " ", with: "-"))"
        return TVAppShortcut(
            id: fallbackID,
            title: state.appName,
            iconSystemName: "play.tv.fill",
            appID: state.appID ?? fallbackID
        )
    }

    private var smartControlHero: some View {
        HStack(alignment: .center, spacing: isNarrowPhone ? 8 : 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Smart Mode · \(smartControlMode.label)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)
                Text(viewModel.nowPlayingState?.appName ?? "Adaptive controls")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Picker(
                "",
                selection: Binding(
                    get: { activeControlSurfaceUsesSwipePad },
                    set: { viewModel.usesSwipePad = $0 }
                )
            ) {
                Text("Ring").tag(false)
                Text("Swipe").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: isPadLayout ? 152 : (isNarrowPhone ? 120 : 136))
            .accessibilityLabel("Smart control surface")

            Button("More") {
                Haptics.tap()
                openAdvancedControls(.watching)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .buttonStyle(.borderless)
            .foregroundStyle(RemoteTheme.accentSoft)
            .padding(.horizontal, isNarrowPhone ? 6 : 8)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(RemoteTheme.key.opacity(0.92))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(RemoteTheme.stroke, lineWidth: 1)
                    )
            )
        }
        .padding(isNarrowPhone ? 12 : 14)
        .background(cardBackground)
    }

    private var focusedEssentialsDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Essentials", systemImage: "bolt.circle.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)

                Spacer()
            }

            HStack(spacing: 8) {
                focusedActionButton(
                    title: "Vol -",
                    symbol: "speaker.minus.fill",
                    accented: false,
                    isEnabled: viewModel.supportsVolumeControls
                ) {
                    viewModel.send(.volumeDown)
                }

                focusedActionButton(
                    title: viewModel.isMuted ? "Unmute" : "Mute",
                    symbol: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    accented: true,
                    isEnabled: viewModel.supportsVolumeControls
                ) {
                    viewModel.toggleMute()
                }

                focusedActionButton(
                    title: "Vol +",
                    symbol: "speaker.plus.fill",
                    accented: false,
                    isEnabled: viewModel.supportsVolumeControls
                ) {
                    viewModel.send(.volumeUp)
                }
            }

            HStack(spacing: 8) {
                focusedActionButton(
                    title: "Back",
                    symbol: "arrow.left",
                    accented: false,
                    isEnabled: viewModel.supportsBackCommand
                ) {
                    viewModel.send(.back)
                }

                focusedActionButton(
                    title: "Home",
                    symbol: "house.fill",
                    accented: false,
                    isEnabled: viewModel.supportsHomeCommand
                ) {
                    viewModel.send(.home)
                }

                focusedActionButton(
                    title: "Power",
                    symbol: "power",
                    accented: true,
                    isEnabled: viewModel.supportsPowerControls || viewModel.canAttemptPowerOn
                ) {
                    if viewModel.supportsPowerControls {
                        viewModel.powerOffTV()
                    } else {
                        viewModel.powerOnTV()
                    }
                }
            }

            if let quickScene = preferredMovieNightScene ?? viewModel.smartScenes.first {
                Button {
                    Haptics.tap()
                    viewModel.runSmartScene(quickScene)
                } label: {
                    Label(quickScene.name, systemImage: quickScene.iconSystemName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: essentialsButtonHeight - 2)
                }
                .buttonStyle(RemoteSecondaryButtonStyle())
                .accessibilityLabel("Run scene \(quickScene.name)")
            } else {
                Button {
                    Haptics.tap()
                    viewModel.presentSmartSceneComposer()
                } label: {
                    Label("Create Scene", systemImage: "sparkles.tv.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: essentialsButtonHeight - 2)
                }
                .buttonStyle(RemoteSecondaryButtonStyle())
            }
        }
        .padding(isNarrowPhone ? 12 : 14)
        .background(cardBackground)
    }

    private var focusedSceneDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Scene Shortcut", systemImage: "sparkles.tv.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)

                Spacer()

                Button("All Scenes") {
                    Haptics.tap()
                    openAdvancedControls(.watching)
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .buttonStyle(.borderless)
                .foregroundStyle(RemoteTheme.accentSoft)
            }

            if let movieNightScene = preferredMovieNightScene {
                Button {
                    Haptics.tap()
                    viewModel.runSmartScene(movieNightScene)
                } label: {
                    Label("Run \(movieNightScene.name)", systemImage: movieNightScene.iconSystemName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(RemoteAccentButtonStyle())
            } else if let firstScene = viewModel.smartScenes.first {
                Button {
                    Haptics.tap()
                    viewModel.runSmartScene(firstScene)
                } label: {
                    Label("Run \(firstScene.name)", systemImage: firstScene.iconSystemName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(RemoteAccentButtonStyle())
            } else {
                Button {
                    Haptics.tap()
                    viewModel.presentSmartSceneComposer()
                } label: {
                    Label("Create Movie Night", systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(RemoteAccentButtonStyle())
            }

            Text(viewModel.sceneStatusMessage ?? "One tap applies your preferred TV setup.")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(RemoteTheme.textSecondary)
                .lineLimit(2)
        }
        .padding(14)
        .background(cardBackground)
    }

    private var quickScenesDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Quick Scenes", systemImage: "sparkles.tv.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)

                Spacer()

                Button(isQuickScenesExpanded ? "Hide" : "Show") {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                        isQuickScenesExpanded.toggle()
                    }
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .buttonStyle(.borderless)
                .foregroundStyle(RemoteTheme.accentSoft)
            }

            if isQuickScenesExpanded {
                focusedSceneDeck
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text("Run your favorite scene in one tap.")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textSecondary)
                    .lineLimit(1)

                Button("Open Scenes") {
                    Haptics.tap()
                    openAdvancedControls(.watching)
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .buttonStyle(RemoteSecondaryButtonStyle())
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var disconnectedRecoveryDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Remote Paused", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(RemoteTheme.textPrimary)

            Text("Connection is \(disconnectedStatusLabel). Reconnect to unlock controls.")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(RemoteTheme.textSecondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Button("Reconnect") {
                    Haptics.tap()
                    viewModel.reconnectCurrentTV()
                }
                .buttonStyle(RemoteAccentButtonStyle())

                Button("Choose TV") {
                    Haptics.tap()
                    viewModel.isDevicePickerPresented = true
                }
                .buttonStyle(RemoteSecondaryButtonStyle())

                Button("Troubleshoot") {
                    Haptics.tap()
                    viewModel.runFixMyTVWorkflow()
                }
                .buttonStyle(RemoteSecondaryButtonStyle())
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var disconnectedControlPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(RemoteTheme.accentSoft)
                Text("Controls lock until TV reconnects")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)
                    .lineLimit(1)
            }

            Text("Reconnect runs in the background. Use Choose TV if your device changed.")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(RemoteTheme.textSecondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                disconnectedTag("Action Ring", systemImage: "circle.grid.cross")
                disconnectedTag("Essentials", systemImage: "bolt.circle")
                disconnectedTag("Scenes", systemImage: "sparkles.tv")
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private func disconnectedTag(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.18))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(RemoteTheme.stroke, lineWidth: 1)
                    )
            )
            .foregroundStyle(RemoteTheme.textSecondary)
    }

    private var disconnectedStatusLabel: String {
        let normalized = viewModel.connectionState.shortLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "offline" }
        return normalized.lowercased()
    }

    private var preferredMovieNightScene: TVSmartScene? {
        viewModel.smartScenes.first { scene in
            let normalized = scene.name.lowercased()
            return normalized.contains("movie")
                || normalized.contains("night")
                || normalized.contains("cinema")
        }
    }

    private func focusedActionButton(
        title: String,
        symbol: String,
        accented: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: essentialsButtonHeight)
        }
        .buttonStyle(accented ? AnyButtonStyle(RemoteAccentButtonStyle()) : AnyButtonStyle(RemoteSecondaryButtonStyle()))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(title)
    }

    private func contextControlButton(
        title: String,
        symbol: String,
        accented: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(accented ? AnyButtonStyle(RemoteAccentButtonStyle()) : AnyButtonStyle(RemoteSecondaryButtonStyle()))
        .accessibilityLabel(title)
    }

    private func statusInfoPill(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(RemoteTheme.accentSoft)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textSecondary)
                Text(value)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.20))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(RemoteTheme.stroke, lineWidth: 1)
                )
        )
    }

    private var rttMiniGraph: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<12, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(headerLatencyTint.opacity(0.85))
                    .frame(width: 3, height: rttBarHeight(for: index))
                    .scaleEffect(y: rttPulsePhase ? 1 : 0.74, anchor: .bottom)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(Double(index) * 0.04),
                        value: rttPulsePhase
                    )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.20))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(RemoteTheme.stroke, lineWidth: 1)
                )
        )
        .accessibilityHidden(true)
    }

    private func rttBarHeight(for index: Int) -> CGFloat {
        let base: CGFloat
        if let latency = viewModel.diagnosticsSnapshot.commandLatencyTelemetry.lastLatencyMs {
            base = max(4, min(14, CGFloat(latency) / 22))
        } else {
            base = 7
        }
        let offset = CGFloat(((index * 11) % 7) - 3)
        return max(4, min(16, base + offset))
    }

    private func statusQuickAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(RemoteSecondaryButtonStyle())
    }

    private func nowPlayingTag(text: String, tint: Color, fill: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .foregroundStyle(tint)
    }

    private func headerLatencyTag(text: String) -> some View {
        Label(text, systemImage: "timer")
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(headerLatencyTint.opacity(0.18))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .foregroundStyle(headerLatencyTint)
            .lineLimit(1)
    }

    private var headerLatencyText: String? {
        guard viewModel.supportsControls else { return nil }
        guard let latency = viewModel.diagnosticsSnapshot.commandLatencyTelemetry.lastLatencyMs else {
            return nil
        }
        return "RTT \(latency)ms"
    }

    private var headerLatencyTint: Color {
        let telemetry = viewModel.diagnosticsSnapshot.commandLatencyTelemetry
        if telemetry.lastWasTimeout {
            return Color(red: 0.95, green: 0.42, blue: 0.48)
        }
        guard let latency = telemetry.lastLatencyMs else {
            return RemoteTheme.textSecondary
        }
        switch latency {
        case ..<120:
            return Color(red: 0.46, green: 0.89, blue: 0.70)
        case ..<280:
            return Color(red: 0.96, green: 0.73, blue: 0.39)
        default:
            return Color(red: 0.95, green: 0.42, blue: 0.48)
        }
    }

    private var headerLatencyAccessibilityLabel: String {
        let telemetry = viewModel.diagnosticsSnapshot.commandLatencyTelemetry
        guard let latency = telemetry.lastLatencyMs else {
            return "No command latency data yet"
        }

        let status: String
        if telemetry.lastWasTimeout {
            status = "timeout"
        } else if telemetry.lastWasSuccess {
            status = "successful"
        } else {
            status = "failed"
        }

        return "Command response time \(latency) milliseconds, \(status)"
    }

    private var nowPlayingConfidenceTint: Color {
        switch viewModel.nowPlayingConfidence {
        case .high:
            return Color.green
        case .medium:
            return Color.orange
        case .low:
            return Color.red
        }
    }

    private func copilotConfidenceTint(_ confidence: TVAICopilotConfidence) -> Color {
        switch confidence {
        case .high:
            return Color.green
        case .medium:
            return Color.orange
        case .low:
            return Color.red
        }
    }

    private var compactEssentialsDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Essentials", systemImage: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)
                Spacer()
                Button {
                    Haptics.tap()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEssentialsExpanded.toggle()
                    }
                } label: {
                    Label(
                        isEssentialsExpanded ? "Hide" : "Show",
                        systemImage: isEssentialsExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill"
                    )
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(RemoteTheme.accentSoft)

                Button("Advanced") {
                    Haptics.tap()
                    openAdvancedControls(.watching)
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .buttonStyle(.borderless)
                .foregroundStyle(RemoteTheme.accentSoft)
            }

            if isEssentialsExpanded {
                Picker("Essentials", selection: $compactPanelSelection) {
                    ForEach(CompactPanel.allCases) { panel in
                        Text(panel.title).tag(panel)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Essentials category")

                compactPanelBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text("Volume, power, apps, and scenes are tucked here.")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    @ViewBuilder
    private var compactPanelBody: some View {
        switch compactPanelSelection {
        case .volume:
            compactVolumePanel
        case .power:
            compactPowerPanel
        case .apps:
            compactAppsPanel
        case .scenes:
            compactScenesPanel
        }
    }

    private var compactVolumePanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                RepeatingCommandButton(action: { viewModel.send(.volumeDown) }) {
                    Label("Vol -", systemImage: "speaker.minus.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(RemoteSecondaryButtonStyle())
                .accessibilityLabel("Volume down")

                Button {
                    Haptics.tap()
                    viewModel.toggleMute()
                } label: {
                    Label(viewModel.isMuted ? "Unmute" : "Mute", systemImage: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(RemoteAccentButtonStyle())
                .accessibilityLabel(viewModel.isMuted ? "Unmute TV" : "Mute TV")

                RepeatingCommandButton(action: { viewModel.send(.volumeUp) }) {
                    Label("Vol +", systemImage: "speaker.plus.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(RemoteSecondaryButtonStyle())
                .accessibilityLabel("Volume up")
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(RemoteTheme.textSecondary)

                Slider(
                    value: Binding(
                        get: { viewModel.volumeLevel },
                        set: { viewModel.setVolumeLevel($0) }
                    ),
                    in: 0 ... 100,
                    step: 1,
                    onEditingChanged: { isEditing in
                        viewModel.setVolumeSliderEditing(isEditing)
                    }
                )
                .tint(RemoteTheme.accentSoft)
                .accessibilityLabel("TV volume")
                .accessibilityValue("\(Int(viewModel.volumeLevel.rounded())) percent")

                Text("\(Int(viewModel.volumeLevel.rounded()))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .allowsHitTesting(viewModel.supportsVolumeControls)
        .opacity(viewModel.supportsVolumeControls ? 1 : 0.45)
    }

    private var compactPowerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    viewModel.powerOnTV()
                } label: {
                    Label("Power On", systemImage: "power.circle.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(RemoteSecondaryButtonStyle())
                .disabled(!viewModel.canAttemptPowerOn)
                .opacity(viewModel.canAttemptPowerOn ? 1 : 0.45)
                .accessibilityLabel("Power on TV")

                Button {
                    Haptics.tap()
                    viewModel.powerOffTV()
                } label: {
                    Label("Power Off", systemImage: "power")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(RemoteAccentButtonStyle())
                .disabled(!viewModel.supportsPowerControls)
                .opacity(viewModel.supportsPowerControls ? 1 : 0.45)
                .accessibilityLabel("Power off TV")
            }

            Text(viewModel.canAttemptPowerOn ? "Wake-ready when supported by your TV and network." : "Power on requires Wake-on-LAN support and prior pairing.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(RemoteTheme.textSecondary)
                .lineLimit(2)
        }
    }

    private var compactAppsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.dockQuickLaunchApps.prefix(4)) { app in
                        Button {
                            Haptics.tap()
                            viewModel.launchApp(app)
                        } label: {
                            VStack(spacing: 6) {
                                TVAppIconView(app: app, size: 30)
                                Text(app.title)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(RemoteTheme.textPrimary)
                                    .lineLimit(1)
                            }
                            .frame(width: 84, height: 62)
                        }
                        .buttonStyle(RemoteSecondaryButtonStyle())
                        .disabled(viewModel.isAppLocked(app))
                        .opacity(viewModel.isAppLocked(app) ? 0.45 : 1)
                        .accessibilityLabel("Launch \(app.title)")
                    }

                    Button {
                        Haptics.tap()
                        viewModel.isQuickLaunchSheetPresented = true
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("More")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .frame(width: 84, height: 62)
                    }
                    .buttonStyle(RemoteSecondaryButtonStyle())
                    .accessibilityLabel("Open app dock editor")
                    .disabled(viewModel.isCaregiverModeEnabled || viewModel.isAppInputLockEnabled)
                    .opacity((viewModel.isCaregiverModeEnabled || viewModel.isAppInputLockEnabled) ? 0.45 : 1)
                }
            }

            Button("Edit Quick Launch") {
                Haptics.tap()
                viewModel.isQuickLaunchSheetPresented = true
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .buttonStyle(.borderless)
            .foregroundStyle(RemoteTheme.accentSoft)
            .disabled(viewModel.isCaregiverModeEnabled || viewModel.isAppInputLockEnabled)
            .opacity((viewModel.isCaregiverModeEnabled || viewModel.isAppInputLockEnabled) ? 0.45 : 1)
        }
        .allowsHitTesting(viewModel.supportsLaunchApps)
        .opacity(viewModel.supportsLaunchApps ? 1 : 0.45)
    }

    private var compactScenesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.smartScenes.isEmpty {
                Text("Save one-tap scenes like \"Movie Night\" and run them here.")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textSecondary)
                    .lineLimit(2)

                Button {
                    Haptics.tap()
                    viewModel.presentSmartSceneComposer()
                } label: {
                    Label("Create Scene", systemImage: "sparkles.tv.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(RemoteSecondaryButtonStyle())
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.smartScenes.prefix(3)) { scene in
                            Button {
                                Haptics.tap()
                                viewModel.runSmartScene(scene)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Image(systemName: scene.iconSystemName)
                                            .font(.system(size: 13, weight: .bold))
                                        Text(scene.name)
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .lineLimit(1)
                                    }
                                    Text(scene.actionSummary)
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .foregroundStyle(RemoteTheme.textSecondary)
                                        .lineLimit(2)
                                }
                                .frame(width: 138, height: 62, alignment: .topLeading)
                            }
                            .buttonStyle(RemoteSecondaryButtonStyle())
                            .accessibilityLabel("Run scene \(scene.name)")
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button("New Scene") {
                    Haptics.tap()
                    viewModel.presentSmartSceneComposer()
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .buttonStyle(.borderless)
                .foregroundStyle(RemoteTheme.accentSoft)

                Spacer()

                if !viewModel.canCreateAdditionalSmartScene {
                    Button("Unlock") {
                        Haptics.tap()
                        viewModel.presentPremiumPaywall(source: "smart_scene_count_limit")
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .buttonStyle(.borderless)
                    .foregroundStyle(RemoteTheme.accentSoft)
                }
            }
        }
    }

    private var proDock: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(RemoteTheme.stroke)
            HStack(spacing: 8) {
                ForEach(predictiveDockShortcuts) { shortcut in
                    proDockButton(
                        title: shortcut.title,
                        systemImage: shortcut.systemImage,
                        accented: shortcut.accented,
                        accessibilityLabel: shortcut.accessibilityLabel,
                        action: shortcut.action
                    )
                }
            }
            .frame(maxWidth: contentMaxWidth)
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.top, isNarrowPhone ? 8 : 10)
            .padding(.bottom, isNarrowPhone ? 10 : 12)
            .background(
                LinearGradient(
                    colors: [RemoteTheme.cardStrong.opacity(0.95), RemoteTheme.card.opacity(0.90)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [RemoteTheme.glassTop, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .ignoresSafeArea(edges: .bottom)
                )
            )
        }
    }

    private var predictiveDockShortcuts: [DockShortcut] {
        [
            DockShortcut(
                id: "remote",
                title: "Remote",
                systemImage: "dot.radiowaves.left.and.right",
                accented: true,
                accessibilityLabel: "Remote controls"
            ) {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                    applySmartModePreferredControlSurface(smartControlMode)
                }
            },
            DockShortcut(
                id: "scenes",
                title: "Scenes",
                systemImage: "sparkles.tv.fill",
                accented: false,
                accessibilityLabel: "Open scenes"
            ) {
                openAdvancedControls(.watching)
            },
            DockShortcut(
                id: "settings",
                title: "Settings",
                systemImage: "gearshape.fill",
                accented: false,
                accessibilityLabel: "Open TV settings"
            ) {
                if viewModel.supportsMenuCommand {
                    viewModel.send(.menu)
                } else {
                    viewModel.isDevicePickerPresented = true
                }
            }
        ]
    }

    private func proDockButton(
        title: String,
        systemImage: String,
        accented: Bool = false,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: isPadLayout ? 52 : (isNarrowPhone ? 44 : 48))
        }
        .buttonStyle(accented ? AnyButtonStyle(RemoteAccentButtonStyle()) : AnyButtonStyle(RemoteSecondaryButtonStyle()))
        .accessibilityLabel(accessibilityLabel)
    }

    private var advancedControlsSheet: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        watchingHistoryDeck
                            .id(AdvancedSection.watching)
                        sceneCopilotDeck
                            .id(AdvancedSection.copilot)
                        inputSwitcherDeck
                            .id(AdvancedSection.inputs)
                        voiceDeck
                            .id(AdvancedSection.talk)
                        powerToolsDeck
                        if isPowerToolsExpanded {
                            commandDeck
                                .id(AdvancedSection.commands)
                            voiceMacroDeck
                                .id(AdvancedSection.macros)
                        }
                    }
                    .padding(16)
                }
                .onAppear {
                    if advancedInitialSection == .commands || advancedInitialSection == .macros {
                        isPowerToolsExpanded = true
                    }
                    scrollAdvancedSheet(to: advancedInitialSection, using: proxy, animated: false)
                }
                .onChange(of: advancedInitialSection) { _, section in
                    guard isAdvancedControlsPresented else { return }
                    if section == .commands || section == .macros {
                        isPowerToolsExpanded = true
                    }
                    scrollAdvancedSheet(to: section, using: proxy, animated: true)
                }
            }
            .navigationTitle("More")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isAdvancedControlsPresented = false
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.48), .medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: isAdvancedControlsPresented) { _, isPresented in
            if !isPresented {
                advancedInitialSection = .watching
                isPowerToolsExpanded = false
            }
        }
    }

    private func openAdvancedControls(_ section: AdvancedSection) {
        if section == .commands || section == .macros {
            isPowerToolsExpanded = true
        }
        advancedInitialSection = section
        isAdvancedControlsPresented = true
    }

    private func scrollAdvancedSheet(
        to section: AdvancedSection,
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        let action = {
            proxy.scrollTo(section, anchor: .top)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.24), action)
        } else {
            action()
        }
    }

    private var powerToolsDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Power Tools", systemImage: "wand.and.stars")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)

                Spacer()

                Button(isPowerToolsExpanded ? "Hide" : "Show") {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                        isPowerToolsExpanded.toggle()
                    }
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .buttonStyle(.borderless)
                .foregroundStyle(RemoteTheme.accentSoft)
            }

                Text("Text commands and voice shortcuts are optional and stay tucked away by default.")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textSecondary)
                    .lineLimit(2)
        }
        .padding(16)
        .background(cardBackground)
    }

    private var dPad: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Action Ring")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(RemoteTheme.textSecondary)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.07), Color.white.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: actionRingDiameter, height: actionRingDiameter)

                Circle()
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                    .frame(width: actionRingDiameter, height: actionRingDiameter)

                ringDirectionalButton(symbol: "chevron.up", action: { viewModel.send(.up) })
                    .offset(y: -actionRingOffset)

                ringDirectionalButton(symbol: "chevron.left", action: { viewModel.send(.left) })
                    .offset(x: -actionRingOffset)

                ringDirectionalButton(symbol: "chevron.right", action: { viewModel.send(.right) })
                    .offset(x: actionRingOffset)

                ringDirectionalButton(symbol: "chevron.down", action: { viewModel.send(.down) })
                    .offset(y: actionRingOffset)

                Button {
                    Haptics.tap()
                    viewModel.send(.select)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: actionRingCenterButtonSize, height: actionRingCenterButtonSize)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [RemoteTheme.accent, RemoteTheme.accent.opacity(0.86)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: RemoteTheme.accent.opacity(0.25), radius: 14, x: 0, y: 6)
                }
                .buttonStyle(RemotePressStyle())
                .accessibilityLabel("Select")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(isNarrowPhone ? 12 : 16)
        .background(cardBackground)
        .allowsHitTesting(viewModel.supportsDirectionalPad)
        .opacity(viewModel.supportsDirectionalPad ? 1 : 0.45)
    }

    private var swipePad: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Swipe with momentum. Two-finger swipe scrolls lists.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(RemoteTheme.textSecondary)

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.20))

                SwipePadSurface(
                    onDirection: { command in
                        Haptics.tap()
                        viewModel.send(command)
                    },
                    onSelect: {
                        Haptics.tap()
                        viewModel.send(.select)
                    },
                    onTwoFingerScroll: { command in
                        Haptics.tap()
                        viewModel.send(command)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(spacing: 8) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(RemoteTheme.accentSoft)
                    Text("Smart Swipepad")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(RemoteTheme.textPrimary)
                    Text("Tap to Select")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(RemoteTheme.textSecondary)
                }
                .allowsHitTesting(false)
            }
            .frame(height: isPadLayout ? 260 : (isNarrowPhone ? 200 : 230))

            Text("One finger: navigate. Two fingers: scroll lists and guides.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(RemoteTheme.textSecondary)
        }
        .padding(isNarrowPhone ? 12 : 16)
        .background(cardBackground)
        .allowsHitTesting(viewModel.supportsDirectionalPad)
        .opacity(viewModel.supportsDirectionalPad ? 1 : 0.45)
    }

    private var watchingHistoryDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Watching")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)

                Spacer()

                if viewModel.hasWatchingHistory {
                    Button("Clear") {
                        Haptics.tap()
                        viewModel.clearWatchingHistory()
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .buttonStyle(.borderless)
                    .foregroundStyle(RemoteTheme.accentSoft)
                    .accessibilityLabel("Clear recent watching history")
                }
            }

            if viewModel.recentWatchingHistory.isEmpty {
                Text("Your timeline appears here as you switch apps or shows.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textSecondary)
                    .lineLimit(2)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.recentWatchingHistory) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(viewModel.watchingHistoryHeadline(for: entry))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(RemoteTheme.textPrimary)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                Text(viewModel.watchingHistoryTimestampLabel(for: entry))
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(RemoteTheme.textSecondary)
                            }

                            Text(viewModel.watchingHistoryDetail(for: entry))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(RemoteTheme.textSecondary)
                                .lineLimit(2)
                        }

                        if entry.id != viewModel.recentWatchingHistory.last?.id {
                            Divider()
                                .overlay(RemoteTheme.stroke)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var sceneCopilotDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Smart Scene Assistant")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)

                Spacer()

                if viewModel.hasSceneCopilotSuggestions {
                    Button("Clear") {
                        Haptics.tap()
                        viewModel.clearSceneCopilotSuggestions()
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .buttonStyle(.borderless)
                    .foregroundStyle(RemoteTheme.accentSoft)
                }
            }

            Text(viewModel.sceneCopilotPlanSummary)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(RemoteTheme.textSecondary)
                .lineLimit(2)

            if viewModel.hasSceneCopilotContextSuggestions {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Context Picks")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(RemoteTheme.textPrimary)

                        Spacer()

                        Button("Hide") {
                            Haptics.tap()
                            viewModel.clearSceneCopilotContextSuggestions()
                        }
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .buttonStyle(.borderless)
                        .foregroundStyle(RemoteTheme.accentSoft)
                    }

                    ForEach(viewModel.sceneCopilotContextSuggestions) { suggestion in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.name)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(RemoteTheme.textPrimary)
                                    .lineLimit(1)

                                Text(suggestion.rationale)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(RemoteTheme.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            Button("Run") {
                                Haptics.tap()
                                viewModel.runSceneCopilotContextSuggestion(suggestion.id)
                            }
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .buttonStyle(RemoteSecondaryButtonStyle())

                            Button("Save") {
                                Haptics.tap()
                                viewModel.saveSceneCopilotContextSuggestion(suggestion.id)
                            }
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .buttonStyle(RemoteAccentButtonStyle())
                        }
                        .padding(9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black.opacity(0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(RemoteTheme.stroke, lineWidth: 1)
                                )
                        )
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.sceneCopilotPromptSuggestions, id: \.self) { prompt in
                        Button {
                            Haptics.tap()
                            viewModel.applySceneCopilotPromptSuggestion(prompt)
                        } label: {
                            Text(prompt)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(RemoteSecondaryButtonStyle())
                    }
                }
            }

            HStack(spacing: 10) {
                TextField(
                    "Describe a scene: movie night on HDMI 1 volume 18",
                    text: $viewModel.sceneCopilotPrompt
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(RemoteTheme.stroke, lineWidth: 1)
                        )
                )

                Button("Generate Scene") {
                    Haptics.tap()
                    viewModel.runSceneCopilotFromPrompt()
                }
                .buttonStyle(RemoteAccentButtonStyle())
                .disabled(viewModel.sceneCopilotPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(viewModel.sceneCopilotPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }

            if viewModel.hasSceneCopilotSuggestions {
                VStack(spacing: 10) {
                    ForEach(viewModel.sceneCopilotSuggestions) { suggestion in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: suggestion.iconSystemName)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(RemoteTheme.accentSoft)

                                Text(suggestion.name)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(RemoteTheme.textPrimary)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                Text(suggestion.confidence.label)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(copilotConfidenceTint(suggestion.confidence).opacity(0.22))
                                    )
                                    .foregroundStyle(copilotConfidenceTint(suggestion.confidence))
                            }

                            Text(suggestion.actionSummary)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(RemoteTheme.textPrimary)
                                .lineLimit(2)

                            Text(suggestion.rationale)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(RemoteTheme.textSecondary)
                                .lineLimit(2)

                            HStack(spacing: 8) {
                                Button("Run") {
                                    Haptics.tap()
                                    viewModel.runSceneCopilotSuggestion(suggestion.id)
                                }
                                .buttonStyle(RemoteSecondaryButtonStyle())

                                Button("Save") {
                                    Haptics.tap()
                                    viewModel.saveSceneCopilotSuggestion(suggestion.id)
                                }
                                .buttonStyle(RemoteAccentButtonStyle())
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.20))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(RemoteTheme.stroke, lineWidth: 1)
                                )
                        )
                    }
                }
            }

            if let status = viewModel.sceneCopilotStatusMessage {
                Text(status)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textSecondary)
                    .lineLimit(2)
            }

            if !viewModel.hasMacroShortcutsAccess {
                Button("Upgrade to Pro") {
                    Haptics.tap()
                    viewModel.presentPremiumPaywall(source: "scene_copilot")
                }
                .buttonStyle(RemoteAccentButtonStyle())
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var commandDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text Commands")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(RemoteTheme.textPrimary)

            Text(viewModel.plainCommandStatusMessage)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(RemoteTheme.textSecondary)
                .lineLimit(2)

            HStack(spacing: 10) {
                TextField("Try: open YouTube TV, switch HDMI 1, volume up", text: $viewModel.plainCommandText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(RemoteTheme.stroke, lineWidth: 1)
                            )
                )

                Button("Send") {
                    Haptics.tap()
                    viewModel.runPlainEnglishCommandFromTextField()
                }
                .buttonStyle(RemoteAccentButtonStyle())
                .disabled(viewModel.plainCommandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(viewModel.plainCommandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var voiceMacroDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voice Shortcuts")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(RemoteTheme.textPrimary)

            Text(viewModel.voiceMacroPlanSummary)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(RemoteTheme.textSecondary)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 8) {
                Text("Adaptive Learning")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)

                Picker(
                    "Adaptive Learning",
                    selection: Binding(
                        get: { viewModel.aiLearningMode },
                        set: { viewModel.setAILearningMode($0) }
                    )
                ) {
                    ForEach(viewModel.aiLearningModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(viewModel.aiLearningModeSummary)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(RemoteTheme.textSecondary)
                    .lineLimit(2)
            }

            if viewModel.hasAIMacroRecommendations {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggested Shortcuts")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(RemoteTheme.textPrimary)

                    ForEach(viewModel.aiMacroRecommendations) { recommendation in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: recommendation.iconSystemName)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(RemoteTheme.accentSoft)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\"\(recommendation.phrase)\"")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(RemoteTheme.textPrimary)
                                        .lineLimit(1)
                                    Text("\(recommendation.sceneName) • \(recommendation.useCount)x")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(RemoteTheme.textSecondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                Text(recommendation.confidence.label)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(copilotConfidenceTint(recommendation.confidence).opacity(0.22))
                                    )
                                    .foregroundStyle(copilotConfidenceTint(recommendation.confidence))
                            }

                            Text(recommendation.rationale)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(RemoteTheme.textSecondary)
                                .lineLimit(2)

                            HStack(spacing: 8) {
                                Button("Run") {
                                    Haptics.tap()
                                    viewModel.runAIMacroRecommendation(recommendation.id)
                                }
                                .buttonStyle(RemoteSecondaryButtonStyle())

                                Button("Save Macro") {
                                    Haptics.tap()
                                    viewModel.saveAIMacroRecommendation(recommendation.id)
                                }
                                .buttonStyle(RemoteAccentButtonStyle())

                                Button("Dismiss") {
                                    Haptics.tap()
                                    viewModel.dismissAIMacroRecommendation(recommendation.id)
                                }
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .buttonStyle(.borderless)
                                .foregroundStyle(RemoteTheme.textSecondary)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.20))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(RemoteTheme.stroke, lineWidth: 1)
                                )
                        )
                    }
                }
            }

            if viewModel.smartScenes.isEmpty {
                Text("Create a Smart Scene first, then map a phrase like \"movie time\".")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textSecondary)
                    .lineLimit(2)
            } else {
                TextField("Phrase: movie time", text: $viewModel.voiceMacroDraftPhrase)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(RemoteTheme.stroke, lineWidth: 1)
                            )
                    )

                Picker("Scene", selection: $viewModel.voiceMacroDraftSceneID) {
                    ForEach(viewModel.smartScenes) { scene in
                        Text(scene.name).tag(Optional(scene.id))
                    }
                }
                .pickerStyle(.menu)

                Button("Save Macro") {
                    Haptics.tap()
                    viewModel.saveVoiceMacroFromDraft()
                }
                .buttonStyle(RemoteAccentButtonStyle())
                .disabled(!viewModel.canSaveVoiceMacroDraft)
                .opacity(viewModel.canSaveVoiceMacroDraft ? 1 : 0.45)
            }

            if viewModel.hasVoiceMacros {
                Divider()
                    .overlay(RemoteTheme.stroke)

                VStack(spacing: 9) {
                    ForEach(viewModel.sortedVoiceMacros.prefix(6)) { macro in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\"\(macro.phrase)\"")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(RemoteTheme.textPrimary)
                                Text("Runs \(viewModel.voiceMacroSceneName(for: macro))")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(RemoteTheme.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            Button("Run") {
                                Haptics.tap()
                                viewModel.runVoiceMacro(macro)
                            }
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .buttonStyle(RemoteSecondaryButtonStyle())

                            Button {
                                Haptics.tap()
                                viewModel.removeVoiceMacro(macro.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(RemoteTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete macro \(macro.phrase)")
                        }
                    }
                }
            }

            if let status = viewModel.voiceMacroStatusMessage {
                Text(status)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textSecondary)
                    .lineLimit(2)
            }

            if !viewModel.hasMacroShortcutsAccess {
                Button("Upgrade to Pro") {
                    Haptics.tap()
                    viewModel.presentPremiumPaywall(source: "voice_macro")
                }
                .buttonStyle(RemoteAccentButtonStyle())
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var caregiverIntroDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Caregiver Home", systemImage: "person.badge.shield.checkmark.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)
                Spacer()
                Text("Advanced hidden")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(RemoteTheme.key)
                    )
            }

            Text("Large essentials only: Power, Volume, Home, Back, Select, and unlocked apps.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(RemoteTheme.textSecondary)
        }
        .padding(16)
        .background(cardBackground)
    }

    private var caregiverPowerDeck: some View {
        HStack(spacing: 12) {
            caregiverLargeButton(
                title: "Power On",
                symbol: "power.circle.fill",
                isEnabled: viewModel.canAttemptPowerOn,
                style: .secondary
            ) {
                viewModel.powerOnTV()
            }

            caregiverLargeButton(
                title: "Power Off",
                symbol: "power",
                isEnabled: viewModel.supportsPowerControls,
                style: .accent
            ) {
                viewModel.powerOffTV()
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var caregiverNavigationDeck: some View {
        HStack(spacing: 12) {
            caregiverLargeButton(
                title: "Home",
                symbol: "house.fill",
                isEnabled: viewModel.supportsHomeCommand,
                style: .secondary
            ) {
                viewModel.send(.home)
            }

            caregiverLargeButton(
                title: "Back",
                symbol: "arrow.left",
                isEnabled: viewModel.supportsBackCommand,
                style: .secondary
            ) {
                viewModel.send(.back)
            }

            caregiverLargeButton(
                title: "Select",
                symbol: "checkmark",
                isEnabled: viewModel.supportsDirectionalPad,
                style: .accent
            ) {
                viewModel.send(.select)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var caregiverVolumeDeck: some View {
        HStack(spacing: 12) {
            caregiverLargeButton(
                title: "Vol -",
                symbol: "speaker.minus.fill",
                isEnabled: viewModel.supportsVolumeControls,
                style: .secondary
            ) {
                viewModel.send(.volumeDown)
            }

            caregiverLargeButton(
                title: viewModel.isMuted ? "Unmute" : "Mute",
                symbol: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                isEnabled: viewModel.supportsVolumeControls,
                style: .accent
            ) {
                viewModel.toggleMute()
            }

            caregiverLargeButton(
                title: "Vol +",
                symbol: "speaker.plus.fill",
                isEnabled: viewModel.supportsVolumeControls,
                style: .secondary
            ) {
                viewModel.send(.volumeUp)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var caregiverAppsDeck: some View {
        let apps = viewModel.dockQuickLaunchApps
            .filter { !viewModel.isAppLocked($0) }
            .prefix(4)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Apps")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(RemoteTheme.textPrimary)

            if apps.isEmpty {
                Text("No unlocked apps available.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(RemoteTheme.textSecondary)
            } else {
                ForEach(Array(apps), id: \.id) { app in
                    Button {
                        Haptics.tap()
                        viewModel.launchApp(app)
                    } label: {
                        HStack(spacing: 10) {
                            TVAppIconView(app: app, size: 24)
                            Text(app.title)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(RemoteTheme.textPrimary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 62)
                    }
                    .buttonStyle(RemoteSecondaryButtonStyle())
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var quickLaunchDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Launch")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)
                Spacer()
                Button("Edit") {
                    viewModel.isQuickLaunchSheetPresented = true
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .buttonStyle(.borderless)
                .foregroundStyle(RemoteTheme.accentSoft)
                .disabled(viewModel.isCaregiverModeEnabled || viewModel.isAppInputLockEnabled)
                .opacity((viewModel.isCaregiverModeEnabled || viewModel.isAppInputLockEnabled) ? 0.45 : 1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.dockQuickLaunchApps.prefix(6)) { app in
                        Button {
                            Haptics.tap()
                            viewModel.launchApp(app)
                        } label: {
                            VStack(spacing: 8) {
                                TVAppIconView(app: app, size: 32)
                                Text(app.title)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(RemoteTheme.textPrimary)
                                    .lineLimit(1)
                                if viewModel.isAppLocked(app) {
                                    Label("Locked", systemImage: "lock.fill")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                }
                            }
                            .frame(width: 90, height: 72)
                        }
                        .buttonStyle(RemoteSecondaryButtonStyle())
                        .disabled(viewModel.isAppLocked(app))
                        .opacity(viewModel.isAppLocked(app) ? 0.45 : 1)
                        .accessibilityLabel("Launch \(app.title)")
                    }

                    Button {
                        viewModel.isQuickLaunchSheetPresented = true
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 18, weight: .bold))
                            Text("More")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .frame(width: 90, height: 72)
                    }
                    .buttonStyle(RemoteSecondaryButtonStyle())
                    .accessibilityLabel("Open app dock editor")
                    .disabled(viewModel.isCaregiverModeEnabled || viewModel.isAppInputLockEnabled)
                    .opacity((viewModel.isCaregiverModeEnabled || viewModel.isAppInputLockEnabled) ? 0.45 : 1)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .allowsHitTesting(viewModel.supportsLaunchApps)
        .opacity(viewModel.supportsLaunchApps ? 1 : 0.45)
    }

    private var smartScenesDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Smart Scenes")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)

                Spacer()

                Text(viewModel.smartScenesUsageSummary)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(RemoteTheme.key)
                    )
                    .foregroundStyle(RemoteTheme.textSecondary)

                Button("New") {
                    Haptics.tap()
                    viewModel.presentSmartSceneComposer()
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .buttonStyle(.borderless)
                .foregroundStyle(RemoteTheme.accentSoft)
            }

            if viewModel.smartScenes.isEmpty {
                Text("Save one-tap scenes like \"TV Night\". Free includes one scene.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textSecondary)
                    .lineLimit(2)

                Button {
                    Haptics.tap()
                    viewModel.presentSmartSceneComposer()
                } label: {
                    Label("Create First Scene", systemImage: "sparkles.tv.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(RemoteSecondaryButtonStyle())
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.smartScenes.prefix(6)) { scene in
                            Button {
                                Haptics.tap()
                                viewModel.runSmartScene(scene)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Image(systemName: scene.iconSystemName)
                                            .font(.system(size: 16, weight: .bold))
                                        Text(scene.name)
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .lineLimit(1)
                                    }

                                    Text(scene.actionSummary)
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(RemoteTheme.textSecondary)
                                        .lineLimit(2)
                                }
                                .frame(width: 150, height: 72, alignment: .topLeading)
                            }
                            .buttonStyle(RemoteSecondaryButtonStyle())
                            .accessibilityLabel("Run scene \(scene.name)")
                        }
                    }
                }
            }

            if !viewModel.canCreateAdditionalSmartScene {
                Button {
                    Haptics.tap()
                    viewModel.presentPremiumPaywall(source: "smart_scene_count_limit")
                } label: {
                    Label("Unlock Unlimited Scenes", systemImage: "crown.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(RemoteSecondaryButtonStyle())
            }

            Text(viewModel.smartScenesPlanSummary)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(RemoteTheme.textSecondary)
                .lineLimit(2)

            if let sceneStatusMessage = viewModel.sceneStatusMessage {
                Text(sceneStatusMessage)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var inputSwitcherDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Inputs")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)
                Spacer()
                Button("All Inputs") {
                    viewModel.presentInputPicker()
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .buttonStyle(.borderless)
                .foregroundStyle(RemoteTheme.accentSoft)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.inputSources.prefix(4)) { input in
                        Button {
                            Haptics.tap()
                            viewModel.switchInput(input)
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: input.iconSystemName)
                                    .font(.system(size: 18, weight: .bold))
                                Text(input.title)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                            }
                            .frame(width: 92, height: 72)
                        }
                        .buttonStyle(RemoteSecondaryButtonStyle())
                        .disabled(viewModel.isInputLocked(input))
                        .opacity(viewModel.isInputLocked(input) ? 0.45 : 1)
                        .accessibilityLabel("Switch to \(input.title)")
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .allowsHitTesting(viewModel.supportsInputSwitching)
        .opacity(viewModel.supportsInputSwitching ? 1 : 0.45)
    }

    private var powerDeck: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                viewModel.powerOnTV()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "power.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("Power On")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, minHeight: 62)
            }
            .buttonStyle(RemoteSecondaryButtonStyle())
            .disabled(!viewModel.canAttemptPowerOn)
            .opacity(viewModel.canAttemptPowerOn ? 1 : 0.45)
            .accessibilityLabel("Power on TV")

            Button {
                Haptics.tap()
                viewModel.powerOffTV()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 18, weight: .bold))
                    Text("Power Off")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, minHeight: 62)
            }
            .buttonStyle(RemoteAccentButtonStyle())
            .disabled(!viewModel.supportsPowerControls)
            .opacity(viewModel.supportsPowerControls ? 1 : 0.45)
            .accessibilityLabel("Power off TV")
        }
        .padding(16)
        .background(cardBackground)
    }

    private var volumeDeck: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Volume")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(RemoteTheme.textPrimary)

            HStack(spacing: 12) {
                RepeatingCommandButton(action: { viewModel.send(.volumeDown) }) {
                    VStack(spacing: 6) {
                        Image(systemName: "speaker.minus.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Volume -")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(RemoteSecondaryButtonStyle())
                .accessibilityLabel("Volume down")

                Button {
                    Haptics.tap()
                    viewModel.toggleMute()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text(viewModel.isMuted ? "Unmute" : "Mute")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(RemoteAccentButtonStyle())
                .accessibilityLabel(viewModel.isMuted ? "Unmute TV" : "Mute TV")

                RepeatingCommandButton(action: { viewModel.send(.volumeUp) }) {
                    VStack(spacing: 6) {
                        Image(systemName: "speaker.plus.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Volume +")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(RemoteSecondaryButtonStyle())
                .accessibilityLabel("Volume up")
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RemoteTheme.textSecondary)

                Slider(
                    value: Binding(
                        get: { viewModel.volumeLevel },
                        set: { viewModel.setVolumeLevel($0) }
                    ),
                    in: 0 ... 100,
                    step: 1,
                    onEditingChanged: { isEditing in
                        viewModel.setVolumeSliderEditing(isEditing)
                    }
                )
                .tint(RemoteTheme.accentSoft)
                .accessibilityLabel("TV volume")
                .accessibilityValue("\(Int(viewModel.volumeLevel.rounded())) percent")

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RemoteTheme.textSecondary)

                Text("\(Int(viewModel.volumeLevel.rounded()))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(16)
        .background(cardBackground)
        .allowsHitTesting(viewModel.supportsVolumeControls)
        .opacity(viewModel.supportsVolumeControls ? 1 : 0.45)
    }

    private var voiceDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Talk to TV")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)
                Spacer()
                Button {
                    Haptics.tap()
                    viewModel.toggleVoiceCapture()
                } label: {
                    Label(viewModel.isVoiceListening ? "Stop" : "Talk", systemImage: viewModel.isVoiceListening ? "waveform.circle.fill" : "mic.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .buttonStyle(viewModel.isVoiceListening ? AnyButtonStyle(RemoteAccentButtonStyle()) : AnyButtonStyle(RemoteSecondaryButtonStyle()))
                .accessibilityLabel(viewModel.isVoiceListening ? "Stop voice capture" : "Start voice capture")
            }

            Text(viewModel.voiceStatusMessage)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(RemoteTheme.textSecondary)
                .lineLimit(2)

            Text(viewModel.voiceTranscript.isEmpty ? "Your speech appears here. Open a text field on TV, then tap Send to TV." : viewModel.voiceTranscript)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(RemoteTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(RemoteTheme.stroke, lineWidth: 1)
                        )
                )
                .accessibilityLabel("Voice transcript")

            HStack(spacing: 10) {
                Button("Clear") {
                    Haptics.tap()
                    viewModel.clearVoiceTranscript()
                }
                .buttonStyle(RemoteSecondaryButtonStyle())
                .disabled(viewModel.voiceTranscript.isEmpty)
                .opacity(viewModel.voiceTranscript.isEmpty ? 0.45 : 1)

                Button(viewModel.isSendingVoiceTranscript ? "Sending..." : "Send to TV") {
                    Haptics.tap()
                    viewModel.sendVoiceTranscriptToTV()
                }
                .buttonStyle(RemoteAccentButtonStyle())
                .disabled(!viewModel.canSendVoiceTranscript)
                .opacity(viewModel.canSendVoiceTranscript ? 1 : 0.45)
                .accessibilityLabel("Send voice text to TV")
            }
        }
        .padding(16)
        .background(cardBackground)
        .allowsHitTesting(viewModel.supportsControls)
        .opacity(viewModel.supportsControls ? 1 : 0.45)
    }

    private var footerDeck: some View {
        HStack(spacing: 12) {
            footerButton(label: "Back", symbol: "arrow.left", isEnabled: viewModel.supportsBackCommand) {
                viewModel.send(.back)
            }
            footerButton(label: "Home", symbol: "house.fill", isEnabled: viewModel.supportsHomeCommand) {
                viewModel.send(.home)
            }
            footerButton(label: "Menu", symbol: "slider.horizontal.3", isEnabled: viewModel.supportsMenuCommand) {
                viewModel.send(.menu)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func footerButton(
        label: String,
        symbol: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(RemoteSecondaryButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(label)
    }

    private func caregiverLargeButton(
        title: String,
        symbol: String,
        isEnabled: Bool,
        style: CaregiverButtonStyle,
        action: @escaping () -> Void
    ) -> some View {
        let buttonStyle: AnyButtonStyle = style == .accent
            ? AnyButtonStyle(RemoteAccentButtonStyle())
            : AnyButtonStyle(RemoteSecondaryButtonStyle())

        return Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .bold))
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 84)
        }
        .buttonStyle(buttonStyle)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func ringDirectionalButton(symbol: String, action: @escaping () -> Void) -> some View {
        RepeatingCommandButton(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: actionRingDirectionButtonSize, height: actionRingDirectionButtonSize)
                .background(
                    Circle()
                        .fill(RemoteTheme.key.opacity(0.90))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                )
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [RemoteTheme.cardStrong.opacity(0.96), RemoteTheme.card.opacity(0.90)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .strokeBorder(RemoteTheme.stroke, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [RemoteTheme.glassTop, .clear, RemoteTheme.glassBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.30), radius: 14, x: 0, y: 7)
    }
}

private enum CaregiverButtonStyle {
    case secondary
    case accent
}

private struct AnyButtonStyle: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        makeBodyClosure = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}

private struct SwipePadSurface: UIViewRepresentable {
    let onDirection: (TVCommand) -> Void
    let onSelect: () -> Void
    let onTwoFingerScroll: (TVCommand) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear

        let oneFingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleOneFingerPan(_:)))
        oneFingerPan.minimumNumberOfTouches = 1
        oneFingerPan.maximumNumberOfTouches = 1

        let twoFingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.require(toFail: oneFingerPan)
        tap.require(toFail: twoFingerPan)

        view.addGestureRecognizer(oneFingerPan)
        view.addGestureRecognizer(twoFingerPan)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject {
        var parent: SwipePadSurface

        private var horizontalAccumulator: CGFloat = 0
        private var verticalAccumulator: CGFloat = 0
        private var scrollAccumulator: CGFloat = 0
        private var inertiaToken = 0

        init(parent: SwipePadSurface) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            parent.onSelect()
        }

        @objc func handleOneFingerPan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                cancelInertia()
                horizontalAccumulator = 0
                verticalAccumulator = 0
            case .changed:
                let delta = recognizer.translation(in: recognizer.view)
                recognizer.setTranslation(.zero, in: recognizer.view)
                horizontalAccumulator += delta.x
                verticalAccumulator += delta.y
                emitDirectionalStep(threshold: 26)
            case .ended, .cancelled, .failed:
                let velocity = recognizer.velocity(in: recognizer.view)
                emitInertia(for: velocity)
                horizontalAccumulator = 0
                verticalAccumulator = 0
            default:
                break
            }
        }

        @objc func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                cancelInertia()
                scrollAccumulator = 0
            case .changed:
                let delta = recognizer.translation(in: recognizer.view)
                recognizer.setTranslation(.zero, in: recognizer.view)
                scrollAccumulator += delta.y
                while abs(scrollAccumulator) >= 22 {
                    let command: TVCommand = scrollAccumulator > 0 ? .down : .up
                    parent.onTwoFingerScroll(command)
                    scrollAccumulator += scrollAccumulator > 0 ? -22 : 22
                }
            case .ended, .cancelled, .failed:
                scrollAccumulator = 0
            default:
                break
            }
        }

        private func emitDirectionalStep(threshold: CGFloat) {
            if abs(horizontalAccumulator) > abs(verticalAccumulator) {
                while abs(horizontalAccumulator) >= threshold {
                    let command: TVCommand = horizontalAccumulator > 0 ? .right : .left
                    parent.onDirection(command)
                    horizontalAccumulator += horizontalAccumulator > 0 ? -threshold : threshold
                }
                verticalAccumulator = 0
            } else {
                while abs(verticalAccumulator) >= threshold {
                    let command: TVCommand = verticalAccumulator > 0 ? .down : .up
                    parent.onDirection(command)
                    verticalAccumulator += verticalAccumulator > 0 ? -threshold : threshold
                }
                horizontalAccumulator = 0
            }
        }

        private func emitInertia(for velocity: CGPoint) {
            let speed = hypot(velocity.x, velocity.y)
            let extraSteps = min(6, max(0, Int(speed / 1050)))
            guard extraSteps > 0 else { return }

            let dominantCommand: TVCommand
            if abs(velocity.x) > abs(velocity.y) {
                dominantCommand = velocity.x > 0 ? .right : .left
            } else {
                dominantCommand = velocity.y > 0 ? .down : .up
            }

            inertiaToken += 1
            let token = inertiaToken
            for step in 0..<extraSteps {
                let delay = 0.07 * Double(step + 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.inertiaToken == token else { return }
                    self.parent.onDirection(dominantCommand)
                }
            }
        }

        private func cancelInertia() {
            inertiaToken += 1
        }
    }
}

private struct TVAppIconView: View {
    let app: TVAppShortcut
    let size: CGFloat

    private var cornerRadius: CGFloat {
        max(7, size * 0.24)
    }

    var body: some View {
        ZStack {
            iconContent
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 5, x: 0, y: 2)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var iconContent: some View {
        if let bundledAssetImage {
            bundledAssetImage
                .resizable()
                .scaledToFill()
        } else if let iconURL = app.iconURL {
            AsyncImage(url: iconURL, transaction: Transaction(animation: .easeOut(duration: 0.16))) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    brandedFallback
                @unknown default:
                    brandedFallback
                }
            }
        } else {
            brandedFallback
        }
    }

    private var bundledAssetImage: Image? {
        guard let assetName = app.iconAssetName else { return nil }
        guard let uiImage = UIImage(named: assetName) else { return nil }
        return Image(uiImage: uiImage)
    }

    @ViewBuilder
    private var brandedFallback: some View {
        if let brand = app.brandIdentity {
            brandFallback(for: brand)
        } else if let tint = Color(remoteHex: app.brandColorHex) {
            ZStack {
                tint
                Image(systemName: app.iconSystemName)
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(Color.white)
            }
        } else {
            ZStack {
                Color.black.opacity(0.18)
                Image(systemName: app.iconSystemName)
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(RemoteTheme.accentSoft)
            }
        }
    }

    @ViewBuilder
    private func brandFallback(for brand: TVAppBrandIdentity) -> some View {
        switch brand {
        case .netflix:
            ZStack {
                Color.black
                Text("N")
                    .font(.system(size: size * 0.64, weight: .black, design: .rounded))
                    .foregroundStyle(Color(remoteHex: "#E50914") ?? .red)
                    .offset(y: 0.5)
            }
        case .youtube:
            ZStack {
                Color(remoteHex: "#FF0000") ?? .red
                PlayGlyph()
                    .fill(Color.white)
                    .frame(width: size * 0.36, height: size * 0.33)
                    .offset(x: size * 0.03)
            }
        case .youtubeTV:
            ZStack {
                LinearGradient(
                    colors: [Color(remoteHex: "#FF4E45") ?? .red, Color(remoteHex: "#E50914") ?? .red],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 2) {
                    PlayGlyph()
                        .fill(Color.white)
                        .frame(width: size * 0.32, height: size * 0.28)
                    Text("TV")
                        .font(.system(size: size * 0.18, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.white)
                }
            }
        case .primeVideo:
            ZStack {
                Color(remoteHex: "#00A8E1") ?? Color.blue
                Text("prime")
                    .font(.system(size: size * 0.26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.horizontal, size * 0.08)
            }
        case .disneyPlus:
            ZStack {
                LinearGradient(
                    colors: [Color(remoteHex: "#0A1D5E") ?? Color.blue, Color(remoteHex: "#113CCF") ?? Color.blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text("Disney+")
                    .font(.system(size: size * 0.20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                    .padding(.horizontal, size * 0.06)
            }
        case .appleTV:
            ZStack {
                Color.black
                Image(systemName: "appletv.fill")
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
        case .plex:
            ZStack {
                Color.black
                PlayGlyph()
                    .fill(Color(remoteHex: "#F9BE03") ?? Color.orange)
                    .frame(width: size * 0.34, height: size * 0.30)
                    .offset(x: size * 0.02)
            }
        }
    }
}

private struct PlayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private extension Color {
    init?(remoteHex: String?) {
        guard var hex = remoteHex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
            return nil
        }

        if hex.hasPrefix("#") {
            hex.removeFirst()
        } else if hex.lowercased().hasPrefix("0x") {
            hex.removeFirst(2)
        }

        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value) else { return nil }

        switch hex.count {
        case 3:
            let r = Double((value >> 8) & 0xF) / 15.0
            let g = Double((value >> 4) & 0xF) / 15.0
            let b = Double(value & 0xF) / 15.0
            self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
        case 6:
            let r = Double((value >> 16) & 0xFF) / 255.0
            let g = Double((value >> 8) & 0xFF) / 255.0
            let b = Double(value & 0xFF) / 255.0
            self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
        case 8:
            let a = Double((value >> 24) & 0xFF) / 255.0
            let r = Double((value >> 16) & 0xFF) / 255.0
            let g = Double((value >> 8) & 0xFF) / 255.0
            let b = Double(value & 0xFF) / 255.0
            self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
        default:
            return nil
        }
    }
}

private struct QuickLaunchSheet: View {
    @ObservedObject var viewModel: TVRemoteAppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Favorites (drag to reorder)") {
                    if viewModel.favoriteQuickLaunchApps.isEmpty {
                        Text("No favorites yet. Tap the star button below to add app shortcuts.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.favoriteQuickLaunchApps) { app in
                            appRow(app, isFavorite: true)
                        }
                        .onMove(perform: viewModel.moveFavoriteQuickLaunches)
                    }
                }

                Section("Available Apps") {
                    ForEach(viewModel.nonFavoriteQuickLaunchApps) { app in
                        appRow(app, isFavorite: false)
                    }
                }
            }
            .navigationTitle("Quick Launch Dock")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.42), .medium, .large])
    }

    private func appRow(_ app: TVAppShortcut, isFavorite: Bool) -> some View {
        HStack(spacing: 12) {
            TVAppIconView(app: app, size: 24)
            Text(app.title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button {
                Haptics.tap()
                viewModel.toggleQuickLaunchFavorite(app)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "Remove \(app.title) from favorites" : "Add \(app.title) to favorites")

            Button {
                Haptics.tap()
                viewModel.toggleAppLock(app)
            } label: {
                Image(systemName: viewModel.isAppLocked(app) ? "lock.fill" : "lock.open.fill")
                    .foregroundStyle(viewModel.isAppLocked(app) ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isAppLocked(app) ? "Unlock \(app.title)" : "Lock \(app.title)")

            Button("Launch") {
                Haptics.tap()
                viewModel.launchApp(app)
                dismiss()
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.supportsLaunchApps || viewModel.isAppLocked(app))
        }
    }
}

private struct InputSwitcherSheet: View {
    @ObservedObject var viewModel: TVRemoteAppViewModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.inputSources) { input in
                        VStack(spacing: 6) {
                            Button {
                                Haptics.tap()
                                viewModel.switchInput(input)
                                dismiss()
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: input.iconSystemName)
                                        .font(.system(size: 20, weight: .bold))
                                    Text(input.title)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                    if viewModel.isInputLocked(input) {
                                        Label("Locked", systemImage: "lock.fill")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 88)
                            }
                            .buttonStyle(RemoteSecondaryButtonStyle())
                            .disabled(!viewModel.supportsInputSwitching || viewModel.isInputLocked(input))
                            .opacity(viewModel.isInputLocked(input) ? 0.45 : 1)
                            .accessibilityLabel("Switch to \(input.title)")

                            Button(viewModel.isInputLocked(input) ? "Unlock Input" : "Lock Input") {
                                Haptics.tap()
                                viewModel.toggleInputLock(input)
                            }
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .buttonStyle(.borderless)
                            .foregroundStyle(viewModel.isInputLocked(input) ? Color.orange : RemoteTheme.accentSoft)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Input Switcher")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh") {
                        Task {
                            await viewModel.refreshInputSources()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.36), .medium])
    }
}

private struct RemotePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.80), value: configuration.isPressed)
    }
}

private struct RemoteSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(RemoteTheme.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [RemoteTheme.keyTop, RemoteTheme.keyBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(RemoteTheme.key)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.20), lineWidth: 0.8)
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .shadow(color: Color.black.opacity(0.24), radius: 6, x: 0, y: 3)
            .animation(.spring(response: 0.20, dampingFraction: 0.84), value: configuration.isPressed)
    }
}

private struct RemoteAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(RemoteTheme.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [RemoteTheme.accentTop, RemoteTheme.accentBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .shadow(color: RemoteTheme.accentGlow.opacity(0.40), radius: 10, x: 0, y: 4)
            .animation(.spring(response: 0.20, dampingFraction: 0.84), value: configuration.isPressed)
    }
}

struct RemoteControlView_Previews: PreviewProvider {
    static var previews: some View {
        RemoteControlView(viewModel: TVRemoteAppViewModel())
    }
}
