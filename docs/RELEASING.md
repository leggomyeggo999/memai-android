# Releasing MemDroid

All release artifacts are produced by [`.github/workflows/release.yml`](../.github/workflows/release.yml).
Nothing is built on a developer machine.

This is separate from `.github/workflows/flutter_ci.yml`, which runs `flutter analyze`,
`flutter test`, and the Android emulator integration test on every push/PR to `main`.
The release workflow does **not** re-run those checks — merge to `main` green first.

---

## What gets built

| # | Job | Runner | Output |
|---|-----|--------|--------|
| 1 | `android` | `ubuntu-latest` | 3 per-ABI APKs, 1 universal APK, 1 AAB |
| 2 | `macos-dmg` | `macos-latest` | `MemDroid-<version>-macos.dmg` |
| 3 | `windows-inno` | `windows-latest` | `MemDroid-<version>-windows-setup.exe` |
| 4 | `ios-testflight` | `macos-latest` | signed `.ipa`, uploaded to TestFlight |

Exact filenames for version `X.Y.Z`:

```
MemDroid-X.Y.Z-android-armeabi-v7a.apk
MemDroid-X.Y.Z-android-arm64-v8a.apk     <- what most modern phones want
MemDroid-X.Y.Z-android-x86_64.apk
MemDroid-X.Y.Z-android-universal.apk     <- works everywhere, larger
MemDroid-X.Y.Z-android.aab               <- Google Play upload format
MemDroid-X.Y.Z-macos.dmg
MemDroid-X.Y.Z-windows-setup.exe
MemDroid-X.Y.Z-build<run_number>.ipa
```

Each platform artifact also ships a short `README-*.txt` explaining its signing caveat.

---

## How to cut a release

### Tagged release (publishes a GitHub Release)

1. Bump `version:` in `pubspec.yaml` (e.g. `1.0.4+5`) and merge to `main`.
2. Tag the merge commit and push the tag:

   ```bash
   git tag v1.0.4
   git push origin v1.0.4
   ```

3. The workflow builds all four platforms and attaches every desktop/mobile
   artifact to a GitHub Release named `MemDroid 1.0.4`.

The tag **must** start with `v` — that is the trigger pattern, and the leading `v`
is stripped to form the version. A tag containing a hyphen (`v1.1.0-beta.1`)
is published as a **pre-release** automatically.

### On-demand build (no tag, no Release)

Actions → **Release** → **Run workflow**. Two optional inputs:

- **version** — override the string used in artifact names. Defaults to the
  `pubspec.yaml` version with the `+build` suffix stripped.
- **run_ios** — set to `false` to skip the TestFlight job even when secrets exist.

Artifacts land under the run's **Artifacts** section (30-day retention). No
GitHub Release is created.

### Where the version comes from

Resolved **once**, in the `version` job, and passed to every other job — including
the Inno Setup `/DAppVersion=` define, so the installer's version can never
disagree with the filename:

```
workflow_dispatch input  >  pushed tag (v prefix stripped)  >  pubspec.yaml
```

### Flutter version

Pinned in one place, at the top of `release.yml`:

```yaml
env:
  FLUTTER_VERSION: "3.44.5"
```

Release builds should be reproducible, so this is pinned rather than floating on
whatever `stable` happens to be. Bump this line when the project moves Flutter
versions. If the pin is ever wrong, every job fails immediately at the setup step
with a clear "version not found" error — it cannot silently produce a bad artifact.

---

## Signing caveats — read before distributing

### Android artifacts are DEBUG-signed

`android/app/build.gradle.kts` uses a release keystore **only if**
`android/key.properties` exists, and falls back to the Flutter debug key
otherwise. CI does not create that file, so release APKs and the AAB are signed
with the debug key.

> The filename is `key.properties`, **not** `keystore.properties`. The Gradle
> script reads `rootProject.file("key.properties")` — `rootProject` here is the
> `android/` directory. A file under any other name is ignored *silently*: the
> build succeeds and quietly falls back to the debug key.

Consequences:

- Fine for sideloading and testing.
- **Cannot be uploaded to Google Play.**
- Will **not** install as an upgrade over a build signed with a different key —
  users must uninstall first.

To produce properly signed builds, create `android/key.properties`:

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Doing this in CI means adding the keystore as a base64 secret plus a step that
decodes it and writes `key.properties` before `flutter build`. That is
deliberately **not** wired up yet — no keystore has been supplied. Nothing in the
workflow needs to change until it is.

### The macOS DMG is unsigned and unnotarized

The app is not code-signed with a Developer ID certificate and has not been
notarized. Gatekeeper will block first launch with either
*"MemDroid is damaged and can't be opened"* or *"cannot be opened because the
developer cannot be verified"*. **The download is not actually corrupt** — that is
just what Gatekeeper says about an unnotarized, quarantined app.

Users must clear the quarantine attribute:

```bash
xattr -dr com.apple.quarantine /Applications/MemDroid.app
```

Or right-click (Control-click) the app → **Open** → confirm. On macOS 15+ they may
instead need **System Settings → Privacy & Security → Open Anyway**.

This text ships inside the artifact as `README-macOS-Gatekeeper.txt` and is
repeated in the GitHub Release body. Removing this caveat requires an Apple
Developer ID certificate and a notarization step (`xcrun notarytool submit`).

### The Windows installer is unsigned

No Authenticode certificate, so SmartScreen shows *"Windows protected your PC"* on
first run. Users choose **More info → Run anyway**. Shipped as
`README-Windows-SmartScreen.txt`.

### Why `hdiutil` instead of `create-dmg`

`create-dmg` needs a Homebrew install and is well known for exiting non-zero even
on success — its AppleScript window-arrangement step fails when no GUI session is
attached, which is exactly the CI case. Working around that requires `|| true`,
which then masks genuine failures. `hdiutil` ships with macOS, is deterministic,
and has a trustworthy exit code. The trade-off is no custom volume background; the
`/Applications` symlink still gives the standard drag-to-install gesture.

---

## Windows installer dependency

The `windows-inno` job compiles `installers/windows/memdroid.iss`. That script is
maintained separately from this workflow. The contract between them:

- The script lives at exactly `installers/windows/memdroid.iss`.
- It accepts `/DAppVersion=X.Y.Z` and uses it for `AppVersion`.
  (If it also sets `VersionInfoVersion`, that field requires a numeric `a.b.c.d`
  form — a pre-release version like `1.1.0-beta.1` must be normalised inside the
  script, not here.)
- It packages the Flutter output from `build\windows\x64\runner\Release\`
  (`MemDroid.exe` plus `data\` and the bundled DLLs). Shipping only the `.exe`
  produces an installer that fails at launch.

The workflow passes `/O` and `/F` to ISCC, overriding whatever `OutputDir` and
`OutputBaseFilename` the script declares, so the artifact name is controlled in
one place. Inno Setup 6 is installed on the runner with `choco install innosetup`.

If the `.iss` file is missing the job fails with an explicit error rather than
silently skipping.

---

## iOS / TestFlight secrets

**The `ios-testflight` job is skipped, not failed, when these are absent.** The
`version` job checks each secret and publishes an `ios_ready` output that gates
the job; the run summary lists exactly which secrets are missing. The Android,
macOS, and Windows artifacts still build and still publish.

(The check has to live in a step rather than a job-level `if:` because the
`secrets` context is not available in job-level conditions.)

Add these under **Settings → Secrets and variables → Actions → Repository secrets**.

| Secret | What it is | Where to get it |
|---|---|---|
| `APP_STORE_CONNECT_KEY_ID` | ~10-char key ID, e.g. `2X9R4HXF34` | App Store Connect → Users and Access → Integrations → App Store Connect API. Shown in the key list. |
| `APP_STORE_CONNECT_ISSUER_ID` | UUID shared by all keys in the team | Same page, labelled **Issuer ID** above the key table. |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Full contents of the `AuthKey_<KEY_ID>.p8` file, including the BEGIN/END lines | Downloaded **once** when the key is created — Apple will not let you download it again. Give the key the **App Manager** role. Paste the file contents verbatim. |
| `IOS_DIST_CERTIFICATE_P12_BASE64` | Apple Distribution certificate + private key, as a base64 `.p12` | Keychain Access → select the cert **and** its private key → Export as `.p12`. Then `base64 -i cert.p12 \| pbcopy`. |
| `IOS_DIST_CERTIFICATE_PASSWORD` | Passphrase set during the `.p12` export | You choose it at export time. **Optional** — omit if the export had an empty passphrase. |
| `IOS_PROVISIONING_PROFILE_BASE64` | App Store provisioning profile, base64-encoded | developer.apple.com → Certificates, Identifiers & Profiles → Profiles → create an **App Store** profile for `com.memai.memaiAndroid` bound to the distribution cert. Then `base64 -i profile.mobileprovision \| pbcopy`. |
| `IOS_PROVISIONING_PROFILE_NAME` | The profile's **name**, not its filename or UUID | Shown in the Profiles list, e.g. `MemDroid App Store`. Must match exactly. |
| `IOS_TEAM_ID` | 10-character Apple Developer Team ID | developer.apple.com → Membership details. |

Everything except `IOS_DIST_CERTIFICATE_PASSWORD` is required; any one missing
skips the job.

### Notes on the iOS job

- **Bundle identifier** is `com.memai.memaiAndroid` (from `ios/Runner.xcodeproj`).
  The provisioning profile must be issued for exactly this identifier, and the
  workflow hardcodes it in the generated `ExportOptions.plist`. If the bundle ID
  ever changes, update `IOS_BUNDLE_ID` in the `ios-testflight` job.
- **`ExportOptions.plist` is generated at runtime**, not committed, so the team ID
  and profile name stay in secrets and never land in the repository. It uses
  `method: app-store-connect` (the Xcode 16+ spelling that replaced `app-store`).
- **Build number** is `github.run_number`. TestFlight rejects a build whose
  `CFBundleVersion` is not greater than the previous upload for the same version
  string. If you have already uploaded builds manually and the run number is
  lower, either bump `pubspec.yaml` to a new version string or change
  `BUILD_NUMBER` in the job to add an offset.
- **Upload uses `xcrun altool --upload-app`** with API-key auth, preceded by a
  `--validate-app` pass so bad metadata fails before a multi-minute upload.
  `notarytool` is deliberately not used — it notarizes Developer-ID *macOS* apps
  and is not an App Store submission path. API-key auth means no Apple ID and no
  app-specific password is ever stored.
- **Signing material is temporary.** The certificate is imported into a
  throwaway keychain whose password is randomly generated per run (never a
  secret). A final `if: always()` step deletes the keychain, the provisioning
  profile, and both copies of the `.p8` key even when the build fails.

### Verifying TestFlight setup before a real release

Run the workflow manually from Actions once the secrets are in place. If
`ios-testflight` still shows as skipped, open the `version` job's summary — it
names the missing secrets explicitly.

---

## Troubleshooting

**A build job succeeded but an artifact is missing.** It should not be possible:
every staging step verifies each expected file exists and calls `::error::` with
the path if not, and each `upload-artifact` uses `if-no-files-found: error`.
Check the "produced by gradle"/"produced by xcodebuild" listing in the log.

**The Release was not created.** The `release` job requires a tag push
(`is_release == 'true'`) *and* success from `android`, `macos-dmg`, and
`windows-inno`. `ios-testflight` is intentionally excluded — TestFlight is its
distribution channel, so a skipped iOS job never blocks a release.

**`ISCC failed with exit code N`.** The `.iss` script itself failed. Common cause
is a source path in the script not matching the Flutter output layout — see the
"Locate build output" step, which prints the actual `Release` directory contents.

**Re-running a release.** Delete the tag and re-push it, or delete the GitHub
Release first. `softprops/action-gh-release@v2` updates an existing release for
the same tag rather than erroring, but stale assets from a prior run may linger.
