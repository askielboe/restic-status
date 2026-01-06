import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
class AppViewModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var isAnyBackupRunning: Bool = false
    @Published var menuBarIcon: String = "arrow.clockwise.circle.fill"
    @Published var launchAtLogin: Bool = false

    var onProgressUpdate: ((BackupProgress, String) -> Void)?

    private let backupRunner = BackupRunner()
    private let resultsKey = "BackupResults"
    private var storedResults: [String: BackupResult] = [:]
    private var resticProfiles: [ResticProfile] = []
    private var cancellables = Set<AnyCancellable>()

    init() {
        loadResticProfiles()
        loadProfiles()
        loadPersistedResults()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        observeProfileChanges()
    }

    private func observeProfileChanges() {
        NotificationCenter.default.publisher(for: .profilesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadProfiles()
                self?.loadPersistedResults()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .profileWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let profileId = notification.object as? UUID,
                      let profile = self.profiles.first(where: { $0.id == profileId })
                else { return }
                self.cancelBackup(for: profile)
            }
            .store(in: &cancellables)
    }

    private func loadResticProfiles() {
        do {
            let configPath = SettingsStore.settings.configPath
            resticProfiles = try ConfigParser.parseResticProfiles(from: configPath)
        } catch {
            print("Failed to load restic profiles: \(error)")
        }
    }

    func loadProfiles() {
        profiles = ProfileStore.profiles
    }

    private func loadPersistedResults() {
        guard let data = UserDefaults.standard.data(forKey: resultsKey),
              let results = try? JSONDecoder().decode([String: BackupResult].self, from: data)
        else {
            return
        }

        storedResults = results

        for (profileIdString, result) in results {
            if let profileId = UUID(uuidString: profileIdString),
               let index = profiles.firstIndex(where: { $0.id == profileId })
            {
                profiles[index].status = statusFromResult(result)
            }
        }
        updateMenuBarIcon()
    }

    private func persistResults() {
        if let data = try? JSONEncoder().encode(storedResults) {
            UserDefaults.standard.set(data, forKey: resultsKey)
        }
    }

    private func statusFromResult(_ result: BackupResult) -> BackupStatus {
        let state: BackupState = result.success ? .success : .failed

        let formattedSize: String?
        if let bytes = result.totalBytes {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .binary
            formattedSize = formatter.string(fromByteCount: bytes)
        } else {
            formattedSize = nil
        }

        let formattedDuration: String?
        if let duration = result.duration {
            let totalSeconds = Int(duration)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let secs = totalSeconds % 60
            if hours > 0 {
                formattedDuration = String(format: "%d:%02d:%02d", hours, minutes, secs)
            } else {
                formattedDuration = String(format: "%d:%02d", minutes, secs)
            }
        } else {
            formattedDuration = nil
        }

        let formattedFiles: String?
        if let total = result.totalFiles {
            let added = result.filesNew ?? 0
            let changed = result.filesChanged ?? 0
            formattedFiles = "\(added) added / \(changed) changed / \(total) total"
        } else {
            formattedFiles = nil
        }

        return BackupStatus(
            state: state,
            lastBackupTime: result.completedAt,
            lastBackupSize: formattedSize,
            lastBackupDuration: formattedDuration,
            lastBackupFiles: formattedFiles,
            errorMessage: result.errorMessage
        )
    }

    private func updateRunningState() {
        isAnyBackupRunning = profiles.contains { $0.status.state == .running }
        updateMenuBarIcon()
    }

    private func updateMenuBarIcon() {
        if isAnyBackupRunning {
            menuBarIcon = "arrow.triangle.2.circlepath"
        } else if profiles.contains(where: { $0.status.state == .failed }) {
            menuBarIcon = "exclamationmark.circle"
        } else if !profiles.isEmpty, profiles.allSatisfy({ $0.status.state == .success }) {
            menuBarIcon = "checkmark.circle.fill"
        } else {
            menuBarIcon = "arrow.clockwise.circle.fill"
        }
    }

    func triggerBackup(for profile: Profile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        guard let resticProfile = resticProfiles.first(where: { $0.id == profile.resticProfileId }) else {
            print("Restic profile not found: \(profile.resticProfileId)")
            return
        }

        profiles[index].status.state = .running
        profiles[index].status.lastBackupTime = Date()
        updateRunningState()

        let profileId = profile.id
        Task {
            do {
                let result = try await backupRunner.runBackup(
                    profileId: profileId.uuidString,
                    resticProfile: resticProfile
                ) { [weak self] progress in
                    guard let self else { return }
                    Task { @MainActor in
                        self.onProgressUpdate?(progress, profileId.uuidString)
                    }
                }
                await MainActor.run {
                    self.handleBackupResult(result, profileId: profileId)
                }
            } catch {
                await MainActor.run {
                    if let idx = self.profiles.firstIndex(where: { $0.id == profileId }) {
                        self.profiles[idx].status.state = .failed
                        self.profiles[idx].status.errorMessage = error.localizedDescription
                        self.profiles[idx].status.lastBackupTime = Date()
                    }
                    self.updateRunningState()
                    self.persistResults()
                }
            }
        }
    }

    private func handleBackupResult(_ result: BackupResult, profileId: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }

        storedResults[profileId.uuidString] = result
        profiles[index].status = statusFromResult(result)
        updateRunningState()
        persistResults()
    }

    func cancelBackup(for profile: Profile) {
        Task {
            await backupRunner.cancelBackup(for: profile.id.uuidString)
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index].status.state = .idle
                profiles[index].status.errorMessage = nil
            }
            updateRunningState()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }

    func viewLogs(for profile: Profile) {
        LogService.openLog(for: profile.id.uuidString, profileName: profile.name)
    }
}
