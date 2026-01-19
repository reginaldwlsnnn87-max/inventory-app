import SwiftUI
import CoreData
import Foundation

private func gallonsTotal(_ item: InventoryItemEntity) -> Double {
    if item.isLiquid {
        return Double(item.looseUnits) + item.gallonFraction
    }
    let unitsTotal = Double(item.quantity * item.unitsPerCase + item.looseUnits)
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

private struct QuickCountBarView: View {
    let onQuickAdd: () -> Void
    let onSetAmount: () -> Void
    let onNotes: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onQuickAdd) {
                Label("Quick Add", systemImage: "bolt.fill")
            }
            .buttonStyle(.bordered)

            Button(action: onSetAmount) {
                Label("Set Amount", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)

            Button(action: onNotes) {
                Label("Notes", systemImage: "note.text")
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
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
    if item.isLiquid {
        return Int((gallonsTotal(item) * 128).rounded())
    }
    return Int(item.quantity * item.unitsPerCase + item.looseUnits)
}

struct ItemsListView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var dataController: InventoryDataController
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.updatedAt, ascending: false)],
        animation: .default
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
    @State private var pendingQuickAction: QuickAction?
    @State private var addPrefillBarcode: String?
    @State private var editingItem: InventoryItemEntity?
    @State private var deleteCandidate: InventoryItemEntity?
    @State private var editingAmountItem: InventoryItemEntity?
    @State private var editingNoteItem: InventoryItemEntity?
    @State private var quickAdjustItem: InventoryItemEntity?
    @State private var isPresentingSetPicker = false
    @State private var isPresentingNotePicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                List {
                    headerSection
                    if filteredItems.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            ItemRowView(
                                item: item,
                                onEdit: { editingItem = item },
                                onStockChange: { delta in adjustQuantity(for: item, delta: delta) },
                                onEditAmount: { editingAmountItem = item },
                                onRequestDelete: { deleteCandidate = item }
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
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.85).delay(Double(index) * 0.02),
                                value: filteredItems.count
                            )
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
                        Image(systemName: "bolt.fill")
                    }
                    .accessibilityLabel("Quick Add")
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
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Quick Actions")
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
                        Image(systemName: "line.3.horizontal")
                    }
                    .accessibilityLabel("Menu")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addPrefillBarcode = nil
                        isPresentingAdd = true
                    } label: { Image(systemName: "plus") }
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
            .sheet(isPresented: $isPresentingQuickActions) {
                QuickActionsView { action in
                    pendingQuickAction = action
                    isPresentingQuickActions = false
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
            .safeAreaInset(edge: .bottom) {
                QuickCountBarView(
                    onQuickAdd: { isPresentingQuickAdd = true },
                    onSetAmount: { isPresentingSetPicker = true },
                    onNotes: { isPresentingNotePicker = true }
                )
            }
        }
    }

    private func handleQuickAction(_ action: QuickAction) {
        switch action {
        case .stockInOut:
            isPresentingQuickAdjust = true
        case .setAmount:
            isPresentingSetPicker = true
        case .addItem:
            addPrefillBarcode = nil
            isPresentingAdd = true
        case .quickAdd:
            isPresentingQuickAdd = true
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

    private func handleBarcodeScan(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let match = items.first(where: { $0.barcode == trimmed }) {
            applyStockIn(to: match, units: 1)
        } else {
            addPrefillBarcode = trimmed
            isPresentingAdd = true
        }
    }

    private func applyStockIn(to item: InventoryItemEntity, units: Int64) {
        guard units > 0 else { return }
        if item.isLiquid {
            let currentGallons = Double(item.looseUnits) + item.gallonFraction
            let updated = currentGallons + Double(units)
            let whole = floor(updated)
            let fraction = updated - whole
            item.looseUnits = Int64(whole)
            item.gallonFraction = fraction
        } else if item.unitsPerCase > 0 {
            let totalUnits = item.quantity * item.unitsPerCase + item.looseUnits + units
            item.quantity = totalUnits / item.unitsPerCase
            item.looseUnits = totalUnits % item.unitsPerCase
        } else {
            item.quantity += units
        }
        item.updatedAt = Date()
        dataController.save()
        Haptics.success()
    }

    private var filteredItems: [InventoryItemEntity] {
        let base = items.filter { item in
            matchesSearch(item) && matchesCategory(item)
        }
        return sortItems(base)
    }

    private var categoryOptions: [String] {
        var options = ["All"]
        let categories = Set(items.map { normalizedCategoryName($0.category) })
            .filter { !$0.isEmpty && $0 != "Uncategorized" }
            .sorted()
        let hasUncategorized = items.contains { normalizedCategoryName($0.category) == "Uncategorized" }
        if hasUncategorized {
            options.append("Uncategorized")
        }
        options.append(contentsOf: categories)
        return options
    }

    private var emptyStateView: some View {
        let title = items.isEmpty ? "No Items" : "No Matches"
        let subtitle = items.isEmpty
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
            if items.isEmpty {
                Button {
                    isPresentingAdd = true
                } label: {
                    Label("Add your first item", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            InspiredBannerView()
            ShiftModePickerView(selection: $shiftMode)
            TodayHeaderView(
                itemCount: items.count,
                totalCases: totalCases,
                totalUnits: totalUnits,
                totalEaches: totalEaches,
                totalGallons: totalGallons
            )
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func delete(_ offsets: IndexSet, from items: [InventoryItemEntity]) {
        let targets = offsets.map { items[$0] }
        targets.forEach(context.delete)
        dataController.save()
    }

    private func adjustQuantity(for item: InventoryItemEntity, delta: Int64) {
        let newValue = max(0, item.quantity + delta)
        item.quantity = newValue
        item.updatedAt = Date()
        dataController.save()
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
                return $0.updatedAt > $1.updatedAt
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
        filteredItems.reduce(0) { $0 + Int($1.quantity) }
    }

    private var totalEaches: Int {
        filteredItems.reduce(0) { total, item in
            if item.isLiquid {
                return total + Int((gallonsTotal(item) * 128).rounded())
            }
            guard item.unitsPerCase > 0, item.eachesPerUnit > 0 else { return total }
            let unitsTotal = item.quantity * item.unitsPerCase + item.looseUnits
            return total + Int(unitsTotal * item.eachesPerUnit + item.looseEaches)
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
                let cases = value.reduce(0) { $0 + Int($1.quantity) }
                let units = value.reduce(0) { total, item in
                    return total + totalUnitsValue(item)
                }
                let eaches = value.reduce(0) { total, item in
                    if item.isLiquid {
                        return total + Int((gallonsTotal(item) * 128).rounded())
                    }
                    guard item.unitsPerCase > 0, item.eachesPerUnit > 0 else { return total }
                    let unitsTotal = item.quantity * item.unitsPerCase + item.looseUnits
                    return total + Int(unitsTotal * item.eachesPerUnit + item.looseEaches)
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
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today")
                        .font(Theme.titleFont())
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(itemCount) items tracked")
                        .font(Theme.font(13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
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
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
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
                .fill(Theme.backgroundTop)
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
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Theme.cardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Theme.subtleBorder, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
    }

}

private struct InspiredBannerView: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Inspired by Racetrac")
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Manager tools, built for managers")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }
}

private struct ItemRowView: View {
    let item: InventoryItemEntity
    let onEdit: () -> Void
    let onStockChange: (Int64) -> Void
    let onEditAmount: () -> Void
    let onRequestDelete: () -> Void

    var body: some View {
        let hasEaches = item.eachesPerUnit > 0 && item.unitsPerCase > 0
        let unitsTotal = Int(item.quantity * item.unitsPerCase + item.looseUnits)
        let totalEaches = item.isLiquid
            ? Int((gallonsTotal(item) * 128).rounded())
            : (hasEaches ? unitsTotal * Int(item.eachesPerUnit) + Int(item.looseEaches) : 0)
        let gallonsTotal = item.isLiquid ? gallonsTotal(item) : 0

        VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(Theme.font(18, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
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
                        Text("Qty \(item.quantity)")
                            .font(Theme.font(13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(item.updatedAt.formatted(date: .abbreviated, time: .omitted))
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
            }
            HStack(spacing: 12) {
                Button {
                    onStockChange(-1)
                } label: {
                    Label("Stock Out", systemImage: "minus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onStockChange(1)
                } label: {
                    Label("Stock In", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    onEditAmount()
                } label: {
                    Label("Set", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .onLongPressGesture {
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
