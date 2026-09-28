# Iron Zapper

A personal native Mac uninstaller. Drop an application, review its associated files, and move the selected items to Trash.

**Apple Silicon and macOS 26+ only.** Native SwiftUI Liquid Glass controls hosted in an AppKit window. No third-party runtime dependencies or older-platform fallbacks.

## Run

Open `/Applications/Iron Zapper.app` (the installed build), or `build/Iron Zapper.app` after building.

1. Drop one `.app` (including Mac-installed iPhone/iPad apps) onto the window, use **Choose Application**, or press ⌘O.
2. Review the selected files. Expand a row to see its path and ownership evidence.
3. Select **Zap!**. A running target must quit first; Iron Zapper never force-quits it.
4. Read the result. Shared, inaccessible, and failed items are reported rather than silently removed.

Application data can include profiles, databases, and saved work. Name-only user-data matches start unchecked. App-group containers and uncertain system files are protected.

For protected Library locations, grant Full Disk Access only if the scan reports that it cannot read them. Administrator privileges do not bypass macOS privacy controls.

## System cleanup

Use **Iron Zapper → Enable System Cleanup…**, then approve Iron Zapper under **System Settings → General → Login Items & Extensions**. The signed helper is embedded in the app and registered through SMAppService. Keep the installed app in `/Applications` while the helper is enabled. An additional administrator authentication is required for each privileged removal operation.

The helper accepts only a matching Apple-signed team/application identity, rejects debuggable peers, independently scans ownership, and restricts operations to supported Library paths. It cannot execute arbitrary caller-supplied commands. It stops verified launch services before moving their files.

Use **Iron Zapper → Disable System Cleanup** before moving, replacing, or uninstalling Iron Zapper. macOS can require renewed approval after the helper changes. Local Apple Development signing is used on this machine; this is not a notarized distribution build. Actual registration behaviour must be verified on the target Mac.

## Recovery and limits

- Ordinary items use macOS's FileManager Trash API.
- Privileged regular files go into a unique `IronZapper-…` recovery folder in the signed-in user's Trash, with original-location instructions. Original privileged file ownership is retained. Finder **Put Back** is not available for those recovery folders; reinstall an app to restore its background-service registration.
- Files are never permanently deleted as a fallback. Cross-volume privileged moves, symlink paths, unsafe system-directory permissions, and unsupported file types are refused.
- System data is eligible when all readable installer receipts show one owning package that installs only the selected app. Shared package files and multi-app suites are preserved. Receipt-owned directories and unrecorded system data stay in place.
- App groups stay protected. Standard application locations and the current user's Library are searched; other users, keychains, arbitrary custom install locations, drivers, and system extensions are not exhaustively covered.
- Embedded SMAppService jobs, extensions, and vendor-managed installations can require the vendor's own uninstaller. A warning in the scan explains this. No universal dependency registry exists, so Iron Zapper does not promise removal of every leftover.
- Cleanup is not a transaction across all files. After a failure, subsequent selected items are preserved. A stopped service may need its app reinstalled even if its file could not be moved.
- Operation records contain paths and outcomes, not file contents, under `~/Library/Application Support/ai.toyo.IronZapper/Operations`.

## Build and tests

Requires Xcode with a macOS 26-or-newer SDK and an Apple Development or Developer ID Application signing identity in the local keychain.

```sh
scripts/build.sh
scripts/test.sh
scripts/test-app.sh
scripts/verify-signatures.sh
open "build/Iron Zapper.app"
```

The build script selects Xcode through `DEVELOPER_DIR` without changing global developer settings. Set `SIGN_IDENTITY` to choose a specific identity. Both binaries are ARM64 with a macOS 26 deployment target and hardened runtime, without `get-task-allow`.

`IronZapper.xcodeproj` exposes the same build script and a Core Tests target. Open `Package.swift` for Swift package test navigation. `scripts/make-project.py` regenerates the Xcode source groups after adding files. The build script is the single source of build/signing configuration; the app and helper compile as separate executables.

Read-only diagnostic scan:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run ironzapper-scan /Applications/AppZapper.app
```

Manual privileged verification (disposable fixture only):

```sh
# First enable system cleanup and approve the macOS prompt.
scripts/probe-helper.sh
sudo scripts/create-system-fixture.sh
```

Drop the exact fixture app printed by the script into Iron Zapper. Select its launch daemon, move both to Trash, and verify that `launchctl print system/<printed label>` reports the service absent and that the root-owned plist is recoverable in Trash. The fixture runs only `/bin/sleep` from its own app bundle. The script prints cleanup instructions if testing is interrupted.

## Source layout

- `Sources/IronZapperCore`: application identity, filesystem discovery, receipt ownership, removal policy, operation records.
- `App`: SwiftUI views, AppKit lifecycle, state model, authenticated helper client.
- `Shared`: XPC protocol and peer signing requirements.
- `Helper`: independently validated privileged operations and descriptor-based Trash moves.
- `Tests`: disposable ownership/removal fixtures and privileged-path rejection tests.
- `Resources`: signed-bundle metadata, generated icon artwork, packaged icon, and exact generation prompt in `ICON.md`.

See `VALIDATION.md` for what has actually been verified and what still requires a macOS 26 machine or interactive administrator approval.
