import Foundation

struct DefaultBackupSettings: Equatable {
    var cleanupCache: Bool
    var excludeCaches: Bool
    var oneFileSystem: Bool
    var unlockBeforeBackup: Bool
    var resticprofilePath: String
    var configPath: String
    var maxConcurrentBackups: Int

    static let `default` = DefaultBackupSettings(
        cleanupCache: true,
        excludeCaches: true,
        oneFileSystem: true,
        unlockBeforeBackup: false,
        resticprofilePath: discoverResticprofilePath() ?? "",
        configPath: discoverConfigPath() ?? "",
        maxConcurrentBackups: 1
    )

    static func discoverResticprofilePath() -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        var searchPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(homeDir)/.nix-profile/bin",
            "/run/current-system/sw/bin",
            "/nix/var/nix/profiles/default/bin",
        ]

        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            searchPaths.append(contentsOf: pathEnv.split(separator: ":").map(String.init))
        }

        for dir in searchPaths {
            let candidate = (dir as NSString).appendingPathComponent("resticprofile")
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    static func discoverConfigPath(resticprofilePath: String? = nil) -> String? {
        // Try resticprofile -v show first
        let execPath = resticprofilePath ?? discoverResticprofilePath()
        if let execPath = execPath, !execPath.isEmpty {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: execPath)
            process.arguments = ["-v", "show"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            if let _ = try? process.run() {
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    for line in output.components(separatedBy: .newlines) {
                        if line.contains("loading:") {
                            let parts = line.components(separatedBy: "loading:")
                            if parts.count > 1 {
                                return parts[1].trimmingCharacters(in: .whitespaces)
                            }
                        }
                    }
                }
            }
        }

        // Fall back to checking common config locations
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let configNames = ["profiles.yaml", "profiles.yml", "profiles.toml", "profiles.conf"]
        let searchDirs = [
            "\(homeDir)/.config/resticprofile",
            "\(homeDir)/.config/restic",
        ]

        for dir in searchDirs {
            for name in configNames {
                let candidate = (dir as NSString).appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate) {
                    return candidate
                }
            }
        }

        return nil
    }

    enum CodingKeys: String, CodingKey {
        case cleanupCache, excludeCaches, oneFileSystem, unlockBeforeBackup
        case resticprofilePath, configPath, maxConcurrentBackups
    }
}

extension DefaultBackupSettings: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cleanupCache = try container.decode(Bool.self, forKey: .cleanupCache)
        excludeCaches = try container.decode(Bool.self, forKey: .excludeCaches)
        oneFileSystem = try container.decode(Bool.self, forKey: .oneFileSystem)
        unlockBeforeBackup = try container.decode(Bool.self, forKey: .unlockBeforeBackup)
        resticprofilePath = try container.decode(String.self, forKey: .resticprofilePath)
        configPath = try container.decode(String.self, forKey: .configPath)
        maxConcurrentBackups = try container.decodeIfPresent(Int.self, forKey: .maxConcurrentBackups) ?? 1
    }

    var resticArguments: [String] {
        var args: [String] = []
        if cleanupCache {
            args.append("--cleanup-cache")
        }
        if excludeCaches {
            args.append("--exclude-caches")
        }
        if oneFileSystem {
            args.append("--one-file-system")
        }
        return args
    }
}
