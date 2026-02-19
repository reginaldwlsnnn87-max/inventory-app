import Foundation

struct TVWidgetCommandContext: Codable, Equatable {
    let deviceID: String
    let ip: String
    let port: Int
    let secure: Bool
    let clientKey: String
    let updatedAt: Date
}

enum TVWidgetCommandContextConstants {
    static let keychainService = "com.reggieboi.pulseremote.tvremote.widget-context"
    static let keychainAccount = "tvremote.widget.context.v1"
}

struct TVWidgetCommandContextStore {
    private let keychain: KeychainStore
    private let account: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        keychain: KeychainStore = KeychainStore(
            service: TVWidgetCommandContextConstants.keychainService
        ),
        account: String = TVWidgetCommandContextConstants.keychainAccount
    ) {
        self.keychain = keychain
        self.account = account
    }

    func save(_ context: TVWidgetCommandContext) throws {
        let data = try encoder.encode(context)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        try keychain.set(raw, for: account)
    }

    func load() throws -> TVWidgetCommandContext? {
        guard let raw = try keychain.string(for: account) else { return nil }
        guard let data = raw.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        return try decoder.decode(TVWidgetCommandContext.self, from: data)
    }

    func clear() throws {
        try keychain.removeValue(for: account)
    }
}
