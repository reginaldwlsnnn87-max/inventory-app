import SwiftUI

struct PremiumPaywallView: View {
    @ObservedObject var viewModel: TVRemoteAppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    featuresCard
                    productsCard
                    actionCard
                }
                .padding(18)
            }
            .navigationTitle("Pulse Remote Pro")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        viewModel.dismissPremiumPaywall()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.62), .large])
        .presentationDragIndicator(.visible)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.premiumPaywallHeadline)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(RemoteTheme.textPrimary)

            Text(viewModel.premiumPaywallBodyText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(RemoteTheme.textSecondary)

            HStack(spacing: 8) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(RemoteTheme.accentSoft)
                Text("Pro Anchor: Unlimited Smart Scenes")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(RemoteTheme.accent.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(RemoteTheme.stroke, lineWidth: 1)
                    )
            )

            HStack(spacing: 8) {
                Text(viewModel.premiumPaywallContextBadge)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(RemoteTheme.accent.opacity(0.24))
                    )
                    .foregroundStyle(RemoteTheme.accentSoft)

                Text(viewModel.premiumStatusLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(RemoteTheme.accent.opacity(0.20))
                    )
                    .foregroundStyle(RemoteTheme.accentSoft)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Includes")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(RemoteTheme.textPrimary)

            ForEach(TVPremiumFeature.allCases, id: \.self) { feature in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(RemoteTheme.accentSoft)
                        .font(.system(size: 14, weight: .semibold))

                    Text(feature.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(RemoteTheme.textPrimary)

                    Spacer(minLength: 0)
                }
            }

            Text("Growth Funnel: \(viewModel.growthFunnelSummary)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(RemoteTheme.textSecondary)
                .padding(.top, 2)
        }
        .padding(16)
        .background(cardBackground)
    }

    private var productsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Plans")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textPrimary)

                Spacer()

                Button("Refresh") {
                    viewModel.refreshPremiumCatalogFromPaywall()
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .buttonStyle(.bordered)
                .tint(RemoteTheme.accentSoft)
                .disabled(viewModel.isPremiumCatalogLoading || viewModel.isPremiumPurchaseInFlight)
            }

            if viewModel.isPremiumCatalogLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Loading App Store plans...")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(RemoteTheme.textSecondary)
                }
                .padding(.vertical, 8)
            } else if viewModel.premiumProducts.isEmpty {
                Text("No plans are available yet. Verify your product IDs and App Store Connect status.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textSecondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.premiumProducts) { product in
                    Button {
                        viewModel.purchasePremiumProduct(product.id)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(product.title)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(RemoteTheme.textPrimary)

                                    if product.isFeatured {
                                        Text("Best")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .fill(RemoteTheme.accent.opacity(0.22))
                                            )
                                            .foregroundStyle(RemoteTheme.accentSoft)
                                    }
                                }

                                Text(product.subtitle)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(RemoteTheme.textSecondary)
                            }

                            Spacer(minLength: 8)

                            if viewModel.purchasingPremiumProductID == product.id {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else {
                                Text(product.price)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(RemoteTheme.textPrimary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(RemoteTheme.cardStrong)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(RemoteTheme.stroke, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        viewModel.premiumSnapshot.tier == .pro
                            || viewModel.isPremiumPurchaseInFlight
                            || viewModel.isPremiumRestoreInFlight
                    )
                    .opacity(viewModel.premiumSnapshot.tier == .pro ? 0.55 : 1)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let premiumStatusMessage = viewModel.premiumStatusMessage {
                Text(premiumStatusMessage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(RemoteTheme.textSecondary)
            }

            Button {
                viewModel.activatePremiumFromPaywall()
            } label: {
                if viewModel.isPremiumPurchaseInFlight {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Processing...")
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 46)
                } else {
                    Text(viewModel.premiumSnapshot.tier == .pro ? "Pro Active" : "Choose Recommended Plan")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(RemoteTheme.accent)
            .disabled(
                viewModel.premiumSnapshot.tier == .pro
                    || viewModel.isPremiumPurchaseInFlight
                    || viewModel.premiumProducts.isEmpty
            )
            .opacity(viewModel.premiumSnapshot.tier == .pro ? 0.55 : 1)

            Button {
                viewModel.restorePremiumFromPaywall()
            } label: {
                if viewModel.isPremiumRestoreInFlight {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Restoring...")
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Text("Restore Purchases")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isPremiumPurchaseInFlight || viewModel.isPremiumRestoreInFlight)
        }
        .padding(16)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [RemoteTheme.cardStrong, RemoteTheme.card],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(RemoteTheme.stroke, lineWidth: 1)
            )
    }
}
