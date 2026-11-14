# Copyright (c) 2026 M5LEE.
# SPDX-License-Identifier: GPL-3.0-or-later
param([Parameter(Mandatory=$true)][string]$Bin)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$fixture=Join-Path (Split-Path $Bin) ('tests\station-ui-'+[Guid]::NewGuid().ToString('N'))
$checks=0
function Check($condition,$name){if(!$condition){throw ('FAIL: '+$name)};$script:checks++;Write-Output ('PASS: '+$name)}
try{
 New-Item -ItemType Directory $fixture|Out-Null
 Copy-Item (Join-Path $Bin 'assets') $fixture -Recurse
 Copy-Item (Join-Path $Bin 'FirstRun.ps1') $fixture
 Copy-Item (Join-Path $Bin 'ExistingStation.ps1') $fixture
 $runtime=Get-Content (Join-Path $Bin 'PublicRuntime.ps1') -Raw
 $lines=$runtime -split '\r?\n';$lines[2]='$script:Root=Join-Path $PSScriptRoot ''fixture-data'''
 $lines -join "`r`n"|Set-Content (Join-Path $fixture 'PublicRuntime.ps1') -Encoding UTF8
 $ui=Get-Content (Join-Path $Bin 'station-setup.ps1') -Raw
 if($ui.Split(@('$null=$form.ShowDialog()'),[StringSplitOptions]::None).Count -ne 2){throw 'ExpectedOneDialogEntryPoint'}
 $ui.Replace('$null=$form.ShowDialog()','')|Set-Content (Join-Path $fixture 'station-setup.ps1') -Encoding UTF8
 . (Join-Path $fixture 'station-setup.ps1')
 Check ($panel.GetControlFromPosition(0,0).Text -ceq 'YSF bridge callsign') 'normal identity field is explicitly YSF-side only'
 Check (!$fields.ContainsKey('OwnRoomId')) 'no native gateway or own-room field is created'
 Check ($ysfChoose -is [Windows.Forms.Button] -and $panel.GetControlFromPosition(0,1).Text -ceq 'YSF destination room') 'normal setup exposes the YSF room chooser'
 Check ($notes.Text -match 'Set up WIRES-X first' -and $notes.Text -match 'room currently connected in WIRES-X') 'simple instructions explain the prerequisite and connected-room behaviour'
 Check ($notes.Text -notmatch '(?i)\b(FTM|HRI|radio|development|metadata|capture|\x41\x49)\b') 'normal instructions stay focused on ordinary bridge setup'
 Check ($advanced.Text -ceq 'Advanced setup') 'advanced tools have a plain-language label'
 Check ($portSummary.Text -notlike 'Unable to list ports*') 'Windows port enumeration succeeds without opening devices'
 Check ($panel.RowStyles[2].Height -eq 0 -and !$advanced.Checked) 'normal setup does not ask novice users for COM numbers'
 $advanced.Checked=$true
 Check ($panel.RowStyles[3].Height -eq 36) 'advanced mode exposes manual port selectors'
 foreach($name in @('PhysicalPort','NativePort','AdapterPort')){
  Check ($fields[$name] -is [Windows.Forms.ComboBox]) ($name+' uses a port selector')
  Check ($fields[$name].DropDownStyle -eq [Windows.Forms.ComboBoxStyle]::DropDownList) ($name+' requires an explicit list selection')
 }
 Check ($refreshPorts -is [Windows.Forms.Button] -and $refreshPorts.Text -ceq 'Refresh ports') 'refresh ports button exists'
 # Inject inventory only: never open a serial port, alter aliases, capture or start a bridge.
 function Get-DetectedPorts {return @('COM10','COM2','COM2','invalid','COM1')}
 Refresh-Ports
 Check (($fields.PhysicalPort.Items -join ',') -ceq 'COM1,COM2,COM10') 'detected ports are valid, unique and numerically sorted'
 Check ($fields.PhysicalPort.SelectedIndex -eq -1) 'no port is guessed for a fresh station'
 $fields.PhysicalPort.SelectedItem='COM1';$fields.NativePort.SelectedItem='COM2';$fields.AdapterPort.SelectedItem='COM10'
 $fields.Gateway.Text='TEST1/YSF'
 $null=Save-Fields
 $saved=Get-Station
 Check ($saved.PhysicalPort -ceq 'COM1' -and $saved.NativePort -ceq 'COM2' -and $saved.AdapterPort -ceq 'COM10') 'selected port values reach station persistence'
 $saved.RadioProfileSha256='A'*64;Save-Station $saved;$fields.Gateway.Text='TEST9/YSF';$null=Save-Fields
 Check ((Get-Station).Gateway -ceq 'TEST9/YSF' -and (Get-Station).RadioProfileSha256 -ceq ('A'*64)) 'changing YSF callsign preserves the existing radio profile'
 $hash=(Get-FileHash (Join-Path $script:Root 'station.json')).Hash
 function Get-DetectedPorts {return @('COM1','COM10','COM20')}
 $form.Show();[Windows.Forms.Application]::DoEvents();$refreshPorts.PerformClick();[Windows.Forms.Application]::DoEvents()
 Check ($automatic.Visible -and $existing.Visible -and $portSummary.Visible -and $capture.Visible -and $import.Visible) 'advanced view retains all connection and profile tools'
 Check ($notes.Text -match 'FTM OFF' -and $notes.Text -match 'radio connected and ON') 'required equipment guidance remains available only in advanced setup'
 Check ($fields.NativePort.Text -ceq 'COM2' -and $fields.AdapterPort.Text -ceq 'COM10') 'refresh button preserves selections including disconnected ports'
 Check ($portSummary.Text -like '*COM2*') 'disconnected selection is reported'
 Check ((Get-FileHash (Join-Path $script:Root 'station.json')).Hash -ceq $hash) 'refresh does not save or alter station data'
 function Get-DetectedPorts {return @()}
 Refresh-Ports
 Check ($fields.NativePort.Text -ceq 'COM2' -and $fields.PhysicalPort.Text -ceq 'COM1') 'empty inventory preserves configured ports'
 Check ($portSummary.Text -like '*No COM ports detected*') 'missing drivers or devices are explained'
 function Get-DetectedPorts {throw 'Synthetic discovery failure'}
 Refresh-Ports
 Check ($fields.NativePort.Text -ceq 'COM2' -and $portSummary.Text -like '*Unable to list ports*') 'discovery failure retains choices with a visible error'
 function Get-DetectedPorts {return @('COM1','COM2','COM10')}
 Refresh-Ports
 $fields.AdapterPort.SelectedItem='COM1';$refused=$false;try{$null=Save-Fields}catch{$refused=$_.Exception.Message -ceq 'DistinctPortsRequired'}
 Check $refused 'duplicate role choices are still refused'
 Check ((Get-FileHash (Join-Path $script:Root 'station.json')).Hash -ceq $hash) 'invalid choices leave the saved station intact'
 $fields.AdapterPort.SelectedItem='COM10';$form.PerformLayout();[Windows.Forms.Application]::DoEvents()
 Check ($fields.PhysicalPort.Text -ceq 'COM1' -and $fields.NativePort.Text -ceq 'COM2' -and $fields.AdapterPort.Text -ceq 'COM10') 'final controls show all three intended selections'
 $advanced.Checked=$false;$form.PerformLayout();[Windows.Forms.Application]::DoEvents()
 Check (!$automatic.Visible -and !$existing.Visible -and !$portSummary.Visible -and !$capture.Visible -and !$import.Visible) 'normal view hides connection, migration and radio tools'
 Check ($status.Text -notmatch '(?i)\b(FTM|HRI|radio|metadata|capture|\x41\x49)\b') 'normal status stays simple and hardware-neutral'
 Check ($notes.GetPreferredSize((New-Object Drawing.Size($notes.Width,0))).Height -le $notes.Height) 'setup notes fit without clipping'
 $bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
 try{$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)));$bitmap.Save((Join-Path (Split-Path $Bin) 'station-setup-preview.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
 Write-Output ('RESULT: '+$checks+' station port-selector checks passed; isolated UI/data only; no serial ports opened')
}finally{
 if($form){$form.Close();$form.Dispose()}
 if(Test-Path $fixture){Remove-Item $fixture -Recurse -Force}
}
