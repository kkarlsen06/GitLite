# Distributing Kvist

Kvist's supported public release path is a Developer ID-signed and notarized
direct download for macOS 26 or later.

## Prerequisites

- An active Apple Developer Program membership.
- A `Developer ID Application` certificate in the login keychain.
- A notarytool keychain profile created once with:

  ```sh
  xcrun notarytool store-credentials kvist-notary
  ```

## Create a release

Run:

```sh
Scripts/release.sh
```

The script locates the Developer ID Application identity, builds the app,
enables the hardened runtime, signs with a secure timestamp, submits a ZIP to
Apple's notary service, staples the accepted ticket to the app, recreates the
ZIP, and verifies the final artifact. It then builds a drag-to-Applications
disk image from the stapled app (`Scripts/dmg.sh`), signs it, and notarizes
and staples the disk image as its own artifact. The release produces both
`dist/Kvist.zip` and `dist/Kvist.dmg`.

The disk image's Finder window layout is written by Finder itself, so
`Scripts/dmg.sh` requires a logged-in GUI session and Automation permission
for Finder; it cannot run headless.

To select a particular identity or notary profile:

```sh
KVIST_SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" \
KVIST_NOTARY_PROFILE="kvist-notary" \
Scripts/release.sh
```

`Scripts/package.sh` intentionally creates an ad-hoc-signed local development
build when `KVIST_SIGNING_IDENTITY` is not set. Do not distribute that build.

The release ZIP contains Kvist's license, privacy notice, and third-party
notices inside the app bundle. Update those documents whenever dependencies or
data flows change.
