# Iron Zapper

**A native macOS uninstaller that explains what it finds before moving anything.**

Drop an application, review its associated files and ownership evidence, then
move the selected items to Trash. Iron Zapper combines SwiftUI and AppKit with a
Swift discovery and removal core, plus an optional privileged helper.

Built by [Stuart Bowness](https://github.com/stuartbowness), with AI coding
assistance. [MIT licensed](LICENSE). No third-party runtime dependencies.

## Why this exists

Finding files with a similar name is easy. Deciding whether they belong only to
one application is harder. Applications share containers, install background
services, and leave data that may contain a user's saved work.

Iron Zapper makes that uncertainty visible:

- Each candidate carries ownership evidence and a file-identity snapshot.
- Exact, exclusive matches start selected; name-only user data starts unchecked.
- Shared app groups and uncertain system files stay protected.
- Removal rescans ownership and rejects changed items before mutation.
- Files move to Trash; failures do not fall back to permanent deletion.

This is a source project for **Apple Silicon and macOS 26+**. Privileged cleanup
is implemented, but its installed, administrator-approved workflow has **not been
verified end to end**. See [validation and limitations](VALIDATION.md). No notarized
download is provided.

## Start with the tests

Requires Xcode with Swift 6.2+ and a macOS 26-or-newer SDK. Core tests do not need a
signing identity, administrator privileges, or helper registration.

```sh
git clone git@github.com:stuartbowness/ironzapper.git
cd ironzapper
scripts/test.sh
```

The tests exercise ownership decisions, shared packages, changed files, symlinks,
wrapped iOS apps, and privileged-path rejection. Real Trash tests use disposable
fixtures and verify recoverability. They do not uninstall your applications.

For a read-only JSON scan of an application you choose:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift run ironzapper-scan /Applications/Example.app
```

Replace the example path with an installed app. Scan output contains local paths;
review it before sharing.

## Build the app

A valid Apple Development or Developer ID Application signing identity must be
available in your keychain. Set `SIGN_IDENTITY` to select one explicitly.

```sh
scripts/build.sh
scripts/verify-signatures.sh
open "build/Iron Zapper.app"
```

Scripts use `DEVELOPER_DIR` (default `/Applications/Xcode.app/Contents/Developer`)
without changing global Xcode settings. App and helper are ARM64 executables with
hardened runtime and no debug entitlement. Signing does not notarize the app.

The Xcode project wraps the same build script; `Package.swift` owns the core test
targets. See [usage and recovery](docs/usage.md) before removing data or enabling
the optional system helper.

## For engineers reviewing the project

Start with [the architecture](docs/architecture.md), then follow the boundaries:

| Area | Read |
| --- | --- |
| Application identity and wrapped bundles | [AppInspector.swift](Sources/IronZapperCore/AppInspector.swift) |
| Candidate discovery and ownership evidence | [Scanner.swift](Sources/IronZapperCore/Scanner.swift), [Receipts.swift](Sources/IronZapperCore/Receipts.swift) |
| Review state, cancellation, and removal orchestration | [AppModel.swift](App/AppModel.swift) |
| Authenticated helper and independent revalidation | [Helper/main.swift](Helper/main.swift), [HelperProtocol.swift](Shared/HelperProtocol.swift) |
| Descriptor-based privileged file moves | [SecureTrash.swift](Helper/SecureTrash.swift) |
| Behavioural fixtures | [Tests](Tests/IronZapperCoreTests) |

The important tradeoff is conservative coverage: preserving uncertain data is
preferable to claiming every leftover was removed. File moves are not one atomic
transaction, and restoring a service's file does not restore its registration.
Vendor uninstallers remain necessary for some installations.

[Contributing](CONTRIBUTING.md) · [Validation](VALIDATION.md) · [Asset provenance](docs/provenance.md)
