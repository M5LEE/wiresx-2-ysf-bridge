param([Parameter(Mandatory=$true)][string]$Bin)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$fixture=Join-Path $env:USERPROFILE ('WX-controller-test-'+[Guid]::NewGuid().ToString('N').Substring(0,10));New-Item -ItemType Directory $fixture,(Join-Path $fixture 'data')|Out-Null
$runtime=Get-Content (Join-Path $Bin 'PublicRuntime.ps1') -Raw;$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($runtime,[ref]$tokens,[ref]$errors)
$assign=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$script:Root'},$true));if($errors.Count -or $assign.Count -ne 1){throw 'FixtureRootIsolationFailed'}
$runtime.Replace($assign[0].Extent.Text,'$script:Root=Join-Path $PSScriptRoot ''data''')|Set-Content (Join-Path $fixture 'PublicRuntime.ps1') -Encoding UTF8
Copy-Item (Join-Path $Bin 'BridgeSupervisor.ps1') $fixture
$output=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $fixture 'BridgeSupervisor.ps1') -Start
if($LASTEXITCODE -ne 1){throw 'MissingSetupMustFail'}
$errorFile=Join-Path $fixture 'data\last-controller-error.json'
if(!(Test-Path $errorFile)){throw 'ControllerErrorReceiptMissing'}
$record=Get-Content $errorFile -Raw|ConvertFrom-Json;$response=$output|ConvertFrom-Json
if($record.Code -cne 'StationSetupRequired' -or $record.Pid -le 0 -or $record.Pid -ne $response.Data.Pid -or $response.Event -cne 'Error'){throw 'ControllerErrorReceiptMismatch'}
if(Test-Path (Join-Path $fixture 'data\launcher-state\owner.json')){throw 'UnexpectedOwnerCreated'}
@{Pass=$true;Code=$record.Code;PidBound=$true;HardwareTouched=$false;Fixture=$fixture}|ConvertTo-Json -Compress
