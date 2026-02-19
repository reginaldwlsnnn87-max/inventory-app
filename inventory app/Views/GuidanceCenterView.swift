import SwiftUI

struct GuidanceCenterView: View {
    let onLaunchFlow: (GuidedFlow) -> Void
    var onReplayCoachMarks: (() -> Void)? = nil

    @EnvironmentObject private var guidanceStore: GuidanceStore
    @State private var selectedFlow: GuidedFlow?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                ScrollView {
                    VStack(spacing: 16) {
                        introCard
                        flowListCard
                        hiddenValueCard
                        footerCard
                    }
                    .padding(16)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("Guided Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(guidanceStore.isFirstRunGuideContext ? "Skip" : "Close") {
                        guidanceStore.closeGuideCenter(markSeen: true)
                    }
                }
            }
            .tint(Theme.accent)
            .sheet(item: $selectedFlow) { flow in
                ProcessWalkthroughView(
                    flow: flow,
                    showLaunchButton: true,
                    onOpenWorkflow: {
                        guidanceStore.markFlowCompleted(flow)
                        guidanceStore.closeGuideCenter(markSeen: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            onLaunchFlow(flow)
                        }
                    },
                    onCompleted: {
                        guidanceStore.markFlowCompleted(flow)
                    }
                )
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(guidanceStore.isFirstRunGuideContext ? "Welcome. Let's get you productive fast." : "Step-by-step help whenever you need it.")
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Pick a guided process below. Each tour explains what to do, why it matters, and what outcome to expect.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.54)
    }

    private var flowListCard: some View {
        sectionCard(title: "Core Tours") {
            ForEach(GuidedFlow.allCases) { flow in
                Button {
                    selectedFlow = flow
                } label: {
                    flowRow(flow)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func flowRow(_ flow: GuidedFlow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: flow.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(flow.title)
                        .font(Theme.font(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if guidanceStore.isFlowCompleted(flow) {
                        Text("DONE")
                            .font(Theme.font(10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Theme.accentSoft.opacity(0.52))
                            )
                            .foregroundStyle(Theme.accentDeep)
                    }
                }
                Text(flow.subtitle)
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private var hiddenValueCard: some View {
        sectionCard(title: "Don't Miss") {
            tipRow(
                title: "Quick Actions",
                detail: "Use the ellipsis button to jump directly into the highest-impact tools."
            )
            tipRow(
                title: "Exception Feed",
                detail: "See only what needs action now instead of scanning full item lists."
            )
            tipRow(
                title: "KPI Dashboard",
                detail: "Use stockout risk and dead-stock signals to decide daily priorities."
            )
        }
    }

    private func tipRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.font(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(Theme.font(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private var footerCard: some View {
        sectionCard(title: "Finish") {
            if let onReplayCoachMarks {
                Button {
                    guidanceStore.closeGuideCenter(markSeen: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onReplayCoachMarks()
                    }
                } label: {
                    Label("Replay On-Screen Tips", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                guidanceStore.closeGuideCenter(markSeen: true)
            } label: {
                Label("Done", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
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
