# Copyright (c) 2026 M5LEE.
# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]param()
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
. (Join-Path $PSScriptRoot 'PublicRuntime.ps1')
. (Join-Path $PSScriptRoot 'FirstRun.ps1')
. (Join-Path $PSScriptRoot 'ExistingStation.ps1')
Add-Type -AssemblyName System.Windows.Forms;Add-Type -AssemblyName System.Drawing
$form=New-Object Windows.Forms.Form;$form.Text='WiresX 2 YSF Bridge - Station setup (ALPHA)';$form.Size=New-Object Drawing.Size(760,610);$form.StartPosition='CenterScreen';$form.Font=New-Object Drawing.Font('Segoe UI',9)
$form.Icon=New-Object Drawing.Icon((Join-Path $script:Bin 'assets\settings.ico'))
$panel=New-Object Windows.Forms.TableLayoutPanel;$panel.Dock='Fill';$panel.Padding=New-Object Windows.Forms.Padding(16);$panel.ColumnCount=2;$panel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',190)));$panel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)));$form.Controls.Add($panel)
# Gateway is the legacy storage key for the YSF-side bridge callsign, NOT a WIRES-X login ID.
$fields=@{};$portNames=@('PhysicalPort','NativePort','AdapterPort');$names=@('Gateway','PhysicalPort','NativePort','AdapterPort','NativePath');$labels=@('YSF bridge callsign','Genuine HRI-200 COM port','Virtual COM used by WIRES-X','Virtual COM used by bridge','Official WIRES-X executable')
$old=$null;try{$old=Get-Station}catch{}
for($row=0;$row -lt 6;$row++){$null=$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',36)))}
for($i=0;$i -lt $names.Count;$i++){
 $row=if($i -eq 0){0}else{$i+1}
 $label=New-Object Windows.Forms.Label;$label.Text=$labels[$i];$label.Dock='Fill';$label.TextAlign='MiddleLeft';$panel.Controls.Add($label,0,$row)
 if($names[$i] -in $portNames){$box=New-Object Windows.Forms.ComboBox;$box.DropDownStyle='DropDownList'}else{$box=New-Object Windows.Forms.TextBox}
 $box.Dock='Fill';$box.Margin=New-Object Windows.Forms.Padding(3,6,3,3);$panel.Controls.Add($box,1,$row);$fields[$names[$i]]=$box
 if($old){if($box -is [Windows.Forms.ComboBox]){$null=$box.Items.Add($old.($names[$i]));$box.SelectedItem=$old.($names[$i])}else{$box.Text=$old.($names[$i])}}
}
$fields.Gateway.MaxLength=10;$fields.Gateway.CharacterCasing='Upper'
$ysfLabel=New-Object Windows.Forms.Label;$ysfLabel.Text='YSF destination room';$ysfLabel.Dock='Fill';$ysfLabel.TextAlign='MiddleLeft';$panel.Controls.Add($ysfLabel,0,1)
$ysfChoose=New-Object Windows.Forms.Button;$ysfChoose.Text='Choose YSF destination room...';$ysfChoose.Dock='Fill';$panel.Controls.Add($ysfChoose,1,1)
$ysfChoose.Add_Click({Start-Process (Join-Path $script:Bin 'Bridge.exe')})
function Refresh-YsfTarget {
 try{Assert-Binary 'BridgeConfigCore.dll';[Reflection.Assembly]::LoadFrom((Join-Path $script:Bin 'BridgeConfigCore.dll'))|Out-Null;$target=[CumbriaCQ.Configuration.SettingsStore]::Open((Join-Path $script:Root 'bridge-config.json')).Settings;$ysfChoose.Text=$target.YsfRoomId+' - '+$target.YsfRoomName+' (change...)'}catch{$ysfChoose.Text='Choose YSF destination room...'}
}
$form.Add_Activated({Refresh-YsfTarget});Refresh-YsfTarget
if(!$old){$fields.NativePath.Text='C:\Program Files (x86)\YAESUMUSEN\WIRES-X\Wires-X.exe'}
$details=New-Object Windows.Forms.TableLayoutPanel;$details.Dock='Fill';$details.ColumnCount=1;$details.RowCount=3;$details.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',34)));$details.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',30)));$details.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)));$panel.Controls.Add($details,0,6);$panel.SetColumnSpan($details,2);$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)))
$portTools=New-Object Windows.Forms.FlowLayoutPanel;$portTools.Dock='Fill';$portTools.WrapContents=$false;$details.Controls.Add($portTools,0,0)
$automatic=New-Object Windows.Forms.Button;$automatic.Text='Automatic setup';$automatic.AutoSize=$true;$portTools.Controls.Add($automatic)
$existing=New-Object Windows.Forms.Button;$existing.Text='Import existing settings';$existing.AutoSize=$true;$portTools.Controls.Add($existing)
$advanced=New-Object Windows.Forms.CheckBox;$advanced.Text='Advanced setup';$advanced.AutoSize=$true;$portTools.Controls.Add($advanced);$portTools.Controls.SetChildIndex($advanced,0)
$refreshPorts=New-Object Windows.Forms.Button;$refreshPorts.Text='Refresh ports';$refreshPorts.AutoSize=$true;$portTools.Controls.Add($refreshPorts)
$portSummary=New-Object Windows.Forms.Label;$portSummary.Dock='Fill';$portSummary.TextAlign='MiddleLeft';$portSummary.AutoEllipsis=$true;$details.Controls.Add($portSummary,0,1)
function Get-DetectedPorts {return [IO.Ports.SerialPort]::GetPortNames()}
function Refresh-Ports {
 try{$ports=@(Get-DetectedPorts|Where-Object {$_ -cmatch '^COM[1-9][0-9]{0,3}$'}|Sort-Object -Unique|Sort-Object {[int]$_.Substring(3)})}catch{$portSummary.Text='Unable to list ports. Selections kept. Check Device Manager.';return}
 $missing=@()
 foreach($name in $portNames){
  $box=$fields[$name];$selected=$box.Text;$choices=@($ports)
  if($selected -and $selected -cnotin $ports){$choices+=,$selected;$missing+=,$selected}
  $box.BeginUpdate()
  try{$box.Items.Clear();if($choices.Count){$box.Items.AddRange([object[]]$choices)};$box.SelectedIndex=-1;if($selected){$box.SelectedItem=$selected}}finally{$box.EndUpdate()}
 }
 $portSummary.Text=if($ports.Count){[string]$ports.Count+' COM ports detected.'}else{'No COM ports detected. Check devices/drivers.'}
 if($missing.Count){$portSummary.Text+=' Not listed (kept): '+(($missing|Select-Object -Unique) -join ', ')}
}
$refreshPorts.Add_Click({Refresh-Ports});Refresh-Ports
$basicNotes="Set up WIRES-X first and connect it to a room.`r`n`r`nEnter the callsign to use on YSF, then choose your YSF destination room.`r`n`r`nThe bridge links your YSF destination to the room currently connected in WIRES-X. Change WIRES-X rooms there as usual.`r`n`r`nSave your changes, then select Open bridge to view status or start. Changes take effect the next time the bridge starts."
$advancedNotes="Connection tools are for initial setup or troubleshooting. Import existing settings reuses a validated connection profile without stopping the previous installation.`r`n`r`nKeep the FTM OFF and HRI connected when bridging. Profile capture requires your own supported radio connected and ON; follow its confirmation instructions. Private connection data stays on this PC."
$notes=New-Object Windows.Forms.Label;$notes.Text=$basicNotes;$notes.Dock='Fill';$details.Controls.Add($notes,0,2)
$advanced.Add_CheckedChanged({foreach($row in @(2,3,4,5)){$panel.RowStyles[$row].Height=if($advanced.Checked){36}else{0};foreach($column in @(0,1)){$panel.GetControlFromPosition($column,$row).Visible=$advanced.Checked}};foreach($tool in @($automatic,$existing,$portSummary,$import,$capture,$refreshPorts)){$tool.Visible=$advanced.Checked};$details.RowStyles[1].Height=if($advanced.Checked){30}else{0};$notes.Text=if($advanced.Checked){$advancedNotes}else{$basicNotes};$panel.RowStyles[8].Height=if($advanced.Checked){76}else{42}})
foreach($row in @(2,3,4,5)){$panel.RowStyles[$row].Height=0;foreach($column in @(0,1)){$panel.GetControlFromPosition($column,$row).Visible=$false}}
$refreshPorts.Visible=$false;$automatic.Visible=$false;$existing.Visible=$false;$portSummary.Visible=$false;$details.RowStyles[1].Height=0
$automatic.Add_Click({
 if([Windows.Forms.MessageBox]::Show('Set up connections automatically? This may install the bundled GPL com0com driver and create a dedicated virtual pair. Existing bridge sessions are refused. Windows security settings are not changed.','Automatic connection setup','YesNo','Information') -ne 'Yes'){return}
 $automatic.Enabled=$false;$form.UseWaitCursor=$true;$portSummary.Text='Checking WIRES-X, HRI-200 and virtual connections. Please wait...';$form.Refresh()
 try{$s=Initialize-StationConnections -Gateway $fields.Gateway.Text -OwnRoomId '' -PhysicalPort $fields.PhysicalPort.Text -NativePath $fields.NativePath.Text
  foreach($name in $names){if($fields[$name] -is [Windows.Forms.ComboBox]){if(!$fields[$name].Items.Contains($s.$name)){$null=$fields[$name].Items.Add($s.$name)};$fields[$name].SelectedItem=$s.$name}else{$fields[$name].Text=$s.$name}}
  Refresh-Ports;$save.Enabled=$true;$status.Text='Connections saved. Complete the connection profile under Advanced setup if needed.'
 }catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Automatic setup needs attention')|Out-Null}finally{$automatic.Enabled=$true;$form.UseWaitCursor=$false}
})
$existing.Add_Click({
 if($fields.Gateway.Text -cnotmatch '^[A-Z0-9][A-Z0-9 /-]{0,9}$'){[Windows.Forms.MessageBox]::Show('Enter the bridge callsign to use on YSF first (maximum 10 characters). This is not your WIRES-X gateway ID.','YSF bridge callsign')|Out-Null;return}
 $dialog=New-Object Windows.Forms.FolderBrowserDialog;$dialog.Description='Select your own working bridge folder (contains voice-adapter.ps1). It will only be read.'
 if($dialog.ShowDialog() -ne 'OK'){return}
 if([Windows.Forms.MessageBox]::Show('Reuse your metadata-only profile and verified port roles with the YSF callsign you entered? Confirm this is your own authorised station. WIRES-X account settings are unchanged. The old bridge is read only and keeps running; existing destination station data is never overwritten.','Import your working bridge','YesNo','Warning') -ne 'Yes'){return}
 $existing.Enabled=$false;$form.UseWaitCursor=$true
 try{$s=Import-ExistingStation $dialog.SelectedPath -YsfCallsign $fields.Gateway.Text
  foreach($name in $names){$box=$fields[$name];if($box -is [Windows.Forms.ComboBox]){if(!$box.Items.Contains($s.$name)){$null=$box.Items.Add($s.$name)};$box.SelectedItem=$s.$name}else{$box.Text=$s.$name}}
  Refresh-Ports;Refresh-YsfTarget;$save.Enabled=$true;$status.Text='Settings imported. Open the bridge when you are ready.'
 }catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Working bridge was not imported')|Out-Null}finally{$existing.Enabled=$true;$form.UseWaitCursor=$false}
})
$status=New-Object Windows.Forms.Label;$status.Dock='Fill';$status.Text=if($old -and $old.RadioProfileSha256){'Ready to use. Saved changes take effect the next time the bridge starts.'}else{'Complete Advanced setup before starting the bridge.'};$panel.Controls.Add($status,0,7);$panel.SetColumnSpan($status,2);$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',42)))
$buttons=New-Object Windows.Forms.FlowLayoutPanel;$buttons.Dock='Fill';$panel.Controls.Add($buttons,0,8);$panel.SetColumnSpan($buttons,2);$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',42)))
function Save-Fields {
 $s=[pscustomobject]@{SchemaVersion=1;Gateway=$fields.Gateway.Text;OwnRoomId='';PhysicalPort=$fields.PhysicalPort.Text;NativePort=$fields.NativePort.Text;AdapterPort=$fields.AdapterPort.Text;NativePath=$fields.NativePath.Text;RadioProfileSha256=''}
 $prior=$null;try{$prior=Get-Station}catch{}
 if($prior){$changed=$false;foreach($name in @('PhysicalPort','NativePort','AdapterPort','NativePath')){if($s.$name -cne $prior.$name){$changed=$true}};if(!$changed){$s.RadioProfileSha256=$prior.RadioProfileSha256}}
 Save-Station $s;return $s
}
$save=New-Object Windows.Forms.Button;$save.Text='Save YSF callsign';$save.AutoSize=$true;$save.Enabled=($null -ne $old);$buttons.Controls.Add($save)
$save.Add_Click({try{$null=Save-Fields;$status.Text='Saved. Changes take effect the next time the bridge starts.'}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Settings not saved')|Out-Null}})
$capture=New-Object Windows.Forms.Button;$capture.Text='Create connection profile';$capture.AutoSize=$true;$buttons.Controls.Add($capture)
$capture.Add_Click({try{
 $null=Save-Fields
 $answer=[Windows.Forms.MessageBox]::Show('I own and am authorised to use this HRI-200, FTM-100 and WIRES-X station. My radio is connected and ON for the startup capture. Start a bounded two-minute metadata-only capture? This may close my existing WIRES-X client; other running bridges are refused.','Confirm your own station','YesNo','Warning')
 if($answer -ne 'Yes'){return}
 $p=New-Object Diagnostics.ProcessStartInfo('powershell.exe',('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $script:Bin 'BridgeSupervisor.ps1')+'" -Capture'));$p.UseShellExecute=$true;$p.Verb='runas';$null=[Diagnostics.Process]::Start($p);$status.Text='Creating a connection profile. Wait two minutes, then reopen Advanced setup and follow its instructions.'
}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Capture not started')|Out-Null}})
$import=New-Object Windows.Forms.Button;$import.Text='Import connection profile';$import.AutoSize=$true;$buttons.Controls.Add($import)
$import.Add_Click({try{
 $null=Save-Fields;$dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Filter='Metadata-only capture (*.json)|*.json';if($dialog.ShowDialog() -ne 'OK'){return}
 if([Windows.Forms.MessageBox]::Show('Import only metadata captured from your own authorised station. It may include private identity/location data. Confirm ownership?','Private profile','YesNo','Warning') -ne 'Yes'){return}
 Import-OwnProfile $dialog.FileName;$status.Text='Connection profile ready. Open the bridge when you are ready.'
}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Profile not imported')|Out-Null}})
$close=New-Object Windows.Forms.Button;$close.Text='Close';$close.AutoSize=$true;$buttons.Controls.Add($close);$close.Add_Click({$form.Close()})

$launcher=New-Object Windows.Forms.Button;$launcher.Text='Open bridge';$launcher.AutoSize=$true;$buttons.Controls.Add($launcher);$launcher.Add_Click({Start-Process (Join-Path $script:Bin 'Bridge.exe') -ArgumentList '--launcher'})
$import.Visible=$false;$capture.Visible=$false
$link=New-Object Windows.Forms.LinkLabel;$link.Text='Free and AS IS. Optional donation to support CumbriaCQ';$link.Dock='Fill';$panel.Controls.Add($link,0,9);$panel.SetColumnSpan($link,2);$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',30)));$link.Add_LinkClicked({Start-Process 'https://cumbriacq.com/donate-support/'})
[Windows.Forms.Application]::EnableVisualStyles();$null=$form.ShowDialog()
