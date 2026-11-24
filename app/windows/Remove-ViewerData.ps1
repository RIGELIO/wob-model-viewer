$ErrorActionPreference = 'Stop'
$folder = Join-Path $env:APPDATA 'Godot\app_userdata\WoB Model Viewer'
if (-not (Test-Path -LiteralPath $folder -PathType Container)) { return }
$root = Get-Item -LiteralPath $folder
for ($part = $root; $part; $part = $part.Parent) {
    if ($part.Attributes -band [IO.FileAttributes]::ReparsePoint) { return }
}
$prefix = $root.FullName + [IO.Path]::DirectorySeparatorChar

function Remove-GeneratedItem([IO.FileSystemInfo]$Item, [string]$FilePattern) {
    if (-not $Item.FullName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
        ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return }
    if ($Item -is [IO.DirectoryInfo]) {
        Get-ChildItem -LiteralPath $Item.FullName -Force | ForEach-Object { Remove-GeneratedItem $_ $FilePattern }
        if (Get-ChildItem -LiteralPath $Item.FullName -Force | Select-Object -First 1) { return }
    } elseif ($Item.Name -notlike $FilePattern) {
        return
    }
    Remove-Item -LiteralPath $Item.FullName -Force
}

$owned = @{
    'viewer.cfg' = 'viewer.cfg'
    'logs' = 'godot*.log'
    'shader_cache' = '*.cache'
    'vulkan' = '*.cache'
    'objectdb_snapshots' = ''
}
foreach ($name in $owned.Keys) {
    $path = Join-Path $root.FullName $name
    if (Test-Path -LiteralPath $path) {
        Remove-GeneratedItem (Get-Item -LiteralPath $path -Force) $owned[$name]
    }
}
if (-not (Get-ChildItem -LiteralPath $root.FullName -Force | Select-Object -First 1)) {
    Remove-Item -LiteralPath $root.FullName -Force
}
