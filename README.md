# Nextcloud Installer & Updater (Linux)

```text
 _   _            _       _                 _ 
| \ | |  _____  _| |_ ___| | ___  _   _  __| |
|  \| |/  _ \ \/  /__/ __| |/ _ \| | | |/ _` |
| |\  |   __/>  <| || (__| | (_) | |_| | (_| |
|_| \_|\\___/_/\_\__\____|_|\___/ \__,_|\__,_|

Linux Installer & Updater
```

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Linux-blue)
![License](https://img.shields.io/badge/License-MIT-green)

A shell script to install, update, and manage the Nextcloud Desktop client on Linux systems.

It automatically download the latest (or specific) release from Github, installs it to `/usr/local/bin`, and handles updates safely.

---

## Features
- Install latest Nextcloud Desktop AppImage
- Update to specific or latest version
- Automatic version detection
- SHA256 checksum verification
- Clean uninstall option
- Colored terminal output
- Optional restart after update
- Supports prereleases

---

## Installation
1. Clone repository
```bash
git clone https://github.com/arthur10o/nextcloud-desktop-installer.git
cd [your-repo]
```
2. Make executable
```bash
chmod +x nextcloud-installer
```
> **Note**: The repository contains both `nextcloud-installer.sh`and `nextcloud-installer`.\
> They are indentica; the second version is simply provided without the `.sh` extension for users who prefer executable-style commands.
3. Then run

Using executable version:
```bash
bash nextcloud-installed.sh
```
Or using the `.sh` version:
```bash
./nextcloud-installer.sh
```
---

## Behavior
Installs Nextcloud binary to `/usr/local/bin/nextcloud`.

## Usage

| Option | Description |
|--------|------------|
| `-r, --release <version>` | Install specific version (e.g. 33.0.5) |
| `--prerelease` | Install latest prerelease |
| `-f, --force` | Force re-download even if up to date |
| `-u, --uninstall` | Remove Nextcloud from system |
| `-h, --help` | Show help |

## 🧠 System Flow

```mermaid
flowchart TD
    A[User runs nextcloud-installer] --> B[Parse terminal arguments]
    B --> C{Flags?}
    C --> |--force / -f| D[Force download enable]
    C --> |none| E[Normal mode]
    D --> F{Action type?}
    E --> F

    F --> |Install / Update| T{Release mode}
    T --> |default| U[Fetch latest stable release]
    T --> |--prerelease| V[Fetch latest prerelease]
    T --> |--release| W[Fetch specific version]
    U --> X[Download AppImage]
    V --> X
    W --> X
    X --> Y[Verify SHA256]
    Y --> Z[Move binary to /usr/local/bin]
    Z --> a[Set permissions root:root + chmod +x]
    a --> b{Restart Nextcloud?}
    b --> |Yes| c[Stop Nextcloud]
    c --> d[Start Nextcloud]
    d --> Z0
    b --> |No| Z0

    F --> |Unknow option| S[Display message]
    S --> Z1

    F --> |Uninstall| H{Is Nextcloud installed?}
    H --> |No| I[Error: not installed]
    H --> |Yes| J[Warning: destructive action]
    J --> K{User confirmation}
    K --> |Yes | M[Stop Nextcloud]
    M --> N[Remove binary]
    N --> O{Binary still exist in PATH?}
    O --> |Yes| P[Error: uninstall failed]
    P --> Z1
    O --> |No| Q[Success uninstall completed]
    K --> |No| R[Cancel uninstall]
    R --> Z0

    F --> |Help| G{Show help}
    G --> Z0

    I --> Z1[Exit 1]
    Q --> Z0[Exit 0]
```