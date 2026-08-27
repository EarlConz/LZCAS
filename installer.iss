; Inno Setup script for the LZCAS / GUTVita Flutter app
; Save this as installer.iss in the project root
; Open with Inno Setup Compiler and click Build > Compile
;
; ── Production vs Staging ─────────────────────────────────────────────
; Compile PRODUCTION (default):
;     iscc installer.iss
; Compile STAGING (side-by-side, never touches the production install):
;     iscc /DSTAGING installer.iss
;
; The two differ by AppId — Inno uses AppId (NOT AppName) to decide whether
; an install is an upgrade of an existing app. Distinct GUIDs mean Windows
; tracks them as two separate programs: separate install folders, separate
; Start Menu groups, separate uninstall entries. Installing/uninstalling one
; never disturbs the other.

#ifdef STAGING
  #define MyAppName "GUTVita Staging"
  ; Distinct GUID — this is what keeps the two installs independent.
  #define MyAppId "{{B7E4A2C1-5F3D-4A8E-9C6B-2D1E8F0A4B93}"
  #define MyOutputBase "GUTVita_Staging_Setup_v"
  #define MyDirName "GUTVita Staging"
#else
  #define MyAppName "LZCAS"
  #define MyAppId "{{3A9C1E57-8B24-4D6F-A1E0-7C5B93D2F846}"
  #define MyOutputBase "GUTVita_Setup_v"
  #define MyDirName "LZCAS"
#endif

; Keep in step with `version:` in pubspec.yaml — this only drives the output
; filename and the Add/Remove Programs entry. AppId is deliberately NOT
; version-derived, so bumping this still upgrades an existing install.
#define MyAppVersion "1.3.0"
#define MyAppPublisher "LZCAS"
#define MyAppURL "https://lzcas.app"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\{#MyDirName}
DefaultGroupName={#MyAppName}
OutputDir=installer_output
OutputBaseFilename={#MyOutputBase}{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
UninstallDisplayIcon={app}\lzcas.exe
UninstallDisplayName={#MyAppName}
PrivilegesRequired=admin

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; Source directory is your Flutter release build output.
; NOTE: build the matching flavor BEFORE compiling this script — see
; docs/staging_builds.md for the exact flutter build commands.
Source: "build\windows\x64\runner\Release\lzcas.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\lzcas.exe"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\lzcas.exe"

[Run]
Filename: "{app}\lzcas.exe"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
