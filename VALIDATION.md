# Validation record

Host: Apple Silicon, macOS 27.0. Xcode 27.0. Deployment target: macOS 26.0. Both installed executables are ARM64 only.

## Verified

- Signed release build with the local Apple Development identity; hardened runtime and no debug entitlement.
- Both app and helper pass strict signature verification and the exact peer signing requirements used by XPC. An unrelated signed system executable fails those requirements.
- 28 automated Swift Testing cases pass, covering exact/near-match names, duplicate installations, shared app groups, nested product data, receipt ownership, multi-app packages, path escape attempts, replaced/changed files, symlinks, shared launch services, inaccessible directories, framework sizes, and privileged-path rejection.
- A real ordinary FileManager Trash operation preserves the disposable fixture's contents for recovery.
- App-model integration: scan → review → reject changed data before mutation → rescan → Trash → success result. Both disposable application and preference file were verified in Trash and then cleaned up. No real application was removed by the test runner.
- Read-only scans of AppZapper, Bartender, and Docker. AppZapper preferences are selected by exact bundle identifier; name-only support data is unchecked. App groups are protected. Docker's declared signed helper and corresponding launch daemon are discovered.
- Installed app launches outside Xcode. Stuart tested the review interface and reported it working. His UI feedback was addressed: custom title badge and plus button removed, leaving the native title; results now use a centred 420-point column with internally left-aligned rows.
- Generated icon inspected at full size and in the rendered idle interface. Light-mode idle layout inspected. SwiftUI ImageRenderer cannot faithfully capture native scroll views or all glass controls, so its review/result renders are not treated as complete visual verification. Stuart's supplied screenshot confirms the actual review list renders.

## Not yet verified

- Live authenticated XPC handshake with a macOS-approved installed daemon. The code-signing predicates are verified independently; the actual connection needs system-cleanup approval.
- Root-owned fixture service shutdown and recovery through the installed privileged helper. A disposable fixture creator and positive/negative XPC probe are provided. No successful privileged run has been recorded in this session; `sudo -n` reports that authentication is required.
- Actual behaviour on macOS 26. This machine runs macOS 27; deployment-target inspection does not substitute for a macOS 26 runtime test.
- Full VoiceOver interaction and all increased-contrast/reduced-transparency combinations.

These gaps mean privileged cleanup is implemented but should not yet be described as end-to-end verified. Nothing in the build bypasses macOS approval or falls back to permanent deletion.

## Wealthica and Dock icon fixes

- Reproduced Wealthica rejection: its macOS-installed iOS application uses `WrappedBundle → Wrapper/Wealthica.app/Info.plist`, not `Contents/Info.plist`.
- Added confined wrapper metadata discovery while retaining the outer application as the removal target. Four regression tests cover recognition, escaping links, redirected wrapper directories, and recovery of the complete wrapper from Trash.
- A read-only scan of the actual `/Applications/Wealthica.app` succeeds. Wealthica was not removed during verification.
- Replaced handwritten legacy icon packaging with an Icon Composer document and `actool` output. Inspected the native macOS 26 icon render at Dock scale: the original artwork fills one tile, with no white surround.

## Iron icon redesign

Replaced the blue phaser artwork with a forged-iron lightning bolt on textured charcoal, generated with the built-in imagegen tool. Updated both the Icon Composer asset and the drop-screen artwork. Inspected the native macOS icon render at Dock scale; the bolt stays legible and the tile has no white surround. This change is limited to icon assets and the bundle build number.

## Native glass surface

Removed the opaque window colour and blue radial gradient. The AppKit window uses a clear, non-opaque backing with an NSVisualEffectView behind-window material. This replaces the full-window NSGlassEffectView, whose separate rounded rim visibly conflicted with the native window corners. macOS now owns the outer frame and corner clipping. Review groups, the action panel, and buttons retain native Liquid Glass effects without an app-wide tint override. The drop target uses a darker translucent fill with an inner shadow and one subtle border.

Build and signing checks pass after the window change. Live appearance depends on desktop content and system accessibility settings; offscreen ImageRenderer snapshots do not validate that backdrop effect. The latest window-edge change still needs visual confirmation on the desktop.

## Branding and sound

The app is displayed and installed as Iron Zapper; internal bundle and helper identifiers remain unchanged. The four main headings use the approved zap-themed copy. A bundled original 0.38-second electrical sound plays asynchronously after removal validation. The WAV is reproducible with `scripts/make-zap-sound.py`. The app-model cleanup integration test passed after the sound was added.
