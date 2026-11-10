# Validation and limitations

## Release verification

The original development host was Apple Silicon running macOS 27 with Xcode 27.
The deployment target is macOS 26; that setting does not establish macOS 26 runtime
compatibility.

Release cleanup on 2026-11-10 used Apple Silicon, macOS 27.2, and Xcode 27.2:

- All 28 core tests passed.
- The app and helper built with a local signing identity and passed strict
  signature verification. Their peer requirements rejected an unrelated executable.
- Shell syntax and local documentation link checks passed.
- Automated secret scanning found no detected secrets in the existing Git history.

CI runs the core suite on a GitHub-hosted macOS runner. It does not verify signing,
helper registration, or interactive UI behaviour.

The automated suite contains 28 Swift Testing cases covering exact and near-name
matches, duplicate installations, shared app groups, receipt ownership, multi-app
packages, path escape attempts, changed files, symlinks, shared launch services,
inaccessible directories, wrapped iOS applications, and privileged-path rejection.
Real Trash tests verify recovery of disposable fixture contents.

The app-model integration test exercises scan → review → changed-file rejection
→ rescan → Trash → result. It uses disposable data and verifies the resulting
Trash paths. Its offscreen image rendering cannot establish that native scroll
views, glass effects, or accessibility work correctly in an interactive window.

## Not verified end to end

- An authenticated XPC session with the macOS-approved installed daemon.
- Root-owned fixture service shutdown and recovery through that daemon.
- Runtime behaviour on macOS 26.
- Full VoiceOver navigation and all increased-contrast/reduced-transparency states.

Code-signing predicates and filesystem rejection tests exercise parts of the
privileged boundary, not the complete installed-helper workflow. This source
release does not include a notarized binary or claim a completed security audit.

## Behavioural limits

Scanning is bounded and can be incomplete because of permissions or nonstandard
installations. Shared app groups, unsupported system components, and uncertain
system data stay in place. Administrator privileges do not bypass macOS privacy
controls. Some applications require their vendor's uninstaller.

Removal is not atomic across files. A stopped service can remain stopped after a
later failure, and recovering its file does not restore its registration. There
is no permanent-delete fallback. See [usage and recovery](docs/usage.md).
