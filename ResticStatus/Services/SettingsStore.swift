import Foundation

enum SettingsStore {
    private static let userDefaultsKey = "DefaultBackupSettings"

    static var settings: DefaultBackupSettings {
        get {
            guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
                  var settings = try? JSONDecoder().decode(DefaultBackupSettings.self, from: data)
            else {
                return .default
            }

            var changed = false
            if settings.resticprofilePath.isEmpty,
               let path = DefaultBackupSettings.discoverResticprofilePath()
            {
                settings.resticprofilePath = path
                changed = true
            }
            if settings.configPath.isEmpty,
               let path = DefaultBackupSettings.discoverConfigPath(resticprofilePath: settings.resticprofilePath)
            {
                settings.configPath = path
                changed = true
            }
            if changed {
                self.settings = settings
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
