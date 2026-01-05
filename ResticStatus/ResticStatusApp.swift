import SwiftUI

@main
struct ResticStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Hidden", id: "hidden") {
            EmptyView()
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
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

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)

        viewModel = AppViewModel()
        menuController = StatusMenuController(viewModel: viewModel)
        viewModel.onProgressUpdate = { [weak self] progress, profileId in
            self?.menuController.updateProgress(progress, for: profileId)
        }

        handleLaunchArguments()
    }

    private func handleLaunchArguments() {
        let args = CommandLine.arguments
        guard let triggerIndex = args.firstIndex(of: "--trigger-backup"),
              triggerIndex + 1 < args.count
        else {
            return
        }

        let profileIdString = args[triggerIndex + 1]
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
