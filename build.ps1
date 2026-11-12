[CmdletBinding()]param([switch]$SkipTests)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root=$PSScriptRoot;$src=Join-Path $root 'src';$bin=Join-Path $root 'bin';$tests=Join-Path $root 'tests\bin'
New-Item -ItemType Directory -Force $bin,$tests|Out-Null
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(!(Test-Path $csc)){throw '.NET Framework 4.8 developer compiler is required'}
foreach($f in Get-ChildItem $src -Filter '*.ps1'){
 $tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)|Out-Null
 if($errors.Count){throw ('PowerShell syntax error in '+$f.Name+': '+($errors.Message -join '; '))}
}
& $csc /nologo /warnaserror+ /target:library /r:System.Web.Extensions.dll ("/out:"+(Join-Path $bin 'BridgeConfigCore.dll')) (Join-Path $src 'YsfCatalog.cs') (Join-Path $src 'BridgeConfigCore.cs')
if($LASTEXITCODE){throw 'Configuration SDK compilation failed'}
& $csc /nologo /warnaserror+ /target:library ("/out:"+(Join-Path $bin 'BridgeProtocol.dll')) (Join-Path $src 'OfflineCore.cs') (Join-Path $src 'YsfWire.cs') (Join-Path $src 'VoiceEngine.cs')
if($LASTEXITCODE){throw 'Protocol SDK compilation failed'}
& $csc /nologo /warnaserror+ /target:winexe /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll ("/win32icon:"+(Join-Path $root 'assets\bridge.ico')) ("/r:"+(Join-Path $bin 'BridgeConfigCore.dll')) ("/out:"+(Join-Path $bin 'Bridge.exe')) (Join-Path $src 'BridgeConfigEditor.cs') (Join-Path $src 'LauncherForm.cs') (Join-Path $src 'AssemblyInfo.cs')
if($LASTEXITCODE){throw 'Application compilation failed'}
$scripts=@('PublicRuntime.ps1','FirstRun.ps1','ExistingStation.ps1','StartupIntegration.ps1','BridgeStatus.ps1','InstallerGuard.ps1','Get-BridgeSettings.ps1','BridgeSupervisor.ps1','voice-adapter.ps1','observe-room-extended.ps1','capture-startup-adapter.ps1','station-setup.ps1')
foreach($name in $scripts){Copy-Item -LiteralPath (Join-Path $src $name) -Destination (Join-Path $bin $name) -Force}
New-Item -ItemType Directory -Force (Join-Path $bin 'assets')|Out-Null
foreach($name in @('bridge.ico','settings.ico','setup.ico')){Copy-Item -LiteralPath (Join-Path $root ('assets\'+$name)) -Destination (Join-Path $bin ('assets\'+$name)) -Force}
$hashes=@{};foreach($name in @('Bridge.exe','BridgeConfigCore.dll','BridgeProtocol.dll')){$hashes[$name]=(Get-FileHash (Join-Path $bin $name)).Hash};$hashes|ConvertTo-Json|Set-Content (Join-Path $bin 'artifact-hashes.json') -Encoding UTF8
Copy-Item (Join-Path $root 'vendor') $bin -Recurse -Force
if(!$SkipTests){
 Copy-Item (Join-Path $bin 'BridgeConfigCore.dll') $tests -Force;Copy-Item (Join-Path $bin 'BridgeProtocol.dll') $tests -Force
 & $csc /nologo /warnaserror+ /r:System.Web.Extensions.dll ("/r:"+(Join-Path $bin 'BridgeConfigCore.dll')) ("/out:"+(Join-Path $tests 'ConfigTests.exe')) (Join-Path $src 'ConfigTests.cs')
 if($LASTEXITCODE){throw 'Configuration test build failed'}
 & (Join-Path $tests 'ConfigTests.exe');if($LASTEXITCODE){throw 'Configuration tests failed'}
 & $csc /nologo /warnaserror+ ("/r:"+(Join-Path $bin 'BridgeProtocol.dll')) ("/out:"+(Join-Path $tests 'ProtocolTests.exe')) (Join-Path $src 'ProtocolTests.cs')
 if($LASTEXITCODE){throw 'Protocol test build failed'}
 & (Join-Path $tests 'ProtocolTests.exe') --self-test;if($LASTEXITCODE){throw 'Protocol tests failed'}
 & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'tests\RuntimeTests.ps1') -Bin $bin
 if($LASTEXITCODE){throw 'Public runtime tests failed'}
 & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'tests\StationSetupTests.ps1') -Bin $bin
 if($LASTEXITCODE){throw 'Station port-selector tests failed'}
 & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'tests\FirstRunTests.ps1') -Bin $bin
 if($LASTEXITCODE){throw 'First-run setup tests failed'}
 & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'tests\MigrationTests.ps1') -Bin $bin
 if($LASTEXITCODE){throw 'Existing-station migration tests failed'}
 & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'tests\StartupTests.ps1') -Bin $bin
 if($LASTEXITCODE){throw 'Sign-in startup tests failed'}
 & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'tests\StatusTests.ps1') -Bin $bin
 if($LASTEXITCODE){throw 'Readable status tests failed'}
 & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'tests\InstallerGuardTests.ps1') -Bin $bin
 if($LASTEXITCODE){throw 'Active-installation protection tests failed'}
 & $csc /nologo /warnaserror+ /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll ("/out:"+(Join-Path $tests 'LauncherUiTests.exe')) (Join-Path $root 'tests\LauncherUiTests.cs')
 if($LASTEXITCODE){throw 'Launcher UI test build failed'}
 & (Join-Path $tests 'LauncherUiTests.exe') $bin (Join-Path $root 'tests\launcher-ui')
 if($LASTEXITCODE){throw 'Launcher tray/autostart UI tests failed'}
}
Write-Output ('BUILD_OK '+$bin)
