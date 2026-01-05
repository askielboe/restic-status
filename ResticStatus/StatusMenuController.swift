import AppKit
import Combine

@MainActor
class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private weak var viewModel: AppViewModel?
    private var cancellables = Set<AnyCancellable>()

    private var profileMenuItems: [UUID: NSMenuItem] = [:]
    private var profileSubmenus: [UUID: NSMenu] = [:]
    private var progressItems: [UUID: NSMenuItem] = [:]
    private var bytesItems: [UUID: NSMenuItem] = [:]
    private var filesItems: [UUID: NSMenuItem] = [:]
    private var emptyStateItems: [NSMenuItem] = []
    private var configWarningItems: [NSMenuItem] = []

    private var animationTimer: Timer?
    private var animationAngle: CGFloat = 0

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()

        super.init()

        menu.delegate = self
        statusItem.menu = menu

        setupStatusItemButton()
        buildMenu()
        observeViewModel()
    }

    private func setupStatusItemButton() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.clockwise.circle.fill", accessibilityDescription: "Backup Status")
            button.image?.isTemplate = true
        }
    }

    private func updateStatusItemIcon(_ iconName: String) {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Backup Status")
            button.image?.isTemplate = true
        }
    }

    private func observeViewModel() {
        viewModel?.$menuBarIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] iconName in
                self?.updateStatusItemIcon(iconName)
            }
            .store(in: &cancellables)

        viewModel?.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildProfileItems()
            }
            .store(in: &cancellables)

        viewModel?.$launchAtLogin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.updateLaunchAtLoginItem(enabled)
            }
            .store(in: &cancellables)

        viewModel?.$isAnyBackupRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRunning in
                if isRunning {
                    self?.startIconAnimation()
                } else {
                    self?.stopIconAnimation()
                }
            }
            .store(in: &cancellables)
    }

    private func startIconAnimation() {
        guard animationTimer == nil else { return }
        animationAngle = 0
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateAnimationFrame()
            }
        }
    }

    private func stopIconAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationAngle = 0
    }

    private func updateAnimationFrame() {
        guard let button = statusItem.button else { return }
        animationAngle -= 15
        if animationAngle <= -360 { animationAngle = 0 }

        guard let baseImage = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Backup Running") else { return }
        let rotatedImage = rotateImage(baseImage, byDegrees: animationAngle)
        rotatedImage.isTemplate = true
        button.image = rotatedImage
    }

    private func rotateImage(_ image: NSImage, byDegrees degrees: CGFloat) -> NSImage {
        let size = image.size
        let rotatedImage = NSImage(size: size)
        rotatedImage.lockFocus()

        let transform = NSAffineTransform()
        transform.translateX(by: size.width / 2, yBy: size.height / 2)
        transform.rotate(byDegrees: degrees)
        transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
        transform.concat()

        image.draw(in: NSRect(origin: .zero, size: size))
        rotatedImage.unlockFocus()
        return rotatedImage
    }

    private func buildMenu() {
        menu.removeAllItems()

        guard let viewModel = viewModel else { return }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem("Settings...", action: #selector(openSettings)))

        let launchItem = actionItem("Launch at Login", action: #selector(toggleLaunchAtLogin))
        if viewModel.launchAtLogin {
            launchItem.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        }
        launchItem.tag = 1000
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem("Quit", action: #selector(quit)))

        rebuildProfileItems()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    private func rebuildProfileItems() {
        guard let viewModel = viewModel else { return }

        for (_, item) in profileMenuItems {
            menu.removeItem(item)
        }
        for item in emptyStateItems {
            menu.removeItem(item)
        }
        for item in configWarningItems {
            menu.removeItem(item)
        }
        profileMenuItems.removeAll()
        profileSubmenus.removeAll()
        progressItems.removeAll()
        bytesItems.removeAll()
        filesItems.removeAll()
        emptyStateItems.removeAll()
        configWarningItems.removeAll()

        var insertIndex = 0

        let settings = SettingsStore.settings
        let isResticprofilePathValid = FileManager.default.isExecutableFile(atPath: settings.resticprofilePath)
        let isConfigPathValid = FileManager.default.fileExists(atPath: settings.configPath)

        if !isResticprofilePathValid || !isConfigPathValid {
            func insertWarning(_ item: NSMenuItem) {
                menu.insertItem(item, at: insertIndex)
                configWarningItems.append(item)
                insertIndex += 1
            }

            insertWarning(infoItem("Configuration Required", icon: "exclamationmark.triangle.fill"))

            if !isResticprofilePathValid {
                insertWarning(infoItem("  resticprofile not found"))
            }

            if !isConfigPathValid {
                insertWarning(infoItem("  config file not found"))
            }

            insertWarning(actionItem("Open Settings...", action: #selector(openSettings)))
            insertWarning(NSMenuItem.separator())
        }

        if viewModel.profiles.isEmpty {
            let emptyItem = infoItem("No profiles configured")
            menu.insertItem(emptyItem, at: insertIndex)
            emptyStateItems.append(emptyItem)

            let hintItem = actionItem("Add profiles in Settings...", action: #selector(openSettings))
            menu.insertItem(hintItem, at: insertIndex + 1)
            emptyStateItems.append(hintItem)
        } else {
            for (index, profile) in viewModel.profiles.enumerated() {
                let item = createProfileMenuItem(for: profile)
                menu.insertItem(item, at: insertIndex + index)
                profileMenuItems[profile.id] = item
            }
        }
    }

    private func createProfileMenuItem(for profile: Profile) -> NSMenuItem {
        let item = NSMenuItem()
        updateProfileMenuItemTitle(item, for: profile)

        let submenu = NSMenu()
        profileSubmenus[profile.id] = submenu
        item.submenu = submenu

        buildSubmenu(submenu, for: profile)

        return item
    }

    private func updateProfileMenuItemTitle(_ item: NSMenuItem, for profile: Profile) {
        let title = NSMutableAttributedString(string: profile.name)

        let subtitle: String
        switch profile.status.state {
        case .running:
            subtitle = " — running"
        case .success:
            subtitle = " — \(profile.status.formattedTime)"
        case .failed:
            subtitle = " — failed"
        case .idle, .unknown:
            subtitle = ""
        }

        if !subtitle.isEmpty {
            let subtitleAttr = NSAttributedString(
                string: subtitle,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            )
            title.append(subtitleAttr)
        }

        item.attributedTitle = title
        item.image = NSImage(systemSymbolName: profile.status.statusIcon, accessibilityDescription: nil)
    }

    private func buildSubmenu(_ submenu: NSMenu, for profile: Profile) {
        submenu.removeAllItems()

        if profile.status.state == .running {
            let progressItem = infoItem("Starting...")
            submenu.addItem(progressItem)
            progressItems[profile.id] = progressItem

            let bytesItem = infoItem("")
            bytesItem.isHidden = true
            submenu.addItem(bytesItem)
            bytesItems[profile.id] = bytesItem

            let filesItem = infoItem("")
            filesItem.isHidden = true
            submenu.addItem(filesItem)
            filesItems[profile.id] = filesItem

            submenu.addItem(NSMenuItem.separator())
            submenu.addItem(actionItem("Stop Backup", action: #selector(cancelBackup(_:)), profileId: profile.id))
        } else {
            if let lastBackup = profile.status.lastBackupTime {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                submenu.addItem(infoItem("Last backup: \(formatter.string(from: lastBackup))"))
            }

            if let duration = profile.status.lastBackupDuration {
                submenu.addItem(infoItem("Duration: \(duration)"))
            }

            if let size = profile.status.lastBackupSize {
                submenu.addItem(infoItem("Size: \(size)"))
            }

            if let files = profile.status.lastBackupFiles {
                submenu.addItem(infoItem("Files: \(files)"))
            }

            if !profile.schedules.isEmpty {
                submenu.addItem(NSMenuItem.separator())
                submenu.addItem(infoItem("Next: \(profile.formattedNextBackup)"))
            }

            if let error = profile.status.errorMessage {
                submenu.addItem(NSMenuItem.separator())
                submenu.addItem(infoItem("Error: \(error)"))
            }

            submenu.addItem(NSMenuItem.separator())
            submenu.addItem(actionItem("Backup Now", action: #selector(backupNow(_:)), profileId: profile.id))
        }

        submenu.addItem(actionItem("View Log", action: #selector(viewLogs(_:)), profileId: profile.id))
    }

    func updateProgress(_ progress: BackupProgress, for profileId: String) {
        guard let uuid = UUID(uuidString: profileId),
              let progressItem = progressItems[uuid] else { return }

        progressItem.title = progress.formattedPercent

        if let bytes = progress.formattedBytes, let bytesItem = bytesItems[uuid] {
            bytesItem.title = bytes
            bytesItem.isHidden = false
        }

        if let files = progress.formattedFiles, let filesItem = filesItems[uuid] {
            filesItem.title = files
            filesItem.isHidden = false
        }
    }

    private func updateLaunchAtLoginItem(_ enabled: Bool) {
        if let item = menu.item(withTag: 1000) {
            item.image = enabled ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) : nil
        }
    }

    @objc private func backupNow(_ sender: NSMenuItem) {
        withProfile(from: sender) { viewModel?.triggerBackup(for: $0) }
    }

    @objc private func cancelBackup(_ sender: NSMenuItem) {
        withProfile(from: sender) { viewModel?.cancelBackup(for: $0) }
    }

    @objc private func viewLogs(_ sender: NSMenuItem) {
        withProfile(from: sender) { viewModel?.viewLogs(for: $0) }
    }

    @objc private func toggleLaunchAtLogin() {
        guard let viewModel = viewModel else { return }
        viewModel.setLaunchAtLogin(!viewModel.launchAtLogin)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func withProfile(from sender: NSMenuItem, perform action: (Profile) -> Void) {
        guard let profileId = sender.representedObject as? UUID,
              let profile = viewModel?.profiles.first(where: { $0.id == profileId }) else { return }
        action(profile)
    }

    private func infoItem(_ title: String, icon: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let icon = icon {
            item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        }
        return item
    }

    private func actionItem(_ title: String, action: Selector, profileId: UUID? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let profileId = profileId {
            item.representedObject = profileId
        }
        return item
    }
}
