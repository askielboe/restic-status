import AppKit
import Foundation

enum LogService {
    static var logDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ResticStatus/Logs", isDirectory: true)
    }

    static func logPath(for profileId: String) -> URL {
        logDirectory.appendingPathComponent("\(profileId).log")
    }

    static func createLogFile(for profileId: String) throws -> FileHandle {
        let logDir = logDirectory
        if !FileManager.default.fileExists(atPath: logDir.path) {
            try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        }

        let logURL = logPath(for: profileId)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        return try FileHandle(forWritingTo: logURL)
    }

    @MainActor static func openLog(for profileId: String, profileName: String) {
        let logURL = logPath(for: profileId)

        if FileManager.default.fileExists(atPath: logURL.path) {
            NSWorkspace.shared.open(logURL)
        } else {
            let alert = NSAlert()
            alert.messageText = "Log file not found"
            alert.informativeText = "No log file exists yet for \(profileName). Run a backup first."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
