import SwiftUI
import CoreData
import Foundation

private func gallonsTotal(_ item: InventoryItemEntity) -> Double {
    if item.isLiquid {
        return item.totalGallonsOnHand
    }
    let unitsTotal = item.unitsPerCase > 0
        ? Double(item.quantity * item.unitsPerCase + item.looseUnits)
        : Double(item.quantity + item.looseUnits)
    let eachesFraction = item.eachesPerUnit > 0
        ? Double(item.looseEaches) / Double(item.eachesPerUnit)
        : 0
    return unitsTotal + eachesFraction + item.gallonFraction
}

private enum ShiftMode: String, CaseIterable, Identifiable {
    case open = "Open"
    case mid = "Mid"
    case close = "Close"

    var id: String { rawValue }
}

private struct ShiftModePickerView: View {
    @Binding var selection: ShiftMode

    var body: some View {
        Picker("Shift", selection: $selection) {
            ForEach(ShiftMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 4)
    }
}

private struct StartWorkSnapshot {
    let totalExceptionCount: Int
    let criticalRestockCount: Int
    let staleCountCount: Int
    let missingPlanningDataCount: Int
    let recommendedAction: QuickAction
    let recommendedTitle: String
    let recommendedReason: String
    let recommendedSystemImage: String
    let urgencyBadge: String
}

private struct QuickCountBarView: View {
    let onQuickAdd: () -> Void
    let onSetAmount: () -> Void
    let onNotes: () -> Void
    var isCoachHighlighted: Bool = false
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onQuickAdd) {
                Label("Quick Add", systemImage: "bolt.fill")
            }
            .inventorySecondaryAction()

            Button(action: onSetAmount) {
                Label("Set Amount", systemImage: "slider.horizontal.3")
            }
            .inventoryPrimaryAction()

            Button(action: onNotes) {
                Label("Notes", systemImage: "note.text")
            }
            .inventorySecondaryAction()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .inventoryCard(cornerRadius: 20, emphasis: 0.74)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    Theme.accent.opacity(isCoachHighlighted ? (pulse ? 0.9 : 0.5) : 0),
                    lineWidth: isCoachHighlighted ? 2.4 : 0
                )
        )
        .shadow(
            color: Theme.accent.opacity(isCoachHighlighted ? (pulse ? 0.28 : 0.14) : 0),
            radius: isCoachHighlighted ? (pulse ? 16 : 10) : 0,
            x: 0,
            y: 0
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .onAppear {
            guard isCoachHighlighted else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
        }
        .onChange(of: isCoachHighlighted) { _, isActive in
            if isActive {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                pulse = false
            }
        }
    }
}

private func formattedGallons(_ value: Double) -> String {
    let rounded = (value * 100).rounded() / 100
    var text = String(format: "%.2f", rounded)
    if text.contains(".") {
        text = text.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
    return text
}

private func totalUnitsValue(_ item: InventoryItemEntity) -> Int {
    Int(item.totalUnitsOnHand)
}

private extension View {
    @ViewBuilder
    func coachHighlight(_ isActive: Bool, cornerRadius: CGFloat = 12) -> some View {
        if isActive {
            self
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.accentSoft.opacity(0.22))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Theme.accent.opacity(0.85), lineWidth: 1.8)
                )
                .shadow(color: Theme.accent.opacity(0.32), radius: 10, x: 0, y: 0)
        } else {
            self
        }
    }
}

struct ItemsListView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var dataController: InventoryDataController
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var guidanceStore: GuidanceStore
    @EnvironmentObject private var automationStore: AutomationStore
    @EnvironmentObject private var automationRouteStore: AutomationRouteStore
    @EnvironmentObject private var platformStore: PlatformStore
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.updatedAt, ascending: false)],
        animation: nil
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var shiftMode: ShiftMode = .open
    @State private var isPresentingAdd = false
    @State private var isPresentingQuickAdd = false
    @State private var isPresentingScan = false
    @State private var isPresentingHelp = false
    @State private var isPresentingQuickActions = false
    @State private var isPresentingMenu = false
    @State private var isPresentingQuickAdjust = false
    @State private var isPresentingBarcodeScan = false
    @State private var isPresentingStarterTemplates = false
    @State private var isPresentingRunShift = false
    @State private var isPresentingDailyOpsBrief = false
    @State private var isPresentingAutomationInbox = false
    @State private var isPresentingIntegrationHub = false
    @State private var isPresentingTrustCenter = false
    @State private var isPresentingOpsIntelligence = false
    @State private var isPresentingKPIDashboard = false
    @State private var isPresentingZoneMission = false
    @State private var isPresentingCyclePlanner = false
    @State private var isPresentingExceptions = false
    @State private var isPresentingReplenishment = false
    @State private var isPresentingCalculations = false
    @State private var pendingQuickAction: QuickAction?
    @State private var addPrefillBarcode: String?
    @State private var editingItem: InventoryItemEntity?
    @State private var deleteCandidate: InventoryItemEntity?
    @State private var editingAmountItem: InventoryItemEntity?
    @State private var editingNoteItem: InventoryItemEntity?
    @State private var quickAdjustItem: InventoryItemEntity?
    @State private var isPresentingSetPicker = false
    @State private var isPresentingNotePicker = false
    @State private var permissionMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                List {
                    headerSection
                    if let nudge = activeGuidanceNudge {
                        guidanceNudgeCard(nudge)
                    }
                    if filteredItems.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { _, item in
                            ItemRowView(
                                item: item,
                                canEditDetails: authStore.canManageCatalog,
                                canDeleteItem: authStore.canDeleteItems,
                                onEdit: {
                                    guard authStore.canManageCatalog else {
                                        permissionMessage = "Only owners and managers can edit item details."
                                        Haptics.tap()
                                        return
                                    }
                                    editingItem = item
                                },
                                onStockChange: { delta in adjustQuantity(for: item, delta: delta) },
                                onEditAmount: { editingAmountItem = item },
                                onRequestDelete: {
                                    guard authStore.canDeleteItems else {
                                        permissionMessage = "Only workspace owners can delete items."
                                        Haptics.tap()
                                        return
                                    }
                                    deleteCandidate = item
                                }
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    editingAmountItem = item
                                } label: {
                                    Label("Set", systemImage: "pencil")
                                }
                                .tint(Theme.accent)

                                Button {
                                    editingNoteItem = item
                                } label: {
                                    Label("Note", systemImage: "note.text")
                                }
                                .tint(.gray)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    item.isPinned.toggle()
                                    item.updatedAt = Date()
                                    dataController.save()
                                } label: {
                                    Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
                                }
                                .tint(.orange)
                            }
                        }
                        .onDelete { offsets in
                            delete(offsets, from: filteredItems)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Inventory")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isPresentingQuickAdd = true } label: {
                        toolbarIcon("bolt.fill", target: .quickAddButton)
                    }
                    .accessibilityLabel("Quick Add")
                    .disabled(!authStore.canManageCatalog)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { isPresentingScan = true } label: {
                        Image(systemName: "camera.viewfinder")
                    }
                    .accessibilityLabel("Shelf Scan")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { isPresentingBarcodeScan = true } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .accessibilityLabel("Scan Barcode")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(categoryOptions, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPresentingQuickActions = true } label: {
                        toolbarIcon("ellipsis.circle", target: .quickActionsButton)
                    }
                    .accessibilityLabel("Quick Actions")
                    .accessibilityIdentifier("toolbar.quickActions")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingHelp = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Features and Help")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingMenu = true
                    } label: {
                        toolbarIcon("line.3.horizontal", target: .menuButton)
                    }
                    .accessibilityLabel("Menu")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addPrefillBarcode = nil
                        isPresentingAdd = true
                    } label: { Image(systemName: "plus") }
                    .disabled(!authStore.canManageCatalog)
                }
            }
            .searchable(text: $searchText, prompt: "Search items")
            .tint(Theme.accent)
            .sheet(isPresented: $isPresentingAdd) {
                ItemFormView(mode: .add(barcode: addPrefillBarcode))
            }
            .sheet(isPresented: $isPresentingQuickAdd) {
                QuickAddView()
            }
            .sheet(isPresented: $isPresentingScan) {
                VisualShelfScanView()
            }
            .sheet(isPresented: $isPresentingHelp) {
                FeaturesMenuView()
            }
            .sheet(isPresented: $guidanceStore.isShowingGuideCenter) {
                GuidanceCenterView { flow in
                    handleGuidedFlowLaunch(flow)
                } onReplayCoachMarks: {
                    guidanceStore.restartCoachMarks()
                }
            }
            .sheet(isPresented: $isPresentingQuickActions) {
                QuickActionsView { action in
                    pendingQuickAction = action
                    isPresentingQuickActions = false
                }
            }
            .sheet(isPresented: $isPresentingReplenishment) {
                NavigationStack {
                    ReplenishmentPlannerView()
                }
            }
            .sheet(isPresented: $isPresentingStarterTemplates) {
                NavigationStack {
                    StarterTemplatesView()
                }
            }
            .sheet(isPresented: $isPresentingRunShift) {
                NavigationStack {
                    RunShiftView()
                }
            }
            .sheet(isPresented: $isPresentingDailyOpsBrief) {
                NavigationStack {
                    DailyOpsBriefView()
                }
            }
            .sheet(isPresented: $isPresentingAutomationInbox) {
                NavigationStack {
                    AutomationInboxView()
                }
            }
            .sheet(isPresented: $isPresentingIntegrationHub) {
                NavigationStack {
                    IntegrationHubView()
                }
            }
            .sheet(isPresented: $isPresentingTrustCenter) {
                NavigationStack {
                    TrustCenterView()
                }
            }
            .sheet(isPresented: $isPresentingOpsIntelligence) {
                NavigationStack {
                    OpsIntelligenceView()
                }
            }
            .sheet(isPresented: $isPresentingKPIDashboard) {
                NavigationStack {
                    KPIDashboardView()
                }
            }
            .sheet(isPresented: $isPresentingZoneMission) {
                NavigationStack {
                    ZoneMissionView()
                }
            }
            .sheet(isPresented: $isPresentingCyclePlanner) {
                NavigationStack {
                    CycleCountPlannerView()
                }
            }
            .sheet(isPresented: $isPresentingExceptions) {
                NavigationStack {
                    ExceptionFeedView()
                }
            }
            .sheet(isPresented: $isPresentingCalculations) {
                NavigationStack {
                    InventoryCalculationsView()
                }
            }
            .sheet(isPresented: $isPresentingMenu) {
                MenuView()
            }
            .sheet(isPresented: $isPresentingBarcodeScan) {
                BarcodeScanView { code in
                    handleBarcodeScan(code)
                }
            }
            .sheet(item: $editingItem) { item in
                ItemFormView(mode: .edit(item))
            }
            .sheet(item: $editingAmountItem) { item in
                QuantityEditView(item: item)
            }
            .sheet(item: $editingNoteItem) { item in
                NotesEditView(item: item)
            }
            .sheet(isPresented: $isPresentingSetPicker) {
                ItemSelectionView(title: "Set Amount", items: filteredItems) { item in
                    editingAmountItem = item
                }
            }
            .sheet(isPresented: $isPresentingNotePicker) {
                ItemSelectionView(title: "Add Note", items: filteredItems) { item in
                    editingNoteItem = item
                }
            }
            .sheet(isPresented: $isPresentingQuickAdjust) {
                ItemSelectionView(title: "Stock In / Out", items: filteredItems) { item in
                    quickAdjustItem = item
                }
            }
            .sheet(item: $quickAdjustItem) { item in
                QuickStockAdjustView(item: item)
            }
            .onChange(of: isPresentingQuickActions) { _, isPresented in
                guard !isPresented, let action = pendingQuickAction else { return }
                pendingQuickAction = nil
                DispatchQueue.main.async {
                    handleQuickAction(action)
                }
            }
            .onChange(of: automationRouteStore.pendingRoute) { _, _ in
                consumePendingAutomationRoute()
            }
            .onAppear {
                let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
                scopeLegacyItemsToActiveWorkspaceIfNeeded()
                if isUITesting {
                    guidanceStore.closeGuideCenter(markSeen: true)
                    guidanceStore.skipCoachMarks()
                } else {
                    guidanceStore.presentFirstRunGuideIfNeeded(isAuthenticated: authStore.isAuthenticated)
                    guidanceStore.startCoachMarksIfNeeded(isAuthenticated: authStore.isAuthenticated)
                }
                refreshGuidanceNudges()
                refreshAutomationCycle(force: true)
                consumePendingAutomationRoute()
            }
            .onChange(of: guidanceStore.isShowingGuideCenter) { _, isShowing in
                guard !isShowing else { return }
                guidanceStore.startCoachMarksIfNeeded(isAuthenticated: authStore.isAuthenticated)
                refreshGuidanceNudges()
                consumePendingAutomationRoute()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .NSManagedObjectContextObjectsDidChange,
                    object: context
                )
            ) { _ in
                refreshGuidanceNudges()
                refreshAutomationCycle()
            }
            .confirmationDialog(
                "Delete item?",
                isPresented: .init(
                    get: { deleteCandidate != nil },
                    set: { if !$0 { deleteCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let item = deleteCandidate {
                        context.delete(item)
                        dataController.save()
                    }
                    deleteCandidate = nil
                }
                Button("Cancel", role: .cancel) {
                    deleteCandidate = nil
                }
            } message: {
                Text("This will remove the item from your inventory.")
            }
            .alert("Permission required", isPresented: .init(
                get: { permissionMessage != nil },
                set: { if !$0 { permissionMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    permissionMessage = nil
                }
            } message: {
                Text(permissionMessage ?? "")
            }
            .safeAreaInset(edge: .bottom) {
                QuickCountBarView(
                    onQuickAdd: {
                        if authStore.canManageCatalog {
                            isPresentingQuickAdd = true
                        } else {
                            permissionMessage = "Only owners and managers can add new items."
                            Haptics.tap()
                        }
                    },
                    onSetAmount: { isPresentingSetPicker = true },
                    onNotes: { isPresentingNotePicker = true },
                    isCoachHighlighted: isCoachTargetActive(.quickCountBar)
                )
            }
            .overlay(alignment: coachOverlayAlignment) {
                if let target = activeCoachTarget {
                    coachCallout(for: target)
                        .padding(coachOverlayPadding(for: target))
                        .transition(.move(edge: target == .quickCountBar ? .bottom : .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: activeCoachTarget?.rawValue ?? "none")
        }
    }

    private func handleQuickAction(_ action: QuickAction) {
        switch action {
        case .runShift:
            isPresentingRunShift = true
        case .stockInOut:
            isPresentingQuickAdjust = true
        case .setAmount:
            isPresentingSetPicker = true
        case .addItem:
            guard authStore.canManageCatalog else {
                permissionMessage = "Only owners and managers can add catalog items."
                Haptics.tap()
                return
            }
            guidanceStore.markFlowEngaged(.addItem)
            addPrefillBarcode = nil
            isPresentingAdd = true
        case .quickAdd:
            guard authStore.canManageCatalog else {
                permissionMessage = "Only owners and managers can add catalog items."
                Haptics.tap()
                return
            }
            guidanceStore.markFlowEngaged(.addItem)
            isPresentingQuickAdd = true
        case .starterTemplates:
            isPresentingStarterTemplates = true
        case .dailyOpsBrief:
            isPresentingDailyOpsBrief = true
        case .automationInbox:
            isPresentingAutomationInbox = true
        case .integrationHub:
            isPresentingIntegrationHub = true
        case .trustCenter:
            isPresentingTrustCenter = true
        case .opsIntelligence:
            isPresentingOpsIntelligence = true
        case .kpiDashboard:
            isPresentingKPIDashboard = true
        case .zoneMission:
            guidanceStore.markFlowEngaged(.zoneMission)
            isPresentingZoneMission = true
        case .cyclePlanner:
            isPresentingCyclePlanner = true
        case .guidedHelp:
            guidanceStore.openGuideCenter()
        case .exceptions:
            isPresentingExceptions = true
        case .replenishment:
            guidanceStore.markFlowEngaged(.replenishment)
            isPresentingReplenishment = true
        case .calculations:
            isPresentingCalculations = true
        case .shelfScan:
            isPresentingScan = true
        case .barcodeScan:
            isPresentingBarcodeScan = true
        case .addNote:
            isPresentingNotePicker = true
        case .close:
            break
        }
    }

    private func consumePendingAutomationRoute() {
        guard !hasBlockingPresentation else { return }
        guard let route = automationRouteStore.consumeRoute() else { return }
        handleAutomationRoute(route)
    }

    private func handleAutomationRoute(_ route: AutomationNotificationRoute) {
        switch route.action {
        case .openAutomationInbox:
            refreshAutomationCycle(force: true)
            isPresentingAutomationInbox = true
        case .openZoneMission:
            guidanceStore.markFlowEngaged(.zoneMission)
            isPresentingZoneMission = true
        case .openReplenishment:
            guidanceStore.markFlowEngaged(.replenishment)
            isPresentingReplenishment = true
        case .createAutoDraftPO:
            refreshAutomationCycle(force: true)
            isPresentingAutomationInbox = true
        case .openKPIDashboard:
            isPresentingKPIDashboard = true
        case .openExceptionFeed:
            isPresentingExceptions = true
        case .openDailyOpsBrief:
            isPresentingDailyOpsBrief = true
        case .openGuidedHelp:
            guidanceStore.openGuideCenter()
        case .openIntegrationHub:
            isPresentingIntegrationHub = true
        case .openTrustCenter:
            isPresentingTrustCenter = true
        }
    }

    private func handleGuidedFlowLaunch(_ flow: GuidedFlow) {
        switch flow {
        case .addItem:
            guard authStore.canManageCatalog else {
                permissionMessage = "Only owners and managers can add catalog items."
                Haptics.tap()
                return
            }
            guidanceStore.markFlowEngaged(.addItem)
            addPrefillBarcode = nil
            isPresentingAdd = true
        case .zoneMission:
            guidanceStore.markFlowEngaged(.zoneMission)
            isPresentingZoneMission = true
        case .replenishment:
            guidanceStore.markFlowEngaged(.replenishment)
            isPresentingReplenishment = true
        }
    }

    private func toolbarIcon(_ systemName: String, target: CoachMarkTarget) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(Theme.pillGradient())
            )
            .overlay(
                Circle()
                    .stroke(Theme.strongBorder.opacity(0.45), lineWidth: 0.8)
            )
            .coachHighlight(isCoachTargetActive(target), cornerRadius: 14)
    }

    private var hasBlockingPresentation: Bool {
        isPresentingAdd
            || isPresentingQuickAdd
            || isPresentingScan
            || isPresentingHelp
            || isPresentingQuickActions
            || isPresentingMenu
            || isPresentingQuickAdjust
            || isPresentingBarcodeScan
            || isPresentingStarterTemplates
            || isPresentingRunShift
            || isPresentingDailyOpsBrief
            || isPresentingAutomationInbox
            || isPresentingIntegrationHub
            || isPresentingTrustCenter
            || isPresentingOpsIntelligence
            || isPresentingKPIDashboard
            || isPresentingZoneMission
            || isPresentingCyclePlanner
            || isPresentingExceptions
            || isPresentingReplenishment
            || isPresentingCalculations
            || editingItem != nil
            || editingAmountItem != nil
            || editingNoteItem != nil
            || quickAdjustItem != nil
            || isPresentingSetPicker
            || isPresentingNotePicker
            || guidanceStore.isShowingGuideCenter
    }

    private var activeCoachTarget: CoachMarkTarget? {
        guard !hasBlockingPresentation else { return nil }
        return guidanceStore.activeCoachTarget
    }

    private var activeGuidanceNudge: GuidanceNudge? {
        guard !hasBlockingPresentation else { return nil }
        return guidanceStore.activeNudge
    }

    private var coachOverlayAlignment: Alignment {
        switch activeCoachTarget {
        case .quickAddButton:
            return .topLeading
        case .quickActionsButton, .menuButton:
            return .topTrailing
        case .shiftMode:
            return .top
        case .quickCountBar:
            return .bottom
        case .none:
            return .top
        }
    }

    private func coachOverlayPadding(for target: CoachMarkTarget) -> EdgeInsets {
        switch target {
        case .quickAddButton:
            return EdgeInsets(top: 94, leading: 12, bottom: 0, trailing: 0)
        case .quickActionsButton:
            return EdgeInsets(top: 94, leading: 0, bottom: 0, trailing: 56)
        case .menuButton:
            return EdgeInsets(top: 94, leading: 0, bottom: 0, trailing: 12)
        case .shiftMode:
            return EdgeInsets(top: 170, leading: 14, bottom: 0, trailing: 14)
        case .quickCountBar:
            return EdgeInsets(top: 0, leading: 14, bottom: 122, trailing: 14)
        }
    }

    private func isCoachTargetActive(_ target: CoachMarkTarget) -> Bool {
        activeCoachTarget == target
    }

    private func coachCallout(for target: CoachMarkTarget) -> some View {
        let step = guidanceStore.coachStepIndex + 1
        let total = CoachMarkTarget.allCases.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: target.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(target.title)
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(step)/\(total)")
                    .font(Theme.font(10, weight: .bold))
                    .foregroundStyle(Theme.accentDeep)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Theme.accentSoft.opacity(0.52))
                    )
            }

            Text(target.detail)
                .font(Theme.font(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 10) {
                Button("Skip Tips") {
                    guidanceStore.skipCoachMarks()
                }
                .inventorySecondaryAction()

                Spacer()

                Button(guidanceStore.isLastCoachStep ? "Finish" : "Next") {
                    guidanceStore.advanceCoachMark()
                }
                .inventoryPrimaryAction()
            }
        }
        .padding(12)
        .frame(maxWidth: 300, alignment: .leading)
        .inventoryCard(cornerRadius: 14, emphasis: 0.58)
    }

    private func guidanceNudgeCard(_ nudge: GuidanceNudge) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: nudge.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                Text(nudge.title)
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                if let badge = nudge.badge {
                    Text(badge.uppercased())
                        .font(Theme.font(9, weight: .bold))
                        .foregroundStyle(Theme.accentDeep)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Theme.accentSoft.opacity(0.55))
                        )
                }
            }

            Text(nudge.message)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 10) {
                Button("Dismiss") {
                    guidanceStore.dismissActiveNudge()
                }
                .inventorySecondaryAction()

                Spacer()

                Button(nudge.actionTitle) {
                    handleGuidanceNudgeAction(nudge.action)
                }
                .inventoryPrimaryAction()
            }
        }
        .padding(14)
        .inventoryCard(cornerRadius: 18, emphasis: 0.56)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func handleGuidanceNudgeAction(_ action: GuidanceNudgeAction) {
        guidanceStore.acknowledgeActiveNudgeAction()

        switch action {
        case .openZoneMission:
            guidanceStore.markFlowEngaged(.zoneMission)
            isPresentingZoneMission = true
        case .openReplenishment:
            guidanceStore.markFlowEngaged(.replenishment)
            isPresentingReplenishment = true
        case .openKPIDashboard:
            isPresentingKPIDashboard = true
        case .openGuidedHelp:
            guidanceStore.openGuideCenter()
        }
    }

    private func refreshGuidanceNudges() {
        guidanceStore.refreshNudge(using: guidanceSignals)
    }

    private var guidanceSignals: GuidanceSignals {
        let staleCutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let staleItemCount = workspaceItems.filter { item in
            item.safeUpdatedAt < staleCutoff
        }.count
        let missingLocationCount = workspaceItems.filter { item in
            item.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count

        var stockoutRiskCount = 0
        var urgentReplenishmentCount = 0
        var coverageReadyCount = 0
        var missingDemandInputCount = 0

        for item in workspaceItems {
            let forecast = max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0)
            let leadTimeDays = max(0, Double(item.leadTimeDays))
            let onHandUnits = Double(max(0, Int64(item.totalUnitsOnHand)))

            guard forecast > 0, leadTimeDays > 0 else {
                missingDemandInputCount += 1
                continue
            }

            coverageReadyCount += 1
            let daysOfCover = onHandUnits / forecast
            let riskThreshold = max(1, leadTimeDays)
            if onHandUnits == 0 || daysOfCover <= riskThreshold {
                stockoutRiskCount += 1
            }

            let urgentThreshold = max(1, leadTimeDays * 0.5)
            if onHandUnits == 0 || daysOfCover <= urgentThreshold {
                urgentReplenishmentCount += 1
            }
        }

        return GuidanceSignals(
            isAuthenticated: authStore.isAuthenticated,
            role: authStore.currentRole,
            itemCount: workspaceItems.count,
            staleItemCount: staleItemCount,
            missingLocationCount: missingLocationCount,
            stockoutRiskCount: stockoutRiskCount,
            urgentReplenishmentCount: urgentReplenishmentCount,
            coverageReadyCount: coverageReadyCount,
            missingDemandInputCount: missingDemandInputCount
        )
    }

    private var automationSignals: AutomationSignals {
        let staleCutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let staleItems = workspaceItems.filter { item in
            item.safeUpdatedAt < staleCutoff
        }
        let staleItemCount = staleItems.count
        var staleZoneBuckets: [String: (label: String, count: Int)] = [:]
        for item in staleItems {
            let trimmedLocation = item.location.trimmingCharacters(in: .whitespacesAndNewlines)
            let zoneKey: String
            let zoneLabel: String
            if trimmedLocation.isEmpty {
                zoneKey = AutomationStore.unassignedZoneKey
                zoneLabel = "No Location"
            } else {
                zoneKey = trimmedLocation.lowercased()
                zoneLabel = trimmedLocation
            }
            var existing = staleZoneBuckets[zoneKey] ?? (label: zoneLabel, count: 0)
            existing.count += 1
            staleZoneBuckets[zoneKey] = existing
        }
        let staleZoneAssignments = staleZoneBuckets.map { key, bucket in
            AutomationZoneAssignment(
                zoneKey: key,
                zoneLabel: bucket.label,
                staleItemCount: bucket.count
            )
        }.sorted { lhs, rhs in
            if lhs.staleItemCount != rhs.staleItemCount {
                return lhs.staleItemCount > rhs.staleItemCount
            }
            return lhs.zoneLabel.localizedCaseInsensitiveCompare(rhs.zoneLabel) == .orderedAscending
        }
        let missingLocationCount = workspaceItems.filter { item in
            item.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        let missingBarcodeCount = workspaceItems.filter { item in
            item.barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count

        var stockoutRiskCount = 0
        var urgentReplenishmentCount = 0
        var autoDraftCandidateCount = 0
        var autoDraftSuggestedUnits: Int64 = 0
        var missingDemandInputCount = 0
        let reconnectBrief = platformStore.inventoryReconnectBrief(workspaceID: authStore.activeWorkspaceID)
        let countSummary = platformStore.countProductivitySummary(
            workspaceID: authStore.activeWorkspaceID,
            windowDays: 14
        )
        let confidenceOverview = platformStore.inventoryConfidenceOverview(
            for: workspaceItems,
            workspaceID: authStore.activeWorkspaceID,
            weakestLimit: workspaceItems.count
        )
        let lowConfidenceItemCount = confidenceOverview.criticalCount + confidenceOverview.weakCount

        for item in workspaceItems {
            let forecast = max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0)
            let leadTimeDays = max(0, Double(item.leadTimeDays))
            let onHand = max(0, Int64(item.totalUnitsOnHand))
            let onHandUnits = Double(onHand)
            let safetyStock = max(0, item.safetyStockUnits)

            guard forecast > 0, leadTimeDays > 0 else {
                missingDemandInputCount += 1
                continue
            }

            let daysOfCover = onHandUnits / forecast
            let riskThreshold = max(1, leadTimeDays)
            if onHandUnits == 0 || daysOfCover <= riskThreshold {
                stockoutRiskCount += 1
            }

            let urgentThreshold = max(1, leadTimeDays * 0.5)
            if onHandUnits == 0 || daysOfCover <= urgentThreshold {
                urgentReplenishmentCount += 1
            }

            let reorderPoint = Int64((forecast * leadTimeDays).rounded(.up)) + safetyStock
            let baseSuggestedUnits = max(0, reorderPoint - onHand)
            let suggestedUnits = item.adjustedSuggestedOrderUnits(from: baseSuggestedUnits)
            if suggestedUnits > 0 && (onHandUnits == 0 || daysOfCover <= max(1, leadTimeDays)) {
                autoDraftCandidateCount += 1
                autoDraftSuggestedUnits += suggestedUnits
            }
        }

        return AutomationSignals(
            role: authStore.currentRole,
            itemCount: workspaceItems.count,
            staleItemCount: staleItemCount,
            staleZoneAssignments: staleZoneAssignments,
            stockoutRiskCount: stockoutRiskCount,
            urgentReplenishmentCount: urgentReplenishmentCount,
            autoDraftCandidateCount: autoDraftCandidateCount,
            autoDraftSuggestedUnits: autoDraftSuggestedUnits,
            missingLocationCount: missingLocationCount,
            missingDemandInputCount: missingDemandInputCount,
            missingBarcodeCount: missingBarcodeCount,
            pendingLedgerEventCount: reconnectBrief.pendingCount,
            failedLedgerEventCount: reconnectBrief.failedCount,
            lowConfidenceItemCount: lowConfidenceItemCount,
            countTargetTrackedSessions: countSummary.targetTrackedSessions,
            countTargetHitRate: countSummary.targetHitRate
        )
    }

    private func refreshAutomationCycle(force: Bool = false) {
        automationStore.runAutomationCycle(
            using: automationSignals,
            workspaceID: authStore.activeWorkspaceID,
            force: force
        )
    }

    private func handleBarcodeScan(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalizedScan = normalizedBarcode(trimmed)
        if let match = workspaceItems.first(where: {
            let itemBarcode = normalizedBarcode($0.barcode)
            return !itemBarcode.isEmpty && itemBarcode == normalizedScan
        }) {
            applyStockIn(to: match, units: 1, source: "barcode-scan")
        } else {
            guard authStore.canManageCatalog else {
                permissionMessage = "Barcode not found. Only owners and managers can create new items."
                Haptics.tap()
                return
            }
            addPrefillBarcode = trimmed
            isPresentingAdd = true
        }
    }

    private func applyStockIn(to item: InventoryItemEntity, units: Int64, source: String = "stock-in") {
        guard units > 0 else { return }
        let previousUnits = item.totalUnitsOnHand
        if item.isLiquid {
            item.applyTotalGallons(item.totalGallonsOnHand + Double(units))
        } else {
            item.applyTotalNonLiquidUnits(item.totalUnitsOnHand + units)
        }
        item.assignWorkspaceIfNeeded(authStore.activeWorkspaceID)
        item.updatedAt = Date()
        dataController.save()
        let deltaUnits = item.totalUnitsOnHand - previousUnits
        platformStore.recordInventoryMovement(
            item: item,
            deltaUnits: deltaUnits,
            actorName: authStore.displayName,
            workspaceID: authStore.activeWorkspaceID,
            type: .adjustment,
            source: source,
            reason: "Stock in"
        )
        Haptics.success()
    }

    private var filteredItems: [InventoryItemEntity] {
        let base = workspaceItems.filter { item in
            matchesSearch(item) && matchesCategory(item)
        }
        return sortItems(base)
    }

    private var workspaceItems: [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(authStore.activeWorkspaceID) }
    }

    private var startWorkSnapshot: StartWorkSnapshot {
        let staleCutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        var criticalRestockCount = 0
        var staleCountCount = 0
        var missingPlanningDataCount = 0

        for item in workspaceItems {
            let demand = max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0)
            let leadTimeDays = max(0, Double(item.leadTimeDays))
            let onHandUnits = Double(max(0, Int64(item.totalUnitsOnHand)))

            if demand > 0, leadTimeDays > 0 {
                let daysOfCover = onHandUnits / demand
                let criticalThreshold = max(1, leadTimeDays * 0.5)
                if onHandUnits == 0 || daysOfCover <= criticalThreshold {
                    criticalRestockCount += 1
                }
            } else {
                missingPlanningDataCount += 1
            }

            if item.safeUpdatedAt < staleCutoff {
                staleCountCount += 1
            }
        }

        let totalExceptionCount = criticalRestockCount + staleCountCount + missingPlanningDataCount

        if criticalRestockCount > 0 {
            return StartWorkSnapshot(
                totalExceptionCount: totalExceptionCount,
                criticalRestockCount: criticalRestockCount,
                staleCountCount: staleCountCount,
                missingPlanningDataCount: missingPlanningDataCount,
                recommendedAction: .exceptions,
                recommendedTitle: "Resolve Critical Exceptions",
                recommendedReason: "\(criticalRestockCount) SKU(s) can stock out before the next delivery window.",
                recommendedSystemImage: "exclamationmark.triangle.fill",
                urgencyBadge: "CRITICAL"
            )
        }

        if staleCountCount >= 3 {
            return StartWorkSnapshot(
                totalExceptionCount: totalExceptionCount,
                criticalRestockCount: criticalRestockCount,
                staleCountCount: staleCountCount,
                missingPlanningDataCount: missingPlanningDataCount,
                recommendedAction: .zoneMission,
                recommendedTitle: "Run Zone Mission Count",
                recommendedReason: "\(staleCountCount) item(s) are stale and need fresh counts today.",
                recommendedSystemImage: "map.fill",
                urgencyBadge: "HIGH"
            )
        }

        if missingPlanningDataCount > 0 {
            return StartWorkSnapshot(
                totalExceptionCount: totalExceptionCount,
                criticalRestockCount: criticalRestockCount,
                staleCountCount: staleCountCount,
                missingPlanningDataCount: missingPlanningDataCount,
                recommendedAction: .exceptions,
                recommendedTitle: "Fix Planning Data",
                recommendedReason: "\(missingPlanningDataCount) item(s) are missing demand or lead-time inputs.",
                recommendedSystemImage: "questionmark.circle.fill",
                urgencyBadge: "HIGH"
            )
        }

        return StartWorkSnapshot(
            totalExceptionCount: totalExceptionCount,
            criticalRestockCount: criticalRestockCount,
            staleCountCount: staleCountCount,
            missingPlanningDataCount: missingPlanningDataCount,
            recommendedAction: .dailyOpsBrief,
            recommendedTitle: "Start With Daily Ops Brief",
            recommendedReason: "No critical blockers right now. Run today’s task queue in one pass.",
            recommendedSystemImage: "checklist.checked",
            urgencyBadge: "READY"
        )
    }

    private var categoryOptions: [String] {
        var options = ["All"]
        let categories = Set(workspaceItems.map { normalizedCategoryName($0.category) })
            .filter { !$0.isEmpty && $0 != "Uncategorized" }
            .sorted()
        let hasUncategorized = workspaceItems.contains { normalizedCategoryName($0.category) == "Uncategorized" }
        if hasUncategorized {
            options.append("Uncategorized")
        }
        options.append(contentsOf: categories)
        return options
    }

    private var emptyStateView: some View {
        let title = workspaceItems.isEmpty ? "No Items" : "No Matches"
        let subtitle = workspaceItems.isEmpty
            ? "Add your first item to start tracking inventory."
            : "Try adjusting your search or category filter."
        return VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.glow)
                    .frame(width: 140, height: 140)
                Image(systemName: "shippingbox.and.arrow.backward")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            Text(title)
                .font(Theme.titleFont())
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(Theme.font(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if workspaceItems.isEmpty {
                VStack(spacing: 10) {
                    Button {
                        if authStore.canManageCatalog {
                            isPresentingStarterTemplates = true
                        } else {
                            permissionMessage = "Only owners and managers can add starter templates."
                            Haptics.tap()
                        }
                    } label: {
                        Label("Use starter template", systemImage: "wand.and.sparkles")
                    }
                    .inventoryPrimaryAction()
                    .disabled(!authStore.canManageCatalog)
                    .opacity(authStore.canManageCatalog ? 1 : 0.55)

                    Button {
                        if authStore.canManageCatalog {
                            isPresentingAdd = true
                        } else {
                            permissionMessage = "Only owners and managers can add new items."
                            Haptics.tap()
                        }
                    } label: {
                        Label("Add your first item", systemImage: "plus.circle.fill")
                    }
                    .inventorySecondaryAction()
                    .disabled(!authStore.canManageCatalog)
                    .opacity(authStore.canManageCatalog ? 1 : 0.55)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            StartWorkLaunchpadView(
                snapshot: startWorkSnapshot,
                onAction: { action in
                    handleQuickAction(action)
                },
                onGuidedHelp: {
                    guidanceStore.openGuideCenter()
                }
            )
            .inventoryStaggered(index: 0, baseDelay: 0.04, initialYOffset: 14)
            InspiredBannerView(
                workspaceName: authStore.activeWorkspaceName,
                roleTitle: authStore.currentRole.title
            )
            .inventoryStaggered(index: 1, baseDelay: 0.04, initialYOffset: 14)
            ShiftModePickerView(selection: $shiftMode)
                .coachHighlight(isCoachTargetActive(.shiftMode))
                .inventoryStaggered(index: 2, baseDelay: 0.04, initialYOffset: 14)
            TodayHeaderView(
                itemCount: workspaceItems.count,
                totalCases: totalCases,
                totalUnits: totalUnits,
                totalEaches: totalEaches,
                totalGallons: totalGallons
            )
            .inventoryStaggered(index: 3, baseDelay: 0.04, initialYOffset: 14)
            if !categorySummaries.isEmpty {
                CategoryShelfView(summaries: categorySummaries)
                    .inventoryStaggered(index: 4, baseDelay: 0.04, initialYOffset: 14)
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func delete(_ offsets: IndexSet, from items: [InventoryItemEntity]) {
        guard authStore.canDeleteItems else {
            permissionMessage = "Only workspace owners can delete items."
            Haptics.tap()
            return
        }
        let targets = offsets.map { items[$0] }
        targets.forEach(context.delete)
        dataController.save()
    }

    private func adjustQuantity(for item: InventoryItemEntity, delta: Int64) {
        let previousUnits = item.totalUnitsOnHand
        if item.isLiquid {
            item.applyTotalGallons(item.totalGallonsOnHand + Double(delta))
        } else {
            item.applyTotalNonLiquidUnits(item.totalUnitsOnHand + delta)
        }
        item.assignWorkspaceIfNeeded(authStore.activeWorkspaceID)
        item.updatedAt = Date()
        dataController.save()
        let deltaUnits = item.totalUnitsOnHand - previousUnits
        platformStore.recordInventoryMovement(
            item: item,
            deltaUnits: deltaUnits,
            actorName: authStore.displayName,
            workspaceID: authStore.activeWorkspaceID,
            type: .adjustment,
            source: "item-row-stepper",
            reason: delta >= 0 ? "Manual increment" : "Manual decrement"
        )
        Haptics.tap()
    }

    private func matchesSearch(_ item: InventoryItemEntity) -> Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let query = trimmed.lowercased()
        return item.name.lowercased().contains(query)
            || item.notes.lowercased().contains(query)
            || item.category.lowercased().contains(query)
            || item.location.lowercased().contains(query)
            || item.barcode.lowercased().contains(query)
    }

    private func matchesCategory(_ item: InventoryItemEntity) -> Bool {
        guard selectedCategory != "All" else { return true }
        let normalized = normalizedCategoryName(item.category)
        return normalized == selectedCategory
    }

    private func normalizedCategoryName(_ category: String) -> String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Uncategorized" : trimmed
    }

    private func normalizedBarcode(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private func sortItems(_ items: [InventoryItemEntity]) -> [InventoryItemEntity] {
        switch shiftMode {
        case .open:
            return items.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .mid:
            return items.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                return $0.safeUpdatedAt > $1.safeUpdatedAt
            }
        case .close:
            return items.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                let lhsUnits = totalUnitsValue($0)
                let rhsUnits = totalUnitsValue($1)
                if lhsUnits != rhsUnits { return lhsUnits < rhsUnits }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private var totalCases: Int {
        filteredItems.reduce(0) { total, item in
            guard !item.isLiquid, item.unitsPerCase > 0 else { return total }
            return total + Int(item.quantity)
        }
    }

    private var totalEaches: Int {
        filteredItems.reduce(0) { total, item in
            if item.isLiquid {
                return total + Int((gallonsTotal(item) * 128).rounded())
            }
            guard item.eachesPerUnit > 0 else { return total }
            return total + Int(Int64(totalUnitsValue(item)) * item.eachesPerUnit + item.looseEaches)
        }
    }

    private var totalUnits: Int {
        filteredItems.reduce(0) { total, item in
            return total + totalUnitsValue(item)
        }
    }

    private var totalGallons: Double {
        filteredItems.reduce(0) { total, item in
            guard item.isLiquid else { return total }
            return total + gallonsTotal(item)
        }
    }

    private var categorySummaries: [CategorySummary] {
        let grouped = Dictionary(grouping: filteredItems) { normalizedCategoryName($0.category) }
        return grouped
            .map { key, value in
                let cases = value.reduce(0) { total, item in
                    guard !item.isLiquid, item.unitsPerCase > 0 else { return total }
                    return total + Int(item.quantity)
                }
                let units = value.reduce(0) { total, item in
                    return total + totalUnitsValue(item)
                }
                let eaches = value.reduce(0) { total, item in
                    if item.isLiquid {
                        return total + Int((gallonsTotal(item) * 128).rounded())
                    }
                    guard item.eachesPerUnit > 0 else { return total }
                    return total + Int(Int64(totalUnitsValue(item)) * item.eachesPerUnit + item.looseEaches)
                }
                let gallons = value.reduce(0.0) { total, item in
                    guard item.isLiquid else { return total }
                    return total + gallonsTotal(item)
                }
                return CategorySummary(
                    name: key,
                    itemCount: value.count,
                    cases: cases,
                    units: units,
                    eaches: eaches,
                    gallons: gallons
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func scopeLegacyItemsToActiveWorkspaceIfNeeded() {
        guard let activeWorkspaceID = authStore.activeWorkspaceID else { return }
        var hasChanges = false
        for item in items where item.workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.workspaceID = activeWorkspaceID.uuidString
            hasChanges = true
        }
        if hasChanges {
            dataController.save()
        }
    }

}

private struct CategorySummary: Identifiable {
    let id = UUID()
    let name: String
    let itemCount: Int
    let cases: Int
    let units: Int
    let eaches: Int
    let gallons: Double
}

private struct TodayHeaderView: View {
    let itemCount: Int
    let totalCases: Int
    let totalUnits: Int
    let totalEaches: Int
    let totalGallons: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today Overview")
                        .font(Theme.titleFont())
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(itemCount) items tracked")
                        .font(Theme.font(13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(Theme.pillGradient())
                    )
                    .overlay(
                        Circle()
                            .stroke(Theme.strongBorder.opacity(0.5), lineWidth: 0.8)
                    )
            }

            HStack(spacing: 16) {
                StatPill(title: "Cases", value: "\(totalCases)")
                StatPill(title: "Units", value: "\(totalUnits)")
                StatPill(title: "Each", value: "\(totalEaches)")
                if totalGallons > 0 {
                    StatPill(title: "Gallons", value: formattedGallons(totalGallons))
                }
            }
        }
        .padding(16)
        .inventoryCard(cornerRadius: 22, emphasis: 0.72)
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(Theme.font(11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.font(20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.pillGradient())
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.strongBorder.opacity(0.45), lineWidth: 0.8)
        )
    }
}

private struct CategoryShelfView: View {
    let summaries: [CategorySummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shelves")
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(summaries) { summary in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(summary.name)
                                .font(Theme.font(14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("\(summary.itemCount) items")
                                .font(Theme.font(12))
                                .foregroundStyle(Theme.textSecondary)
                            Text("\(summary.cases) cases")
                                .font(Theme.font(12))
                                .foregroundStyle(Theme.textSecondary)
                            if summary.units > 0 {
                                Text("\(summary.units) units")
                                    .font(Theme.font(12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if summary.eaches > 0 {
                                Text("\(summary.eaches) each")
                                    .font(Theme.font(12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if summary.gallons > 0 {
                                Text("\(formattedGallons(summary.gallons)) gallons")
                                    .font(Theme.font(12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .padding(12)
                        .frame(width: 140, alignment: .leading)
                        .inventoryCard(cornerRadius: 16, emphasis: 0.2)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
    }

}

private struct StartWorkLaunchpadView: View {
    let snapshot: StartWorkSnapshot
    let onAction: (QuickAction) -> Void
    let onGuidedHelp: () -> Void

    private let columns = [
        GridItem(.flexible(minimum: 110), spacing: 10),
        GridItem(.flexible(minimum: 110), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text("Start Work")
                    .font(Theme.titleFont())
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(snapshot.urgencyBadge)
                    .font(Theme.font(10, weight: .bold))
                    .foregroundStyle(Theme.accentDeep)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Theme.accentSoft.opacity(0.6))
                    )
            }

            HStack(spacing: 10) {
                launchMetric(title: "Exceptions", value: "\(snapshot.totalExceptionCount)")
                launchMetric(title: "Critical", value: "\(snapshot.criticalRestockCount)")
                launchMetric(title: "Stale", value: "\(snapshot.staleCountCount)")
                launchMetric(title: "Data", value: "\(snapshot.missingPlanningDataCount)")
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(snapshot.recommendedTitle, systemImage: snapshot.recommendedSystemImage)
                    .font(Theme.font(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(snapshot.recommendedReason)
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    onAction(snapshot.recommendedAction)
                } label: {
                    Label("Run Recommended Action", systemImage: "arrow.forward.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .inventoryPrimaryAction()
            }
            .padding(12)
            .inventoryCard(cornerRadius: 14, emphasis: 0.44)

            LazyVGrid(columns: columns, spacing: 10) {
                launchButton(
                    title: "Count Now",
                    icon: "map.fill",
                    action: .zoneMission
                )
                launchButton(
                    title: "Fix Exceptions",
                    icon: "exclamationmark.bubble",
                    action: .exceptions
                )
                launchButton(
                    title: "Replenish",
                    icon: "chart.line.uptrend.xyaxis",
                    action: .replenishment
                )
                launchButton(
                    title: "Daily Brief",
                    icon: "checklist.checked",
                    action: .dailyOpsBrief
                )
            }

            HStack(spacing: 8) {
                Text("Need help getting started?")
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Button("Open Guided Help") {
                    onGuidedHelp()
                }
                .font(Theme.font(11, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accentDeep)
            }
        }
        .padding(16)
        .inventoryCard(cornerRadius: 20, emphasis: 0.68)
    }

    private func launchMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.font(10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.font(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.pillGradient())
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.strongBorder.opacity(0.32), lineWidth: 0.8)
        )
    }

    private func launchButton(title: String, icon: String, action: QuickAction) -> some View {
        Button {
            onAction(action)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .lineLimit(1)
            }
            .font(Theme.font(12, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .inventorySecondaryAction()
    }
}

private struct InspiredBannerView: View {
    let workspaceName: String
    let roleTitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.pillGradient())
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .stroke(Theme.strongBorder.opacity(0.44), lineWidth: 0.8)
                    )
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(workspaceName)
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Signed in as \(roleTitle)")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Text("LIVE")
                .font(Theme.font(10, weight: .bold))
                .foregroundStyle(Theme.accentDeep)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Theme.accentSoft.opacity(0.55))
                )
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .inventoryCard(cornerRadius: 16, emphasis: 0.56)
    }
}

private struct ItemRowView: View {
    let item: InventoryItemEntity
    let canEditDetails: Bool
    let canDeleteItem: Bool
    let onEdit: () -> Void
    let onStockChange: (Int64) -> Void
    let onEditAmount: () -> Void
    let onRequestDelete: () -> Void

    var body: some View {
        let hasEaches = item.eachesPerUnit > 0
        let unitsTotal = totalUnitsValue(item)
        let totalEaches = item.isLiquid
            ? Int((gallonsTotal(item) * 128).rounded())
            : (hasEaches ? unitsTotal * Int(item.eachesPerUnit) + Int(item.looseEaches) : 0)
        let gallonsTotal = item.isLiquid ? gallonsTotal(item) : 0
        let emphasis = item.isPinned ? 0.7 : 0.26

        VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(Theme.font(18, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if item.isPinned {
                            Label("Pinned", systemImage: "pin.fill")
                                .font(Theme.font(10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Theme.accentSoft.opacity(0.58))
                                )
                                .foregroundStyle(Theme.accentDeep)
                        }
                    }
                    HStack(spacing: 8) {
                        if !item.category.isEmpty {
                            Label(item.category, systemImage: "tag")
                                .font(Theme.font(12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        if !item.location.isEmpty {
                            Label(item.location, systemImage: "mappin.and.ellipse")
                                .font(Theme.font(12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    if !item.notes.isEmpty {
                        Text(item.notes)
                            .font(Theme.font(13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if item.isLiquid {
                        Text("Total Units \(totalUnitsValue(item))")
                            .font(Theme.font(13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Text("\(formattedGallons(gallonsTotal)) gallons")
                            .font(Theme.font(12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    } else if item.unitsPerCase > 0 {
                        let casesText = item.quantity == 1 ? "1 case" : "\(item.quantity) cases"
                        let unitsText = item.looseUnits == 1 ? "1 unit" : "\(item.looseUnits) units"
                        let eachesText = "\(item.looseEaches) each"
                        let parts = [
                            casesText,
                            item.looseUnits > 0 ? unitsText : nil,
                            item.looseEaches > 0 ? eachesText : nil
                        ].compactMap { $0 }
                        Text(parts.joined(separator: " + "))
                            .font(Theme.font(13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        if hasEaches {
                            Text("\(totalEaches) total each")
                                .font(Theme.font(12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else {
                        Text("Qty \(unitsTotal)")
                            .font(Theme.font(13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        if hasEaches {
                            Text("\(totalEaches) total each")
                                .font(Theme.font(12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Text(item.safeUpdatedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            if let recommendation = reorderRecommendation {
                Label(
                    reorderStatusText(recommendation),
                    systemImage: recommendation.suggestedUnits > 0
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.seal"
                )
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(recommendation.suggestedUnits > 0 ? Color.orange : Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(
                            recommendation.suggestedUnits > 0
                                ? Color.orange.opacity(0.16)
                                : Theme.accentSoft.opacity(0.2)
                        )
                )
            }
            HStack(spacing: 12) {
                Button {
                    onStockChange(-1)
                } label: {
                    Label("Stock Out", systemImage: "minus.circle")
                }
                .inventorySecondaryAction()

                Button {
                    onStockChange(1)
                } label: {
                    Label("Stock In", systemImage: "plus.circle")
                }
                .inventoryPrimaryAction()

                Button {
                    onEditAmount()
                } label: {
                    Label("Set", systemImage: "pencil")
                }
                .inventorySecondaryAction()
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .inventoryCard(cornerRadius: 18, emphasis: emphasis)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canEditDetails else { return }
            onEdit()
        }
        .onLongPressGesture {
            guard canDeleteItem else { return }
            Haptics.tap()
            onRequestDelete()
        }
    }

    private var onHandUnits: Int64 {
        Int64(totalUnitsValue(item))
    }

    private var reorderRecommendation: (reorderPoint: Int64, suggestedUnits: Int64)? {
        guard item.averageDailyUsage > 0, item.leadTimeDays > 0 else { return nil }
        let demandDuringLead = Int64((item.averageDailyUsage * Double(item.leadTimeDays)).rounded(.up))
        let reorderPoint = max(0, demandDuringLead + item.safetyStockUnits)
        let suggestedUnits = max(0, reorderPoint - onHandUnits)
        return (reorderPoint, suggestedUnits)
    }

    private func reorderStatusText(_ recommendation: (reorderPoint: Int64, suggestedUnits: Int64)) -> String {
        let reorderPointText = unitText(recommendation.reorderPoint)
        if recommendation.suggestedUnits > 0 {
            return "Reorder \(unitText(recommendation.suggestedUnits)) (target \(reorderPointText))"
        }
        return "On track (target \(reorderPointText))"
    }

    private func unitText(_ value: Int64) -> String {
        value == 1 ? "1 unit" : "\(value) units"
    }
}
