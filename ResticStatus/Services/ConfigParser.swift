import Foundation
import Yams

enum ConfigParser {
    static let defaultConfigPath = NSString(string: "~/.config/restic/profiles.yaml").expandingTildeInPath

    static func parseResticProfiles(from configPath: String = defaultConfigPath) throws -> [ResticProfile] {
        guard !configPath.isEmpty else {
            return []
        }
        let url = URL(fileURLWithPath: configPath)
        let yamlString = try String(contentsOf: url, encoding: .utf8)

        guard let yaml = try Yams.load(yaml: yamlString) as? [String: Any] else {
            throw ConfigError.invalidFormat
        }

        var profiles: [ResticProfile] = []

        for (key, value) in yaml {
            guard let profileConfig = value as? [String: Any] else { continue }

            if profileConfig["backup"] is [String: Any] {
                let profile = ResticProfile(
                    id: key,
                    name: key,
                    configPath: configPath
                )
                profiles.append(profile)
            }
        }

        return profiles.sorted { $0.name < $1.name }
    }

    enum ConfigError: Error {
        case invalidFormat
        case fileNotFound
    }
}
