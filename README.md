# ResticStatus

A native macOS menu bar app for monitoring [resticprofile](https://github.com/creativeprojects/resticprofile) backups.

## Features

- Create profiles linked to resticprofile configurations
- Automatic scheduled backups using macOS Launch Agents
- Live backup progress
- Launch at login

## Requirements

- macOS 26+
- Swift 6+
- resticprofile installed

## Build & Install

```bash
make install
```

## Development

```bash
make run
```

## Configuration

The app auto-discovers resticprofile and its config file. If auto-discovery fails, configure paths manually in Settings.

Profiles and schedules are managed in Settings. Schedules use cron format.

## License

MIT
