# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
swift build                          # Debug build
swift build -c release               # Release build
.build/debug/ResticStatus            # Run debug build
just run                             # Build + run (debug)
just bundle                          # Create .app bundle
just install                         # Install to /Applications
just test                            # Run tests (swift test)
```

No linter or formatter is configured.

## Architecture

Swift 6.2 macOS menu bar app (`.macOS(.v26)`) using Swift Package Manager. Single dependency: Yams for YAML parsing.

### Core Components

- **AppViewModel** (`@MainActor`, `ObservableObject`) — Central state coordinator. Owns profile list, triggers backups, updates status. Publishes `@Published` properties observed by the menu controller via Combine.
- **StatusMenuController** (`@MainActor`) — Builds and updates the `NSMenu` in the menu bar. Subscribes to AppViewModel's published properties. Implements `NSMenuDelegate` to refresh on open.
- **BackupRunner** (`actor`) — Executes resticprofile as a subprocess via `Process`. Runs under `taskpolicy -b` for background QoS. Parses streaming JSON output (progress and summary messages) line-by-line. Manages graceful termination (SIGINT → SIGTERM → SIGKILL).
- **AppDelegate** — Sets app to `.accessory` policy (no dock icon), wires up the view model and menu controller, handles `resticstatus://` URL scheme for Launch Agent triggers.

### Services (all `enum` with static methods)

- **ConfigParser** — Parses `~/.config/restic/profiles.yaml` via Yams to discover restic profiles
- **ProfileStore** — CRUD for profiles in UserDefaults, posts notifications on changes
- **SettingsStore** — Persists `DefaultBackupSettings` to UserDefaults
- **CronParser** — Parses cron expressions, calculates next run dates, converts to launchd `StartCalendarInterval` format
- **LaunchAgentManager** — Installs/uninstalls macOS Launch Agents that trigger backups via URL scheme
- **LogService** — Manages per-profile log files in `~/Library/Application Support/ResticStatus/Logs/`
- **JSONLogParser** — Extracts `BackupProgress` from restic's JSON output

### Data Flow

1. **Config** → `ConfigParser` reads YAML → `[ResticProfile]` (available backup profiles)
2. **Profiles** → `ProfileStore` manages user-created `[Profile]` in UserDefaults, each linking to a `ResticProfile` by ID
3. **Backup** → `AppViewModel.triggerBackup()` → `BackupRunner.runBackup()` → streams `BackupProgress` → returns `BackupResult`
4. **Scheduling** → Profile schedules (cron strings) → `CronParser` → `LaunchAgentManager` creates plist → launchd runs `open -g resticstatus://trigger-backup/{uuid}` → `AppDelegate` handles URL

### Key Paths

- Resticprofile config: `~/.config/restic/profiles.yaml`
- App logs: `~/Library/Application Support/ResticStatus/Logs/{profile-id}.log`
- Launch Agents: `~/Library/LaunchAgents/com.resticstatus.backup.{profile-id}.plist`
- Profile/settings data: UserDefaults (`Profiles`, `BackupResults`, `DefaultBackupSettings` keys)

### URL Scheme

`resticstatus://trigger-backup/<profile-id>` — Used by Launch Agents to trigger scheduled backups without bringing the app to the foreground.

## Dependencies

- [Yams](https://github.com/jpsim/Yams) 5.0+ — YAML parsing for resticprofile config files
