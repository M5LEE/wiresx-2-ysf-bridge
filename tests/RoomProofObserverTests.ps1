param([Parameter(Mandatory=$true)][string]$ObserverPath,[Parameter(Mandatory=$true)][string]$AssemblyPath)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
[Reflection.Assembly]::LoadFrom($AssemblyPath)|Out-Null
$source=[IO.File]::ReadAllText($ObserverPath);$from=$source.IndexOf(' $state=[pscustomobject]');$to=$source.IndexOf(' $path=Join-Path',$from)
if($from -lt 0 -or $to -le $from){throw 'ActualObserverStateBlockNotFound'}
# Inject only the external native-window read. Parse/state/error logic is production code.
$body=$source.Substring($from,$to-$from).Replace('[CumbriaCQ.Offline.NativeLogTail]::ReadNative($p.MainWindowHandle)','(& $script:ReadNative)')
$block=[ScriptBlock]::Create($body);$Tag='testproof';$AppPid=123;$StartUtc=[DateTime]::UtcNow.AddHours(-1).ToString('o');$lastConnectionLine='';$tracker=[CumbriaCQ.Offline.RoomProofTracker]::new()
$script:processStart=[DateTime]::Parse($StartUtc);$script:checks=0;$script:readFailure=$false;$script:partial=$false;$script:text="2026/01/02 12:00:00 Connected to TEST(12345).`n`n"
function Get-Process {param($Id)return [pscustomobject]@{StartTime=$script:processStart;MainWindowHandle=[IntPtr]1}}
$script:ReadNative={if($script:readFailure){throw [InvalidOperationException]::new('ReadTimeout')};$v=[CumbriaCQ.Offline.NativeLogView]::new();$v.Text=$script:text;$v.Lines=$script:text.Split("`n").Length-1;$v.TotalLines=$v.Lines;$v.Partial=$script:partial;return $v}
function Check($ok,$why){$script:checks++;if(!$ok){throw $why}}
. $block;Check ($state.Connected -and $state.RoomId -ceq '12345') 'Complete native structured connection must verify';$key=$state.ConnectionKey
$script:readFailure=$true;. $block
Check (!$state.Connected -and !$state.RoomId -and !$state.ConnectionKey) 'Read failure must never publish connected state'
Check ($state.Error -ceq 'NativeLogRead' -and $state.ErrorDetail -ceq 'ReadTimeout') 'Publish the bounded underlying read reason rather than only a PowerShell invocation wrapper'
Check ($state.RecoveryKey -ceq $key -and $state.AppStartUtc -ceq $StartUtc) 'Uncertain proof retains only process-bound continuation identity'
$script:readFailure=$false;. $block;Check ($state.Connected -and $state.ConnectionKey -ceq $key) 'Fresh continuous reread can restore the same token'
$script:partial=$true;. $block;Check (!$state.Connected -and $state.Error -ceq 'NativeLogRead') 'Partial reads remain fail-closed'
$script:partial=$false;$script:text="2026/01/02 12:00:00 Connected to TEST(12345).`n2026/01/02 12:00:00 Disconnect.`n2026/01/02 12:00:00 Connected to TEST(12345).`n`n";. $block
Check ($state.Connected -and $state.ConnectionKey -cne $key) 'Missed same-second reconnect must not reuse prior recovery token'
$script:processStart=[DateTime]::UtcNow;. $block
Check (!$state.Connected -and !$state.RecoveryKey -and $state.Error -cne 'NativeLogRead') 'Process binding failure is a hard boundary, not a recoverable read pause'
Write-Output ('ROOM_PROOF_OBSERVER_PASS checks='+$script:checks+' actual_state_logic=true native_io=injected')
