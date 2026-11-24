import Foundation

struct RememberedRFCOMMDevice: Codable, Equatable, Sendable {
    let address: String
    let name: String
    let channel: UInt8

    var validated: Self? {
        guard let address = RFCOMMConnectionPreferences.normalizedAddress(address), (1...30).contains(channel) else { return nil }
        return Self(address: address, name: name, channel: channel)
    }
}

struct RFCOMMConnectionPreferences: Equatable, Sendable {
    var enabled = true
    var device: RememberedRFCOMMDevice?
    var mayReconnect: Bool { enabled && device?.validated != nil }

    private static let enabledKey = "mac.bluetooth.automaticConnection.enabled"
    private static let deviceKey = "mac.bluetooth.automaticConnection.successfulDevice"

    static func load(from defaults: UserDefaults) -> Self {
        let enabled = defaults.object(forKey: enabledKey) == nil ? true : defaults.bool(forKey: enabledKey)
        let device = defaults.data(forKey: deviceKey)
            .flatMap { try? JSONDecoder().decode(RememberedRFCOMMDevice.self, from: $0) }?.validated
        return Self(enabled: enabled, device: device)
    }
    func save(to defaults: UserDefaults) {
        defaults.set(enabled, forKey: Self.enabledKey)
        if let device = device?.validated, let encoded = try? JSONEncoder().encode(device) {
            defaults.set(encoded, forKey: Self.deviceKey)
        } else { defaults.removeObject(forKey: Self.deviceKey) }
    }
    static func normalizedAddress(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: ":").uppercased()
        let parts = normalized.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6, parts.allSatisfy({ $0.count == 2 && UInt8($0, radix: 16) != nil }) else { return nil }
        return normalized
    }
}

struct RFCOMMReconnectBackoff: Sendable {
    private(set) var failureCount = 0
    mutating func nextDelay() -> TimeInterval {
        let delays: [TimeInterval] = [1, 2, 4, 8, 15, 30, 60]
        let delay = delays[min(failureCount, delays.count - 1)]
        failureCount = min(failureCount + 1, delays.count - 1)
        return delay
    }
    mutating func reset() { failureCount = 0 }
}

/// Every open gets an immutable delegate epoch. A late callback must match BOTH the
/// connection attempt and channel object before it may mutate the controller or a write.
struct RFCOMMCallbackScope: Sendable {
    let epoch: UUID
    let channelID: ObjectIdentifier
    func isCurrent(epoch: UUID, channelID: ObjectIdentifier) -> Bool {
        self.epoch == epoch && self.channelID == channelID
    }
}
