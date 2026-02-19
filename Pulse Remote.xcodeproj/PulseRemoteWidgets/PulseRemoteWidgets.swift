import WidgetKit
import SwiftUI
import AppIntents

enum PulseWidgetCommand: String, CaseIterable, Identifiable, AppEnum {
    case home
    case volumeDown
    case playPause
    case volumeUp
    case mute
    case powerOff

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Pulse Remote Command")
    }

    static var caseDisplayRepresentations: [PulseWidgetCommand: DisplayRepresentation] {
        [
            .home: DisplayRepresentation(title: "Home"),
            .volumeDown: DisplayRepresentation(title: "Volume Down"),
            .playPause: DisplayRepresentation(title: "Play/Pause"),
            .volumeUp: DisplayRepresentation(title: "Volume Up"),
            .mute: DisplayRepresentation(title: "Mute"),
            .powerOff: DisplayRepresentation(title: "Power Off")
        ]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .volumeDown:
            return "Vol -"
        case .playPause:
            return "Play"
        case .volumeUp:
            return "Vol +"
        case .mute:
            return "Mute"
        case .powerOff:
            return "Off"
        }
    }

    var symbol: String {
        switch self {
        case .home:
            return "house.fill"
        case .volumeDown:
            return "speaker.minus.fill"
        case .playPause:
            return "playpause.fill"
        case .volumeUp:
            return "speaker.plus.fill"
        case .mute:
            return "speaker.slash.fill"
        case .powerOff:
            return "power"
        }
    }

}

private struct PulseRemoteEntry: TimelineEntry {
    let date: Date
}

private enum PulseWidgetLayout {
    static let smallCommands: [PulseWidgetCommand] = [.volumeDown, .playPause, .volumeUp, .powerOff]
    static let mediumCommands: [PulseWidgetCommand] = [.home, .volumeDown, .playPause, .volumeUp, .mute, .powerOff]
    static let lockScreenCommands: [PulseWidgetCommand] = [.volumeDown, .playPause, .volumeUp, .mute, .powerOff]
}

private struct PulseRemoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseRemoteEntry {
        PulseRemoteEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseRemoteEntry) -> Void) {
        completion(PulseRemoteEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseRemoteEntry>) -> Void) {
        let now = Date()
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [PulseRemoteEntry(date: now)], policy: .after(refresh)))
    }
}

private struct PulseRemoteWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PulseRemoteEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        case .accessoryInline:
            lockScreenInlineWidget
        case .accessoryCircular:
            lockScreenCircularWidget
        case .accessoryRectangular:
            lockScreenWidget
        default:
            mediumWidget
        }
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                ForEach(PulseWidgetLayout.smallCommands) { command in
                    quickCommandChip(command)
                }
            }
        }
        .padding(12)
        .widgetCardBackground
    }

    private var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            Text("Quick Controls")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.84))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(PulseWidgetLayout.mediumCommands) { command in
                    quickCommandChip(command)
                }
            }
        }
        .padding(14)
        .widgetCardBackground
    }

    private var lockScreenWidget: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text("Pulse Remote")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("TV")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.70))
            }
            HStack(spacing: 0) {
                ForEach(PulseWidgetLayout.lockScreenCommands) { command in
                    lockActionGlyph(command, isAccent: command == .playPause || command == .powerOff)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10.5)
        .padding(.vertical, 8)
        .widgetCardBackground
    }

    private var lockScreenInlineWidget: some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
            Text("Pulse Remote")
                .fontWeight(.semibold)
            Image(systemName: "playpause.fill")
        }
        .widgetAccentable()
        .widgetCardBackground
    }

    private var lockScreenCircularWidget: some View {
        Button(intent: PulseRemoteWidgetCommandIntent(command: .playPause)) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.20, green: 0.23, blue: 0.35),
                                Color(red: 0.12, green: 0.14, blue: 0.26)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "playpause.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .widgetCardBackground
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.98, green: 0.29, blue: 0.53), Color(red: 0.99, green: 0.49, blue: 0.73)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)

            Text("Pulse Remote")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()
        }
    }

    private func quickCommandChip(_ command: PulseWidgetCommand) -> some View {
        Button(intent: PulseRemoteWidgetCommandIntent(command: command)) {
            VStack(spacing: 4) {
                Image(systemName: command.symbol)
                    .font(.system(size: 15.5, weight: .bold))
                Text(command.title)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func lockActionGlyph(_ command: PulseWidgetCommand, isAccent: Bool = false) -> some View {
        Button(intent: PulseRemoteWidgetCommandIntent(command: command)) {
            ZStack {
                Circle()
                    .fill(
                        isAccent
                            ? Color(red: 0.88, green: 0.20, blue: 0.40)
                            : Color.white.opacity(0.20)
                    )
                    .frame(width: 28, height: 28)

                Image(systemName: command.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    var widgetCardBackground: some View {
        self
    }
}

struct PulseRemoteQuickControlsWidget: Widget {
    let kind = "PulseRemoteQuickControlsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseRemoteProvider()) { entry in
            PulseRemoteWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.11, green: 0.13, blue: 0.24),
                            Color(red: 0.07, green: 0.08, blue: 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Pulse Remote")
        .description("Quick Home, Back, Mute, and Power controls from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

@main
struct PulseRemoteWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PulseRemoteQuickControlsWidget()
    }
}
