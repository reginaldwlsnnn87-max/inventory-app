import SwiftUI
import CoreData

struct QuantityEditView: View {
    @EnvironmentObject private var dataController: InventoryDataController
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss

    let item: InventoryItemEntity

    @State private var casesText: String
    @State private var unitsText: String
    @State private var eachesText: String
    @State private var partialUnitText: String

    init(item: InventoryItemEntity) {
        self.item = item
        _casesText = State(initialValue: String(item.quantity))
        _unitsText = State(initialValue: String(item.looseUnits))
        _eachesText = State(initialValue: String(item.looseEaches))
        _partialUnitText = State(initialValue: item.gallonFraction == 0 ? "" : String(item.gallonFraction))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                ScrollView {
                    VStack(spacing: 16) {
                        headerCard

                        sectionCard(title: "Counts") {
                            if item.isLiquid {
                                cardTextField("Units (Gallons)", text: $unitsText, keyboard: .numberPad)
                            } else {
                                cardTextField("Cases", text: $casesText, keyboard: .numberPad)
                                cardTextField("Units", text: $unitsText, keyboard: .numberPad)
                                cardTextField("Each", text: $eachesText, keyboard: .numberPad)
                            }
                        }

                        sectionCard(title: "Preview") {
                            previewRow(title: "Total Units", value: "\(totalUnitsPreview)")
                            previewRow(title: "Total Each", value: "\(totalEachesPreview) each")
                            if item.isLiquid {
                                previewRow(title: "Total Gallons", value: formattedGallons(totalGallonsPreview))
                            }
                        }

                        if item.isLiquid {
                            sectionCard(title: "Gallons") {
                                cardTextField(
                                    "Partial unit (e.g. 0.5, 1.25)",
                                    text: $partialUnitText,
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
            .navigationTitle("Set Amount")
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
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Theme.accentSoft.opacity(0.34))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name.isEmpty ? "Adjust quantity" : item.name)
                    .font(Theme.font(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Update physical counts and save the current on-hand amount.")
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
                    Text("Save Amount")
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
            partialUnitText = value
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

    private var totalUnitsPreview: Int {
        let casesValue = Int(casesText) ?? 0
        let unitsValue = Int(unitsText) ?? 0
        guard item.isLiquid else { return nonLiquidBaseUnits(casesValue: casesValue, unitsValue: unitsValue) }
        return Int((totalGallonsPreview * 128).rounded())
    }

    private var totalEachesPreview: Int {
        if item.isLiquid {
            return totalUnitsPreview
        }
        let casesValue = Int(casesText) ?? 0
        let unitsValue = Int(unitsText) ?? 0
        let eachesValue = Int(eachesText) ?? 0
        let eachesPerUnit = Int(item.eachesPerUnit)
        return nonLiquidBaseUnits(casesValue: casesValue, unitsValue: unitsValue) * eachesPerUnit + eachesValue
    }

    private var totalGallonsPreview: Double {
        let casesValue = Int(casesText) ?? 0
        let unitsValue = Int(unitsText) ?? 0
        let baseUnits = item.isLiquid
            ? Double(unitsValue)
            : Double(nonLiquidBaseUnits(casesValue: casesValue, unitsValue: unitsValue))
        let eachesValue = Int(eachesText) ?? 0
        let eachesPerUnit = Int(item.eachesPerUnit)
        let eachesFraction = eachesPerUnit > 0 ? Double(eachesValue) / Double(eachesPerUnit) : 0
        let extraGallons = Double(partialUnitText) ?? 0
        return baseUnits + eachesFraction + extraGallons
    }

    private func nonLiquidBaseUnits(casesValue: Int, unitsValue: Int) -> Int {
        if item.unitsPerCase > 0 {
            return casesValue * Int(item.unitsPerCase) + unitsValue
        }
        return casesValue + unitsValue
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

    private func save() {
        let casesValue = Int(casesText) ?? 0
        let unitsValue = Int(unitsText) ?? 0
        let eachesValue = Int(eachesText) ?? 0
        let extraGallons = Double(partialUnitText) ?? 0

        let normalized = normalizeCounts(
            cases: casesValue,
            unitsPerCase: Int(item.unitsPerCase),
            units: unitsValue,
            eachesPerUnit: Int(item.eachesPerUnit),
            eaches: eachesValue
        )

        item.quantity = Int64(normalized.cases)
        item.looseUnits = Int64(normalized.units)
        item.looseEaches = Int64(normalized.eaches)
        if item.isLiquid {
            item.gallonFraction = extraGallons
        }
        item.assignWorkspaceIfNeeded(authStore.activeWorkspaceID)
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
    ) -> (cases: Int, units: Int, eaches: Int) {
        let clampedCases = max(0, cases)
        let clampedUnitsPerCase = max(1, unitsPerCase)
        let clampedUnits = max(0, units)
        let clampedEachesPerUnit = max(1, eachesPerUnit)
        let clampedEaches = max(0, eaches)

        let totalEaches = (clampedCases * clampedUnitsPerCase + clampedUnits) * clampedEachesPerUnit + clampedEaches
        let totalUnits = totalEaches / clampedEachesPerUnit
        let normalizedEaches = totalEaches % clampedEachesPerUnit
        let normalizedCases = totalUnits / clampedUnitsPerCase
        let normalizedUnits = totalUnits % clampedUnitsPerCase
        return (normalizedCases, normalizedUnits, normalizedEaches)
    }
}
