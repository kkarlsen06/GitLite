# Distributing Kvist

Kvist's supported public release path is a Developer ID-signed and notarized
direct download for macOS 14 or later.

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
ZIP, and verifies the final artifact.

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
