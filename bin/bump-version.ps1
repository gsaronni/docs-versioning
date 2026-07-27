# bin/bump-version.ps1
param(
    [ValidateSet('Patch','Minor','Major')][string]$Level = 'Patch',
    [switch]$Alpha,
    [switch]$Beta
)

if ($Alpha -and $Beta) {
    Write-Host "ERROR: -Alpha and -Beta are mutually exclusive — pick one." -ForegroundColor Red
    exit 1
}

$VersionFile = Join-Path $PSScriptRoot "..\VERSION"
$current = (Get-Content $VersionFile -Raw).Trim() -replace '-(alpha|beta)$',''
$parts = $current.Split('.') | ForEach-Object { [int]$_ }
switch ($Level) {
    'Major' { $parts[0]++; $parts[1] = 0; $parts[2] = 0 }
    'Minor' { $parts[1]++; $parts[2] = 0 }
    'Patch' { $parts[2]++ }
}
$suffix = if ($Alpha) { '-alpha' } elseif ($Beta) { '-beta' } else { '' }
$new = ($parts -join '.') + $suffix
Set-Content -Path $VersionFile -Value $new -NoNewline
Write-Host "Version bumped: $current -> $new" -ForegroundColor Green