import Foundation

extension Notification.Name {
    static let profilesDidChange = Notification.Name("profilesDidChange")
    static let profileWillChange = Notification.Name("profileWillChange")
}

enum ProfileStore {
    private static let userDefaultsKey = "Profiles"

    static var profiles: [Profile] {
        get {
            guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
                  let profiles = try? JSONDecoder().decode([Profile].self, from: data)
            else {
                return []
            }
            return profiles
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
            }
            NotificationCenter.default.post(name: .profilesDidChange, object: nil)
        }
    }

    static func add(_ profile: Profile) {
        var current = profiles
        current.append(profile)
        profiles = current
        updateLaunchAgent(for: profile)
    }

    static func remove(id: UUID) {
        NotificationCenter.default.post(name: .profileWillChange, object: id)
        var current = profiles
        current.removeAll { $0.id == id }
        profiles = current
        removeLaunchAgent(for: id)
    }

    static func update(_ profile: Profile) {
        NotificationCenter.default.post(name: .profileWillChange, object: profile.id)
        var current = profiles
        if let index = current.firstIndex(where: { $0.id == profile.id }) {
            current[index] = profile
            profiles = current
            updateLaunchAgent(for: profile)
        }
    }

    private static func updateLaunchAgent(for profile: Profile) {
        do {
            try LaunchAgentManager.installAgent(for: profile)
        } catch {
            print("Failed to update launch agent for \(profile.name): \(error)")
        }
    }

    private static func removeLaunchAgent(for profileId: UUID) {
        do {
            try LaunchAgentManager.uninstallAgent(for: profileId)
        } catch {
            print("Failed to remove launch agent: \(error)")
        }
    }
}
