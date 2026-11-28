param(
    [string]$Executable = (Join-Path $PSScriptRoot 'WoB Model Viewer.exe'),
    [switch]$RegisterOnly
)

$ErrorActionPreference = 'Stop'
$file = Get-Item -LiteralPath $Executable
if ($file -isnot [System.IO.FileInfo] -or $file.Name -ne 'WoB Model Viewer.exe') {
    throw 'Select the WoB Model Viewer executable.'
}
$exe = $file.FullName
$displayName = 'WoB Model Viewer'
$command = '"{0}" -- "%1"' -f $exe
$currentUser = [Microsoft.Win32.Registry]::CurrentUser

function Set-UserValue($Path, $Name, $Value, $Kind = [Microsoft.Win32.RegistryValueKind]::String) {
    $key = $currentUser.CreateSubKey($Path)
    try { $key.SetValue($Name, $Value, $Kind) }
    finally { $key.Dispose() }
}

$capabilities = 'Software\RIGELIO\WoBModelViewer\Capabilities'
Set-UserValue $capabilities 'ApplicationName' $displayName
Set-UserValue $capabilities 'ApplicationDescription' 'Offline 3D model viewer for GLB, glTF, FBX, OBJ and STL'
foreach ($type in @(
    @{ Extension = '.glb'; Id = 'GLB'; Description = 'glTF Binary Model' }
    @{ Extension = '.gltf'; Id = 'GLTF'; Description = 'glTF Model' }
    @{ Extension = '.fbx'; Id = 'FBX'; Description = 'FBX Model' }
    @{ Extension = '.obj'; Id = 'OBJ'; Description = 'Wavefront OBJ Model' }
    @{ Extension = '.stl'; Id = 'STL'; Description = 'STL Model' }
    @{ Extension = '.wobview'; Id = 'View'; Description = 'WoB Model Viewer View' }
)) {
    $progId = "RIGELIO.WoBModelViewer.$($type.Id)"
    $class = "Software\Classes\$progId"
    Set-UserValue $class '' $type.Description
    Set-UserValue "$class\DefaultIcon" '' ('"{0}",0' -f $exe)
    Set-UserValue "$class\shell\open\command" '' $command
    Set-UserValue "Software\Classes\$($type.Extension)\OpenWithProgids" $progId ([byte[]]@()) None
    Set-UserValue "$capabilities\FileAssociations" $type.Extension $progId
}
Set-UserValue 'Software\RegisteredApplications' $displayName $capabilities
if (-not ('WoB.Windows.Shell' -as [type])) {
    Add-Type -Namespace WoB.Windows -Name Shell -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll")]
public static extern void SHChangeNotify(int eventId, uint flags, System.IntPtr item1, System.IntPtr item2);
'@
}
[WoB.Windows.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
if (-not $RegisterOnly) {
    Start-Process ("ms-settings:defaultapps?registeredAppUser={0}" -f [Uri]::EscapeDataString($displayName))
}
