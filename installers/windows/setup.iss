; Inno Setup Script for Front Porch AI
; Produces a Windows installer with AGPL V3 license acceptance

#define MyAppName "Front Porch AI"
#define MyAppPublisher "linux4life1"
#define MyAppURL "https://github.com/linux4life1/front-porch-AI"
#define MyAppExeName "front_porch_ai.exe"

; ── Channel identity: stable / Beta / Nightly ────────────────────────────────
;
; Each channel gets its OWN AppId AND its own install folder so Windows/Inno
; tracks them as three independent applications that can coexist cleanly.
;
; History: all three channels used to share ONE AppId. Windows tracks installs
; by AppId and remembers a single previous install directory per AppId, so the
; channels fought over one location — each channel's update would follow the
; single recorded path and clobber whichever channel installed there last. True
; side-by-side stable + Nightly was therefore never really possible.
;
; Stable KEEPS its original AppId (so existing stable installs upgrade in place);
; Beta and Nightly get fresh AppIds and Nightly moves to its own folder so it no
; longer collides with Beta in "...\Front Porch AI Beta".
;
; The build channel is selected by the defines the CI passes to ISCC:
;   release.yml      -> (nothing)                -> stable
;   beta-release.yml -> /DPRE_RELEASE=1          -> Beta
;   nightly.yml      -> /DPRE_RELEASE=1 /DNIGHTLY=1 -> Nightly
;
; IMPORTANT: directives are line-based (#ifdef ... #else ... #endif). The inline
; form ({#ifdef ...}...{#else}...{#endif}) mis-parses when a branch contains
; nested braces ({localappdata}, {#MyAppName}); that exact bug shipped in
; v0.9.9.0.1 and put stable installs in the Beta folder. Never use it here.
#ifdef NIGHTLY
  #define ChannelAppId "{{2BBF113C-2BC7-42C3-A654-2BC8478FCDE1}"
  #define ChannelSuffix " Nightly"
#else
  #ifdef PRE_RELEASE
    #define ChannelAppId "{{FAAC0B26-5672-4005-A81F-DE7CBA31D327}"
    #define ChannelSuffix " Beta"
  #else
    #define ChannelAppId "{{B7E2F8A1-4D3C-4E5B-9F1A-2C8D6E0F3B9A}"
    #define ChannelSuffix ""
  #endif
#endif

[Setup]
AppId={#ChannelAppId}
AppName={#MyAppName}{#ChannelSuffix}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
; User-local install directory so no elevation is needed. A fresh install of any
; channel still shows the "Select Destination Location" page (DisableDirPage is
; left at its default 'auto'), so users can always pick a custom folder; only
; in-place upgrades and /VERYSILENT auto-updates skip it.
#ifdef NIGHTLY
; Nightly. Pre-split Nightly builds shared the old AppId and lived in the
; "...\Front Porch AI Beta" folder. After the AppId split, Windows has no record
; of Nightly's new AppId, so a /VERYSILENT auto-update FORKED a brand-new copy
; into "...\Front Porch AI Nightly" and left the running build untouched — the app
; never actually updated, so the update prompt reappeared forever (and the new
; copy landed in {localappdata} with no chance to choose a folder). The code
; routine GetNightlyInstallDir adopts the pre-split folder (detected via Nightly's
; own Start Menu group) on that first migration so the silent update overwrites
; the running install in place. Fresh Nightly installs default to the dedicated
; "...\Front Porch AI Nightly" folder and still show the directory page.
;
; UsePreviousAppDir=no is REQUIRED here: a looping user has already forked a copy
; into the dedicated folder, so the new AppId already records that path. With the
; default (yes) Inno would reuse that recorded path and ignore the code below,
; reinstalling to the dedicated folder forever while the running build in the Beta
; folder is never replaced. Taking charge of the directory in code (exactly like
; stable) lets GetNightlyInstallDir redirect the update onto the running build.
UsePreviousAppDir=no
DefaultDirName={code:GetNightlyInstallDir}
#else
#ifdef PRE_RELEASE
; Beta -> "...\Front Porch AI Beta".
DefaultDirName={localappdata}\{#MyAppName}{#ChannelSuffix}
#else
; Stable channel. v0.9.9.0.1 shipped with the inline-conditional brace bug noted
; above, which recorded the WRONG "...\Front Porch AI Beta" directory for stable
; installs. Because Inno remembers the previous install location by AppId, a
; normal /VERYSILENT auto-update would silently reinstall right back into that
; wrong folder forever. So for stable we take charge of the directory ourselves:
;   * UsePreviousAppDir=no    -> don't blindly reuse the recorded (bugged) path
;   * DefaultDirName via code  -> force the correct stable folder, while still
;                                honoring a genuine user-chosen custom location.
; The stray Beta folder is cleaned up safely in [Code] (CurStepChanged).
UsePreviousAppDir=no
DefaultDirName={code:GetStableInstallDir}
#endif
#endif
DefaultGroupName={#MyAppName}{#ChannelSuffix}
LicenseFile={#MyAppLicenseFile}
#ifdef PRE_RELEASE
OutputBaseFilename=Front_Porch_AI_Beta_Setup
#else
OutputBaseFilename=Front_Porch_AI_Setup
#endif
OutputDir=.
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile={#MyAppIconFile}
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Install per-user — avoids UAC elevation requirement and install failures
; Users can opt-in to a machine-wide install via the dialog
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
RestartApplications=yes
AppMutex=FrontPorchAI_{#ChannelAppId}
; Require Windows 10 or later (Flutter + ANGLE requires it)
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Main application files
Source: "{#MyAppBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Bundle VC++ 2015-2022 Redistributable alongside the installer
; Downloaded by the CI build step before calling ISCC
Source: "{#MyAppBuildDir}\..\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[INI]
; Marker file so the app knows it was installed (not from zip)
; Self-update is disabled without this file
Filename: "{app}\.installed"; Section: "install"; Key: "method"; String: "innosetup"

[Icons]
; Names are channel-aware via {#ChannelSuffix} ("", " Beta", " Nightly"), so each
; channel gets distinct Start Menu / desktop entries that never collide.
Name: "{group}\{#MyAppName}{#ChannelSuffix}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}{#ChannelSuffix}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}{#ChannelSuffix}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Install Visual C++ 2015-2022 Redistributable silently first.
; /install /quiet /norestart — suppresses all UI and reboot prompts.
; The check flag ensures we skip this if it's already installed at the required version.
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; \
  StatusMsg: "Installing Visual C++ Runtime (required)..."; \
  Check: VCRedistNeedsInstall; Flags: waituntilterminated

; Launch the app after install (user can uncheck this)
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// ── Channel separation + stable Beta-folder self-heal ────────────────────────
//
// AppIds (must match the channel AppIds in the [Setup] section above). Used to
// read Inno's recorded install directories from the uninstall registry.
const
  APP_ID_STABLE  = '{B7E2F8A1-4D3C-4E5B-9F1A-2C8D6E0F3B9A}';
  APP_ID_BETA    = '{FAAC0B26-5672-4005-A81F-DE7CBA31D327}';
  APP_ID_NIGHTLY = '{2BBF113C-2BC7-42C3-A654-2BC8478FCDE1}';

function CorrectStableDir(): String;
begin
  Result := ExpandConstant('{localappdata}\Front Porch AI');
end;

function BetaDir(): String;
begin
  Result := ExpandConstant('{localappdata}\Front Porch AI Beta');
end;

// Inno records the last install directory under each AppId. Per-user installs
// (PrivilegesRequired=lowest) land in HKCU; check it first, then machine-wide.
function RecordedInstallDirFor(AppId: String): String;
var
  Key, V: String;
begin
  Result := '';
  Key := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' + AppId + '_is1';
  if RegQueryStringValue(HKCU, Key, 'Inno Setup: App Path', V) then
    Result := V
  else if RegQueryStringValue(HKLM, Key, 'Inno Setup: App Path', V) then
    Result := V;
end;

// DefaultDirName for STABLE builds. Forces the correct folder (repairing the
// v0.9.9.0.1 installs the bug placed in the Beta directory) while preserving any
// genuine custom location the user previously chose. Reads the STABLE AppId,
// which is the same one the bugged stable build used.
function GetStableInstallDir(Param: String): String;
var
  Prev: String;
begin
  Prev := RecordedInstallDirFor(APP_ID_STABLE);
  if (Prev <> '') and
     (CompareText(Prev, CorrectStableDir()) <> 0) and
     (CompareText(Prev, BetaDir()) <> 0) then
    Result := Prev                 // genuine custom path -> honor it
  else
    Result := CorrectStableDir();  // fresh / already-correct / bugged-Beta -> correct dir
end;

// True if a Beta-channel build currently owns the "...\Front Porch AI Beta"
// folder (so we must never delete it). Post-separation, Beta is the only channel
// that legitimately lives there.
function BetaAppInstalled(): Boolean;
begin
  Result := (RecordedInstallDirFor(APP_ID_BETA) <> '') or
            DirExists(ExpandConstant('{userprograms}\Front Porch AI Beta')) or
            DirExists(ExpandConstant('{commonprograms}\Front Porch AI Beta'));
end;

// True if a Rawhide Nightly build is installed (detected via its dedicated
// Start Menu group, which hasn't changed across the AppId split). Prevents
// cleanup from deleting the Beta folder when a pre-split Nightly still lives
// there.
function IsRawhideNightlyInstalled(): Boolean;
begin
  Result := DirExists(ExpandConstant('{userprograms}\Front Porch AI Nightly')) or
            DirExists(ExpandConstant('{commonprograms}\Front Porch AI Nightly'));
end;

// DefaultDirName for NIGHTLY builds (UsePreviousAppDir=no, so this code fully
// owns where Nightly installs — like the stable self-heal).
//
// THE LOOP HEAL: pre-split Nightly shared the old AppId and ran from the
// "...\Front Porch AI Beta" folder. After the AppId split a /VERYSILENT update
// forks a copy into the dedicated folder and leaves that running build in place,
// so the app never updates and the prompt reappears forever. When a pre-split
// Nightly is still sitting in the Beta folder, return that folder so the update
// overwrites the RUNNING build in place — this works even after earlier updates
// already forked a dedicated-folder copy (the reason UsePreviousAppDir must be
// no: otherwise the recorded dedicated-folder path would win and bypass this).
//
// NO-CLOBBER GUARD: a REAL Beta install owns the Beta folder under the Beta AppId
// ({FAAC0B26}). A pre-split Nightly never used that AppId, so when the Beta AppId
// records the Beta folder we must NOT adopt it. Combined with Nightly's dedicated
// Start Menu group, this distinguishes "Nightly squatting in the Beta folder"
// from "a genuine Beta install" even when both exist.
//
// Otherwise: honor the new Nightly AppId's recorded path (preserves a custom
// folder the user chose) and fall back to the dedicated folder for fresh
// installs (which still show the directory page so the user can pick).
function GetNightlyInstallDir(Param: String): String;
var
  Prev: String;
begin
  if IsRawhideNightlyInstalled() and
     FileExists(BetaDir() + '\front_porch_ai.exe') and
     (CompareText(RecordedInstallDirFor(APP_ID_BETA), BetaDir()) <> 0) then
  begin
    Result := BetaDir();
    exit;
  end;

  Prev := RecordedInstallDirFor(APP_ID_NIGHTLY);
  if Prev <> '' then
    Result := Prev
  else
    Result := ExpandConstant('{localappdata}\Front Porch AI Nightly');
end;

// Safe to remove the "...\Front Porch AI Beta" folder ONLY when nothing
// currently claims it:
//   * this install is not the Beta folder itself (so a Beta build never deletes
//     its own target, and any install that landed elsewhere is eligible),
//   * the stable/legacy shared AppId no longer records the Beta folder as its
//     home (a stable that has NOT yet relocated, or a legacy pre-release still
//     tracked there, keeps us from deleting too early — that install repairs
//     itself on its own next update),
//   * no Beta-channel install owns it (post-split Beta detected via its
//     distinct AppId), and
//   * no Rawhide Nightly install owns it (pre-split Nightly detected via its
//     dedicated Start Menu group).
// This cleans up the common stable-only case (after stable relocates out) while
// never harming a real Beta or Nightly install.
function SafeToRemoveBetaFolder(): Boolean;
begin
  Result :=
    DirExists(BetaDir()) and
    (CompareText(ExpandConstant('{app}'), BetaDir()) <> 0) and
    (CompareText(RecordedInstallDirFor(APP_ID_STABLE), BetaDir()) <> 0) and
    (not BetaAppInstalled()) and
    (not IsRawhideNightlyInstalled());
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  // Runs after files are installed and the uninstall registry is written, so the
  // stable AppId's recorded path already reflects THIS install's location.
  if CurStep = ssPostInstall then
  begin
    if SafeToRemoveBetaFolder() then
      DelTree(BetaDir(), True, True, True);
  end;
end;

// Returns true if VC++ 2015-2022 x64 Redistributable is NOT already installed.
// Checks the registry key that Microsoft documents as the canonical detection method.
// See: https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files
function VCRedistNeedsInstall: Boolean;
var
  Installed: Cardinal;
begin
  // The "Installed" DWORD under this key is set to 1 when VC++ 2022 x64 is present
  Result := not RegQueryDWordValue(
    HKLM,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64',
    'Installed',
    Installed
  ) or (Installed <> 1);
end;
