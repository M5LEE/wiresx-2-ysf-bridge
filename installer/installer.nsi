Unicode True
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "WinVer.nsh"
!define PRODUCT "WiresX 2 YSF Bridge"
!define VERSION "0.1.0-alpha.14"
!define MUI_ICON "../assets/setup.ico"
!define MUI_UNICON "../assets/bridge.ico"
!define KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\M5LEE.WIRESXtoYSF"
Name "${PRODUCT}"
OutFile "../dist/WiresX-2-YSF-Bridge-${VERSION}-Setup.exe"
InstallDir "$PROGRAMFILES64\M5LEE\WiresX-2-YSF-Bridge"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
ManifestSupportedOS all
VIProductVersion "0.1.0.14"
VIAddVersionKey /LANG=1033 "ProductName" "${PRODUCT}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "FileVersion" "0.1.0.14"
VIAddVersionKey /LANG=1033 "FileDescription" "Experimental alpha bridge tools installer"
VIAddVersionKey /LANG=1033 "LegalCopyright" "Copyright (c) 2026 M5LEE"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TEXT "WiresX 2 YSF Bridge by M5LEE - experimental alpha.$\r$\n$\r$\nSet up official WIRES-X first with your existing account and genuine HRI-200.$\r$\n$\r$\nAlpha.14 automatically recovers a safe interrupted session after reboot when Windows sign-in startup is enabled. No manual Recover or Start click is normally needed.$\r$\n$\r$\nBefore upgrading, Stop bridge, wait for cleanup and Exit its tray app. Running sessions are not stopped by the installer.$\r$\n$\r$\nPlease report problems through GitHub Issues rather than messaging M5LEE directly wherever possible."
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "../LICENSE"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TEXT "Installation complete.$\r$\n$\r$\nEnter your YSF callsign, choose a room and select 3. Save setup. First use also needs Advanced setup and a valid connection profile.$\r$\n$\r$\nSelect Back to bridge, then 2. Check status and 3. Start bridge. WIRES-X starts automatically; allow several minutes for login.$\r$\n$\r$\nUse What to do next or Help / recommended fixes if something is missing. Closing the status window does not stop the bridge.$\r$\n$\r$\nExisting station data is retained. Experimental and AS IS; donations are optional."
!define MUI_FINISHPAGE_RUN "$INSTDIR\Bridge.exe"
!define MUI_FINISHPAGE_RUN_PARAMETERS "--setup"
!define MUI_FINISHPAGE_RUN_TEXT "Set up my bridge"
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Application (required)" Core
 SectionIn RO
 IfFileExists "$INSTDIR\launcher-state\owner.json" destination_in_use 0
 IfFileExists "$INSTDIR\discovery-name-backup.json" destination_in_use 0
 Goto destination_ok
 destination_in_use:
  IfSilent +2
  MessageBox MB_OK|MB_ICONSTOP "This folder contains a working bridge ownership record. Nothing was copied. Keep that folder for rollback and install to the separate default Program Files directory."
  SetErrorLevel 6
  Abort
 destination_ok:
 InitPluginsDir
 SetOutPath "$PLUGINSDIR\BridgeGuard"
 File "../bin/InstallerGuard.ps1"
 File "../bin/PublicRuntime.ps1"
 File "../bin/StartupIntegration.ps1"
 ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\BridgeGuard\InstallerGuard.ps1" -TargetDir "$INSTDIR" -Action Install' $0
 ${If} $0 != 0
  IfSilent +2
  MessageBox MB_OK|MB_ICONSTOP "This installed bridge or one of its windows is still running. Stop the bridge, wait for cleanup, and Exit its tray/status app before upgrading. No running session was changed."
  SetErrorLevel 7
  Abort
 ${EndIf}
 SetShellVarContext all
 SetRegView 64
 SetOutPath "$INSTDIR"
 ClearErrors
 File "../bin/Bridge.exe"
 File "../bin/BridgeConfigCore.dll"
 File "../bin/BridgeProtocol.dll"
 File "../bin/artifact-hashes.json"
 File "../bin/PublicRuntime.ps1"
 File "../bin/FirstRun.ps1"
 File "../bin/ExistingStation.ps1"
 File "../bin/StartupIntegration.ps1"
 File "../bin/BridgeStatus.ps1"
 File "../bin/InstallerGuard.ps1"
 File "../bin/Get-BridgeSettings.ps1"
 File "../bin/BridgeSupervisor.ps1"
 File "../bin/voice-adapter.ps1"
 File "../bin/observe-room-extended.ps1"
 File "../bin/capture-startup-adapter.ps1"
 File "../bin/station-setup.ps1"
 File "../LICENSE"
 File "../THIRD_PARTY_NOTICES.md"
 File "../README.md"
 SetOutPath "$INSTDIR\assets"
 File "../bin/assets/bridge.ico"
 File "../bin/assets/settings.ico"
 File "../bin/assets/setup.ico"
 File "../assets/icon-preview.png"
 SetOutPath "$INSTDIR\docs"
 File "../docs/VERIFICATION.md"
 File "../docs/LIVE-YSF-APPLY.md"
 File "../docs/RELEASE-alpha.10.md"
 File "../docs/RELEASE-alpha.14.md"
 File "../docs/TROUBLESHOOTING.md"
 File "../docs/DEVELOPMENT.md"
 File "../docs/C4FM-METADATA-PROFILES.md"
 File "../docs/YAESU-TERMS-REVIEW.md"
 SetOutPath "$INSTDIR\vendor\com0com"
 ; Explicit entries make missing upstream source or notices a compile error.
 File "../vendor/com0com/LICENSE.txt"
 File "../vendor/com0com/ORIGIN.md"
 File "../vendor/com0com/ReadMe.txt"
 File "../vendor/com0com/hashes.json"
 File "../vendor/com0com/com0com-3.0.0.0-source.zip"
 File "../vendor/com0com/Setup_com0com_v3.0.0.0_W7_x64_signed.exe"
 File "../vendor/com0com/cncport.inf"
 File "../vendor/com0com/com0com.cat"
 File "../vendor/com0com/com0com.inf"
 File "../vendor/com0com/com0com.sys"
 File "../vendor/com0com/comport.inf"
 File "../vendor/com0com/setup.dll"
 File "../vendor/com0com/setupc.exe"
 SetOutPath "$INSTDIR"
 IfErrors install_failed
 WriteUninstaller "$INSTDIR\Uninstall.exe"
 IfErrors install_failed
 CreateDirectory "$SMPROGRAMS\${PRODUCT}"
 CreateShortcut "$SMPROGRAMS\${PRODUCT}\Bridge launcher.lnk" "$INSTDIR\Bridge.exe" "--launcher" "$INSTDIR\assets\bridge.ico"
 CreateShortcut "$SMPROGRAMS\${PRODUCT}\YSF configuration.lnk" "$INSTDIR\Bridge.exe" "" "$INSTDIR\assets\settings.ico"
 CreateShortcut "$SMPROGRAMS\${PRODUCT}\Station setup.lnk" "$INSTDIR\Bridge.exe" "--setup" "$INSTDIR\assets\settings.ico"
 CreateShortcut "$SMPROGRAMS\${PRODUCT}\Read me.lnk" "$INSTDIR\README.md"
 WriteRegStr HKLM "${KEY}" "DisplayName" "${PRODUCT}"
 WriteRegStr HKLM "${KEY}" "DisplayVersion" "${VERSION}"
 WriteRegStr HKLM "${KEY}" "Publisher" "M5LEE"
 WriteRegStr HKLM "${KEY}" "DisplayIcon" "$INSTDIR\Bridge.exe,0"
 WriteRegStr HKLM "${KEY}" "InstallLocation" "$INSTDIR"
 WriteRegStr HKLM "${KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
 WriteRegStr HKLM "${KEY}" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
 WriteRegStr HKLM "${KEY}" "URLInfoAbout" "https://cumbriacq.com/donate-support/"
 WriteRegDWORD HKLM "${KEY}" "NoModify" 1
 WriteRegDWORD HKLM "${KEY}" "NoRepair" 1
 Goto install_done
 install_failed:
  IfSilent +2
  MessageBox MB_OK|MB_ICONSTOP "Installation could not complete. Close this product's windows/sessions and check the destination permissions. No unrelated application was stopped."
  SetErrorLevel 2
  Abort
 install_done:
SectionEnd

Section /o "Desktop shortcuts" Desktop
 SetShellVarContext all
 CreateShortcut "$DESKTOP\WiresX 2 YSF Bridge.lnk" "$INSTDIR\Bridge.exe" "--launcher" "$INSTDIR\assets\bridge.ico"
 CreateShortcut "$DESKTOP\WiresX 2 YSF Bridge Config.lnk" "$INSTDIR\Bridge.exe" "" "$INSTDIR\assets\settings.ico"
SectionEnd

Function .onInit
 ${IfNot} ${RunningX64}
  IfSilent +2
  MessageBox MB_OK|MB_ICONSTOP "Windows 10 or later, x64, is required."
  SetErrorLevel 3
  Abort
 ${EndIf}
 ${IfNot} ${AtLeastWin10}
  IfSilent +2
  MessageBox MB_OK|MB_ICONSTOP "Windows 10 or later is required."
  SetErrorLevel 3
  Abort
 ${EndIf}
 SetRegView 64
 ReadRegDWORD $0 HKLM "SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" "Release"
 IntCmp $0 528040 framework_ok framework_missing framework_ok
 framework_missing:
  IfSilent +2
  MessageBox MB_OK|MB_ICONSTOP "Microsoft .NET Framework 4.8 or later is required. Obtain it from Microsoft. This installer does not download or install runtimes."
  SetErrorLevel 4
  Abort
 framework_ok:
FunctionEnd

Section "Uninstall"
 SetShellVarContext all
 SetRegView 64
 ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$INSTDIR\InstallerGuard.ps1" -TargetDir "$INSTDIR" -Action Uninstall' $0
 ${If} $0 != 0
  IfSilent +2
  MessageBox MB_OK|MB_ICONSTOP "Uninstall stopped safely. Stop the bridge and Exit its tray app first. If startup restoration is blocked, resolve its shortcut/task ownership conflict in the same Windows account before retrying. Private station data and backups were retained."
  SetErrorLevel 7
  Abort
 ${EndIf}
 ClearErrors
 Delete "$INSTDIR\Bridge.exe"
 Delete "$INSTDIR\BridgeConfigCore.dll"
 Delete "$INSTDIR\BridgeProtocol.dll"
 Delete "$INSTDIR\artifact-hashes.json"
 Delete "$INSTDIR\PublicRuntime.ps1"
 Delete "$INSTDIR\FirstRun.ps1"
 Delete "$INSTDIR\ExistingStation.ps1"
 Delete "$INSTDIR\StartupIntegration.ps1"
 Delete "$INSTDIR\BridgeStatus.ps1"
 Delete "$INSTDIR\InstallerGuard.ps1"
 Delete "$INSTDIR\Get-BridgeSettings.ps1"
 Delete "$INSTDIR\BridgeSupervisor.ps1"
 Delete "$INSTDIR\voice-adapter.ps1"
 Delete "$INSTDIR\observe-room-extended.ps1"
 Delete "$INSTDIR\capture-startup-adapter.ps1"
 Delete "$INSTDIR\station-setup.ps1"
 Delete "$INSTDIR\LICENSE"
 Delete "$INSTDIR\THIRD_PARTY_NOTICES.md"
 Delete "$INSTDIR\README.md"
 Delete "$INSTDIR\docs\VERIFICATION.md"
 Delete "$INSTDIR\docs\LIVE-YSF-APPLY.md"
 Delete "$INSTDIR\docs\RELEASE-alpha.10.md"
 Delete "$INSTDIR\docs\RELEASE-alpha.14.md"
 Delete "$INSTDIR\docs\TROUBLESHOOTING.md"
 Delete "$INSTDIR\docs\DEVELOPMENT.md"
 Delete "$INSTDIR\docs\C4FM-METADATA-PROFILES.md"
 Delete "$INSTDIR\docs\YAESU-TERMS-REVIEW.md"
 Delete "$INSTDIR\assets\bridge.ico"
 Delete "$INSTDIR\assets\settings.ico"
 Delete "$INSTDIR\assets\setup.ico"
 Delete "$INSTDIR\assets\icon-preview.png"
 Delete "$INSTDIR\vendor\com0com\setupc.exe"
 Delete "$INSTDIR\vendor\com0com\setup.dll"
 Delete "$INSTDIR\vendor\com0com\com0com.sys"
 Delete "$INSTDIR\vendor\com0com\com0com.cat"
 Delete "$INSTDIR\vendor\com0com\com0com.inf"
 Delete "$INSTDIR\vendor\com0com\comport.inf"
 Delete "$INSTDIR\vendor\com0com\cncport.inf"
 Delete "$INSTDIR\vendor\com0com\ReadMe.txt"
 Delete "$INSTDIR\vendor\com0com\Setup_com0com_v3.0.0.0_W7_x64_signed.exe"
 Delete "$INSTDIR\vendor\com0com\com0com-3.0.0.0-source.zip"
 Delete "$INSTDIR\vendor\com0com\LICENSE.txt"
 Delete "$INSTDIR\vendor\com0com\hashes.json"
 Delete "$INSTDIR\vendor\com0com\ORIGIN.md"
 IfErrors uninstall_failed
 RMDir "$INSTDIR\docs"
 RMDir "$INSTDIR\assets"
 RMDir "$INSTDIR\vendor\com0com"
 RMDir "$INSTDIR\vendor"
 ClearErrors
 Delete "$SMPROGRAMS\${PRODUCT}\Bridge launcher.lnk"
 Delete "$SMPROGRAMS\${PRODUCT}\YSF configuration.lnk"
 Delete "$SMPROGRAMS\${PRODUCT}\Station setup.lnk"
 Delete "$SMPROGRAMS\${PRODUCT}\Read me.lnk"
 RMDir "$SMPROGRAMS\${PRODUCT}"
 Delete "$DESKTOP\WiresX 2 YSF Bridge.lnk"
 Delete "$DESKTOP\WiresX 2 YSF Bridge Config.lnk"
 DeleteRegKey HKLM "${KEY}"
 Delete "$INSTDIR\Uninstall.exe"
 RMDir "$INSTDIR"
 Goto uninstall_done
 uninstall_failed:
  IfSilent +2
  MessageBox MB_OK|MB_ICONSTOP "Some application files are in use or cannot be removed. Stop this product's sessions and close its windows, then retry. Your private station data has been preserved."
  SetErrorLevel 5
  Abort
 uninstall_done:
 ; Never remove local station data, captures, logs, backups, drivers or Yaesu files.
SectionEnd
