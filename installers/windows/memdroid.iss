; ============================================================================
;  MemDroid - Inno Setup 6 installer script
; ============================================================================
;
;  Packages the output of `flutter build windows --release`, which lands in
;  <repo>\build\windows\x64\runner\Release\ and consists of:
;
;    MemDroid.exe                              <- runner. windows/CMakeLists.txt
;                                                 sets BINARY_NAME "MemDroid",
;                                                 so the exe is NOT named after
;                                                 the pub package memai_android.
;    flutter_windows.dll                       <- Flutter engine
;    dartjni.dll
;    flutter_local_notifications_windows.dll
;    flutter_secure_storage_windows_plugin.dll
;    record_windows_plugin.dll                 <- plugin / FFI DLLs
;    data\icudtl.dat
;    data\app.so                               <- AOT snapshot
;    data\flutter_assets\...                   <- assets, fonts, shaders
;
;  The data\ tree MUST be shipped, recursively. Omitting it produces an
;  installer that installs cleanly and then crashes on first launch. This
;  script recurses it, and additionally hard-fails at COMPILE time (see the
;  preflight checks below) if the tree is absent, so CI can never silently
;  publish a broken installer.
;
;  Build locally:
;    iscc /DAppVersion=1.0.3 installers\windows\memdroid.iss
;  See installers\windows\README.md for details.
;
;  Requires Inno Setup 6.3 or newer (for the x64compatible architecture ids).
; ============================================================================


; ---------------------------------------------------------------------------
;  Toolchain guard
; ---------------------------------------------------------------------------
; Guarded on VER being available so an unexpected ISPP build can never fail a
; valid compile here. If this check is skipped on a too-old Inno Setup, the
; ArchitecturesAllowed directive below rejects the compile on its own anyway.
#ifdef VER
  #if VER < EncodeVer(6, 3, 0)
    #error Inno Setup 6.3 or newer is required for the x64compatible architecture identifiers.
  #endif
#endif


; ---------------------------------------------------------------------------
;  Inputs - override any of these with /D<Name>=<Value> on the iscc command line
; ---------------------------------------------------------------------------

; Version. CI passes the release tag, e.g. /DAppVersion=1.0.4 or /DAppVersion=v1.0.4.
; Default tracks pubspec.yaml (version: 1.0.3+4).
#ifndef AppVersion
  #define AppVersion "1.0.3"
#endif

#ifndef AppPublisher
  #define AppPublisher "com.memai"
#endif

#ifndef AppPublisherURL
  #define AppPublisherURL "https://github.com/leggomyeggo999/memai-android"
#endif

; Repo root, derived from this script's own location (installers\windows\).
; SourcePath is the directory containing this .iss file.
#ifndef RepoRoot
  #define RepoRoot AddBackslash(SourcePath) + "..\.."
#endif

; Where `flutter build windows --release` puts the app bundle.
#ifndef BuildDir
  #define BuildDir RepoRoot + "\build\windows\x64\runner\Release"
#endif

; Where the finished setup .exe is written.
#ifndef OutputDir
  #define OutputDir RepoRoot + "\build\windows\installer"
#endif


; ---------------------------------------------------------------------------
;  Fixed values
; ---------------------------------------------------------------------------
#define AppName "MemDroid"
#define AppDescription "Mem client for Windows"
#define AppExeName "MemDroid.exe"
#define AppIcoFile RepoRoot + "\windows\runner\resources\app_icon.ico"


; ---------------------------------------------------------------------------
;  Derived versions
; ---------------------------------------------------------------------------

; Accept a leading "v" from a git tag: v1.0.4 -> 1.0.4.
#if (Len(AppVersion) > 1) && ((Copy(AppVersion, 1, 1) == "v") || (Copy(AppVersion, 1, 1) == "V"))
  #define DisplayVersion Copy(AppVersion, 2, Len(AppVersion) - 1)
#else
  #define DisplayVersion AppVersion
#endif

; VersionInfoVersion needs a strictly numeric x.y.z, so drop any "+build"
; suffix (1.0.3+4 -> 1.0.3) and then any "-prerelease" suffix (1.0.4-rc1 -> 1.0.4).
#if Pos("+", DisplayVersion) > 0
  #define VersionNoBuild Copy(DisplayVersion, 1, Pos("+", DisplayVersion) - 1)
#else
  #define VersionNoBuild DisplayVersion
#endif

#if Pos("-", VersionNoBuild) > 0
  #define NumericVersion Copy(VersionNoBuild, 1, Pos("-", VersionNoBuild) - 1)
#else
  #define NumericVersion VersionNoBuild
#endif

; Filename-safe version: 1.0.3+4 -> 1.0.3-4.
#define FileVersionTag StringChange(DisplayVersion, "+", "-")


; ---------------------------------------------------------------------------
;  Preflight - fail the COMPILE, not the end user's machine
; ---------------------------------------------------------------------------
#if !FileExists(BuildDir + "\" + AppExeName)
  #error MemDroid.exe was not found in BuildDir. Run flutter build windows --release first, or pass /DBuildDir=PATH.
#endif

#if !FileExists(BuildDir + "\flutter_windows.dll")
  #error flutter_windows.dll was not found in BuildDir. The Flutter engine is missing from the build output.
#endif

#if !DirExists(BuildDir + "\data\flutter_assets")
  #error data\flutter_assets was not found in BuildDir. Packaging this would install an app that crashes on launch.
#endif

#if !FileExists(BuildDir + "\data\icudtl.dat")
  #error data\icudtl.dat was not found in BuildDir. The Flutter ICU data file is missing from the build output.
#endif

#if !FileExists(BuildDir + "\data\app.so")
  #error data\app.so was not found in BuildDir. This does not look like a --release build, the AOT snapshot is missing.
#endif


[Setup]
; ---------------------------------------------------------------------------
;  Identity
; ---------------------------------------------------------------------------
; NEVER change this GUID. It is what ties one release to the next; a different
; AppId makes Windows treat an upgrade as a separate product, orphaning the old
; install and its uninstall entry. The doubled leading brace is Inno's escape
; for a literal "{".
AppId={{374B72B7-4010-408B-9D88-7A07BD3209B3}
AppName={#AppName}
AppVersion={#DisplayVersion}
AppVerName={#AppName} {#DisplayVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppPublisherURL}
AppSupportURL={#AppPublisherURL}/issues
AppUpdatesURL={#AppPublisherURL}/releases
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
VersionInfoVersion={#NumericVersion}
VersionInfoProductVersion={#NumericVersion}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup
VersionInfoCompany={#AppPublisher}

; ---------------------------------------------------------------------------
;  Install target
; ---------------------------------------------------------------------------
; Per-user by default, so a CI-built unsigned installer never demands admin.
; With PrivilegesRequired=lowest, {autopf} resolves to %LOCALAPPDATA%\Programs
; and {autoprograms}/{autodesktop} resolve to the per-user Start Menu/Desktop.
; "commandline" lets a determined admin still pass /ALLUSERS, while silent and
; CI runs stay per-user with no extra prompt.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes
UsePreviousAppDir=yes

; 64-bit only. Flutter Windows produces an x64 bundle; x64compatible also
; permits ARM64 machines running it under x64 emulation.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Flutter's minimum supported Windows release (10, version 1809).
MinVersion=10.0.17763

; ---------------------------------------------------------------------------
;  Output
; ---------------------------------------------------------------------------
OutputDir={#OutputDir}
OutputBaseFilename={#AppName}-{#FileVersionTag}-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes

; ---------------------------------------------------------------------------
;  Behaviour
; ---------------------------------------------------------------------------
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
ChangesAssociations=no
#if FileExists(AppIcoFile)
SetupIconFile={#AppIcoFile}
#endif


[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"


[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked


[Files]
; ONE recursive entry covering the whole Flutter bundle: MemDroid.exe,
; flutter_windows.dll, every plugin/FFI DLL, and the entire data\ tree
; (icudtl.dat, app.so, and flutter_assets\ with its fonts\, packages\ and
; shaders\ subdirectories). recursesubdirs + createallsubdirs is what keeps
; data\flutter_assets\... intact - without it the app installs and then dies
; at startup on missing assets. Using a wildcard rather than an explicit file
; list also means a newly added plugin DLL is picked up automatically.
; Debug/link byproducts are excluded in case a toolchain leaves any behind.
Source: "{#BuildDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.exp,*.lib,*.ilk,*.iobj,*.ipdb"; Flags: ignoreversion recursesubdirs createallsubdirs


[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Comment: "{#AppDescription}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Comment: "{#AppDescription}"; Tasks: desktopicon


[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent


[UninstallDelete]
; Installed files are tracked and removed individually; these entries clean up
; the (by then empty) bundle directories so no stale shell is left behind.
; User data lives in %APPDATA% and the credential store and is left alone.
Type: dirifempty; Name: "{app}\data\flutter_assets"
Type: dirifempty; Name: "{app}\data"
Type: dirifempty; Name: "{app}"
