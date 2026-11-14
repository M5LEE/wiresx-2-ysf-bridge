# Copyright (c) 2026 M5LEE.
# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param(
 [string]$Root=(Split-Path $PSScriptRoot -Parent),
 [string]$LicensePath,
 [string]$FixtureParent=[IO.Path]::GetTempPath()
)
$ErrorActionPreference='Stop'
if(!$LicensePath){$LicensePath=Join-Path $Root 'LICENSE'}
$guard=Join-Path $Root 'tools/Assert-DistributionNotices.ps1'
$fixture=Join-Path $FixtureParent ('bridge-notices-'+[Guid]::NewGuid().ToString('N'))
$vendor=Join-Path $fixture 'vendor/com0com'
$checks=0
function Reset-Fixture {
 New-Item -ItemType Directory -Force $vendor|Out-Null
 Copy-Item -LiteralPath $LicensePath -Destination (Join-Path $fixture 'LICENSE') -Force
 foreach($name in @('LICENSE.txt','ReadMe.txt','ORIGIN.md','hashes.json','com0com-3.0.0.0-source.zip')){
  Copy-Item -LiteralPath (Join-Path $Root ('vendor/com0com/'+$name)) -Destination (Join-Path $vendor $name) -Force
 }
 @'
Copyright (c) 2026 M5LEE. Original bridge contributions are licensed under GNU GPL version 3 or later (SPDX-License-Identifier: GPL-3.0-or-later).

This independent bridge is not affiliated with or endorsed by Yaesu.

com0com is a separate GPL-licensed component. Its original upstream licence and copyright notices remain unchanged.
'@|Set-Content -LiteralPath (Join-Path $fixture 'THIRD_PARTY_NOTICES.md') -Encoding UTF8
}
function Assert-Rejected([string]$Expected){
 $message=$null
 try{$null=& $guard -Root $fixture}catch{$message=$_.Exception.Message}
 if(!$message -or $message -notmatch $Expected){throw ('Expected refusal matching '+$Expected+'; got: '+$message)}
 $script:checks++
}
try{
 Reset-Fixture
 $result=@(& $guard -Root $fixture)
 if($result.Count -ne 1 -or $result[0] -notlike 'DISTRIBUTION_NOTICES_OK *'){throw 'Complete GPLv3 fixture was not accepted'}
 $checks++
 'GNU GENERAL PUBLIC LICENSE'+"`n"+'Version 3, 29 June 2007'|Set-Content -LiteralPath (Join-Path $fixture 'LICENSE') -Encoding UTF8
 Assert-Rejected 'complete.*GPL version 3'
 Reset-Fixture
 'MIT License'|Set-Content -LiteralPath (Join-Path $fixture 'LICENSE') -Encoding UTF8
 Assert-Rejected 'GPL version 3'
 Reset-Fixture
 $text=(Get-Content -LiteralPath $LicensePath -Raw).Replace("`r`n","`n").Replace("`n","`r`n")
 [IO.File]::WriteAllText((Join-Path $fixture 'LICENSE'),$text)
 $null=& $guard -Root $fixture;$checks++
 foreach($relative in @('LICENSE','THIRD_PARTY_NOTICES.md','vendor/com0com/LICENSE.txt','vendor/com0com/ReadMe.txt','vendor/com0com/ORIGIN.md','vendor/com0com/hashes.json','vendor/com0com/com0com-3.0.0.0-source.zip')){
  Reset-Fixture
  Remove-Item -LiteralPath (Join-Path $fixture $relative)
  Assert-Rejected 'missing or empty'
  Reset-Fixture
  [IO.File]::WriteAllText((Join-Path $fixture $relative),'')
  Assert-Rejected 'missing or empty'
 }
 foreach($name in @('LICENSE.txt','ReadMe.txt','com0com-3.0.0.0-source.zip')){
  Reset-Fixture
  [IO.File]::AppendAllText((Join-Path $vendor $name),'changed')
  Assert-Rejected 'integrity check failed'
  Reset-Fixture
  $manifest=Get-Content -LiteralPath (Join-Path $vendor 'hashes.json') -Raw|ConvertFrom-Json
  $manifest.PSObject.Properties.Remove($name)
  $manifest|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $vendor 'hashes.json') -Encoding UTF8
  Assert-Rejected 'SHA256 entry is missing or invalid'
 }
 Reset-Fixture
 $notices=Get-Content -LiteralPath (Join-Path $fixture 'THIRD_PARTY_NOTICES.md') -Raw
 $notices.Replace('not affiliated with or endorsed by','affiliated with and endorsed by')|Set-Content -LiteralPath (Join-Path $fixture 'THIRD_PARTY_NOTICES.md') -Encoding UTF8
 Assert-Rejected 'Yaesu independence'
 Reset-Fixture
 $notices.Replace('a separate GPL-licensed component','an included GPL-licensed component')|Set-Content -LiteralPath (Join-Path $fixture 'THIRD_PARTY_NOTICES.md') -Encoding UTF8
 Assert-Rejected 'separate upstream com0com'
 Write-Output ('DISTRIBUTION_NOTICE_TESTS_OK '+$checks)
}finally{
 if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
