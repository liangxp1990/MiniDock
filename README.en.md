# MiniDock · Micro App Dock

English | [中文](README.md)

> Tired of hunting for apps in the macOS 26+ Dock? MiniDock groups your favorite apps into
> **category folders** living in your Dock: each folder icon is a synthesized **glass mosaic
> thumbnail** showing the apps inside, clicking it opens the **native system glass grid**,
> and clicking any icon launches instantly. Whichever display your Dock is on (including
> external monitors), the popup follows — positioned entirely by the system.

**Free and open source** (MIT). Every feature is unrestricted, and the UI supports
**English / 简体中文** (follows your system language).

## Features

- **Category management**: create / rename / delete categories, pick apps from a searchable
  list of installed applications, drag-and-drop `.app` bundles, reorder by dragging
- **Glass mosaic covers**: plate styles (glass light / glass dark / solid / two-color gradient /
  custom image), layouts (auto / 2×2 / 3×3), corner radius / spacing / scale sliders, count badge — with live preview
- **Dock popup parameters**: popup style (auto / fan / grid / list), sorting (including
  "by my order"), icon size (follow-system default is the most compact)
- **Unified settings panel**: "Cover & Popup" in one place — live preview stage (tile +
  popup linked) on the left, Settings-style form on the right, every control in Liquid Glass
- **Liquid Glass**: native `glassEffect` on macOS 26 (Finder-style toolbar capsules with
  labels beneath, glass cards in settings), automatic fallback on older systems
- **Health checks**: moved/deleted apps are flagged in red and repairable in one click;
  the sync engine has an empty-config fuse against accidental wipes

## How it works

MiniDock is a manager — the actual Dock experience comes from the native macOS Stack:

```
~/Applications/MiniDock/
├── VPN/                  ← category folder (pin with one click / drag into Dock)
│   ├── AnyConnect -> /Applications/AnyConnect.app   (symlink)
│   └── ...
└── .minidock-state.json  ← engine state (icon signatures, folder mapping)
```

- Each category is a real folder containing **symlinks** to your apps (nothing is copied or moved)
- The folder icon is synthesized and written as a hand-built multi-size ICNS (1024→16px);
  it regenerates automatically whenever members change
- Click the mosaic tile in your Dock → native grid popup → click any icon to launch
- Category name = folder name (shown on Dock hover), rename anytime

## Build & Package

```bash
./Scripts/make-app.sh          # release build into build/MiniDock.app (ad-hoc signed)
./Scripts/make-app.sh debug    # debug build
./Scripts/make-dmg.sh 1.14     # DMG installer (drag-to-Applications layout)
swift build && swift test      # build & run tests (33)
```

Requirements: Xcode command line tools (swift 6+, iconutil, sips, codesign), macOS 14+.

## Usage (three steps)

1. **Create a category**, name it, and pick apps from the installed-apps list
2. **Put it in the Dock**: click "Pin to Dock" in the toolbar (Dock restarts for ~1s),
   or drag the category folder to the right of the Dock divider
3. **Click to use**: click the mosaic tile in your Dock to open the grid, click any icon to launch

If the tile shows only one app: right-click it → Display As → Folder.

## FAQ

- **Tile shows only the first app** — the Dock tile is in stack mode; right-click →
  Display As → Folder (MiniDock writes this automatically on pin; manual fix is a rare fallback)
- **Popup too big / too small** — Settings → Dock Popup → "Follow system default size" (most compact)
- **The 5th app doesn't show with forced 2×2** — 2×2 shows at most 4 icons; extras are
  collapsed (3×3 shows up to 9)
- **An app was moved or deleted** — it's flagged red in the manager; click to choose its new location

## Project layout

```
Sources/MiniDock/
├── MiniDockApp.swift          # entry point + Dock-click window reopen
├── AppState.swift             # global state (categories/apps/settings/health)
├── Models/AppConfig.swift     # config models (category/cover style/popup prefs, JSON persisted)
├── Services/
│   ├── DockSyncEngine.swift   # folder/symlink/icon sync engine (signature-based updates)
│   ├── DockPinner.swift       # pin to Dock (dock plist writes + parameter calibration)
│   ├── FolderIconWriter.swift # hand-built ICNS resource-fork writer (bypasses IconServices crash)
│   ├── MosaicIconGenerator.swift # mosaic cover synthesis
│   └── AppScanner.swift       # installed-apps scanner
├── Views/                     # main window / settings sheets / glass components / onboarding
└── Resources/en.lproj/        # English UI strings (base language: Simplified Chinese)
Tests/MiniDockTests/           # 33 unit tests
Scripts/                       # make-app.sh packaging + make-dmg.sh installer + gen-icon.swift
docs/pitfalls.md               # macOS 26 pitfalls log (toolbar material, resource forks, reopen, …)
```

## Safety boundaries

- Only creates folders and **symlinks** under `~/Applications/MiniDock/`; never copies,
  moves, or deletes any real app
- Deleting a category removes only its folder and links
- Dock parameters are written only to the tile keys of `persistent-others`
  (displayas / showas / arrangement / preferreditemsize)

## Roadmap

The open-source edition stays free with full features. A more powerful
**Website Edition** (free MAS version as funnel + paid website version) is planned in
[docs/roadmap-website-edition.md](docs/roadmap-website-edition.md).

## License

[MIT](LICENSE) · See [CHANGELOG.md](CHANGELOG.md) for release history.
