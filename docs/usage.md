# Using Iron Zapper

## Run

After building, open `build/Iron Zapper.app`. Install your signed build in `/Applications` before enabling the optional helper.

1. Drop one `.app` (including Mac-installed iPhone/iPad apps) onto the window, use **Choose Application**, or press ⌘O.
2. Review the selected files. Expand a row to see its path and ownership evidence.
3. Select **Zap!**. A running target must quit first; Iron Zapper never force-quits it.
4. Read the result. Shared, inaccessible, and failed items are reported rather than silently removed.

Application data can include profiles, databases, and saved work. Name-only user-data matches start unchecked. App-group containers and uncertain system files are protected.

For protected Library locations, grant Full Disk Access only if the scan reports that it cannot read them. Administrator privileges do not bypass macOS privacy controls.

## System cleanup

Use **Iron Zapper → Enable System Cleanup…**, then approve Iron Zapper under **System Settings → General → Login Items & Extensions**. The signed helper is embedded in the app and registered through SMAppService. Keep the installed app in `/Applications` while the helper is enabled. An additional administrator authentication is required for each privileged removal operation.

The helper accepts only a matching Apple-issued signing team and application identity, rejects debuggable peers, independently scans ownership, and restricts operations to supported Library paths. It cannot execute arbitrary caller-supplied commands. It stops verified launch services before moving their files.

Use **Iron Zapper → Disable System Cleanup** before moving, replacing, or uninstalling Iron Zapper. macOS can require renewed approval after the helper changes. The build script produces a locally signed build, not a notarized distribution. Actual registration behaviour must be verified on the target Mac.

## Recovery and limits

- Ordinary items use macOS's FileManager Trash API.
- Privileged regular files go into a unique `IronZapper-…` recovery folder in the signed-in user's Trash, with original-location instructions. Original privileged file ownership is retained. Finder **Put Back** is not available for those recovery folders; reinstall an app to restore its background-service registration.
- Files are never permanently deleted as a fallback. Cross-volume privileged moves, symlink paths, unsafe system-directory permissions, and unsupported file types are refused.
- System data is eligible when all readable installer receipts show one owning package that installs only the selected app. Shared package files and multi-app suites are preserved. Receipt-owned directories and unrecorded system data stay in place.
- App groups stay protected. Standard application locations and the current user's Library are searched; other users, keychains, arbitrary custom install locations, drivers, and system extensions are not exhaustively covered.
- Embedded SMAppService jobs, extensions, and vendor-managed installations can require the vendor's own uninstaller. A warning in the scan explains this. No universal dependency registry exists, so Iron Zapper does not promise removal of every leftover.
- Cleanup is not a transaction across all files. After a failure, subsequent selected items are preserved. A stopped service may need its app reinstalled even if its file could not be moved.
- Operation records contain paths and outcomes, not file contents, under `~/Library/Application Support/ai.toyo.IronZapper/Operations`.


For build instructions, see [the README](../README.md). For verification gaps, see [VALIDATION.md](../VALIDATION.md).
