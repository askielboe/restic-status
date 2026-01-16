import Foundation

enum LaunchAgentManager {
    private static let labelPrefix = "com.resticstatus.backup"

    private static var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    private static func plistURL(for profileId: UUID) -> URL {
        launchAgentsDirectory.appendingPathComponent("\(labelPrefix).\(profileId.uuidString).plist")
    }

    private static func label(for profileId: UUID) -> String {
        "\(labelPrefix).\(profileId.uuidString)"
    }

    static func installAgent(for profile: Profile) throws {
        guard !profile.schedules.isEmpty else {
            try uninstallAgent(for: profile.id)
            return
        }

        var allIntervals: [[String: Int]] = []
        for schedule in profile.schedules {
            guard let cronSchedule = CronParser.parse(schedule) else {
                throw LaunchAgentError.invalidSchedule
            }
            allIntervals.append(contentsOf: CronParser.toLaunchdIntervals(cronSchedule))
        }

        guard !allIntervals.isEmpty else {
            throw LaunchAgentError.invalidSchedule
        }

        let intervals = allIntervals

        try FileManager.default.createDirectory(
            at: launchAgentsDirectory,
            withIntermediateDirectories: true
        )

        try unloadAgent(for: profile.id)

        let plist = buildPlist(for: profile.id, intervals: intervals)
        let plistURL = plistURL(for: profile.id)

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL)

        try loadAgent(for: profile.id)
    }

    static func uninstallAgent(for profileId: UUID) throws {
        try unloadAgent(for: profileId)

        let plistURL = plistURL(for: profileId)
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    static func uninstallAllAgents() throws {
        let profiles = ProfileStore.profiles
        for profile in profiles {
            try? uninstallAgent(for: profile.id)
        }
    }

    private static func loadAgent(for profileId: UUID) throws {
        try launchctl("load", plistPath: plistURL(for: profileId).path)
    }

    private static func unloadAgent(for profileId: UUID) throws {
        let plistPath = plistURL(for: profileId).path
        guard FileManager.default.fileExists(atPath: plistPath) else { return }
        try launchctl("unload", plistPath: plistPath)
    }

    private static func launchctl(_ command: String, plistPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [command, plistPath]
        try process.run()
        process.waitUntilExit()
    }

    private static func buildPlist(for profileId: UUID, intervals: [[String: Int]]) -> [String: Any] {
        let urlString = "resticstatus://trigger-backup/\(profileId.uuidString)"

        var plist: [String: Any] = [
            "Label": label(for: profileId),
            "ProgramArguments": [
                "/usr/bin/open",
                "-g",
                urlString,
            ],
            "RunAtLoad": false,
        ]

        if intervals.count == 1 {
            plist["StartCalendarInterval"] = intervals[0]
        } else {
            plist["StartCalendarInterval"] = intervals
        }

        return plist
    }
}

enum LaunchAgentError: LocalizedError {
    case invalidSchedule
    case installFailed(String)
    case uninstallFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSchedule:
            return "Invalid cron schedule format"
        case let .installFailed(reason):
            return "Failed to install launch agent: \(reason)"
        case let .uninstallFailed(reason):
            return "Failed to uninstall launch agent: \(reason)"
        }
    }
}
