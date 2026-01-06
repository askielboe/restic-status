import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ProfilesSettingsView()
                .tabItem {
                    Label("Profiles", systemImage: "list.bullet")
                }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct GeneralSettingsView: View {
    @State private var settings = SettingsStore.settings

    private var isPathValid: Bool {
        FileManager.default.isExecutableFile(atPath: settings.resticprofilePath)
    }

    private var isConfigPathValid: Bool {
        FileManager.default.fileExists(atPath: settings.configPath)
    }

    private func saveSettings() {
        SettingsStore.settings = settings
    }

    var body: some View {
        Form {
            Section("Resticprofile") {
                HStack {
                    CommitTextField(placeholder: "Path", text: $settings.resticprofilePath, onCommit: saveSettings)
                    Image(systemName: isPathValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isPathValid ? .green : .red)
                    Button("Discover") {
                        if let path = DefaultBackupSettings.discoverResticprofilePath() {
                            settings.resticprofilePath = path
                            saveSettings()
                        }
                    }
                }
                HStack {
                    CommitTextField(placeholder: "Config", text: $settings.configPath, onCommit: saveSettings)
                    Image(systemName: isConfigPathValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isConfigPathValid ? .green : .red)
                    Button("Discover") {
                        if let path = DefaultBackupSettings.discoverConfigPath(resticprofilePath: settings.resticprofilePath) {
                            settings.configPath = path
                            saveSettings()
                        }
                    }
                }
            }

            Section("Backup Options") {
                Toggle("Unlock repository before backup", isOn: $settings.unlockBeforeBackup)
                Toggle("Cleanup cache after backup", isOn: $settings.cleanupCache)
                Toggle("Exclude cache directories", isOn: $settings.excludeCaches)
                Toggle("Stay on one file system", isOn: $settings.oneFileSystem)
            }

            Section {
                Button("Reset to Defaults") {
                    settings = .default
                    saveSettings()
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.unlockBeforeBackup) { _, _ in saveSettings() }
        .onChange(of: settings.cleanupCache) { _, _ in saveSettings() }
        .onChange(of: settings.excludeCaches) { _, _ in saveSettings() }
        .onChange(of: settings.oneFileSystem) { _, _ in saveSettings() }
    }
}

struct ProfilesSettingsView: View {
    @State private var profiles: [Profile] = ProfileStore.profiles
    @State private var resticProfiles: [ResticProfile] = []
    @State private var selectedProfileId: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedProfileId) {
                ForEach(profiles) { profile in
                    Text(profile.name)
                        .tag(profile.id)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let profileId = profiles[index].id
                        ProfileStore.remove(id: profileId)
                        if selectedProfileId == profileId {
                            selectedProfileId = nil
                        }
                    }
                    profiles = ProfileStore.profiles
                }
            }
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 0) {
                    Button(action: addProfile) {
                        Image(systemName: "plus")
                            .frame(width: 28, height: 22)
                    }
                    .buttonStyle(.borderless)
                    Divider()
                        .frame(height: 16)
                    Button(action: removeSelectedProfile) {
                        Image(systemName: "minus")
                            .frame(width: 28, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedProfileId == nil)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.bar)
            }
        } detail: {
            profileDetail
        }
        .onAppear {
            loadResticProfiles()
            if selectedProfileId == nil, let first = profiles.first {
                selectedProfileId = first.id
            }
        }
    }

    @ViewBuilder
    private var profileDetail: some View {
        if let selectedId = selectedProfileId,
           let index = profiles.firstIndex(where: { $0.id == selectedId })
        {
            ProfileDetailView(
                profile: $profiles[index],
                resticProfiles: resticProfiles,
                onDelete: {
                    ProfileStore.remove(id: selectedId)
                    profiles = ProfileStore.profiles
                    selectedProfileId = nil
                }
            )
        } else {
            ContentUnavailableView("No Profile Selected", systemImage: "doc")
        }
    }

    private func addProfile() {
        let defaultResticProfileId = resticProfiles.first?.id ?? ""
        let newProfile = Profile(name: "New Profile", resticProfileId: defaultResticProfileId)
        ProfileStore.add(newProfile)
        profiles = ProfileStore.profiles
        selectedProfileId = newProfile.id
    }

    private func removeSelectedProfile() {
        guard let selectedId = selectedProfileId else { return }
        ProfileStore.remove(id: selectedId)
        profiles = ProfileStore.profiles
        selectedProfileId = nil
    }

    private func loadResticProfiles() {
        do {
            let configPath = SettingsStore.settings.configPath
            resticProfiles = try ConfigParser.parseResticProfiles(from: configPath)
        } catch {
            print("Failed to load restic profiles: \(error)")
        }
    }
}

struct ProfileDetailView: View {
    @Binding var profile: Profile
    let resticProfiles: [ResticProfile]
    let onDelete: () -> Void

    @State private var editingScheduleIndex: Int?
    @State private var editingScheduleText: String = ""
    @FocusState private var focusedScheduleIndex: Int?

    var body: some View {
        Form {
            Section("Profile") {
                CommitTextField(placeholder: "Name", text: $profile.name) {
                    ProfileStore.update(profile)
                }
                Picker("Resticprofile", selection: $profile.resticProfileId) {
                    ForEach(resticProfiles) { rp in
                        Text(rp.displayName).tag(rp.id)
                    }
                }
            }

            Section {
                if profile.schedules.isEmpty {
                    Text("No schedules")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(profile.schedules.enumerated()), id: \.offset) { index, schedule in
                        ScheduleRowView(
                            schedule: schedule,
                            isValid: profile.isValidSchedule(schedule),
                            isEditing: editingScheduleIndex == index,
                            editText: editingScheduleIndex == index ? $editingScheduleText : .constant(schedule),
                            isFocused: focusedScheduleIndex == index,
                            onTap: {
                                editingScheduleIndex = index
                                editingScheduleText = schedule
                                focusedScheduleIndex = index
                            },
                            onSubmit: {
                                commitScheduleEdit(at: index)
                            },
                            onDelete: {
                                profile.schedules.remove(at: index)
                                ProfileStore.update(profile)
                            }
                        )
                        .focused($focusedScheduleIndex, equals: index)
                    }
                }

                if let next = profile.nextBackupTime {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("Next: \(next, style: .relative)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            } header: {
                HStack {
                    Text("Schedules")
                    Spacer()
                    Button(action: addSchedule) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section {
                Button("Delete Profile", role: .destructive, action: onDelete)
            }
        }
        .formStyle(.grouped)
        .onTapGesture { focusedScheduleIndex = nil }
        .onChange(of: focusedScheduleIndex) { _, newValue in
            if newValue == nil, let index = editingScheduleIndex {
                commitScheduleEdit(at: index)
            }
        }
        .onChange(of: profile.resticProfileId) { _, _ in
            ProfileStore.update(profile)
        }
    }

    private func addSchedule() {
        let newIndex = profile.schedules.count
        profile.schedules.append("0 * * * *")
        editingScheduleIndex = newIndex
        editingScheduleText = "0 * * * *"
        focusedScheduleIndex = newIndex
        ProfileStore.update(profile)
    }

    private func commitScheduleEdit(at index: Int) {
        guard index < profile.schedules.count else { return }
        let trimmed = editingScheduleText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            profile.schedules.remove(at: index)
        } else {
            profile.schedules[index] = trimmed
        }
        editingScheduleIndex = nil
        ProfileStore.update(profile)
    }
}

struct ScheduleRowView: View {
    let schedule: String
    let isValid: Bool
    let isEditing: Bool
    @Binding var editText: String
    let isFocused: Bool
    let onTap: () -> Void
    let onSubmit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .onSubmit(onSubmit)
            } else {
                Text(schedule)
                    .onTapGesture(perform: onTap)
            }
            Spacer()
            if !isEditing {
                if isValid {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
    }
}

struct CommitTextField: View {
    let placeholder: String
    @Binding var text: String
    var onCommit: () -> Void = {}

    @State private var localText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $localText, prompt: Text(placeholder))
            .focused($isFocused)
            .onAppear { localText = text }
            .onChange(of: text) { _, newValue in
                if !isFocused { localText = newValue }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onSubmit { commit() }
    }

    private func commit() {
        text = localText
        onCommit()
    }
}
