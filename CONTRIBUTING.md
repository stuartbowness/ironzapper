# Contributing

Read [the architecture](docs/architecture.md) before changing ownership or removal
policy. Explain which observable behaviour changes and why an existing file is
now eligible or protected.

## Checks

On Apple Silicon with Xcode and a macOS 26-or-newer SDK:

```sh
scripts/test.sh
scripts/test-app.sh
scripts/build.sh
scripts/verify-signatures.sh
```

Core tests need no signing identity. The app-model integration test creates a
uniquely named app fixture and preference file in the current user's Library,
moves only those fixtures to Trash, verifies recovery, and removes its own test
data and operation records. It writes images under ignored `Artifacts/`.
It is not a full interactive UI or accessibility test.

Building and signature verification require your own signing identity. Never
commit certificates, keys, real scan results, local paths, or operation records.
CI runs core tests and shell syntax checks; it does not install a privileged daemon.

Use disposable fixtures for mutation tests. Do not use installed applications as
removal fixtures. Tests should demonstrate preservation as well as successful
moves, especially for shared ownership, changed identities, and symlink paths.

## Optional privileged verification

This is a separate interactive check, not part of CI. Build and install your signed
app, enable system cleanup, and approve the macOS prompt. Then use
`scripts/probe-helper.sh` and inspect `scripts/create-system-fixture.sh` before
running it with administrator privileges. The fixture runs `/bin/sleep` from its
own disposable app and prints cleanup instructions.

Verify service shutdown, the original file's absence, the recovery file's contents
and ownership, and rejection of unrelated requests. Record actual results in
`VALIDATION.md`; a passing signature predicate alone is not an XPC integration test.

Run `scripts/make-project.py` after changing the source-file layout. Runtime code
has no third-party dependencies. Preserve [MIT](LICENSE) and asset provenance.
