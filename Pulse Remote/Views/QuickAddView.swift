import SwiftUI
import CoreData

struct QuickAddView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var dataController: InventoryDataController
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var casesText = "1"
    @State private var unitsPerCaseText = ""
    @State private var eachesPerUnitText = ""
    @State private var unitsText = ""
    @State private var eachesText = ""
    @State private var category = ""
    @State private var location = ""
    @State private var isLiquid = false
    @State private var gallonFractionText = ""
    @State private var isShowingPermissionAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                ScrollView {
                    VStack(spacing: 16) {
                        introCard

                        sectionCard(title: "Item") {
                            cardTextField("Item name", text: $name)
                            cardTextField("Cases", text: $casesText, keyboard: .numberPad)
                        }

                        sectionCard(title: "Units") {
                            cardTextField("Units per Case", text: $unitsPerCaseText, keyboard: .numberPad)
                            cardTextField("Each per Unit", text: $eachesPerUnitText, keyboard: .numberPad)
                            cardTextField("Units", text: $unitsText, keyboard: .numberPad)
                            cardTextField("Each", text: $eachesText, keyboard: .numberPad)
                        }

                        sectionCard(title: "Details") {
                            cardTextField("Category", text: $category)
                            cardTextField("Location", text: $location)
                        }

                        sectionCard(title: "Gallons") {
                            Toggle("Liquid item", isOn: $isLiquid)
                                .font(Theme.font(14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .tint(Theme.accent)

                            if isLiquid {
                                cardTextField(
                                    "Partial unit (e.g. 0.5, 1.25)",
                                    text: $gallonFractionText,
                                    keyboard: .decimalPad
                                )
                                fractionButtons
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 96)
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveBar
            }
            .tint(Theme.accent)
            .alert("Permission required", isPresented: $isShowingPermissionAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Only owners and managers can add new catalog items.")
            }
        }
    }

    private var introCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Theme.accentSoft.opacity(0.34))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Fast inventory entry")
                    .font(Theme.font(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Capture counts in one pass and save immediately.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .inventoryCard(cornerRadius: 16, emphasis: 0.62)
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
                    Text("Save Item")
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

    private func save() {
        guard authStore.canManageCatalog else {
            isShowingPermissionAlert = true
            Haptics.tap()
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let casesValue = Int(casesText) ?? 0
        let unitsPerCaseValue = Int(unitsPerCaseText) ?? 0
        let eachesPerUnitValue = Int(eachesPerUnitText) ?? 0
        let unitsValue = Int(unitsText) ?? 0
        let eachesValue = Int(eachesText) ?? 0
        let extraGallons = Double(gallonFractionText) ?? 0
        let normalized = normalizeCounts(
            cases: casesValue,
            unitsPerCase: unitsPerCaseValue,
            units: unitsValue,
            eachesPerUnit: eachesPerUnitValue,
            eaches: eachesValue
        )

        let item = InventoryItemEntity(context: context)
        item.id = UUID()
        item.name = trimmedName
        item.quantity = Int64(normalized.cases)
        item.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        item.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = ""
        item.unitsPerCase = Int64(normalized.unitsPerCase)
        item.looseUnits = Int64(normalized.units)
        item.eachesPerUnit = Int64(normalized.eachesPerUnit)
        item.looseEaches = Int64(normalized.eaches)
        item.isLiquid = isLiquid
        item.gallonFraction = isLiquid ? extraGallons : 0
        item.isPinned = false
        item.barcode = ""
        item.averageDailyUsage = 0
        item.leadTimeDays = 0
        item.safetyStockUnits = 0
        item.workspaceID = authStore.activeWorkspaceIDString()
        item.recentDemandSamples = ""
        item.createdAt = Date()
        item.updatedAt = Date()

        dataController.save()
        Haptics.success()
        dismiss()
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
