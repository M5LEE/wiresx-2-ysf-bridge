[CmdletBinding()]param([switch]$SkipTests)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root=$PSScriptRoot;$src=Join-Path $root 'src';$bin=Join-Path $root 'bin';$tests=Join-Path $root 'tests\bin'
& (Join-Path $root 'tools\Assert-DistributionNotices.ps1') -Root $root
New-Item -ItemType Directory -Force $bin,$tests|Out-Null
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(!(Test-Path $csc)){throw '.NET Framework 4.8 developer compiler is required'}
foreach($f in Get-ChildItem $src -Filter '*.ps1'){
 $tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)|Out-Null
 if($errors.Count){throw ('PowerShell syntax error in '+$f.Name+': '+($errors.Message -join '; '))}
}
& $csc /nologo /warnaserror+ /target:library /r:System.Web.Extensions.dll ("/out:"+(Join-Path $bin 'BridgeConfigCore.dll')) (Join-Path $src 'YsfCatalog.cs') (Join-Path $src 'BridgeConfigCore.cs') (Join-Path $src 'LiveYsfLink.cs') (Join-Path $src 'YsfApplyStore.cs')
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
foreach($name in @('LICENSE','THIRD_PARTY_NOTICES.md')){Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $bin $name) -Force}
& (Join-Path $root 'tools\Assert-DistributionNotices.ps1') -Root $bin
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
 & $csc /nologo /warnaserror+ /r:System.Web.Extensions.dll ("/out:"+(Join-Path $tests 'StatusWorkerTests.exe')) (Join-Path $root 'tests\StatusWorkerTests.cs')
 if($LASTEXITCODE){throw 'Status worker test compilation failed'}
 & (Join-Path $tests 'StatusWorkerTests.exe') $bin (Join-Path $root 'tests')
 if($LASTEXITCODE){throw 'Status helper lifecycle tests failed'}
 & $csc /nologo /warnaserror+ ("/r:"+(Join-Path $bin 'BridgeProtocol.dll')) ("/out:"+(Join-Path $tests 'ReceiveAccountingTests.exe')) (Join-Path $root 'tests\ReceiveAccountingTests.cs')
 if($LASTEXITCODE){throw 'Receive accounting test compilation failed'}
 & (Join-Path $tests 'ReceiveAccountingTests.exe')
 if($LASTEXITCODE){throw 'Incoming capacity accounting regression failed'}
 & $csc /nologo /warnaserror+ ("/r:"+(Join-Path $bin 'BridgeProtocol.dll')) ("/out:"+(Join-Path $tests 'CallsignMetadataTests.exe')) (Join-Path $root 'tests\CallsignMetadataTests.cs')
 if($LASTEXITCODE){throw 'Callsign metadata test compilation failed'}
 & (Join-Path $tests 'CallsignMetadataTests.exe')
 if($LASTEXITCODE){throw 'Callsign metadata contract failed'}
 & $csc /nologo /warnaserror+ ("/r:"+(Join-Path $bin 'BridgeProtocol.dll')) ("/out:"+(Join-Path $tests 'C4fmProfileTests.exe')) (Join-Path $root 'tests\C4fmProfileTests.cs')
 if($LASTEXITCODE){throw 'C4FM profile test compilation failed'}
 & (Join-Path $tests 'C4fmProfileTests.exe')
 if($LASTEXITCODE){throw 'C4FM metadata profile contract failed'}
 & $csc /nologo /warnaserror+ ("/r:"+(Join-Path $bin 'BridgeProtocol.dll')) ("/out:"+(Join-Path $tests 'NativeCounterCompatibilityTests.exe')) (Join-Path $root 'tests\NativeCounterCompatibilityTests.cs')
 if($LASTEXITCODE){throw 'Native counter compatibility test compilation failed'}
 & (Join-Path $tests 'NativeCounterCompatibilityTests.exe')
 if($LASTEXITCODE){throw 'Native counter compatibility contract failed'}
 & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'tests\AdapterClockTests.ps1') -AdapterPath (Join-Path $bin 'voice-adapter.ps1') -AssemblyPath (Join-Path $bin 'BridgeProtocol.dll')
 if($LASTEXITCODE){throw 'Adapter clock and batch dispatch contract failed'}
 & $csc /nologo /warnaserror+ ("/r:"+(Join-Path $bin 'BridgeProtocol.dll')) ("/out:"+(Join-Path $tests 'YsfIdleBoundaryTests.exe')) (Join-Path $root 'tests\YsfIdleBoundaryTests.cs')
 if($LASTEXITCODE){throw 'YSF idle boundary test compilation failed'}
 & (Join-Path $tests 'YsfIdleBoundaryTests.exe');if($LASTEXITCODE){throw 'YSF idle boundary tests failed'}
 foreach($name in @('YsfLiveLinkTests','YsfApplyStoreTests','YsfLogoutTests')){
  & $csc /nologo /warnaserror+ /r:System.Web.Extensions.dll ("/r:"+(Join-Path $bin 'BridgeConfigCore.dll')) ("/out:"+(Join-Path $tests ($name+'.exe'))) (Join-Path $root ('tests\'+$name+'.cs'))
  if($LASTEXITCODE){throw ($name+' compilation failed')}
  & (Join-Path $tests ($name+'.exe')) (Join-Path $root ('tests\'+$name+'-'+[Guid]::NewGuid().ToString('N')))
  if($LASTEXITCODE){throw ($name+' failed')}
 }
 & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'tests\YsfAdapterApplyTests.ps1') -AdapterPath (Join-Path $bin 'voice-adapter.ps1') -Bin $bin -Fixture (Join-Path $root ('tests\ysf-adapter-'+[Guid]::NewGuid().ToString('N')))
 if($LASTEXITCODE){throw 'Actual YSF adapter apply tests failed'}
 & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'tests\YsfLogoutPollTests.ps1') -AdapterPath (Join-Path $bin 'voice-adapter.ps1') -Bin $bin
 if($LASTEXITCODE){throw 'YSF logout keepalive suppression tests failed'}
 & $csc /nologo /warnaserror+ /r:System.Web.Extensions.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll ("/r:"+(Join-Path $bin 'BridgeConfigCore.dll')) ("/out:"+(Join-Path $tests 'YsfApplyUiTests.exe')) (Join-Path $root 'tests\YsfApplyUiTests.cs')
 if($LASTEXITCODE){throw 'YSF apply UI test compilation failed'}
 & (Join-Path $tests 'YsfApplyUiTests.exe') $bin (Join-Path $root ('tests\ysf-ui-'+[Guid]::NewGuid().ToString('N')))
 if($LASTEXITCODE){throw 'YSF apply UI tests failed'}
}
Write-Output ('BUILD_OK '+$bin)
