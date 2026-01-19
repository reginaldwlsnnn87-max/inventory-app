import SwiftUI

struct MenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingInfo: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                ScrollView {
                    VStack(spacing: 16) {
                        profileCard
                        menuSection(
                            title: "Workspace",
                            rows: [
                                MenuRow(title: "Workflows", systemImage: "square.stack.3d.up", destination: .workflows),
                                MenuRow(title: "User Profile", systemImage: "person.crop.circle"),
                                MenuRow(title: "Company Details", systemImage: "briefcase"),
                                MenuRow(title: "Addresses", systemImage: "mappin.and.ellipse", badge: "NEW")
                            ]
                        )
                        menuSection(
                            title: "Reports",
                            rows: [
                                MenuRow(title: "Reports", systemImage: "chart.pie"),
                                MenuRow(title: "Bulk Import", systemImage: "tray.and.arrow.down"),
                                MenuRow(title: "Custom Fields", systemImage: "list.bullet.rectangle")
                            ]
                        )
                        menuSection(
                            title: "Labels",
                            rows: [
                                MenuRow(title: "Create Labels", systemImage: "barcode"),
                                MenuRow(title: "Manage Tags", systemImage: "tag"),
                                MenuRow(title: "Sync Inventory", systemImage: "arrow.triangle.2.circlepath")
                            ]
                        )
                        menuSection(
                            title: "Support",
                            rows: [
                                MenuRow(title: "Product News", systemImage: "megaphone", badge: "NEW"),
                                MenuRow(title: "Help & Support", systemImage: "questionmark.circle"),
                                MenuRow(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            ]
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .tint(Theme.accent)
            .alert("Coming soon", isPresented: .init(
                get: { showingInfo != nil },
                set: { if !$0 { showingInfo = nil } }
            )) {
                Button("OK", role: .cancel) {
                    showingInfo = nil
                }
            } message: {
                Text(showingInfo ?? "")
            }
        }
    }

    private var profileCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.accent.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Text("RW")
                        .font(Theme.font(16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("Reginald Wilson")
                    .font(Theme.font(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("reginald@inventory.app")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func menuSection(title: String, rows: [MenuRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    menuRow(row)

                    if row.id != rows.last?.id {
                        Divider()
                            .background(Theme.subtleBorder)
                            .padding(.leading, 48)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.cardBackground.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.subtleBorder, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func menuRow(_ row: MenuRow) -> some View {
        if let destination = row.destination {
            NavigationLink {
                destinationView(destination)
            } label: {
                menuRowLabel(row)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                showingInfo = "\(row.title) will be available soon."
            } label: {
                menuRowLabel(row)
            }
            .buttonStyle(.plain)
        }
    }

    private func menuRowLabel(_ row: MenuRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            Text(row.title)
                .font(Theme.font(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if let badge = row.badge {
                Text(badge)
                    .font(Theme.font(10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.85))
                    )
                    .foregroundStyle(.white)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func destinationView(_ destination: MenuDestination) -> some View {
        switch destination {
        case .workflows:
            WorkflowsView()
        }
    }
}

private struct MenuRow: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    var badge: String? = nil
    var destination: MenuDestination? = nil
}

private enum MenuDestination {
    case workflows
}
