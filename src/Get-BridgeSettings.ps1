function Get-BridgeSettings {
 param([string]$ConfigPath,[string]$CorePath)
 Assert-Binary 'BridgeConfigCore.dll'
 [Reflection.Assembly]::LoadFrom($CorePath)|Out-Null
 return [CumbriaCQ.Configuration.SettingsStore]::Open($ConfigPath).Settings
}
