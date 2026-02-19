import Foundation

protocol TVKeyValueStore: AnyObject {
    func data(forKey defaultName: String) -> Data?
    func string(forKey defaultName: String) -> String?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: TVKeyValueStore {}

@MainActor
final class KnownDevicesStore {
    private let storage: TVKeyValueStore
    private let devicesStorageKey: String
    private let lastConnectedIDStorageKey: String

    init(
        defaults: UserDefaults = .standard,
        devicesStorageKey: String = "tvremote.known_devices.v1",
        lastConnectedIDStorageKey: String = "tvremote.last_connected_device_id.v1"
    ) {
        self.storage = defaults
        self.devicesStorageKey = devicesStorageKey
        self.lastConnectedIDStorageKey = lastConnectedIDStorageKey
    }

    init(
        storage: TVKeyValueStore,
        devicesStorageKey: String = "tvremote.known_devices.v1",
        lastConnectedIDStorageKey: String = "tvremote.last_connected_device_id.v1"
    ) {
        self.storage = storage
        self.devicesStorageKey = devicesStorageKey
        self.lastConnectedIDStorageKey = lastConnectedIDStorageKey
    }

    func loadDevices() -> [TVDevice] {
        guard let data = storage.data(forKey: devicesStorageKey) else { return [] }
        guard let devices = try? JSONDecoder().decode([TVDevice].self, from: data) else { return [] }
        return devices.sorted(by: Self.sortRule)
    }

    func saveDevices(_ devices: [TVDevice]) {
        let sorted = devices.sorted(by: Self.sortRule)
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        storage.set(data, forKey: devicesStorageKey)
    }

    func upsert(_ device: TVDevice) {
        var existing = loadDevices()
        if let index = existing.firstIndex(where: { $0.id == device.id }) {
            var merged = device
            if merged.lastConnectedAt == nil {
                merged.lastConnectedAt = existing[index].lastConnectedAt
            }
            if merged.wakeMACAddress == nil {
                merged.wakeMACAddress = existing[index].wakeMACAddress
            }
            existing[index] = merged
        } else {
            existing.append(device)
        }
        saveDevices(existing)
    }

    func markConnected(_ device: TVDevice) {
        var connectedDevice = device
        connectedDevice.lastConnectedAt = Date()
        upsert(connectedDevice)
        storage.set(connectedDevice.id, forKey: lastConnectedIDStorageKey)
    }

    func lastConnectedDevice() -> TVDevice? {
        let devices = loadDevices()
        if let lastID = storage.string(forKey: lastConnectedIDStorageKey),
           let exactMatch = devices.first(where: { $0.id == lastID }) {
            return exactMatch
        }
        return devices.first
    }

    private static func sortRule(lhs: TVDevice, rhs: TVDevice) -> Bool {
        switch (lhs.lastConnectedAt, rhs.lastConnectedAt) {
        case let (leftDate?, rightDate?):
            if leftDate != rightDate {
                return leftDate > rightDate
            }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
