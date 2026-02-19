import Foundation
import Combine
import LocalAuthentication

enum WorkspaceRole: String, Codable, CaseIterable, Identifiable {
    case owner
    case manager
    case staff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .owner:
            return "Owner"
        case .manager:
            return "Manager"
        case .staff:
            return "Staff"
        }
    }

    var canManageCatalog: Bool {
        switch self {
        case .owner, .manager:
            return true
        case .staff:
            return false
        }
    }

    var canDeleteItems: Bool {
        self == .owner
    }

    var canManageWorkspace: Bool {
        self == .owner
    }
}

struct WorkspaceMembership: Identifiable, Codable, Hashable {
    let id: UUID
    var workspaceID: UUID
    var workspaceName: String
    var role: WorkspaceRole
}

struct AuthAccount: Identifiable, Codable, Hashable {
    let id: UUID
    var fullName: String
    var email: String
    var password: String
    var memberships: [WorkspaceMembership]
}

private struct AuthSession: Codable, Hashable {
    var accountID: UUID
    var activeWorkspaceID: UUID
}

enum AuthStoreError: LocalizedError {
    case missingFields
    case emailInUse
    case invalidCredentials
    case workspaceMissing
    case biometricUnavailable
    case biometricAuthFailed

    var errorDescription: String? {
        switch self {
        case .missingFields:
            return "Please fill in all required fields."
        case .emailInUse:
            return "This email is already in use."
        case .invalidCredentials:
            return "Invalid email or password."
        case .workspaceMissing:
            return "No workspace is available for this account."
        case .biometricUnavailable:
            return "Face ID quick sign-in is not set up on this device yet."
        case .biometricAuthFailed:
            return "Face ID authentication was not successful."
        }
    }
}

enum AuthBiometricType: Equatable {
    case none
    case faceID
    case touchID

    var title: String {
        switch self {
        case .none:
            return "Biometric"
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        }
    }
}

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var accounts: [AuthAccount] = []
    @Published private(set) var currentAccount: AuthAccount?
    @Published private(set) var activeWorkspaceID: UUID?
    @Published private(set) var biometricType: AuthBiometricType = .none
    @Published private(set) var biometricSignInAvailable = false

    private let defaults: UserDefaults
    private let accountsKey = "inventory.auth.accounts.v1"
    private let sessionKey = "inventory.auth.session.v1"
    private let biometricCredentialStore = AuthBiometricCredentialStore(
        service: "com.reggieboi.pulseremote.auth-biometric.v1"
    )

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        refreshBiometricAvailability()
    }

    var isAuthenticated: Bool {
        currentAccount != nil && activeWorkspaceID != nil
    }

    var memberships: [WorkspaceMembership] {
        currentAccount?.memberships ?? []
    }

    var activeMembership: WorkspaceMembership? {
        guard let activeWorkspaceID else { return nil }
        return memberships.first(where: { $0.workspaceID == activeWorkspaceID })
    }

    var displayName: String {
        currentAccount?.fullName ?? "Guest"
    }

    var email: String {
        currentAccount?.email ?? ""
    }

    var currentRole: WorkspaceRole {
        activeMembership?.role ?? .staff
    }

    var activeWorkspaceName: String {
        activeMembership?.workspaceName ?? "No Workspace"
    }

    var canManageCatalog: Bool {
        currentRole.canManageCatalog
    }

    var canManagePurchasing: Bool {
        currentRole.canManageCatalog
    }

    var canDeleteItems: Bool {
        currentRole.canDeleteItems
    }

    var canManageWorkspace: Bool {
        currentRole.canManageWorkspace
    }

    var biometricButtonTitle: String {
        "Sign in with \(biometricType.title)"
    }

    func signUp(
        fullName: String,
        email: String,
        password: String,
        workspaceName: String,
        role: WorkspaceRole = .owner,
        enableBiometricSignIn: Bool = true
    ) throws {
        let normalizedFullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWorkspaceName = workspaceName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedFullName.isEmpty,
              !normalizedEmail.isEmpty,
              !normalizedPassword.isEmpty,
              !normalizedWorkspaceName.isEmpty else {
            throw AuthStoreError.missingFields
        }

        guard !accounts.contains(where: { $0.email == normalizedEmail }) else {
            throw AuthStoreError.emailInUse
        }

        let workspaceID = UUID()
        let membership = WorkspaceMembership(
            id: UUID(),
            workspaceID: workspaceID,
            workspaceName: normalizedWorkspaceName,
            role: role
        )

        let account = AuthAccount(
            id: UUID(),
            fullName: normalizedFullName,
            email: normalizedEmail,
            password: normalizedPassword,
            memberships: [membership]
        )

        accounts.append(account)
        persistAccounts()
        setSession(accountID: account.id, activeWorkspaceID: workspaceID)
        if enableBiometricSignIn {
            _ = biometricCredentialStore.save(email: normalizedEmail, password: normalizedPassword)
        }
        refreshBiometricAvailability()
    }

    func signIn(
        email: String,
        password: String,
        enableBiometricSignIn: Bool = true
    ) throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let account = accounts.first(where: {
            $0.email == normalizedEmail && $0.password == normalizedPassword
        }) else {
            throw AuthStoreError.invalidCredentials
        }

        guard let workspaceID = account.memberships.first?.workspaceID else {
            throw AuthStoreError.workspaceMissing
        }

        setSession(accountID: account.id, activeWorkspaceID: workspaceID)
        if enableBiometricSignIn {
            _ = biometricCredentialStore.save(email: normalizedEmail, password: normalizedPassword)
        }
        refreshBiometricAvailability()
    }

    func signOut() {
        activeWorkspaceID = nil
        currentAccount = nil
        defaults.removeObject(forKey: sessionKey)
        refreshBiometricAvailability()
    }

    func resetForUITesting() {
        accounts = []
        currentAccount = nil
        activeWorkspaceID = nil
        defaults.removeObject(forKey: accountsKey)
        defaults.removeObject(forKey: sessionKey)
        biometricCredentialStore.remove()
        refreshBiometricAvailability()
    }

    func switchWorkspace(to workspaceID: UUID) {
        guard let account = currentAccount,
              account.memberships.contains(where: { $0.workspaceID == workspaceID }) else {
            return
        }
        setSession(accountID: account.id, activeWorkspaceID: workspaceID)
    }

    func createWorkspace(name: String, role: WorkspaceRole = .owner) throws {
        guard var account = currentAccount else { return }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw AuthStoreError.missingFields }

        let newMembership = WorkspaceMembership(
            id: UUID(),
            workspaceID: UUID(),
            workspaceName: normalized,
            role: role
        )
        account.memberships.append(newMembership)
        replaceAccount(account)
        setSession(accountID: account.id, activeWorkspaceID: newMembership.workspaceID)
    }

    func belongsToActiveWorkspace(_ itemWorkspaceID: String) -> Bool {
        guard let activeWorkspaceID else { return true }
        let trimmed = itemWorkspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        return trimmed == activeWorkspaceID.uuidString
    }

    func activeWorkspaceIDString() -> String {
        activeWorkspaceID?.uuidString ?? ""
    }

    func disableBiometricSignIn() {
        biometricCredentialStore.remove()
        refreshBiometricAvailability()
    }

    func refreshBiometricAvailability() {
        let hasSavedCredential = biometricCredentialStore.load() != nil

        let context = LAContext()
        var error: NSError?
        let canUseBiometrics = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )

        if canUseBiometrics {
            switch context.biometryType {
            case .faceID:
                biometricType = .faceID
            case .touchID:
                biometricType = .touchID
            default:
                biometricType = .none
            }
        } else {
            biometricType = .none
        }

        biometricSignInAvailable = hasSavedCredential && canUseBiometrics
    }

    func signInWithBiometrics() async throws {
        guard biometricSignInAvailable,
              let credential = biometricCredentialStore.load() else {
            throw AuthStoreError.biometricUnavailable
        }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) else {
            refreshBiometricAvailability()
            throw AuthStoreError.biometricUnavailable
        }

        let reason = "Quickly sign in to your inventory workspace."
        let didAuthenticate = try await evaluateBiometricPolicy(context: context, reason: reason)
        guard didAuthenticate else {
            throw AuthStoreError.biometricAuthFailed
        }

        do {
            try signIn(
                email: credential.email,
                password: credential.password,
                enableBiometricSignIn: false
            )
        } catch AuthStoreError.invalidCredentials {
            biometricCredentialStore.remove()
            refreshBiometricAvailability()
            throw AuthStoreError.invalidCredentials
        }
    }

    private func setSession(accountID: UUID, activeWorkspaceID: UUID) {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        currentAccount = account
        self.activeWorkspaceID = activeWorkspaceID
        persistSession(AuthSession(accountID: accountID, activeWorkspaceID: activeWorkspaceID))
    }

    private func evaluateBiometricPolicy(
        context: LAContext,
        reason: String
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: success)
            }
        }
    }

    private func replaceAccount(_ updated: AuthAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == updated.id }) else { return }
        accounts[index] = updated
        persistAccounts()
        currentAccount = updated
    }

    private func persistAccounts() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(accounts) else { return }
        defaults.set(data, forKey: accountsKey)
    }

    private func persistSession(_ session: AuthSession) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(session) else { return }
        defaults.set(data, forKey: sessionKey)
    }

    private func load() {
        let decoder = JSONDecoder()

        if let accountsData = defaults.data(forKey: accountsKey),
           let decodedAccounts = try? decoder.decode([AuthAccount].self, from: accountsData) {
            accounts = decodedAccounts
        } else {
            accounts = []
        }

        if let sessionData = defaults.data(forKey: sessionKey),
           let session = try? decoder.decode(AuthSession.self, from: sessionData),
           let account = accounts.first(where: { $0.id == session.accountID }),
           account.memberships.contains(where: { $0.workspaceID == session.activeWorkspaceID }) {
            currentAccount = account
            activeWorkspaceID = session.activeWorkspaceID
        } else {
            currentAccount = nil
            activeWorkspaceID = nil
        }

        refreshBiometricAvailability()
    }
}
