import SwiftUI

struct RepeatingCommandButton<Label: View>: View {
    let initialDelayNanoseconds: UInt64
    let repeatDelayNanoseconds: UInt64
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var repeatTask: Task<Void, Never>?

    init(
        initialDelayNanoseconds: UInt64 = 210_000_000,
        repeatDelayNanoseconds: UInt64 = 115_000_000,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.initialDelayNanoseconds = initialDelayNanoseconds
        self.repeatDelayNanoseconds = repeatDelayNanoseconds
        self.action = action
        self.label = label
    }

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            label()
        }
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: 36,
            pressing: handlePressing(_:),
            perform: {}
        )
        .onDisappear {
            stopRepeating()
        }
    }

    private func handlePressing(_ pressing: Bool) {
        if pressing {
            startRepeating()
        } else {
            stopRepeating()
        }
    }

    private func startRepeating() {
        guard repeatTask == nil else { return }
        repeatTask = Task {
            try? await Task.sleep(nanoseconds: initialDelayNanoseconds)
            while !Task.isCancelled {
                await MainActor.run {
                    Haptics.tap()
                    action()
                }
                try? await Task.sleep(nanoseconds: repeatDelayNanoseconds)
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}
