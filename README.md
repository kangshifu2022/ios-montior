# ios-montior

This repository now includes a GitHub Actions workflow that builds an Ad Hoc `.ipa` from a manually supplied distribution certificate and provisioning profile.

## Required GitHub Secrets

- `BUILD_CERTIFICATE_BASE64`: Base64 content of your `.p12` distribution certificate.
- `P12_PASSWORD`: Password for the `.p12` certificate.
- `BUILD_PROVISIONING_PROFILE_BASE64`: Base64 content of your Ad Hoc `.mobileprovision` file.
- `KEYCHAIN_PASSWORD`: Optional password for the temporary CI keychain. If omitted, the workflow generates one.

## What The Workflow Does

1. Imports your `.p12` certificate into a temporary keychain on the macOS runner.
2. Installs the Ad Hoc provisioning profile.
3. Resolves the app bundle identifier from the Xcode project.
4. Archives the app with manual signing.
5. Exports the `.ipa` and uploads it as a GitHub Actions artifact.

The workflow file is [`.github/workflows/ios.yml`](/root/ios-montior/.github/workflows/ios.yml) and the shared scheme used by CI is [`test.xcodeproj/xcshareddata/xcschemes/test.xcscheme`](/root/ios-montior/test/test.xcodeproj/xcshareddata/xcschemes/test.xcscheme).

## Base64 Examples

On macOS:

```bash
base64 -i certificate.p12 | pbcopy
base64 -i profile.mobileprovision | pbcopy
```

On Linux:

```bash
base64 -w 0 certificate.p12
base64 -w 0 profile.mobileprovision
```

## Triggering A Build

The workflow runs on pushes to `master` and also supports manual triggering from the GitHub Actions UI. The exported IPA artifact is uploaded under the name `ios-adhoc-ipa`.
