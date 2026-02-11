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
        let execPath = resticprofilePath ?? discoverResticprofilePath()
        guard let execPath = execPath, !execPath.isEmpty else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: execPath)
        process.arguments = ["-v", "show"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        for line in output.components(separatedBy: .newlines) {
            if line.contains("loading:") {
                let parts = line.components(separatedBy: "loading:")
                if parts.count > 1 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
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
