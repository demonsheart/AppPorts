# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AppPorts** is a macOS application migration tool that moves apps from `/Applications` to external storage while maintaining a local "portal" (either a symlink or a shallow `.app` wrapper with a linked `Contents` directory).

**Tech Stack:** Swift + SwiftUI (native macOS app), requires macOS 14.0+ (Sonoma)

**Key Architecture Pattern:**
- **Actor-based concurrency**: `AppScanner`, `DataDirScanner` use actors for background scanning
- **Service layer**: `AppMigrationService`, `AppLogger` handle business logic
- **SwiftUI views**: `ContentView`, `WelcomeView`, `DataDirsView` + reusable components
- **MVVM-style**: Views observe `@StateObject` services, minimal view logic

## Build and Test Commands

### Build Project
```bash
# Using Xcode MCP Bridge (PREFERRED)
mcp__xcode__BuildProject tabIdentifier="windowtab4"

# Traditional xcodebuild (fallback)
xcodebuild clean build \
  -scheme "AppPorts" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO
```

### Run Tests

```bash
# Run all tests
xcodebuild test \
  -scheme "AppPorts" \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/AppPortsDerived test

# Run specific test suite
xcodebuild test \
  -scheme "AppPorts" \
  -destination 'platform=macOS' \
  -only-testing:"AppPortsTests/AppScannerTests" \
  CODE_SIGNING_ALLOWED=NO

# Run localization audit
xcodebuild test \
  -scheme "AppPorts" \
  -destination 'platform=macOS' \
  -only-testing:"AppPortsTests/LocalizationAuditTests" \
  CODE_SIGNING_ALLOWED=NO
```

### Development Workflow

1. Open `AppPorts.xcodeproj` in Xcode
2. Build and Run (⌘R) - requires Full Disk Access permission on first run
3. Use Xcode's built-in test navigator for individual tests

## Architecture Overview

### Core Models (`Models/`)

- **`AppModels.swift`**: `AppItem` struct (app metadata), `AppMoverError` enum, `AppContainerKind` enum
- **`AppLanguageOption.swift`**: `AppLanguageOption` struct for language catalog
- **`DataDirItem.swift`**: `DataDirItem` struct for data directory migration

### Services Layer (`Services/`)

- **`AppMigrationService.swift`**: Core migration logic (move + link/restore)
  - Handles two portal strategies: `wholeAppSymlink` vs `deepContentsWrapper`
  - Uses Finder AppleScript for safe deletion
  - Includes permission checking and fallback mechanisms

- **`AppLogger.swift`**: Comprehensive logging with rotation, export diagnostics
  - Writes to `~/Library/Logs/AppPorts/AppPorts_Log.txt` by default
  - Provides `exportDiagnosticPackageInteractively()` for bug reports

### Utilities Layer (`Utils/`)

- **`AppScanner.swift`** (Actor): Scans `/Applications` for apps, detects status, calculates sizes
- **`DataDirScanner.swift`** (Actor): Scans app data directories (`~/Library/Application Support`, etc.)
- **`DataDirMover.swift`**: Handles data directory migration logic
- **`FileCopier.swift`**: Async file copying with progress callbacks
- **`FolderMonitor.swift`**: Watches for external volume mount/unmount
- **`LanguageManager.swift`**: Manages app language (20+ languages)
- **`UpdateChecker.swift`**: Checks GitHub releases for updates
- **`LocalizedByteCountFormatter.swift`**: Formats byte counts respecting locale

### Views (`Views/`)

- **`ContentView.swift`**: Main UI - app lists, search, batch operations
- **`WelcomeView.swift`**: First-run onboarding
- **`AboutView.swift`**: About sheet
- **`DataDirsView.swift`**: Data directory migration UI
- **`AppStoreSettingsView.swift`**: App Store app opt-in settings
- **Components/**: Reusable SwiftUI components (`AppIconView`, `AppRowView`, `ProgressOverlay`, `StatusBadge`)

### Entry Point

- **`Appports.swift`**: `@main` app struct with `WindowGroup`, custom menus (About, Language, Log)

## Localization (Critical!)

AppPorts supports 20+ languages with strict automation:

**Three-Layer Architecture:**
1. `Localizable.xcstrings` - Single source of truth for UI translations
2. `AppLanguageCatalog` (in `AppLanguageOption.swift`) - Single source for supported languages list
3. `LocalizationAuditTests` - Automated gatekeeping in CI

**Rules:**
- SwiftUI literals are OK for `LocalizedStringKey` APIs: `Text("你好")`, `Button("确定")`
- **All AppKit/imperative strings must call `.localized`**: `panel.prompt = "选择".localized`
- Dynamic sentences use format keys: `String(format: "排序：%@".localized, value)`
- Language names come from `AppLanguageCatalog`, never hardcoded in views
- New UI copy must be added to `Localizable.xcstrings`

**Verification:**
```bash
# Run localization audit
xcodebuild test -scheme AppPorts -only-testing:"AppPortsTests/LocalizationAuditTests"
```

See `LOCALIZATION.md` for full details.

## Migration Strategy

AppPorts doesn't migrate all apps the same way:

| App Type | Default Strategy | Notes |
|----------|------------------|-------|
| Native macOS apps | Keep `.app` wrapper, link `Contents` | Default for most apps |
| Self-updating apps (Sparkle/Squirrel) | Symlink whole bundle | Better for auto-updaters |
| iOS apps on Mac | Symlink whole bundle | Disabled by default |
| App Store apps | Follow detected bundle strategy | Disabled by default |
| Multi-app suites/folders | Move & symlink folder | e.g., Microsoft Office |
| System apps | Not migrated | Blocked |
| Running apps | Not migrated | Blocked |

## Git Workflow

- **Main branch**: `main`
- **Development branch**: `develop` (PR target)
- **Commit convention**: Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`)
- PR checks:
  - **Required**: Build smoke test (compilation)
  - **Advisory**: Data directory tests, localization audit (for feedback only)

## Permissions

AppPorts requires **Full Disk Access** to read/modify `/Applications`:
1. System Settings → Privacy & Security → Full Disk Access
2. Add AppPorts and enable toggle
3. Relaunch app

## Key Files to Understand

For understanding core logic:
1. `AppModels.swift` - Data structures
2. `AppMigrationService.swift` - Migration orchestration
3. `AppScanner.swift` - App discovery and classification
4. `ContentView.swift` - Main UI state management

For localization:
1. `Localizable.xcstrings` - All UI strings
2. `AppLanguageOption.swift` - Language catalog
3. `LanguageManager.swift` - Language switching

## Common Issues

- **"App is damaged" error**: Run `xattr -rd com.apple.quarantine /Applications/AppPorts.app`
- **Tests fail locally**: Ensure Xcode is selected: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
- **Localization audit fails**: Missing translations in `Localizable.xcstrings` or unlocalized AppKit strings
