import SwiftUI

private enum AuthMode {
    case signIn
    case signUp
}

struct AuthGateView: View {
    @EnvironmentObject private var authStore: AuthStore

    @State private var mode: AuthMode = .signIn
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var workspaceName = ""
    @State private var role: WorkspaceRole = .owner
    @State private var errorMessage: String?
    @State private var isBiometricSigningIn = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                ScrollView {
                    VStack(spacing: 16) {
                        introCard
                        authCard
                        switchModeCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Inventory Cloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tint(Theme.accent)
            .alert("Unable to continue", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                authStore.refreshBiometricAvailability()
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SaaS-ready inventory for teams.")
                .font(Theme.font(17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Sign in to your workspace to sync roles, workflows, and purchasing decisions.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.56)
    }

    private var authCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode == .signIn ? "Sign In" : "Create Account")
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 2)

            VStack(spacing: 10) {
                if mode == .signUp {
                    field("Full name", text: $fullName)
                }

                field("Email", text: $email, keyboard: .emailAddress, textInputAutocapitalization: .never)

                SecureField(
                    "",
                    text: $password,
                    prompt: Theme.inputPrompt("Password")
                )
                    .inventoryTextInputField()

                if mode == .signUp {
                    field("Workspace name", text: $workspaceName)
                    Picker("Role", selection: $role) {
                        ForEach(WorkspaceRole.allCases) { role in
                            Text(role.title).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Button {
                    submit()
                } label: {
                    Text(mode == .signIn ? "Sign In" : "Create Account")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.55)

                if mode == .signIn && authStore.biometricSignInAvailable {
                    Button {
                        Task {
                            await quickBiometricSignIn()
                        }
                    } label: {
                        HStack {
                            Image(systemName: authStore.biometricType == .faceID ? "faceid" : "touchid")
                            Text(isBiometricSigningIn ? "Authenticating..." : authStore.biometricButtonTitle)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBiometricSigningIn)
                }

                if mode == .signUp {
                    Text("Quick sign-in will be enabled on this device after account creation.")
                        .font(Theme.font(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
            .padding(12)
            .inventoryCard(cornerRadius: 14, emphasis: 0.28)
        }
        .padding(14)
        .inventoryCard(cornerRadius: 16, emphasis: 0.42)
    }

    private var switchModeCard: some View {
        HStack {
            Text(mode == .signIn ? "Need an account?" : "Already have an account?")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button(mode == .signIn ? "Create one" : "Sign in") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    mode = mode == .signIn ? .signUp : .signIn
                    errorMessage = nil
                }
            }
            .font(Theme.font(12, weight: .semibold))
        }
        .padding(14)
        .inventoryCard(cornerRadius: 14, emphasis: 0.22)
    }

    private var canSubmit: Bool {
        switch mode {
        case .signIn:
            return !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .signUp:
            return !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func submit() {
        do {
            switch mode {
            case .signIn:
                try authStore.signIn(email: email, password: password)
            case .signUp:
                try authStore.signUp(
                    fullName: fullName,
                    email: email,
                    password: password,
                    workspaceName: workspaceName,
                    role: role
                )
            }
            Haptics.success()
            clearTransientFields()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Unexpected authentication error."
        }
    }

    private func quickBiometricSignIn() async {
        guard !isBiometricSigningIn else { return }
        isBiometricSigningIn = true
        defer { isBiometricSigningIn = false }

        do {
            try await authStore.signInWithBiometrics()
            Haptics.success()
            clearTransientFields()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Face ID sign-in failed."
        }
    }

    private func clearTransientFields() {
        password = ""
        if mode == .signIn {
            return
        }
        fullName = ""
        workspaceName = ""
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        textInputAutocapitalization: TextInputAutocapitalization = .sentences
    ) -> some View {
        TextField(
            "",
            text: text,
            prompt: Theme.inputPrompt(title)
        )
            .keyboardType(keyboard)
            .textInputAutocapitalization(textInputAutocapitalization)
            .autocorrectionDisabled(keyboard == .emailAddress)
            .inventoryTextInputField()
    }
}
