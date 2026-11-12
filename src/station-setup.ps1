# Copyright (c) 2026 M5LEE. MIT; see LICENSE.
[CmdletBinding()]param()
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
. (Join-Path $PSScriptRoot 'PublicRuntime.ps1')
. (Join-Path $PSScriptRoot 'FirstRun.ps1')
Add-Type -AssemblyName System.Windows.Forms;Add-Type -AssemblyName System.Drawing
$form=New-Object Windows.Forms.Form;$form.Text='WiresX 2 YSF Bridge - Station setup (ALPHA)';$form.Size=New-Object Drawing.Size(760,610);$form.StartPosition='CenterScreen';$form.Font=New-Object Drawing.Font('Segoe UI',9)
$form.Icon=New-Object Drawing.Icon((Join-Path $script:Bin 'assets\settings.ico'))
$panel=New-Object Windows.Forms.TableLayoutPanel;$panel.Dock='Fill';$panel.Padding=New-Object Windows.Forms.Padding(16);$panel.ColumnCount=2;$panel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',190)));$panel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)));$form.Controls.Add($panel)
$fields=@{};$portNames=@('PhysicalPort','NativePort','AdapterPort');$names=@('Gateway','OwnRoomId','PhysicalPort','NativePort','AdapterPort','NativePath');$labels=@('Your gateway callsign (max10)','Your licensed WIRES-X room ID','Genuine HRI-200 COM port','Virtual COM used by WIRES-X','Virtual COM used by bridge','Official WIRES-X executable')
$old=$null;try{$old=Get-Station}catch{}
for($i=0;$i -lt $names.Count;$i++){
 $panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',36)))
 $label=New-Object Windows.Forms.Label;$label.Text=$labels[$i];$label.Dock='Fill';$label.TextAlign='MiddleLeft';$panel.Controls.Add($label,0,$i)
 if($names[$i] -in $portNames){$box=New-Object Windows.Forms.ComboBox;$box.DropDownStyle='DropDownList'}else{$box=New-Object Windows.Forms.TextBox}
 $box.Dock='Fill';$box.Margin=New-Object Windows.Forms.Padding(3,6,3,3);$panel.Controls.Add($box,1,$i);$fields[$names[$i]]=$box
 if($old){if($box -is [Windows.Forms.ComboBox]){$null=$box.Items.Add($old.($names[$i]));$box.SelectedItem=$old.($names[$i])}else{$box.Text=$old.($names[$i])}}
}
if(!$old){$fields.NativePath.Text='C:\Program Files (x86)\YAESUMUSEN\WIRES-X\Wires-X.exe'}
$details=New-Object Windows.Forms.TableLayoutPanel;$details.Dock='Fill';$details.ColumnCount=1;$details.RowCount=3;$details.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',34)));$details.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',30)));$details.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)));$panel.Controls.Add($details,0,6);$panel.SetColumnSpan($details,2);$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)))
$portTools=New-Object Windows.Forms.FlowLayoutPanel;$portTools.Dock='Fill';$portTools.WrapContents=$false;$details.Controls.Add($portTools,0,0)
$automatic=New-Object Windows.Forms.Button;$automatic.Text='Automatic setup';$automatic.AutoSize=$true;$portTools.Controls.Add($automatic)
$advanced=New-Object Windows.Forms.CheckBox;$advanced.Text='Advanced COM settings';$advanced.AutoSize=$true;$portTools.Controls.Add($advanced)
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
$notes=New-Object Windows.Forms.Label;$notes.Text="1. Enter your gateway callsign and five-digit room number shown in WIRES-X. Connect the HRI-200 USB cable, then click Automatic setup. WIRES-X is detected and the bundled virtual-port driver/pair is configured for you. Windows may ask for administrator approval.`r`n`r`n2. With YOUR FTM-100 connected and powered ON, click Capture my radio profile. This takes about two minutes and blocks PTT/voice. The HRI-200 and radio must be yours.`r`n`r`n3. After capture finishes, power the FTM OFF. Choose your YSF room in YSF settings, then use Open launcher to start the bridge.`r`n`r`nExperimental FTM-100 profile only. Windows security is never disabled. Station settings are stored locally.";$notes.Dock='Fill';$details.Controls.Add($notes,0,2)
$advanced.Add_CheckedChanged({foreach($row in @(2,3,4,5)){$panel.RowStyles[$row].Height=if($advanced.Checked){36}else{0};foreach($column in @(0,1)){$panel.GetControlFromPosition($column,$row).Visible=$advanced.Checked}};$save.Visible=$advanced.Checked;$import.Visible=$advanced.Checked;$refreshPorts.Visible=$advanced.Checked;$panel.RowStyles[8].Height=if($advanced.Checked){76}else{42}})
foreach($row in @(2,3,4,5)){$panel.RowStyles[$row].Height=0;foreach($column in @(0,1)){$panel.GetControlFromPosition($column,$row).Visible=$false}}
$refreshPorts.Visible=$false
$automatic.Add_Click({
 if([Windows.Forms.MessageBox]::Show('Set up connections automatically? This may install the bundled GPL com0com driver and create a dedicated virtual pair. Existing bridge sessions are refused. Windows security settings are not changed.','Automatic connection setup','YesNo','Information') -ne 'Yes'){return}
 $automatic.Enabled=$false;$form.UseWaitCursor=$true;$portSummary.Text='Checking WIRES-X, HRI-200 and virtual connections. Please wait...';$form.Refresh()
 try{$s=Initialize-StationConnections -Gateway $fields.Gateway.Text -OwnRoomId $fields.OwnRoomId.Text -PhysicalPort $fields.PhysicalPort.Text -NativePath $fields.NativePath.Text
  foreach($name in $names){if($fields[$name] -is [Windows.Forms.ComboBox]){if(!$fields[$name].Items.Contains($s.$name)){$null=$fields[$name].Items.Add($s.$name)};$fields[$name].SelectedItem=$s.$name}else{$fields[$name].Text=$s.$name}}
  Refresh-Ports;$status.Text='Connections ready. Step 2: power your FTM-100 ON and capture your radio profile.'
 }catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Automatic setup needs attention')|Out-Null}finally{$automatic.Enabled=$true;$form.UseWaitCursor=$false}
})
$status=New-Object Windows.Forms.Label;$status.Dock='Fill';$status.Text=if($old -and $old.RadioProfileSha256){'Private profile is present; changing station fields requires recapture.'}else{'No private radio profile. Capture or import your own before Start.'};$panel.Controls.Add($status,0,7);$panel.SetColumnSpan($status,2);$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',42)))
$buttons=New-Object Windows.Forms.FlowLayoutPanel;$buttons.Dock='Fill';$panel.Controls.Add($buttons,0,8);$panel.SetColumnSpan($buttons,2);$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',42)))
function Save-Fields {
 $s=[pscustomobject]@{SchemaVersion=1;Gateway=$fields.Gateway.Text;OwnRoomId=$fields.OwnRoomId.Text;PhysicalPort=$fields.PhysicalPort.Text;NativePort=$fields.NativePort.Text;AdapterPort=$fields.AdapterPort.Text;NativePath=$fields.NativePath.Text;RadioProfileSha256=''}
 $prior=$null;try{$prior=Get-Station}catch{}
 if($prior){$changed=$false;foreach($name in $names){if($s.$name -cne $prior.$name){$changed=$true}};if(!$changed){$s.RadioProfileSha256=$prior.RadioProfileSha256}}
 Save-Station $s;return $s
}
$save=New-Object Windows.Forms.Button;$save.Text='Save station';$save.AutoSize=$true;$buttons.Controls.Add($save)
$save.Add_Click({try{$null=Save-Fields;$status.Text='Station saved. Changes apply only on next startup.'}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Station not saved')|Out-Null}})
$capture=New-Object Windows.Forms.Button;$capture.Text='Capture my radio profile';$capture.AutoSize=$true;$buttons.Controls.Add($capture)
$capture.Add_Click({try{
 $null=Save-Fields
 $answer=[Windows.Forms.MessageBox]::Show('I own and am authorised to use this HRI-200, FTM-100 and WIRES-X station. My radio is connected and ON for the startup capture. Start a bounded two-minute metadata-only capture? This may close my existing WIRES-X client; other running bridges are refused.','Confirm your own station','YesNo','Warning')
 if($answer -ne 'Yes'){return}
 $p=New-Object Diagnostics.ProcessStartInfo('powershell.exe',('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $script:Bin 'BridgeSupervisor.ps1')+'" -Capture'));$p.UseShellExecute=$true;$p.Verb='runas';$null=[Diagnostics.Process]::Start($p);$status.Text='Capture requested. Wait two minutes, then reopen setup to check the profile. Power FTM OFF before bridge Start.'
}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Capture not started')|Out-Null}})
$import=New-Object Windows.Forms.Button;$import.Text='Import my own capture';$import.AutoSize=$true;$buttons.Controls.Add($import)
$import.Add_Click({try{
 $null=Save-Fields;$dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Filter='Metadata-only capture (*.json)|*.json';if($dialog.ShowDialog() -ne 'OK'){return}
 if([Windows.Forms.MessageBox]::Show('Import only metadata captured from your own authorised station. It may include private identity/location data. Confirm ownership?','Private profile','YesNo','Warning') -ne 'Yes'){return}
 Import-OwnProfile $dialog.FileName;$status.Text='Private profile imported and validated. Keep FTM OFF for bridge startup.'
}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Profile not imported')|Out-Null}})
$close=New-Object Windows.Forms.Button;$close.Text='Close';$close.AutoSize=$true;$buttons.Controls.Add($close);$close.Add_Click({$form.Close()})
$ysf=New-Object Windows.Forms.Button;$ysf.Text='YSF settings';$ysf.AutoSize=$true;$buttons.Controls.Add($ysf);$ysf.Add_Click({Start-Process (Join-Path $script:Bin 'Bridge.exe')})
$launcher=New-Object Windows.Forms.Button;$launcher.Text='Open launcher';$launcher.AutoSize=$true;$buttons.Controls.Add($launcher);$launcher.Add_Click({Start-Process (Join-Path $script:Bin 'Bridge.exe') -ArgumentList '--launcher'})
$save.Visible=$false;$import.Visible=$false
$link=New-Object Windows.Forms.LinkLabel;$link.Text='Free and AS IS. Optional donation to support CumbriaCQ';$link.Dock='Fill';$panel.Controls.Add($link,0,9);$panel.SetColumnSpan($link,2);$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',30)));$link.Add_LinkClicked({Start-Process 'https://cumbriacq.com/donate-support/'})
[Windows.Forms.Application]::EnableVisualStyles();$null=$form.ShowDialog()
