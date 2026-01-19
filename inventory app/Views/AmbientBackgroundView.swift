import SwiftUI

struct AmbientBackgroundView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.backgroundTop, Theme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Theme.glow)
                .frame(width: 360, height: 360)
                .blur(radius: 40)
                .offset(x: -160, y: -220)

            Circle()
                .fill(Theme.glow.opacity(0.75))
                .frame(width: 260, height: 260)
                .blur(radius: 50)
                .offset(x: 180, y: 120)
        }
    }
}
