import SwiftUI

@main
struct ResticStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    SettingsWindowController.shared.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: AppViewModel!
    private var menuController: StatusMenuController!

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard viewModel.isAnyBackupRunning else { return .terminateNow }

        Task {
            await viewModel.cancelAllBackups()
            await MainActor.run {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)

        viewModel = AppViewModel()
        menuController = StatusMenuController(viewModel: viewModel)
        viewModel.onProgressUpdate = { [weak self] progress, profileId in
            self?.menuController.updateProgress(progress, for: profileId)
        }
    }

    func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            handleURL(url)
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "resticstatus",
              url.host == "trigger-backup"
        else { return }

        let profileIdString = url.lastPathComponent
        guard let profileId = UUID(uuidString: profileIdString),
              let profile = viewModel.profiles.first(where: { $0.id == profileId })
        else {
            print("Profile not found: \(profileIdString)")
            return
        }

        print("Triggering scheduled backup for profile: \(profile.name)")
        viewModel.triggerBackup(for: profile)
    }
}
