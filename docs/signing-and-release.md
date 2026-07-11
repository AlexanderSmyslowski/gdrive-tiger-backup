# Signing and release checklist

Unsigned packages remain useful for development and CI. Public releases should
use both Apple Developer ID certificate types:

- `Developer ID Application` for `GDrive Backup Tiger.app`
- `Developer ID Installer` for the final `.pkg`

The build never stores certificate material or notarization credentials in the
repository. Import the certificates into the login keychain through Apple's
normal certificate workflow.

## One-time notarization setup

Create a keychain-backed notary profile. Run this interactively and enter the
Apple credentials only at the prompt:

```bash
xcrun notarytool store-credentials "gdrive-tiger-notary"
```

Do not put an app-specific password, private key, certificate archive, or
keychain password in Git, a config file, or a shell script.

## Build, sign, and notarize

Use the exact identity names reported by `security find-identity`:

```bash
APP_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
INSTALLER_SIGN_IDENTITY="Developer ID Installer: Example (TEAMID)" \
NOTARY_PROFILE="gdrive-tiger-notary" \
make pkg
```

`NOTARY_PROFILE` is accepted only when both signing identities are provided.
The package builder signs the app with hardened runtime and a secure timestamp,
signs the installer, waits for Apple's notary result, and staples the ticket.

## Verify before publishing

```bash
./packaging/verify-pkg.sh --expect-signed dist/GDrive-Backup-Tiger-*.pkg
pkgutil --check-signature dist/GDrive-Backup-Tiger-*.pkg
spctl --assess --type install --verbose=2 dist/GDrive-Backup-Tiger-*.pkg
xcrun stapler validate dist/GDrive-Backup-Tiger-*.pkg
```

Also install the package on a clean macOS 13 test account and on the current
macOS release, then complete one `--dry-run` on each before attaching it to a
GitHub release. GitHub's hosted CI verifies the deployment metadata and both
binary architectures, but it does not provide a macOS 13 runtime test here.

## CI behavior

The normal GitHub Actions workflow deliberately builds an unsigned package. It
checks source syntax, unit/integration tests, app linking, ad-hoc code-signing,
package contents, permissions, identifiers, and metadata without exposing
release credentials. Release signing and notarization stay an explicit
maintainer action until a separately reviewed secret-management workflow is
introduced.
