import Foundation

actor BackupRunner {
    private var runningProcesses: [String: Process] = [:]

    struct SummaryMessage: Decodable, Sendable {
        let messageType: String
        let totalFilesProcessed: Int?
        let filesNew: Int?
        let filesChanged: Int?
        let totalBytesProcessed: Int64?
        let totalDuration: Double?
        let snapshotId: String?

        enum CodingKeys: String, CodingKey {
            case messageType = "message_type"
            case totalFilesProcessed = "total_files_processed"
            case filesNew = "files_new"
            case filesChanged = "files_changed"
            case totalBytesProcessed = "total_bytes_processed"
            case totalDuration = "total_duration"
            case snapshotId = "snapshot_id"
        }
    }

    func runBackup(
        profileId: String,
        resticProfile: ResticProfile,
        settings: DefaultBackupSettings = SettingsStore.settings,
        onProgress: (@Sendable (BackupProgress) -> Void)? = nil
    ) async throws -> BackupResult {
        let logHandle = try LogService.createLogFile(for: profileId)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: settings.resticprofilePath)
        process.arguments = [
            "--config", resticProfile.configPath,
            "\(resticProfile.name).backup",
            "--json",
        ] + settings.resticArguments

        let execPath = process.executableURL?.path ?? ""
        let commandString = execPath + " " + (process.arguments ?? []).joined(separator: " ") + "\n\n"
        try? logHandle.write(contentsOf: Data(commandString.utf8))

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        runningProcesses[profileId] = process

        let startTime = Date()

        do {
            try process.run()
        } catch {
            runningProcesses.removeValue(forKey: profileId)
            try? logHandle.close()
            throw error
        }

        var summary: SummaryMessage?
        var errorMessage: String?

        await withTaskGroup(of: OutputResult?.self) { group in
            group.addTask {
                await self.readOutput(
                    from: stdoutPipe.fileHandleForReading,
                    logHandle: logHandle,
                    onProgress: onProgress
                )
            }

            group.addTask {
                await self.readOutput(
                    from: stderrPipe.fileHandleForReading,
                    logHandle: logHandle,
                    onProgress: nil
                )
            }

            group.addTask {
                process.waitUntilExit()
                return nil
            }

            for await result in group {
                guard let result = result else { continue }
                if result.summary != nil {
                    summary = result.summary
                }
                if errorMessage == nil, let error = result.error {
                    errorMessage = error
                }
            }
        }

        runningProcesses.removeValue(forKey: profileId)
        try? logHandle.close()

        let success = process.terminationStatus == 0

        return BackupResult(
            profileId: profileId,
            completedAt: Date(),
            success: success,
            totalBytes: summary?.totalBytesProcessed,
            totalFiles: summary?.totalFilesProcessed,
            filesNew: summary?.filesNew,
            filesChanged: summary?.filesChanged,
            duration: summary?.totalDuration ?? Date().timeIntervalSince(startTime),
            errorMessage: success ? nil : (errorMessage ?? "Exit code: \(process.terminationStatus)"),
            snapshotId: summary?.snapshotId
        )
    }

    private struct OutputResult: Sendable {
        let summary: SummaryMessage?
        let error: String?
    }

    private nonisolated func readOutput(
        from handle: FileHandle,
        logHandle: FileHandle,
        onProgress: (@Sendable (BackupProgress) -> Void)?
    ) async -> OutputResult {
        var buffer = Data()
        var summary: SummaryMessage?
        var errorMessage: String?
        var lastNonJsonLine: String?

        while true {
            let data = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: handle.availableData)
                }
            }
            if data.isEmpty { break }

            try? logHandle.write(contentsOf: data)

            buffer.append(data)

            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[..<newlineIndex]
                buffer = buffer[(newlineIndex + 1)...]

                guard let line = String(data: lineData, encoding: .utf8),
                      !line.isEmpty else { continue }

                let trimmed = line.trimmingCharacters(in: .whitespaces)

                guard trimmed.hasPrefix("{") else {
                    if !trimmed.isEmpty {
                        lastNonJsonLine = trimmed
                    }
                    continue
                }

                if let progress = JSONLogParser.parseProgress(from: line) {
                    onProgress?(progress)
                }

                if let data = line.data(using: .utf8),
                   let msg = try? JSONDecoder().decode(SummaryMessage.self, from: data),
                   msg.messageType == "summary"
                {
                    summary = msg
                }

                if errorMessage == nil,
                   let data = line.data(using: .utf8),
                   let errMsg = try? JSONDecoder().decode(ErrorMessage.self, from: data),
                   errMsg.messageType == "error"
                {
                    errorMessage = errMsg.error?.message ?? errMsg.item
                }
            }
        }

        return OutputResult(summary: summary, error: errorMessage ?? lastNonJsonLine)
    }

    private struct ErrorMessage: Decodable {
        let messageType: String
        let error: ErrorDetail?
        let item: String?

        struct ErrorDetail: Decodable {
            let message: String?
        }

        enum CodingKeys: String, CodingKey {
            case messageType = "message_type"
            case error
            case item
        }
    }

    func isRunning(profileId: String) -> Bool {
        if let process = runningProcesses[profileId] {
            return process.isRunning
        }
        return false
    }

    func cancelBackup(for profileId: String) async {
        guard let process = runningProcesses[profileId], process.isRunning else { return }
        await gracefullyTerminate(process: process)
    }

    func cancelAllBackups() async {
        let processes = runningProcesses.values.filter { $0.isRunning }
        await withTaskGroup(of: Void.self) { group in
            for process in processes {
                group.addTask {
                    await self.gracefullyTerminate(process: process)
                }
            }
        }
    }

    private func gracefullyTerminate(process: Process) async {
        let pid = process.processIdentifier

        kill(pid, SIGINT)

        if await waitForExit(process: process, timeout: 5.0) { return }

        kill(pid, SIGTERM)

        if await waitForExit(process: process, timeout: 3.0) { return }

        kill(pid, SIGKILL)
    }

    private func waitForExit(process: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return !process.isRunning
    }
}
