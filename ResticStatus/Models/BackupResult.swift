import Foundation

struct BackupResult: Codable, Equatable {
    let profileId: String
    let completedAt: Date
    let success: Bool
    let totalBytes: Int64?
    let totalFiles: Int?
    let filesNew: Int?
    let filesChanged: Int?
    let duration: Double?
    let errorMessage: String?
    let snapshotId: String?
}
