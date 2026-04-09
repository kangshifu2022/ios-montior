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
6. Publishes an install page, manifest, and IPA to GitHub Pages for direct iPhone/iPad installation.

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

## Stable Baseline

The current known-good CI and installation baseline is tagged as `adhoc-pages-stable-20260409`. That tag represents the first version confirmed to:

1. Archive and export an Ad Hoc IPA in GitHub Actions.
2. Publish an install page through GitHub Pages.
3. Install successfully from Safari on iPhone.

## Certificate Truth Test

[`test-certs.yml`](/root/ios-montior/.github/workflows/test-certs.yml) is intentionally kept as a minimal certificate and provisioning-profile verifier. Its purpose is to answer one narrow question: are the stored secrets valid and importable on a macOS runner.

Use that workflow before blaming `p12` content, password, or provisioning-profile secrets. If `test-certs.yml` passes, certificate input data is not the primary problem and the bug is elsewhere in the build or signing workflow.

## Direct Install Link

After a successful build, the workflow also deploys a GitHub Pages install site. The default install URL for this repository is:

`https://kangshifu2022.github.io/ios-montior/`

Open that page in Safari on the device, then tap the install button. iOS will use the generated `manifest.plist` to install the app.

If you want to serve the install page from a custom domain instead of the default GitHub Pages URL, add a repository variable named `IOS_INSTALL_BASE_URL`, for example:

```text
https://downloads.example.com/ios-montior
```

If the deploy job fails the first time, enable GitHub Pages for the repository and use GitHub Actions as the deployment source. GitHub's official Pages deployment actions are [`actions/upload-pages-artifact`](https://github.com/actions/upload-pages-artifact) and [`actions/deploy-pages`](https://github.com/actions/deploy-pages).
