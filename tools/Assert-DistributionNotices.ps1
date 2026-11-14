[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Root)

$ErrorActionPreference='Stop'
$required=@(
 'LICENSE',
 'THIRD_PARTY_NOTICES.md',
 'vendor\com0com\LICENSE.txt',
 'vendor\com0com\ReadMe.txt',
 'vendor\com0com\ORIGIN.md',
 'vendor\com0com\hashes.json',
 'vendor\com0com\com0com-3.0.0.0-source.zip'
)
foreach($relative in $required){
 $path=Join-Path $Root $relative
 if(!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0){
  throw ('Required distribution file is missing or empty: '+$relative)
 }
}

# Require these names independently of the manifest so deleting a manifest
# entry cannot silently remove a required licence/source integrity check.
$vendor=Join-Path $Root 'vendor\com0com'
$manifest=Get-Content -LiteralPath (Join-Path $vendor 'hashes.json') -Raw|ConvertFrom-Json
foreach($name in @('LICENSE.txt','ReadMe.txt','com0com-3.0.0.0-source.zip')){
 $entry=$manifest.PSObject.Properties[$name]
 if($null -eq $entry -or [string]$entry.Value -notmatch '\A[0-9a-fA-F]{64}\z'){
  throw ('Required com0com SHA256 entry is missing or invalid: '+$name)
 }
 $actual=(Get-FileHash -LiteralPath (Join-Path $vendor $name) -Algorithm SHA256).Hash
 if($actual -ne [string]$entry.Value){
  throw ('Bundled com0com licence/source integrity check failed: '+$name)
 }
}

foreach($relative in @('LICENSE','THIRD_PARTY_NOTICES.md','vendor\com0com\ORIGIN.md')){
 if([string]::IsNullOrWhiteSpace((Get-Content -LiteralPath (Join-Path $Root $relative) -Raw))){
  throw ('Required distribution notice is blank: '+$relative)
 }
}
$licence=Get-Content -LiteralPath (Join-Path $Root 'LICENSE') -Raw
# Pin the complete, unmodified GPLv3 text; allow Windows or Unix line endings.
$normalized=$licence.Replace("`r`n","`n").Trim()+"`n"
$sha=[Security.Cryptography.SHA256]::Create()
try{$licenceHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized)))).Replace('-','')}finally{$sha.Dispose()}
if($licenceHash -cne '605E9047A563C5C8396FFB18232AA4304EC56586AEE537C45064C6FB425E44AD'){
 throw 'The distribution must include the complete, unmodified GNU GPL version 3 licence.'
}

# Check disclosures within a paragraph, allowing formatting and wording edits.
$notices=Get-Content -LiteralPath (Join-Path $Root 'THIRD_PARTY_NOTICES.md') -Raw
$paragraphs=$notices -split '\r?\n\s*\r?\n'
$yaesuNotice=@($paragraphs|Where-Object {
 $_ -match '\bYaesu\b' -and
 ($_ -match '\bnot\b[^.?!]*\b(?:official|affiliated|endorsed|sponsored)\b' -or
  $_ -match '\b(?:no|without)\s+(?:official\s+)?(?:affiliation|endorsement|sponsorship)\b')
})
if($yaesuNotice.Count -eq 0){
 throw 'THIRD_PARTY_NOTICES.md must retain the Yaesu independence / non-endorsement disclosure.'
}
$com0comNotice=@($paragraphs|Where-Object {
 $_ -match '\bcom0com\b' -and $_ -match '\b(?:GPL|General Public Licen[cs]e)\b' -and
 $_ -match '\b(?:separate|separately)\b|\bnot\s+under\b|\bdoes\s+not\s+replace\b'
})
if($com0comNotice.Count -eq 0){
 throw 'THIRD_PARTY_NOTICES.md must retain the separate upstream com0com GPL disclosure.'
}

Write-Output ('DISTRIBUTION_NOTICES_OK '+$Root)
