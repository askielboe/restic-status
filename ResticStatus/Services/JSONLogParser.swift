import Foundation

enum JSONLogParser {
    struct StatusMessage: Decodable {
        let messageType: String
        let percentDone: Double?
        let totalFiles: Int?
        let filesDone: Int?
        let totalBytes: Int64?
        let bytesDone: Int64?

        enum CodingKeys: String, CodingKey {
            case messageType = "message_type"
            case percentDone = "percent_done"
            case totalFiles = "total_files"
            case filesDone = "files_done"
            case totalBytes = "total_bytes"
            case bytesDone = "bytes_done"
        }
    }

    static func parseProgress(from line: String) -> BackupProgress? {
        guard let data = line.data(using: .utf8) else { return nil }

        do {
            let message = try JSONDecoder().decode(StatusMessage.self, from: data)

            guard message.messageType == "status",
                  let percentDone = message.percentDone
            else {
                return nil
            }

            return BackupProgress(
                percentDone: percentDone,
                totalFiles: message.totalFiles,
                filesDone: message.filesDone,
                totalBytes: message.totalBytes,
                bytesDone: message.bytesDone
            )
        } catch {
            return nil
        }
    }
}
