import SwiftUI
import CoreData
import Foundation

struct ItemFormView: View {
    enum Mode: Identifiable {
        case add(barcode: String?)
        case edit(InventoryItemEntity)

        var id: String {
            switch self {
            case .add(let barcode):
                return "add-\(barcode ?? "none")"
            case .edit(let item):
                return item.id.uuidString
            }
        }
    }

    let mode: Mode

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var dataController: InventoryDataController
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var guidanceStore: GuidanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var quantity: Int
    @State private var notes: String
    @State private var category: String
    @State private var location: String
    @State private var unitsPerCase: Int
    @State private var units: Int
    @State private var eachesPerUnit: Int
    @State private var eaches: Int
    @State private var isLiquid: Bool
    @State private var gallonFractionText: String
    @State private var isPinned: Bool
    @State private var barcode: String
    @State private var averageDailyUsage: Double
    @State private var leadTimeDays: Int
    @State private var safetyStockUnits: Int
    @State private var preferredSupplier: String
    @State private var supplierSKU: String
    @State private var minimumOrderQuantity: Int
    @State private var reorderCasePack: Int
    @State private var leadTimeVarianceDays: Int
    @State private var isShowingPermissionAlert = false
    @State private var isShowingWalkthrough = false

    init(mode: Mode) {
        self.mode = mode

        switch mode {
        case .add(let barcode):
            _name = State(initialValue: "")
            _quantity = State(initialValue: 1)
            _notes = State(initialValue: "")
            _category = State(initialValue: "")
            _location = State(initialValue: "")
            _unitsPerCase = State(initialValue: 0)
            _units = State(initialValue: 0)
            _eachesPerUnit = State(initialValue: 0)
            _eaches = State(initialValue: 0)
            _isLiquid = State(initialValue: false)
            _gallonFractionText = State(initialValue: "")
            _isPinned = State(initialValue: false)
            _barcode = State(initialValue: barcode ?? "")
            _averageDailyUsage = State(initialValue: 0)
            _leadTimeDays = State(initialValue: 0)
            _safetyStockUnits = State(initialValue: 0)
            _preferredSupplier = State(initialValue: "")
            _supplierSKU = State(initialValue: "")
            _minimumOrderQuantity = State(initialValue: 0)
            _reorderCasePack = State(initialValue: 0)
            _leadTimeVarianceDays = State(initialValue: 0)
        case .edit(let item):
            _name = State(initialValue: item.name)
            _quantity = State(initialValue: Int(item.quantity))
            _notes = State(initialValue: item.notes)
            _category = State(initialValue: item.category)
            _location = State(initialValue: item.location)
            _unitsPerCase = State(initialValue: Int(item.unitsPerCase))
            _units = State(initialValue: Int(item.looseUnits))
            _eachesPerUnit = State(initialValue: Int(item.eachesPerUnit))
            _eaches = State(initialValue: Int(item.looseEaches))
            _isLiquid = State(initialValue: item.isLiquid)
            _gallonFractionText = State(initialValue: item.gallonFraction == 0 ? "" : String(item.gallonFraction))
            _isPinned = State(initialValue: item.isPinned)
            _barcode = State(initialValue: item.barcode)
            _averageDailyUsage = State(initialValue: item.averageDailyUsage)
            _leadTimeDays = State(initialValue: Int(item.leadTimeDays))
            _safetyStockUnits = State(initialValue: Int(item.safetyStockUnits))
            _preferredSupplier = State(initialValue: item.preferredSupplier)
            _supplierSKU = State(initialValue: item.supplierSKU)
            _minimumOrderQuantity = State(initialValue: Int(item.minimumOrderQuantity))
            _reorderCasePack = State(initialValue: Int(item.reorderCasePack))
            _leadTimeVarianceDays = State(initialValue: Int(item.leadTimeVarianceDays))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                ScrollView {
                    VStack(spacing: 16) {
                        headerCard

                        sectionCard(title: "Item") {
                            cardTextField("Name", text: $name)
                            cardTextField("Category", text: $category)
                            cardTextField("Location", text: $location)
                            cardTextField("Barcode", text: $barcode)
                        }

                        sectionCard(title: "Counts") {
                            Toggle("Liquid (Gallons)", isOn: $isLiquid)
                                .font(Theme.font(14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .tint(Theme.accent)

                            if isLiquid {
                                stepperField("Units (Gallons)", value: $units, range: 0...1_000_000)
                                cardTextField(
                                    "Partial unit (e.g. 0.5, 1.25)",
                                    text: $gallonFractionText,
                                    keyboard: .decimalPad
                                )
                                fractionButtons
                            } else {
                                stepperField("Cases", value: $quantity, range: 0...1_000_000)
                                stepperField("Units per Case", value: $unitsPerCase, range: 0...1_000)
                                stepperField("Each per Unit", value: $eachesPerUnit, range: 0...1_000)
                                stepperField("Units", value: $units, range: 0...1_000_000)
                                stepperField("Each", value: $eaches, range: eachesRange)
                            }
                        }

                        sectionCard(title: "Priority") {
                            Toggle("Pin Item", isOn: $isPinned)
                                .font(Theme.font(14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .tint(Theme.accent)
                        }

                        sectionCard(title: "Reorder") {
                            TextField(
                                "Avg daily usage",
                                value: $averageDailyUsage,
                                format: .number.precision(.fractionLength(0...2))
                            )
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .inventoryTextInputField()

                            stepperField("Lead time (days)", value: $leadTimeDays, range: 0...365)
                            stepperField("Safety stock (units)", value: $safetyStockUnits, range: 0...1_000_000)
                        }

                        sectionCard(title: "Supplier Intelligence") {
                            cardTextField("Preferred supplier", text: $preferredSupplier)
                            cardTextField("Supplier SKU", text: $supplierSKU)
                            stepperField("Minimum order quantity (MOQ)", value: $minimumOrderQuantity, range: 0...1_000_000)
                            stepperField("Case pack increment", value: $reorderCasePack, range: 0...1_000_000)
                            stepperField("Lead time variance (days)", value: $leadTimeVarianceDays, range: 0...90)
                        }

                        sectionCard(title: "Preview") {
                            previewRow(title: "Total Units", value: "\(totalUnitsPreview)")
                            previewRow(title: "Total Eaches", value: "\(totalEachesPreview) each")
                            if isLiquid {
                                previewRow(title: "Total Gallons", value: formattedGallons(totalGallonsPreview))
                            }
                        }

                        sectionCard(title: "Notes") {
                            TextField("", text: $notes, prompt: Theme.inputPrompt("Optional"), axis: .vertical)
                                .lineLimit(3...6)
                                .inventoryTextInputField()
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 96)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingWalkthrough = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("How to use Add Item")
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveBar
            }
            .tint(Theme.accent)
            .sheet(isPresented: $isShowingWalkthrough) {
                ProcessWalkthroughView(
                    flow: .addItem,
                    showLaunchButton: false,
                    onCompleted: {
                        guidanceStore.markFlowCompleted(.addItem)
                    }
                )
            }
            .alert("Permission required", isPresented: $isShowingPermissionAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Only owners and managers can create or edit item details.")
            }
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: modeIcon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Theme.accentSoft.opacity(0.34))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(isAddMode ? "Create inventory item" : "Update inventory item")
                    .font(Theme.font(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Use counts, reorder data, and notes to keep this item accurate.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .inventoryCard(cornerRadius: 16, emphasis: 0.62)
    }

    private var modeIcon: String {
        switch mode {
        case .add:
            return "plus.circle.fill"
        case .edit:
            return "square.and.pencil"
        }
    }

    private var isAddMode: Bool {
        if case .add = mode {
            return true
        }
        return false
    }

    private var fractionButtons: some View {
        HStack(spacing: 8) {
            fractionButton("1/4", value: "0.25")
            fractionButton("1/2", value: "0.5")
            fractionButton("3/4", value: "0.75")
            fractionButton("1/3", value: "0.33")
        }
    }

    private var saveBar: some View {
        HStack {
            Button(action: save) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Save")
                        .font(Theme.font(14, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent, Theme.accentDeep],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !authStore.canManageCatalog)
            .opacity((name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !authStore.canManageCatalog) ? 0.55 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 2)

            VStack(spacing: 10) {
                content()
            }
            .padding(12)
            .inventoryCard(cornerRadius: 14, emphasis: 0.24)
        }
        .padding(14)
        .inventoryCard(cornerRadius: 16, emphasis: 0.44)
    }

    private func stepperField(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title)
                    .font(Theme.font(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.cardBackground.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.subtleBorder, lineWidth: 1)
            )
        }
    }

    private func previewRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.font(13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.font(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func fractionButton(_ title: String, value: String) -> some View {
        Button(title) {
            gallonFractionText = value
        }
        .font(Theme.font(12, weight: .semibold))
        .foregroundStyle(Theme.accentDeep)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.pillGradient())
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func cardTextField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField("", text: text, prompt: Theme.inputPrompt(title))
            .keyboardType(keyboard)
            .inventoryTextInputField()
    }

    private var title: String {
        switch mode {
        case .add:
            return "Add Item"
        case .edit:
            return "Edit Item"
        }
    }

    private func save() {
        guard authStore.canManageCatalog else {
            isShowingPermissionAlert = true
            Haptics.tap()
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let updatedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let extraGallons = Double(gallonFractionText) ?? 0
        let normalized = normalizeCounts(
            cases: quantity,
            unitsPerCase: unitsPerCase,
            units: units,
            eachesPerUnit: eachesPerUnit,
            eaches: eaches
        )
        let clampedDailyUsage = max(0, averageDailyUsage)
        let clampedLeadTimeDays = max(0, leadTimeDays)
        let clampedSafetyStock = max(0, safetyStockUnits)
        let normalizedPreferredSupplier = preferredSupplier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSupplierSKU = supplierSKU.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedMOQ = max(0, minimumOrderQuantity)
        let clampedCasePack = max(0, reorderCasePack)
        let clampedLeadTimeVariance = max(0, leadTimeVarianceDays)

        switch mode {
        case .add:
            let item = InventoryItemEntity(context: context)
            item.id = UUID()
            item.name = trimmedName
            item.quantity = Int64(normalized.cases)
            item.notes = updatedNotes
            item.category = updatedCategory
            item.location = updatedLocation
            item.unitsPerCase = Int64(normalized.unitsPerCase)
            item.looseUnits = Int64(normalized.units)
            item.eachesPerUnit = Int64(normalized.eachesPerUnit)
            item.looseEaches = Int64(normalized.eaches)
            item.isLiquid = isLiquid
            item.gallonFraction = isLiquid ? extraGallons : 0
            item.isPinned = isPinned
            item.barcode = updatedBarcode
            item.averageDailyUsage = clampedDailyUsage
            item.leadTimeDays = Int64(clampedLeadTimeDays)
            item.safetyStockUnits = Int64(clampedSafetyStock)
            item.preferredSupplier = normalizedPreferredSupplier
            item.supplierSKU = normalizedSupplierSKU
            item.minimumOrderQuantity = Int64(clampedMOQ)
            item.reorderCasePack = Int64(clampedCasePack)
            item.leadTimeVarianceDays = Int64(clampedLeadTimeVariance)
            item.workspaceID = authStore.activeWorkspaceIDString()
            item.recentDemandSamples = ""
            item.createdAt = Date()
            item.updatedAt = Date()
        case .edit(let item):
            item.name = trimmedName
            item.quantity = Int64(normalized.cases)
            item.notes = updatedNotes
            item.category = updatedCategory
            item.location = updatedLocation
            item.unitsPerCase = Int64(normalized.unitsPerCase)
            item.looseUnits = Int64(normalized.units)
            item.eachesPerUnit = Int64(normalized.eachesPerUnit)
            item.looseEaches = Int64(normalized.eaches)
            item.isLiquid = isLiquid
            item.gallonFraction = isLiquid ? extraGallons : 0
            item.isPinned = isPinned
            item.barcode = updatedBarcode
            item.averageDailyUsage = clampedDailyUsage
            item.leadTimeDays = Int64(clampedLeadTimeDays)
            item.safetyStockUnits = Int64(clampedSafetyStock)
            item.preferredSupplier = normalizedPreferredSupplier
            item.supplierSKU = normalizedSupplierSKU
            item.minimumOrderQuantity = Int64(clampedMOQ)
            item.reorderCasePack = Int64(clampedCasePack)
            item.leadTimeVarianceDays = Int64(clampedLeadTimeVariance)
            item.assignWorkspaceIfNeeded(authStore.activeWorkspaceID)
            item.updatedAt = Date()
        }

        dataController.save()
        Haptics.success()
        dismiss()
    }

    private var eachesRange: ClosedRange<Int> {
        if eachesPerUnit > 0 {
            return 0...max(eachesPerUnit - 1, 0)
        }
        return 0...1_000
    }

    private var nonLiquidBaseUnitsPreview: Int {
        if unitsPerCase > 0 {
            return quantity * unitsPerCase + units
        }
        return quantity + units
    }

    private var totalUnitsPreview: Int {
        guard isLiquid else { return nonLiquidBaseUnitsPreview }
        return Int((totalGallonsPreview * 128).rounded())
    }

    private var totalEachesPreview: Int {
        if isLiquid {
            let gallons = totalGallonsPreview
            return Int((gallons * 128).rounded())
        }
        return nonLiquidBaseUnitsPreview * eachesPerUnit + eaches
    }

    private var totalGallonsPreview: Double {
        let extraGallons = Double(gallonFractionText) ?? 0
        if isLiquid {
            return Double(units) + extraGallons
        }
        let baseUnits = Double(nonLiquidBaseUnitsPreview)
        let eachesFraction = eachesPerUnit > 0 ? Double(eaches) / Double(eachesPerUnit) : 0
        return baseUnits + eachesFraction + extraGallons
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

    private func normalizeCounts(
        cases: Int,
        unitsPerCase: Int,
        units: Int,
        eachesPerUnit: Int,
        eaches: Int
    ) -> (cases: Int, unitsPerCase: Int, units: Int, eachesPerUnit: Int, eaches: Int) {
        let clampedCases = max(0, cases)
        let clampedUnitsPerCase = max(0, unitsPerCase)
        let clampedUnits = max(0, units)
        let clampedEachesPerUnit = max(0, eachesPerUnit)
        let clampedEaches = max(0, eaches)

        guard clampedUnitsPerCase > 0, clampedEachesPerUnit > 0 else {
            return (clampedCases, clampedUnitsPerCase, clampedUnits, clampedEachesPerUnit, clampedEaches)
        }

        let totalEaches = (clampedCases * clampedUnitsPerCase + clampedUnits) * clampedEachesPerUnit + clampedEaches
        let totalUnits = totalEaches / clampedEachesPerUnit
        let normalizedEaches = totalEaches % clampedEachesPerUnit
        let normalizedCases = totalUnits / clampedUnitsPerCase
        let normalizedUnits = totalUnits % clampedUnitsPerCase
        return (normalizedCases, clampedUnitsPerCase, normalizedUnits, clampedEachesPerUnit, normalizedEaches)
    }
}
