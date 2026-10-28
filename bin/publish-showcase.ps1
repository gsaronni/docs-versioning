#Requires -Version 7.0
<#
.SYNOPSIS
    Export the committed tree of this (private) repo into the public showcase clone, anonymised.

.DESCRIPTION
    One-way publication: private Gitea repo -> public GitHub showcase.

    1. git archive HEAD of this repo into a temp folder (working tree is never used, so uncommitted
       and ignored files cannot leak).
    2. Delete every path listed under Exclude in etc/showcase-replacements.psd1.
    3. Apply every Replace rule (whole-word, case-insensitive) to every text file.
    4. Verify: scan the export for every Replace source term and every Verify term. Any hit aborts
       before anything touches the showcase clone.
    5. Mirror the export into the showcase clone (everything except .git is replaced), stage it and
       commit "Sync showcase from v<VERSION>". Push only with -Push.

    The showcase clone keeps its own history: one commit per publish. Nothing from this repo's
    history is ever transferred.

.PARAMETER ShowcaseRoot
    Path to the local clone of the public showcase repo. Must contain .git and have an origin
    remote on github.com.

.PARAMETER DryRun
    Export, replace and verify, then show what would change in the showcase clone. No commit.

.PARAMETER Push
    After committing, run git push in the showcase clone.

.EXAMPLE
    .\bin\publish-showcase.ps1 -ShowcaseRoot C:\Users\me\proj\docs-versioning -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ShowcaseRoot,

    [switch]$DryRun,
    [switch]$Push
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$PrivateRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RulesPath   = Join-Path $PrivateRoot 'etc\showcase-replacements.psd1'
$VersionPath = Join-Path $PrivateRoot 'VERSION'

$TextExtensions = @('.ps1', '.psm1', '.psd1', '.md', '.txt', '.yml', '.yaml', '.json', '.gitignore', '.gitattributes', '')

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Fail([string]$Message) { throw "publish-showcase: $Message" }

function Invoke-Git {
    param([string]$Repo, [string[]]$GitArgs)
    $out = & git -C $Repo @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { Fail "git $($GitArgs -join ' ') failed in $Repo`n$out" }
    return $out
}

function Test-IsTextFile([System.IO.FileInfo]$File) {
    if ($TextExtensions -notcontains $File.Extension.ToLowerInvariant()) { return $false }
    if ($File.Length -eq 0) { return $true }
    $bytes = [System.IO.File]::ReadAllBytes($File.FullName)
    $probe = [Math]::Min($bytes.Length, 8000)
    for ($i = 0; $i -lt $probe; $i++) { if ($bytes[$i] -eq 0) { return $false } }
    return $true
}

# --- 0. Preconditions ----------------------------------------------------------------------------

Write-Step 'Checking preconditions'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'git is not on PATH' }
if (-not (Test-Path $RulesPath))   { Fail "rules file not found: $RulesPath" }
if (-not (Test-Path $VersionPath)) { Fail "VERSION file not found: $VersionPath" }

$ShowcaseRoot = (Resolve-Path $ShowcaseRoot).Path
if (-not (Test-Path (Join-Path $ShowcaseRoot '.git'))) { Fail "showcase root is not a git repo: $ShowcaseRoot" }
if ($ShowcaseRoot -eq $PrivateRoot) { Fail 'showcase root and private root are the same folder' }

$origin = (Invoke-Git $ShowcaseRoot @('remote', 'get-url', 'origin')) -join ''
if ($origin -notmatch 'github\.com') { Fail "showcase origin does not point at github.com: $origin" }

$privateOrigin = (& git -C $PrivateRoot remote get-url origin 2>$null) -join ''
if ($privateOrigin -match 'github\.com') { Fail "this repo's origin points at github.com; refusing to treat it as the private source" }

$dirty = Invoke-Git $PrivateRoot @('status', '--porcelain')
if ($dirty) {
    Write-Warning "private repo has uncommitted changes; the export uses HEAD, so they will NOT be published:`n$($dirty -join "`n")"
}

$showcaseDirty = Invoke-Git $ShowcaseRoot @('status', '--porcelain')
if ($showcaseDirty) { Fail "showcase clone has uncommitted changes; commit or discard them first:`n$($showcaseDirty -join "`n")" }

$Version = (Get-Content $VersionPath -Raw).Trim()
if (-not $Version) { Fail 'VERSION is empty' }

$Rules = Import-PowerShellDataFile $RulesPath
foreach ($key in 'Exclude', 'Replace', 'Verify') {
    if (-not $Rules.ContainsKey($key)) { Fail "rules file is missing the '$key' key" }
}
if ($Rules.Replace.Count -eq 0) { Fail 'rules file has no Replace entries' }

# Longest source term first, so a term that contains another is replaced before the shorter one.
$ReplaceRules = @($Rules.Replace | Sort-Object { $_.From.Length } -Descending)
foreach ($r in $ReplaceRules) {
    if (-not $r.From -or $null -eq $r.To) { Fail "Replace rule without From/To: $($r | Out-String)" }
    if ($r.From -eq $r.To) { Fail "Replace rule maps '$($r.From)' to itself" }
}

# The key's content is checked, never its file name (code and docs legitimately mention the name).
$KeyPath   = Join-Path $PrivateRoot 'etc\restic-repo.key'
$KeySecret = if (Test-Path $KeyPath) { (Get-Content $KeyPath -Raw).Trim() } else { $null }
if ($KeySecret -and $KeySecret.Length -lt 16) { Fail 'restic key is suspiciously short; refusing to use it as a verify term' }

Write-Host "    private : $PrivateRoot (HEAD $((Invoke-Git $PrivateRoot @('rev-parse','--short','HEAD')) -join ''))"
Write-Host "    showcase: $ShowcaseRoot ($origin)"
Write-Host "    version : $Version"
Write-Host "    rules   : $($Rules.Exclude.Count) exclude, $($ReplaceRules.Count) replace, $($Rules.Verify.Count) verify"

# --- 1. Export HEAD ------------------------------------------------------------------------------

$Export = Join-Path ([System.IO.Path]::GetTempPath()) "docs-versioning-showcase-$([guid]::NewGuid().ToString('N'))"
$Zip    = "$Export.zip"
New-Item -ItemType Directory -Path $Export | Out-Null

try {
    Write-Step "Exporting HEAD to $Export"
    Invoke-Git $PrivateRoot @('archive', '--format=zip', '-o', $Zip, 'HEAD') | Out-Null
    Expand-Archive -Path $Zip -DestinationPath $Export -Force
    Remove-Item $Zip

    # --- 2. Exclude ------------------------------------------------------------------------------

    Write-Step 'Removing excluded paths'
    foreach ($rel in $Rules.Exclude) {
        $target = Join-Path $Export $rel
        if (Test-Path $target) {
            Remove-Item $target -Recurse -Force
            Write-Host "    removed  $rel"
        }
        else {
            Write-Host "    absent   $rel"
        }
    }

    # --- 3. Replace ------------------------------------------------------------------------------

    Write-Step 'Applying replacements'
    $files = Get-ChildItem $Export -Recurse -File -Force
    $utf8  = [System.Text.UTF8Encoding]::new($false)
    $totalHits = 0

    foreach ($f in $files) {
        if (-not (Test-IsTextFile $f)) { continue }
        $original = [System.IO.File]::ReadAllText($f.FullName)
        $text = $original
        $fileHits = 0
        foreach ($r in $ReplaceRules) {
            $pattern = if ($r.ContainsKey('WholeWord') -and -not $r.WholeWord) { [regex]::Escape($r.From) } else { '\b' + [regex]::Escape($r.From) + '\b' }
            $rx = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $n = $rx.Matches($text).Count
            if ($n -gt 0) {
                $text = $rx.Replace($text, $r.To)
                $fileHits += $n
            }
        }
        if ($fileHits -gt 0) {
            [System.IO.File]::WriteAllText($f.FullName, $text, $utf8)
            $rel = $f.FullName.Substring($Export.Length + 1)
            Write-Host "    $($fileHits.ToString().PadLeft(4))  $rel"
            $totalHits += $fileHits
        }
    }
    Write-Host "    $totalHits replacement(s) in total"

    # --- 4. Verify -------------------------------------------------------------------------------

    Write-Step 'Verifying the export contains no private terms'
    $terms = @($ReplaceRules.From) + @($Rules.Verify) | Where-Object { $_ } | Select-Object -Unique
    $violations = @()
    foreach ($f in (Get-ChildItem $Export -Recurse -File -Force)) {
        $rel = $f.FullName.Substring($Export.Length + 1)
        foreach ($ex in $Rules.Exclude) {
            if ($rel -like "$ex*") { $violations += "excluded path still present: $rel" }
        }
        if ($KeySecret -and [System.IO.File]::ReadAllText($f.FullName).Contains($KeySecret)) {
            $violations += "${rel}: contains the restic key content"
        }
        if (-not (Test-IsTextFile $f)) { continue }
        $hits = Select-String -Path $f.FullName -Pattern $terms -SimpleMatch -CaseSensitive:$false
        foreach ($h in $hits) {
            $violations += "{0}:{1}: {2}" -f $rel, $h.LineNumber, $h.Line.Trim()
        }
    }
    if ($violations.Count -gt 0) {
        Write-Host ($violations -join "`n") -ForegroundColor Red
        Fail "$($violations.Count) violation(s) found; nothing was written to the showcase clone"
    }
    Write-Host '    clean'

    # --- 5. Mirror into the showcase clone -------------------------------------------------------

    Write-Step 'Mirroring export into the showcase clone'
    Get-ChildItem $ShowcaseRoot -Force | Where-Object Name -ne '.git' | Remove-Item -Recurse -Force
    Copy-Item -Path (Join-Path $Export '*') -Destination $ShowcaseRoot -Recurse -Force

    Invoke-Git $ShowcaseRoot @('add', '-A') | Out-Null
    $stat = Invoke-Git $ShowcaseRoot @('diff', '--cached', '--stat')
    if (-not $stat) {
        Write-Host '    showcase already matches the export; nothing to commit'
        return
    }
    Write-Host ($stat -join "`n")

    if ($DryRun) {
        Write-Step 'Dry run: restoring the showcase clone'
        Invoke-Git $ShowcaseRoot @('reset', '--hard', '--quiet') | Out-Null
        Invoke-Git $ShowcaseRoot @('clean', '-fdq') | Out-Null
        return
    }

    $message = "Sync showcase from v$Version"
    Invoke-Git $ShowcaseRoot @('commit', '--quiet', '-m', $message) | Out-Null
    Write-Host "    committed: $message"

    if ($Push) {
        Write-Step 'Pushing'
        Invoke-Git $ShowcaseRoot @('push') | Out-Null
        Write-Host '    pushed'
    }
    else {
        Write-Host "    not pushed; run: git -C `"$ShowcaseRoot`" push"
    }
}
finally {
    if (Test-Path $Export) { Remove-Item $Export -Recurse -Force }
    if (Test-Path $Zip)    { Remove-Item $Zip -Force }
}
