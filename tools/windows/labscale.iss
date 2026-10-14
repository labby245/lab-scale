; Inno Setup script for the LabScale Windows installer.
; Run by tools/package_windows.ps1, which passes the version and folders:
;   ISCC /DAppVersion=2.1.0 /DSourceDir=<Release dir> /DOutputDir=<dist> labscale.iss
;
; PrivilegesRequired=lowest installs per user with no UAC prompt — LabScale
; needs nothing system-wide, and a silent install (/VERYSILENT) must not stall
; on a prompt nobody answers. Same choice as Fotolane's installer.

#ifndef AppVersion
  #error AppVersion is not set. Run tools/package_windows.ps1.
#endif
#ifndef SourceDir
  #error SourceDir is not set. Run tools/package_windows.ps1.
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

#define AppName "LabScale"
#define AppExe "labscale.exe"

[Setup]
; Never change AppId: it is how Windows recognises an upgrade of this app.
AppId={{6F1C2B7A-3D4E-4B8F-9A21-5C3E7D9B0A14}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Labstory Studio
AppPublisherURL=https://github.com/labby245/lab-scale
AppSupportURL=https://github.com/labby245/lab-scale/issues
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
LicenseFile={#SourceDir}\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename=LabScale-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
; Closes a running LabScale before files are replaced on upgrade.
CloseApplications=yes

[Languages]
; English only: Indonesian is not among Inno Setup's bundled translations,
; and the wizard is four clicks of standard buttons.
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Model weights 2.2.0 stopped shipping. [Files] only adds and replaces, so
; an upgrade over 2.1.x would otherwise leave them in bin\models for good.
Type: files; Name: "{app}\bin\models\realesrgan-x4plus-anime.*"
Type: files; Name: "{app}\bin\models\realesr-animevideov3-x*.*"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
