import Foundation
import StoreKit

struct TVPremiumProduct: Identifiable, Equatable {
    let id: String
    let title: String
    let price: String
    let subtitle: String
    let isFeatured: Bool
}

enum TVPremiumPurchaseResult: Equatable {
    case purchased(productID: String)
    case pending
    case userCancelled
}

enum TVPremiumBillingError: LocalizedError {
    case productCatalogMissing
    case productUnavailable(productID: String)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .productCatalogMissing:
            return "Pro products are not configured yet. Add product IDs in App Store Connect."
        case let .productUnavailable(productID):
            return "Could not load product: \(productID)."
        case .verificationFailed:
            return "Could not verify App Store purchase."
        }
    }
}

@MainActor
final class TVPremiumBillingService {
    var onEntitlementsChanged: ((Set<String>) -> Void)?

    private let configuredProductIDs: [String]
    private var productsByID: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?

    init(bundle: Bundle = .main, productIDs: [String]? = nil) {
        configuredProductIDs = Self.resolveProductIDs(bundle: bundle, productIDs: productIDs)
    }

    func start() {
        guard updatesTask == nil else { return }

        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                await self.handleTransactionUpdate(update)
            }
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    func loadProducts() async throws -> [TVPremiumProduct] {
        guard !configuredProductIDs.isEmpty else {
            throw TVPremiumBillingError.productCatalogMissing
        }

        let products = try await Product.products(for: configuredProductIDs)
        productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

        return products
            .sorted(by: Self.sortProducts)
            .map { product in
                let order = Self.sortRank(for: product)
                return TVPremiumProduct(
                    id: product.id,
                    title: product.displayName,
                    price: product.displayPrice,
                    subtitle: Self.subtitle(for: product),
                    isFeatured: order == 0
                )
            }
    }

    func purchase(productID: String) async throws -> TVPremiumPurchaseResult {
        let product = try await resolveProduct(productID: productID)
        let result = try await product.purchase()

        switch result {
        case let .success(verification):
            let transaction = try Self.requireVerified(verification)
            await transaction.finish()
            let entitlements = await currentEntitlementProductIDs()
            onEntitlementsChanged?(entitlements)
            return .purchased(productID: transaction.productID)
        case .pending:
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            return .userCancelled
        }
    }

    @discardableResult
    func restorePurchases() async throws -> Bool {
        try await AppStore.sync()
        let entitlements = await currentEntitlementProductIDs()
        onEntitlementsChanged?(entitlements)
        return !entitlements.isEmpty
    }

    @discardableResult
    func syncCurrentEntitlements() async -> Set<String> {
        let entitlements = await currentEntitlementProductIDs()
        onEntitlementsChanged?(entitlements)
        return entitlements
    }

    private func resolveProduct(productID: String) async throws -> Product {
        if let cached = productsByID[productID] {
            return cached
        }

        let loaded = try await Product.products(for: [productID])
        guard let product = loaded.first else {
            throw TVPremiumBillingError.productUnavailable(productID: productID)
        }
        productsByID[productID] = product
        return product
    }

    private func currentEntitlementProductIDs() async -> Set<String> {
        var productIDs = Set<String>()

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else {
                continue
            }

            if let expirationDate = transaction.expirationDate, expirationDate < Date() {
                continue
            }

            if transaction.revocationDate != nil {
                continue
            }

            if transaction.isUpgraded {
                continue
            }

            productIDs.insert(transaction.productID)
        }

        return productIDs
    }

    private func handleTransactionUpdate(_ update: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = update else {
            return
        }

        await transaction.finish()
        let entitlements = await currentEntitlementProductIDs()
        onEntitlementsChanged?(entitlements)
    }

    private static func requireVerified<T>(_ result: VerificationResult<T>) throws -> T {
        guard case let .verified(payload) = result else {
            throw TVPremiumBillingError.verificationFailed
        }
        return payload
    }

    private static func resolveProductIDs(bundle: Bundle, productIDs: [String]?) -> [String] {
        let configured = productIDs ?? (bundle.object(forInfoDictionaryKey: "TVPremiumProductIDs") as? [String])
        let fallback = [
            "com.reggieboi.pulseremote.pro.yearly",
            "com.reggieboi.pulseremote.pro.monthly",
            "com.reggieboi.pulseremote.pro.lifetime"
        ]

        let source = (configured?.isEmpty == false ? configured : nil) ?? fallback
        var seen = Set<String>()

        return source
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func sortProducts(_ lhs: Product, _ rhs: Product) -> Bool {
        let lhsOrder = sortRank(for: lhs)
        let rhsOrder = sortRank(for: rhs)
        if lhsOrder != rhsOrder {
            return lhsOrder < rhsOrder
        }
        return lhs.displayPrice.localizedCaseInsensitiveCompare(rhs.displayPrice) == .orderedAscending
    }

    private static func sortRank(for product: Product) -> Int {
        let identifier = product.id.lowercased()
        if identifier.contains("year") || identifier.contains("annual") {
            return 0
        }
        if identifier.contains("month") {
            return 1
        }
        if identifier.contains("life") || identifier.contains("forever") || identifier.contains("one") {
            return 2
        }
        return 3
    }

    private static func subtitle(for product: Product) -> String {
        if let subscription = product.subscription {
            let period = subscription.subscriptionPeriod
            let unitLabel: String
            switch period.unit {
            case .day:
                unitLabel = period.value == 1 ? "day" : "days"
            case .week:
                unitLabel = period.value == 1 ? "week" : "weeks"
            case .month:
                unitLabel = period.value == 1 ? "month" : "months"
            case .year:
                unitLabel = period.value == 1 ? "year" : "years"
            @unknown default:
                unitLabel = "period"
            }
            return "Renews every \(period.value) \(unitLabel)"
        }

        if product.type == .nonConsumable {
            return "One-time unlock"
        }
        return "In-app purchase"
    }
}
