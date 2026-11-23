import Foundation

struct RememberedBLEDevice: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    /// Stable persistence identifier, independent of the user-facing picker label.
    var protocolIdentifier: String
    var selection: BLEProtocolSelection { protocolIdentifier == "ditoo-plus-rcsp" ? .ditooPlusRCSP : .diagnostic }

    init(id: UUID, name: String, selection: BLEProtocolSelection) {
        self.id = id
        self.name = name
        protocolIdentifier = selection == .ditooPlusRCSP ? "ditoo-plus-rcsp" : "diagnostic"
    }
}

struct BLEAutomaticPreferences: Equatable, Sendable {
    var enabled = true
    var device: RememberedBLEDevice?
    var mayReconnect: Bool { enabled && device != nil }

    private static let enabledKey = "bluetooth.automaticConnection.enabled"
    private static let deviceKey = "bluetooth.automaticConnection.rememberedDevice"

    static func load(from defaults: UserDefaults) -> Self {
        let enabled = defaults.object(forKey: enabledKey) == nil ? true : defaults.bool(forKey: enabledKey)
        let device = defaults.data(forKey: deviceKey).flatMap { try? JSONDecoder().decode(RememberedBLEDevice.self, from: $0) }
        return Self(enabled: enabled, device: device)
    }
    func save(to defaults: UserDefaults) {
        defaults.set(enabled, forKey: Self.enabledKey)
        if let device, let data = try? JSONEncoder().encode(device) { defaults.set(data, forKey: Self.deviceKey) }
        else { defaults.removeObject(forKey: Self.deviceKey) }
    }
    func allowsRestoration(of id: UUID) -> Bool { mayReconnect && device?.id == id }
}

/// Actual failures back off; an OS-pending connect has no repeated timeout/retry loop.
struct BLEReconnectBackoff: Sendable {
    private(set) var failureCount = 0
    mutating func nextDelay() -> TimeInterval {
        let delays: [TimeInterval] = [1, 2, 4, 8, 15, 30, 60]
        let delay = delays[min(failureCount, delays.count - 1)]
        failureCount = min(failureCount + 1, delays.count - 1)
        return delay
    }
    mutating func reset() { failureCount = 0 }
}
