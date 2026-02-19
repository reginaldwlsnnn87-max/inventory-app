import SwiftUI

private enum LGRemotePalette {
    static let canvasTop = Color(red: 0.06, green: 0.08, blue: 0.12)
    static let canvasMid = Color(red: 0.10, green: 0.12, blue: 0.17)
    static let canvasBottom = Color(red: 0.03, green: 0.04, blue: 0.06)
    static let cardSurface = Color(red: 0.14, green: 0.16, blue: 0.23).opacity(0.9)
    static let cardSurfaceStrong = Color(red: 0.18, green: 0.20, blue: 0.29).opacity(0.95)
    static let keySurface = Color(red: 0.20, green: 0.22, blue: 0.31)
    static let accent = Color(red: 0.80, green: 0.06, blue: 0.24)
    static let accentSoft = Color(red: 1.00, green: 0.54, blue: 0.65)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.7)
    static let stroke = Color.white.opacity(0.12)
}

struct LGRemoteRootView: View {
    @StateObject private var viewModel = LGRemoteViewModel()

    var body: some View {
        ZStack {
            remoteBackground

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    heroCard
                    commandDeck
                    mediaDeck
                    quickLaunchDeck
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 24)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.connectionState.title)
    }

    private var remoteBackground: some View {
        ZStack {
            LinearGradient(
                colors: [LGRemotePalette.canvasTop, LGRemotePalette.canvasMid, LGRemotePalette.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [LGRemotePalette.accent.opacity(0.35), .clear],
                        center: .center,
                        startRadius: 6,
                        endRadius: 230
                    )
                )
                .blur(radius: 24)
                .offset(x: 120, y: -200)

            RoundedRectangle(cornerRadius: 240, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.09), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .rotationEffect(.degrees(25))
                .offset(x: -210, y: -290)
        }
        .ignoresSafeArea()
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LG Wi-Fi Remote")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(LGRemotePalette.textPrimary)
                    Text("Elegant control for your webOS TV")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(LGRemotePalette.textSecondary)
                }
                Spacer()
                statusBadge
            }

            HStack(spacing: 12) {
                Image(systemName: "wifi.router.fill")
                    .foregroundStyle(LGRemotePalette.accentSoft)
                    .font(.system(size: 20, weight: .semibold))

                TextField("TV IP (example 192.168.1.47)", text: $viewModel.tvAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(LGRemotePalette.textPrimary)

                if viewModel.isBusy {
                    ProgressView()
                        .tint(LGRemotePalette.accentSoft)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(LGRemotePalette.stroke, lineWidth: 1)
                    )
            )

            HStack(spacing: 10) {
                Button(viewModel.connectButtonTitle) {
                    viewModel.connectOrDisconnect()
                }
                .buttonStyle(LGPrimaryButtonStyle())

                if let feedback = viewModel.commandFeedback {
                    Text(feedback)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.orange.opacity(0.95))
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                } else {
                    Text(viewModel.connectionState.subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(LGRemotePalette.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [LGRemotePalette.cardSurfaceStrong, LGRemotePalette.cardSurface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.22), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.1
                        )
                )
                .shadow(color: LGRemotePalette.accent.opacity(0.22), radius: 22, y: 10)
        )
    }

    private var statusBadge: some View {
        Text(viewModel.connectionState.title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(statusColor.opacity(0.95))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            )
    }

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .connected:
            return Color.green
        case .connecting, .waitingForPairing:
            return Color.orange
        case .failed:
            return Color.red
        case .disconnected:
            return Color.gray
        }
    }

    private var commandDeck: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Navigation")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(LGRemotePalette.textPrimary)
                Spacer()
                Text("Tap and control")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(LGRemotePalette.textSecondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    directionalPad
                    sideRails
                }
                VStack(spacing: 12) {
                    directionalPad
                    sideRails
                }
            }

            HStack(spacing: 10) {
                utilityButton("arrow.left", "Back") {
                    viewModel.send(.back)
                }
                utilityButton("house.fill", "Home") {
                    viewModel.send(.home)
                }
                utilityButton("slider.horizontal.3", "Menu") {
                    viewModel.send(.settings)
                }
                utilityButton("power", "Power") {
                    viewModel.send(.powerOff)
                }
            }
        }
        .padding(16)
        .background(deckBackground)
    }

    private var directionalPad: some View {
        VStack(spacing: 10) {
            roundActionButton(symbol: "chevron.up", size: 62) { viewModel.send(.up) }
            HStack(spacing: 10) {
                roundActionButton(symbol: "chevron.left", size: 62) { viewModel.send(.left) }
                roundActionButton(symbol: "checkmark", size: 78, emphasized: true) { viewModel.send(.ok) }
                roundActionButton(symbol: "chevron.right", size: 62) { viewModel.send(.right) }
            }
            roundActionButton(symbol: "chevron.down", size: 62) { viewModel.send(.down) }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(LGRemotePalette.stroke, lineWidth: 1)
                )
        )
    }

    private var sideRails: some View {
        VStack(spacing: 10) {
            controlRail(
                title: "VOL",
                topSymbol: "plus",
                bottomSymbol: "minus",
                topAction: { viewModel.send(.volumeUp) },
                bottomAction: { viewModel.send(.volumeDown) }
            )
            controlRail(
                title: viewModel.isMuted ? "UNMUTE" : "MUTE",
                topSymbol: "speaker.slash.fill",
                bottomSymbol: "speaker.wave.2.fill",
                topAction: { viewModel.send(.mute(true)) },
                bottomAction: { viewModel.send(.mute(false)) }
            )
            controlRail(
                title: "CH",
                topSymbol: "chevron.up",
                bottomSymbol: "chevron.down",
                topAction: { viewModel.send(.channelUp) },
                bottomAction: { viewModel.send(.channelDown) }
            )
        }
        .frame(width: 104)
    }

    private func controlRail(
        title: String,
        topSymbol: String,
        bottomSymbol: String,
        topAction: @escaping () -> Void,
        bottomAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(LGRemotePalette.textSecondary)
                .tracking(0.7)

            Button(action: topAction) {
                Image(systemName: topSymbol)
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(LGSecondaryButtonStyle())

            Button(action: bottomAction) {
                Image(systemName: bottomSymbol)
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(LGSecondaryButtonStyle())
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(LGRemotePalette.stroke, lineWidth: 1)
                )
        )
    }

    private func utilityButton(
        _ symbol: String,
        _ label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(LGSecondaryButtonStyle())
    }

    private var mediaDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playback")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(LGRemotePalette.textPrimary)

            HStack(spacing: 10) {
                utilityButton("backward.fill", "Rewind") {
                    viewModel.send(.rewind)
                }
                utilityButton("play.fill", "Play") {
                    viewModel.send(.play)
                }
                utilityButton("pause.fill", "Pause") {
                    viewModel.send(.pause)
                }
                utilityButton("stop.fill", "Stop") {
                    viewModel.send(.stop)
                }
                utilityButton("forward.fill", "Forward") {
                    viewModel.send(.fastForward)
                }
            }
        }
        .padding(16)
        .background(deckBackground)
    }

    private var quickLaunchDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Launch")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(LGRemotePalette.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.launchTargets) { target in
                        Button {
                            viewModel.launch(target)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: target.icon)
                                    .font(.system(size: 15, weight: .bold))
                                Text(target.title)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .frame(width: 112, alignment: .leading)
                            .padding(14)
                        }
                        .buttonStyle(LGTileButtonStyle())
                    }
                }
            }
        }
        .padding(16)
        .background(deckBackground)
    }

    private func roundActionButton(
        symbol: String,
        size: CGFloat,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: emphasized ? 21 : 20, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(emphasized ? LGRemotePalette.accent : LGRemotePalette.keySurface)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                )
        }
        .buttonStyle(LGPressFeedbackStyle())
    }

    private var deckBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LGRemotePalette.cardSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(LGRemotePalette.stroke, lineWidth: 1)
            )
    }
}

private struct LGPressFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct LGPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(LGRemotePalette.accent)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct LGSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(LGRemotePalette.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LGRemotePalette.keySurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.09 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct LGTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(LGRemotePalette.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LGRemotePalette.keySurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct LGRemoteRootView_Previews: PreviewProvider {
    static var previews: some View {
        LGRemoteRootView()
    }
}
