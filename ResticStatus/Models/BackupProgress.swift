import Foundation

struct BackupProgress: Equatable {
    var percentDone: Double
    var totalFiles: Int?
    var filesDone: Int?
    var totalBytes: Int64?
    var bytesDone: Int64?

    static let zero = BackupProgress(percentDone: 0)

    var formattedPercent: String {
        "\(Int(percentDone * 100))%"
    }

    var formattedBytes: String? {
        guard let done = bytesDone, let total = totalBytes else { return nil }
        return "\(formatBytes(done)) / \(formatBytes(total))"
    }

    var formattedFiles: String? {
        guard let done = filesDone, let total = totalFiles else { return nil }
        return "\(done) / \(total) files"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}
