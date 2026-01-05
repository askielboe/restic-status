import Foundation

enum SettingsStore {
    private static let userDefaultsKey = "DefaultBackupSettings"

    static var settings: DefaultBackupSettings {
        get {
            guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
                  let settings = try? JSONDecoder().decode(DefaultBackupSettings.self, from: data)
            else {
                return .default
            }
            return settings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
            }
        }
    }

    static func reset() {
        settings = .default
    }
}
