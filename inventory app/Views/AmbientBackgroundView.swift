import SwiftUI

struct AmbientBackgroundView: View {
    @State private var drift = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldAnimate: Bool {
        !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.backgroundTop, Theme.backgroundBottom, Theme.backgroundEdge],
                startPoint: drift ? .topLeading : .topTrailing,
                endPoint: drift ? .bottomTrailing : .bottomLeading
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Theme.accentSoft.opacity(0.40),
                    Theme.accent.opacity(0.08),
                    .clear
                ],
                center: drift ? .topLeading : .bottomTrailing,
                startRadius: 24,
                endRadius: 320
            )
            .ignoresSafeArea()
            .blendMode(.screen)

            AngularGradient(
                colors: [
                    Theme.accent.opacity(0.16),
                    Theme.accentSoft.opacity(0.12),
                    .clear,
                    Theme.accentDeep.opacity(0.16),
                    .clear
                ],
                center: drift ? .topTrailing : .bottomLeading
            )
            .blur(radius: 28)
            .scaleEffect(pulse ? 1.16 : 1.0)
            .rotationEffect(.degrees(drift ? 10 : -8))
            .offset(x: drift ? -44 : 40, y: drift ? -112 : 94)
            .ignoresSafeArea()

            Circle()
                .fill(Theme.glow)
                .frame(width: 260, height: 260)
                .blur(radius: 26)
                .offset(x: drift ? -138 : -88, y: drift ? -208 : -150)

            Circle()
                .fill(Theme.accent.opacity(0.12))
                .frame(width: 230, height: 230)
                .blur(radius: 24)
                .offset(x: drift ? 94 : 140, y: drift ? -172 : -130)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.clear,
                            Theme.accent.opacity(0.07)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()
                .blendMode(.softLight)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Theme.accent.opacity(0.07),
                            Color.clear,
                            Theme.accentSoft.opacity(0.06)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .ignoresSafeArea()
                .blendMode(.softLight)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard shouldAnimate else { return }
            withAnimation(.easeInOut(duration: 20).repeatForever(autoreverses: true)) {
                drift = true
            }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
