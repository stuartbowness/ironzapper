# IronZapper implementation plan

## Product contract

Personal-use native macOS application for Stuart. Apple Silicon only, minimum macOS 26. No Intel target, Rosetta dependency, pre-26 fallback, or compatibility layer. SwiftUI with AppKit where needed, native Liquid Glass, no third-party runtime dependencies.

One application at a time: drop an application, review associated files, move selected items to Trash, see the outcome. Include user files and demonstrably exclusive system-wide components. Preserve shared components and system components whose exclusive ownership cannot be established. No permanent-delete fallback.

Deliver a locally installable IronZapper.app, source, custom icon, and concise build/use instructions. No App Store submission, telemetry, account, updater, bulk cleanup, or background monitoring.

## 1. Establish build and privileged-operation feasibility

- Create an Xcode project with ARM64/macOS 26 settings, an application target, a privileged helper target, and test targets. Keep scanning and ownership policy in a testable Swift module.
- Use an unsandboxed app for filesystem cleanup. Determine available signing credentials and establish repeatable local app/helper signing without committing credentials.
- Prototype SMAppService registration, authenticated XPC, permission denial, and one disposable root-owned file moved into recoverable Trash on its volume.
- Verify the actual destination, Finder visibility, ownership, and recovery of privileged trashed files. Never assume a root process's default Trash is the user's Trash. If the supported route cannot safely trash an item, leave it in place and report it.
- Verify helper lifecycle and Settings approval requirements before integrating the complete UI. The helper runs on demand and does not monitor the machine.

Acceptance: a signed local build launches natively; the helper accepts only the signed app, safely trashes the fixture, rejects unrelated paths, and reports denied permissions accurately.

Environment checked during planning: Xcode 27.0 is installed at /Applications/Xcode.app; the global developer directory selects Command Line Tools. Build with DEVELOPER_DIR explicitly set, without changing global settings. Host reports macOS 27; macOS 26 runtime verification remains a separate requirement.

## 2. Implement read-only discovery and ownership policy

- Extract bundle identifiers, nested bundles/helpers, signing identity, app-group entitlements, service definitions, and relevant installer receipt evidence. Treat metadata as evidence, not authority to delete.
- Search bounded, relevant locations rather than recursively scanning the entire disk:
  - User Library: Preferences (including ByHost), Caches, Application Support, Logs, Saved Application State, Containers, Group Containers, LaunchAgents, and applicable app-specific WebKit/HTTP storage.
  - System Library: application support, preferences, caches, logs, LaunchAgents, LaunchDaemons, and PrivilegedHelperTools.
  - Receipt-referenced files outside those locations only when exclusive ownership and a safe removal policy can be established.
- Inventory installed applications in standard application locations and assess sibling applications, app-group membership, service references, and receipt ownership. Incomplete access or inventory reduces confidence.
- Classify candidates as confirmed exclusive, uncertain, shared, or protected. Record path, category, size, evidence, and access status. Same vendor/signing team or a partial name match is insufficient proof of ownership.
- Select confirmed exclusive items by default. User-level uncertain candidates may be selected after review; shared items and uncertain system components remain ineligible for removal.
- Never select broad vendor folders, system roots, another user's home, or arbitrary receipt paths. Deduplicate nested candidates and avoid double-counting sizes. Exclude IronZapper itself and protected Apple system applications.
- Report inaccessible locations and incomplete scans. Offer Full Disk Access guidance only where needed; admin privileges do not bypass privacy restrictions.

Acceptance: fixture scans find direct matches, preserve shared app groups/vendor data, resist misleading names and receipt paths, and explain every candidate. Scanning never mutates files or stops services.

## 3. Build the review workflow

- Compact resizable single window, approximately 560 × 480 points initially. Native title bar, prominent drop target, and Choose Application button.
- Explicit states: idle, scanning, review, removing, and result. Keep scans asynchronous and cancellable; prevent overlapping removals.
- Review shows the application icon/name, grouped checklist, selected count and size, expandable paths, ownership explanations, and preserved shared components.
- A single Move to Trash action authorizes the displayed selection. Clearly identify when selected support data includes app-created databases or profiles.
- Prompt to quit a running target before removal; cancellation leaves it intact. Do not silently force-quit it.
- Result lists trashed, preserved, failed, and unscanned items separately. Offer Open Trash and Remove Another App. Do not claim complete cleanup after partial failure.

Acceptance: drop and picker workflows agree; keyboard navigation works; incomplete scans and denied privileges remain understandable and actionable.

## 4. Implement removal and service handling

- Convert the reviewed selection into an explicit removal plan. Revalidate file identity, ownership evidence, and permissions immediately before mutation. Reject changed items rather than broadening the selection.
- Use FileManager Trash operations for ordinary files. The helper independently validates every privileged request using an allowlisted policy; it accepts neither arbitrary shell commands nor unrestricted deletion paths.
- Authenticate XPC clients using signing identity and process identity. Harden path handling against symlink traversal, path replacement, and time-of-check/time-of-use races; avoid shell interpolation entirely.
- Stop only confirmed exclusive app services through supported lifecycle operations. Do not misuse SMAppService to manage arbitrary third-party registrations. If safe service removal is unsupported, preserve the relevant component and explain the vendor-uninstaller requirement.
- Move owned data/helpers before the application bundle; leave the app available when prerequisite service handling fails. Track each completed operation, including stopped services, since the operation is not globally atomic.
- Preserve original and resulting Trash paths in a minimal local operation record. Never log file contents. Explain that restoring files may not restore service registration and reinstalling the app may be needed.
- Recognise extensions, drivers, managed software, and other vendor-managed components that require their own uninstaller. Report these explicitly rather than promising exhaustive cleanup.

Acceptance: all successful removals are recoverable in Trash; shared components remain untouched; permission failures, disk errors, changed paths, and partial service failures produce truthful per-item results.

## 5. Finish visual design and icon

- Use native macOS 26 Liquid Glass controls and toolbar treatment directly. Keep the file list on a readable surface; use one restrained electric-blue accent.
- Support light/dark appearance, Dynamic Type where appropriate, VoiceOver labels, keyboard focus, Increase Contrast, Reduce Transparency, and Reduce Motion.
- Create an original titanium zapper icon with an electric-blue energy accent, simple silhouette, and no lettering. Use the imagegen skill for raster artwork, then package appropriate macOS icon assets; inspect at Dock and small list sizes.
- Keep animations brief and subordinate to accurate progress and completion state.

Acceptance: visually inspect idle, review, permission, progress, and partial-result states in both appearances. Icon remains legible at small sizes and ships in the installed app.

## 6. Validate and package

- Automated behavioural tests: exact ownership, shared containers, similar names, malicious metadata, overlapping candidates, access-denied scans, changed files, symlinks, and partial removals.
- Integration tests with disposable applications/services for ordinary and privileged Trash operations, cancellation, recovery, and helper authentication. Never use a real installed application as a destructive test fixture.
- Compare read-only findings against several real installed applications. Real-world scan comparison complements fixtures without treating another uninstaller as ground truth.
- Verify ARM64 architecture, code signatures, embedded helper configuration, deployment target, and launch outside Xcode.
- Test on macOS 26 hardware or a VM before claiming verified support; record separately what was tested only on the macOS 27 host.
- Package a local installable app and document build, permissions, helper lifecycle, recovery limitations, and unsupported component types.

Definition of done: the installed app performs the complete drop → review → Trash → result workflow for both user-owned files and verified exclusive privileged fixtures, preserves shared data, and accurately reports remaining files. Source and build instructions reproduce the verified artifact.

## Reference APIs

- Liquid Glass: https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass
- Service Management: https://developer.apple.com/documentation/servicemanagement/smappservice
- FileManager Trash: https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)

Confirm implementation details against the installed SDK and current Apple documentation during implementation, particularly signing, service lifecycle, and privileged Trash semantics.

## Implementation status

The native app, generated icon, read-only scanner, conservative ownership rules, receipt discovery, signed helper/client, Trash workflow, operation results, and local build are implemented. The installed app lives at `/Applications/Iron Zapper.app`.

The Xcode project intentionally wraps one reproducible build script, which compiles the app and helper as separate executables; Swift Package Manager owns the behavioural tests. This avoids maintaining two independent signing/build configurations.

Stuart's UI feedback is incorporated: one native window title, no add button in the title bar, and a centred results column with left-aligned rows. Full test results and remaining administrator/macOS 26 runtime verification are tracked in `VALIDATION.md`.
