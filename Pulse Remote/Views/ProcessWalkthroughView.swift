import SwiftUI

private struct WalkthroughStep: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let checklist: [String]
    let result: String
}

private extension GuidedFlow {
    var goalText: String {
        switch self {
        case .addItem:
            return "Capture clean item data quickly so every later workflow works better."
        case .zoneMission:
            return "Count faster by moving one location at a time with fewer mistakes."
        case .replenishment:
            return "Catch stock risk early and turn it into clear PO actions."
        }
    }

    var steps: [WalkthroughStep] {
        switch self {
        case .addItem:
            return [
                WalkthroughStep(
                    title: "Start With Essentials",
                    detail: "Open Add Item and only fill what matters first: name, category, location, and initial count.",
                    checklist: [
                        "Name and category are clear",
                        "Location matches how the team searches",
                        "Opening count entered"
                    ],
                    result: "Item is searchable and countable immediately."
                ),
                WalkthroughStep(
                    title: "Set Packaging Rules",
                    detail: "If the item uses cases/units/eaches, define the pack structure now to avoid bad math later.",
                    checklist: [
                        "Units per case is correct",
                        "Eaches per unit set only if needed"
                    ],
                    result: "Stock in/out and counts stay consistent."
                ),
                WalkthroughStep(
                    title: "Enable Reorder Intelligence",
                    detail: "Fill reorder fields so the app can forecast and suggest actions automatically.",
                    checklist: [
                        "Average daily usage entered",
                        "Lead time days entered",
                        "Safety stock entered"
                    ],
                    result: "Item appears correctly in planner and KPI risk views."
                )
            ]
        case .zoneMission:
            return [
                WalkthroughStep(
                    title: "Choose A Zone",
                    detail: "Pick one location (or all) and start a focused mission for that area only.",
                    checklist: [
                        "Right location selected",
                        "Blind mode on for unbiased count"
                    ],
                    result: "Team stays focused and counts faster."
                ),
                WalkthroughStep(
                    title: "Count In Sequence",
                    detail: "Enter one item at a time with Save & Next to keep pace and prevent skips.",
                    checklist: [
                        "Every item gets a value",
                        "No empty rows left behind"
                    ],
                    result: "Mission progress becomes predictable and measurable."
                ),
                WalkthroughStep(
                    title: "Review Variance Before Apply",
                    detail: "On review, high variance rows must get reason codes before posting final counts.",
                    checklist: [
                        "Variance reasons selected",
                        "Unexpected differences verified"
                    ],
                    result: "Shrink insights improve with every mission."
                )
            ]
        case .replenishment:
            return [
                WalkthroughStep(
                    title: "Prioritize Risk",
                    detail: "Start with Auto-Reorder and Urgent items first to prevent avoidable stockouts.",
                    checklist: [
                        "Critical items reviewed first",
                        "Low-confidence rows flagged for data updates"
                    ],
                    result: "Team acts on impact, not noise."
                ),
                WalkthroughStep(
                    title: "Improve Forecast Inputs",
                    detail: "Log daily usage and correct lead time to raise recommendation quality.",
                    checklist: [
                        "Usage logged for top movers",
                        "Lead time confirmed with suppliers"
                    ],
                    result: "Order suggestions become more reliable."
                ),
                WalkthroughStep(
                    title: "Create Action Output",
                    detail: "Use Copy Plan or Create Draft PO so decisions become executable tasks immediately.",
                    checklist: [
                        "Draft PO generated or plan copied",
                        "Owner/manager reviews final order"
                    ],
                    result: "Replenishment closes the loop from signal to action."
                )
            ]
        }
    }
}

struct ProcessWalkthroughView: View {
    let flow: GuidedFlow
    var showLaunchButton = true
    var onOpenWorkflow: (() -> Void)? = nil
    var onCompleted: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var stepIndex = 0

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                        stepCard
                        progressCard
                        actionsCard
                    }
                    .padding(16)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle(flow.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .tint(Theme.accent)
        }
    }

    private var currentStep: WalkthroughStep {
        flow.steps[min(max(0, stepIndex), flow.steps.count - 1)]
    }

    private var isLastStep: Bool {
        stepIndex >= flow.steps.count - 1
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: flow.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(flow.subtitle)
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(flow.goalText)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.52)
    }

    private var stepCard: some View {
        sectionCard(title: "Step \(stepIndex + 1) of \(flow.steps.count)") {
            Text(currentStep.title)
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(currentStep.detail)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(currentStep.checklist, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text(line)
                            .font(Theme.font(12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Result: \(currentStep.result)")
                .font(Theme.font(11, weight: .semibold))
                .foregroundStyle(Theme.accentDeep)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var progressCard: some View {
        sectionCard(title: "Progress") {
            ProgressView(value: Double(stepIndex + 1), total: Double(flow.steps.count))
                .tint(Theme.accent)

            HStack(spacing: 10) {
                Button("Back") {
                    stepIndex = max(0, stepIndex - 1)
                }
                .buttonStyle(.bordered)
                .disabled(stepIndex == 0)

                Button(isLastStep ? "Restart" : "Next") {
                    if isLastStep {
                        stepIndex = 0
                    } else {
                        stepIndex = min(flow.steps.count - 1, stepIndex + 1)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var actionsCard: some View {
        sectionCard(title: "Actions") {
            Button {
                onCompleted?()
                dismiss()
            } label: {
                Label("Mark As Learned", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if showLaunchButton {
                Button {
                    onOpenWorkflow?()
                    dismiss()
                } label: {
                    Label("Open Workflow Now", systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
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
        .inventoryCard(cornerRadius: 16, emphasis: 0.42)
    }
}
