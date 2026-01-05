import Foundation

enum BackupState: Equatable {
    case unknown
    case idle
    case running
    case success
    case failed
}

struct BackupStatus: Equatable {
    var state: BackupState
    var lastBackupTime: Date?
    var lastBackupSize: String?
    var lastBackupDuration: String?
    var lastBackupFiles: String?
    var errorMessage: String?

    static let initial = BackupStatus(state: .unknown, lastBackupTime: nil, lastBackupSize: nil, lastBackupDuration: nil, lastBackupFiles: nil, errorMessage: nil)

    var statusIcon: String {
        switch state {
        case .unknown: return "questionmark.circle"
        case .idle: return "circle"
        case .running: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var formattedTime: String {
        if state == .running {
            guard let startTime = lastBackupTime else { return "In progress" }
            let elapsed = Date().timeIntervalSince(startTime)
            let minutes = Int(elapsed / 60)
            let seconds = Int(elapsed) % 60
            if minutes > 0 {
                return "In progress (\(minutes)m \(seconds)s)"
            } else {
                return "In progress (\(seconds)s)"
            }
        }
        guard let time = lastBackupTime else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: time, relativeTo: Date())
    }
}
