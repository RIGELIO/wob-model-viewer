param([switch]$RegisterOnly)

$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'WoB Model Viewer.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw 'Keep WoB Model Viewer.exe and Register-GLB.ps1 in the same folder.'
}
$progId = 'RIGELIO.WoBModelViewer.GLB'
$displayName = 'WoB Model Viewer'
$command = '"{0}" -- "%1"' -f $exe
$currentUser = [Microsoft.Win32.Registry]::CurrentUser

function Set-UserValue($Path, $Name, $Value, $Kind = [Microsoft.Win32.RegistryValueKind]::String) {
    $key = $currentUser.CreateSubKey($Path)
    try { $key.SetValue($Name, $Value, $Kind) }
    finally { $key.Dispose() }
}

Set-UserValue "Software\Classes\$progId" '' 'glTF Binary Model'
Set-UserValue "Software\Classes\$progId\DefaultIcon" '' ('"{0}",0' -f $exe)
Set-UserValue "Software\Classes\$progId\shell\open\command" '' $command
Set-UserValue 'Software\Classes\.glb\OpenWithProgids' $progId ([byte[]]@()) None
$capabilities = 'Software\RIGELIO\WoBModelViewer\Capabilities'
Set-UserValue $capabilities 'ApplicationName' $displayName
Set-UserValue $capabilities 'ApplicationDescription' 'Offline viewer for Wars of Bohemia GLB models'
Set-UserValue "$capabilities\FileAssociations" '.glb' $progId
Set-UserValue 'Software\RegisteredApplications' $displayName $capabilities
if (-not $RegisterOnly) {
    Start-Process 'ms-settings:defaultapps'
}
