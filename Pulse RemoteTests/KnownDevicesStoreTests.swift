import XCTest
@testable import inventory_app

private final class InMemoryKeyValueStore: TVKeyValueStore {
    private var values: [String: Any] = [:]

    func data(forKey defaultName: String) -> Data? {
        values[defaultName] as? Data
    }

    func string(forKey defaultName: String) -> String? {
        values[defaultName] as? String
    }

    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }
}

final class KnownDevicesStoreTests: XCTestCase {
    func testMarkConnectedPersistsAndPromotesLastConnectedDevice() async {
        await MainActor.run {
            let storage = InMemoryKeyValueStore()
            let keySeed = "tvremote.tests.persistence.\(UUID().uuidString)"
            let devicesKey = "\(keySeed).devices"
            let lastConnectedKey = "\(keySeed).last_connected"

            let store = KnownDevicesStore(
                storage: storage,
                devicesStorageKey: devicesKey,
                lastConnectedIDStorageKey: lastConnectedKey
            )
            let older = TVDevice.manualLG(ip: "192.168.1.40")
            let newer = TVDevice.manualLG(ip: "192.168.1.41")

            store.upsert(older)
            store.upsert(newer)
            store.markConnected(older)

            let all = store.loadDevices()
            XCTAssertEqual(all.count, 2)
            XCTAssertEqual(store.lastConnectedDevice()?.id, older.id)
        }
    }

    func testUpsertUpdatesExistingRecordWithoutDroppingLastConnectedDate() async {
        await MainActor.run {
            let storage = InMemoryKeyValueStore()
            let keySeed = "tvremote.tests.upsert.\(UUID().uuidString)"
            let devicesKey = "\(keySeed).devices"
            let lastConnectedKey = "\(keySeed).last_connected"

            let store = KnownDevicesStore(
                storage: storage,
                devicesStorageKey: devicesKey,
                lastConnectedIDStorageKey: lastConnectedKey
            )
            let base = TVDevice(
                id: "lg-living-room",
                name: "Living Room TV",
                ip: "192.168.1.50",
                manufacturer: "LG",
                model: "C3",
                capabilities: Set(TVCapability.allCases),
                port: 3000,
                lastConnectedAt: Date()
            )

            store.upsert(base)

            var refreshed = base
            refreshed.name = "Living Room OLED"
            refreshed.lastConnectedAt = nil
            store.upsert(refreshed)

            let stored = store.loadDevices()
            XCTAssertEqual(stored.count, 1)
            XCTAssertEqual(stored.first?.name, "Living Room OLED")
            XCTAssertNotNil(stored.first?.lastConnectedAt)
        }
    }
}
