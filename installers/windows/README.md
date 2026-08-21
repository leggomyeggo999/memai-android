# MemDroid — Windows installer (Inno Setup 6)

Packaging for the Windows desktop build. `memdroid.iss` turns the output of
`flutter build windows --release` into a per-user setup executable.

| File | Purpose |
| --- | --- |
| `memdroid.iss` | The Inno Setup 6 script. Run by CI and by hand. |
| `build_installer.ps1` | Convenience wrapper: build + compile in one command. |

## Requirements

- **Inno Setup 6.3 or newer.** The script uses the `x64compatible` architecture
  identifiers, which do not exist before 6.3. The script refuses to compile on
  anything older rather than mis-targeting.
  ```powershell
  winget install --id JRSoftware.InnoSetup --exact
  ```
  `ISCC.exe` normally lands in `C:\Program Files (x86)\Inno Setup 6\`.
- Flutter 3.44.5 with Windows desktop support and Visual Studio's
  "Desktop development with C++" workload.

## Quick start

```powershell
# From the repo root. Builds the app, then compiles the installer.
.\installers\windows\build_installer.ps1
```

The result is `build\windows\installer\MemDroid-<version>-windows-x64-setup.exe`.

> That is the *local* name, from this script's own `OutputBaseFilename`. The
> release workflow overrides it with `iscc /F` and publishes the shorter
> `MemDroid-<version>-windows-setup.exe`. Both are the same installer; only the
> filename differs. See `docs/RELEASING.md`.
Version defaults to `pubspec.yaml`'s. To pin one and reuse an existing bundle:

```powershell
.\installers\windows\build_installer.ps1 -Version 1.0.4 -SkipFlutterBuild
```

## Doing it manually

```powershell
# 1. Build the Flutter bundle (from the repo root).
flutter build windows --release

# 2. Compile the installer.
iscc /DAppVersion=1.0.3 installers\windows\memdroid.iss
```

Relative paths inside the script are resolved against the script's own location
(`SourcePath`), so `iscc` can be invoked from any working directory.

### Command-line defines

Every define has a working default; pass one only to override it.

| Define | Default | Notes |
| --- | --- | --- |
| `AppVersion` | `1.0.3` | Matches `pubspec.yaml`. A leading `v` is stripped, so a raw tag (`/DAppVersion=v1.0.4`) works. |
| `AppPublisher` | `com.memai` | Matches `CompanyName` in `windows/runner/Runner.rc`. |
| `AppPublisherURL` | the GitHub repo | Also seeds the support and updates URLs. |
| `BuildDir` | `build\windows\x64\runner\Release` | The Flutter bundle to package. |
| `OutputDir` | `build\windows\installer` | Where the setup `.exe` is written. |

Example with everything set explicitly, which is roughly what CI does:

```powershell
iscc /DAppVersion=v1.0.4 `
     /DAppPublisher="com.memai" `
     /DBuildDir="D:\a\memai-android\memai-android\build\windows\x64\runner\Release" `
     /DOutputDir="D:\a\memai-android\memai-android\build\windows\installer" `
     installers\windows\memdroid.iss
```

`AppVersion` is normalised in three ways: `v1.0.4` → `1.0.4` for display, and
`1.0.3+4` / `1.0.4-rc1` → `1.0.3` / `1.0.4` for `VersionInfoVersion`, which only
accepts numeric `x.y.z`. `+` becomes `-` in the output filename.

## What ends up in the installer

The executable is **`MemDroid.exe`**, not `memai_android.exe` — `windows/CMakeLists.txt`
sets `BINARY_NAME "MemDroid"`, which is independent of the pub package name.

A single recursive `[Files]` entry copies the entire bundle:

```
MemDroid.exe
flutter_windows.dll
dartjni.dll
flutter_local_notifications_windows.dll
flutter_secure_storage_windows_plugin.dll
record_windows_plugin.dll
data\icudtl.dat
data\app.so
data\flutter_assets\...        (fonts\, packages\, shaders\, manifests)
```

The wildcard is deliberate: a plugin added later ships automatically, with no
edit here. `recursesubdirs createallsubdirs` is what preserves the nested
`data\flutter_assets\` tree. **Dropping `data\` is the classic Flutter-on-Inno
bug** — the installer succeeds and the app then crashes on launch. To make that
unfixable-by-accident, the script runs preprocessor preflight checks and aborts
the *compile* if `MemDroid.exe`, `flutter_windows.dll`, `data\icudtl.dat`,
`data\app.so`, or `data\flutter_assets\` is missing. A CI job that forgets to
build first gets a failed step, never a broken artifact.

## Install behaviour

- **Per-user by default** (`PrivilegesRequired=lowest`), installing to
  `%LOCALAPPDATA%\Programs\MemDroid`. An unsigned CI-built installer never
  demands admin. `PrivilegesRequiredOverridesAllowed=commandline` lets an admin
  opt into a machine-wide install with `/ALLUSERS`; silent and CI runs stay
  per-user with no extra prompt.
- **64-bit only** (`ArchitecturesAllowed=x64compatible`), which also covers
  ARM64 machines running the x64 build under emulation.
- **Windows 10 1809 (10.0.17763) minimum**, matching Flutter's floor.
- Start-menu shortcut always; desktop shortcut is an **opt-in task**, unchecked
  by default.
- Standard Add/Remove Programs entry with the app icon.

Silent install, e.g. for testing:

```powershell
.\MemDroid-1.0.3-windows-x64-setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

Add `/LOG="install.log"` when diagnosing.

## The AppId is frozen

```
AppId={{374B72B7-4010-408B-9D88-7A07BD3209B3}
```

Do not change this GUID, ever. It is the identity Windows uses to recognise one
release as an upgrade of the previous one. Changing it makes every future
installer look like a separate product: the old copy is left installed and a
duplicate uninstall entry appears.

## Notes and known gaps

- **The installer is unsigned.** SmartScreen will warn on first run. Adding a
  signing step means an `[Setup] SignTool=` directive plus a certificate in CI
  secrets; deliberately out of scope here.
- **No VC++ redistributable is bundled.** Flutter's release output does not
  include `msvcp140.dll` / `vcruntime140*.dll`, and this script ships only what
  the build produces. That is fine on any machine with the Visual C++ 2015-2022
  redistributable — near-universal, but not guaranteed on a clean image. If it
  ever bites, add the redist DLLs to the build output and they will be picked up
  by the existing wildcard with no change here.
- **`flutter_appauth` has no Windows implementation**, so MCP OAuth sign-in
  cannot run in the packaged app. This is handled in app code rather than here:
  `MemMcpOAuth.isSupported` (`lib/core/mcp/mem_oauth.dart`) gates the flow, and
  the Settings tile renders "Not available here" with no Connect button instead
  of throwing `MissingPluginException`. Chat tools fall back to the Mem REST API
  key, so the Windows build is fully usable. `home_widget` is likewise
  Android/iOS-only, and its call sites are already platform-guarded and no-op
  here.
