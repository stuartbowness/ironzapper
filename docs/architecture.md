# Architecture

Iron Zapper separates read-only discovery, user selection, and mutation. The
scanner supplies evidence; the UI selects eligible candidates; the removal path
checks that the evidence still applies.

## Data flow

```text
Application URL → AppInspector → AppScanner + ReceiptInspector
                                      ↓
                            ScanReport / Candidate[]
                                      ↓
                             review and selection
                                      ↓
                          rescan + identity comparison
                             ↙                  ↘
                    ordinary files       privileged candidates
                    RemovalEngine        authenticated XPC helper
                    FileManager Trash    independent scan + SecureTrash
                             ↘                  ↙
                         per-item outcomes + local record
```

`Models.swift` holds the boundary types. A candidate records category, ownership,
reason, size completeness, privilege requirement, and filesystem identity.
Ownership is exclusive, uncertain, shared, or protected. Uncertain ordinary data
can be selected manually; uncertain services and system data cannot.

## Discovery is evidence, not permission

`AppInspector` reads bundle metadata, signing information, and declared groups.
It recognises wrapped iOS applications while keeping the outer bundle as the
removal target. Wrapper traversal must remain confined to that bundle.

`Scanner` searches bounded Library locations and inventories standard application
roots. `Receipts` uses installer evidence to distinguish exclusive files from
shared packages and multi-app suites. Incomplete access produces warnings;
matching a vendor or a partial name does not establish exclusive ownership.

App groups stay protected. There is no universal dependency registry, and other
users' data, arbitrary install locations, drivers, and system extensions are not
exhaustively covered.

## UI and concurrency

`AppModel` is main-actor isolated and exposes idle, scanning, review, removing,
and result states. Discovery runs in a detached task. Cancelling a scan propagates
cancellation and prevents its result from replacing newer UI state. Removal
blocks overlapping operations and performs a fresh scan before acting.

A running target is asked to quit; it is not force-killed. Selected items are
ordered so services and support data precede the application. After a reported
failure, later selected items are preserved. Results distinguish what moved
from what failed or stayed in place.

## Privilege boundary

The app registers its embedded daemon with SMAppService. macOS approval and a
per-operation administrator authorization are required. Client and helper use
code-signing requirements tied to application identifier and the executing
binary's signing team, excluding debug-entitled peers.

The helper derives the user's identity from XPC, checks authorization, limits
request size, verifies the selected app under `/Applications`, and rescans
ownership independently. It does not accept arbitrary shell commands. Launch
service operations use an executable plus argument array.

`SecureTrash` walks directory descriptors without following symlinks, checks
trusted source ancestry and file identity, and restricts privileged moves to
supported locations and root-owned regular files. It uses an exclusive rename
into a recovery folder in the user's Trash; cross-volume moves are refused.
These checks narrow filesystem risks but are not a claim of a formal security
proof or atomicity across validation and mutation.

## Recovery and failure

Ordinary files use FileManager's Trash API. Privileged files retain their original
ownership in a recovery directory with original-location instructions. Finder
Put Back is unavailable for that directory. Reinstalling the application may be
necessary to restore background-service registration.

The operation is not transactional. A service can stop before a file move fails;
an earlier successful move is not rolled back. Local records contain paths and
outcomes, not file contents. See [usage](usage.md) for their location.

## Build boundary

Swift Package Manager builds the core, scan CLI, privileged filesystem module,
and tests. The app and daemon are separate executables compiled and signed by
`scripts/build.sh`. The Xcode project wraps that script to avoid a second set of
signing settings. Internal `ai.toyo.IronZapper` identifiers are retained for
compatibility; publishing the source does not change installed registrations.

See [VALIDATION.md](../VALIDATION.md) for tested behaviour and the unverified
installed-helper, macOS 26 runtime, and accessibility paths.
