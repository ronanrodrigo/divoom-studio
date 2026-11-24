import Foundation

/// Local draft and whether it was explicitly forwarded; never device readback.
struct MacAlarmPreferences: Equatable {
    var time: Date
    var enabled: Bool
    var weekdays: UInt8
    var volume: Double
    var configured: Bool

    static func load(from defaults: UserDefaults) -> Self {
        let legacyTime = defaults.object(forKey: "alarm.configuredTime") as? Date
        let rawVolume = defaults.object(forKey: "alarm.volume") as? Double ?? 50
        let days = defaults.object(forKey: "alarm.weekdays") as? Int ?? 0x3E
        return Self(time: defaults.object(forKey: "alarm.time") as? Date ?? legacyTime ?? Date(),
                    enabled: defaults.object(forKey: "alarm.enabled") as? Bool ?? defaults.bool(forKey: "alarm.configuredEnabled"),
                    weekdays: UInt8(clamping: days) & 0x7F,
                    volume: rawVolume.isFinite ? min(100, max(0, rawVolume)) : 50,
                    configured: defaults.object(forKey: "alarm.configured") as? Bool ?? (legacyTime != nil))
    }

    func save(to defaults: UserDefaults) {
        defaults.set(time, forKey: "alarm.time")
        defaults.set(enabled, forKey: "alarm.enabled")
        defaults.set(Int(weekdays & 0x7F), forKey: "alarm.weekdays")
        defaults.set(volume.isFinite ? min(100, max(0, volume)) : 50, forKey: "alarm.volume")
        defaults.set(configured, forKey: "alarm.configured")
    }
}
