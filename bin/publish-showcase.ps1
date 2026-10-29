#Requires -Version 7.0
<#
.SYNOPSIS
    Export the committed tree of this (private) repo into the public showcase clone, anonymised,
    and optionally cut a release on both sides.

.DESCRIPTION
    One-way publication: private Gitea repo -> public GitHub showcase.

    1. git archive HEAD of this repo into a temp folder (working tree is never used, so uncommitted
       and ignored files cannot leak).
    2. Delete every path listed under Exclude in etc/showcase-replacements.psd1.
    3. Apply every Replace rule (whole-word, case-insensitive) to every text file.
    4. Verify: scan the export for every Replace source term, every Verify term and the restic key
       content. Any hit aborts before anything touches the showcase clone.
    5. Mirror the export into the showcase clone (everything except .git is replaced), stage it and
       commit "Sync showcase from v<VERSION>" with the Identity from the rules file.
    6. With -Push: push the showcase. With -Release as well:
       - private repo: annotated tag v<VERSION> on HEAD, pushed to origin (Gitea); a Gitea release
         object is created too when the tea CLI is installed and logged in;
       - showcase: annotated tag v<VERSION> on the sync commit, pushed, and a GitHub release created
         with gh, its notes taken from the matching CHANGELOG section of the anonymised export.

    The showcase keeps its own history: one commit per publish. Nothing from this repo's history is
    ever transferred.

.PARAMETER ShowcaseRoot
    Path to the local clone of the public showcase repo. Must contain .git and have an origin
    remote on github.com.

.PARAMETER DryRun
    Export, replace and verify, then show what would change in the showcase clone. No commit.

.PARAMETER Push
    After committing, push the showcase clone.

.PARAMETER Release
    Tag and release v<VERSION> on both repos. Requires -Push. Refuses if the tag already exists on
    a different commit, or if CHANGELOG.md has no section for the version.

.EXAMPLE
    .\bin\publish-showcase.ps1 -ShowcaseRoot ..\docs-versioning -DryRun
    .\bin\publish-showcase.ps1 -ShowcaseRoot ..\docs-versioning -Push -Release
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ShowcaseRoot,

    [switch]$DryRun,
    [switch]$Push,
    [switch]$Release
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

function Get-TagCommit([string]$Repo, [string]$Tag) {
    $sha = & git -C $Repo rev-parse --verify --quiet "refs/tags/$Tag^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($sha -join '').Trim()
}

function Test-IsTextFile([System.IO.FileInfo]$File) {
    if ($TextExtensions -notcontains $File.Extension.ToLowerInvariant()) { return $false }
    if ($File.Length -eq 0) { return $true }
    $bytes = [System.IO.File]::ReadAllBytes($File.FullName)
    $probe = [Math]::Min($bytes.Length, 8000)
    for ($i = 0; $i -lt $probe; $i++) { if ($bytes[$i] -eq 0) { return $false } }
    return $true
}

function Get-ChangelogSection([string]$Path, [string]$Version) {
    if (-not (Test-Path $Path)) { return $null }
    $lines = Get-Content $Path
    $start = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($null -eq $start) {
            if ($lines[$i] -match "^##\s+$([regex]::Escape($Version))(\s|$)") { $start = $i + 1 }
        }
        elseif ($lines[$i] -match '^##\s') {
            return ($lines[$start..($i - 1)] -join "`n").Trim()
        }
    }
    if ($null -ne $start) { return ($lines[$start..($lines.Count - 1)] -join "`n").Trim() }
    return $null
}

# --- 0. Preconditions ----------------------------------------------------------------------------

Write-Step 'Checking preconditions'

if ($Release -and -not $Push) { Fail '-Release requires -Push' }
if ($Release -and $DryRun)    { Fail '-Release cannot be combined with -DryRun' }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'git is not on PATH' }
if ($Release -and -not (Get-Command gh -ErrorAction SilentlyContinue)) { Fail 'gh (GitHub CLI) is not on PATH; it is needed for -Release' }
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
    if ($Release) { Fail "private repo has uncommitted changes; commit them before releasing:`n$($dirty -join "`n")" }
    Write-Warning "private repo has uncommitted changes; the export uses HEAD, so they will NOT be published:`n$($dirty -join "`n")"
}

$showcaseDirty = Invoke-Git $ShowcaseRoot @('status', '--porcelain')
if ($showcaseDirty) { Fail "showcase clone has uncommitted changes; commit or discard them first:`n$($showcaseDirty -join "`n")" }

# The showcase must sit exactly on its remote: after a history rewrite on GitHub, an old local
# clone would otherwise push the old history straight back.
Invoke-Git $ShowcaseRoot @('fetch', '--quiet', 'origin') | Out-Null
$branch     = ((Invoke-Git $ShowcaseRoot @('rev-parse', '--abbrev-ref', 'HEAD')) -join '').Trim()
$localHead  = ((Invoke-Git $ShowcaseRoot @('rev-parse', 'HEAD')) -join '').Trim()
$remoteHead = ((Invoke-Git $ShowcaseRoot @('rev-parse', "origin/$branch")) -join '').Trim()
if ($localHead -ne $remoteHead) {
    Fail "showcase clone is not at origin/$branch ($($localHead.Substring(0,7)) vs $($remoteHead.Substring(0,7))). If GitHub was rewritten, run: git -C `"$ShowcaseRoot`" reset --hard origin/$branch"
}

$Version = (Get-Content $VersionPath -Raw).Trim()
if (-not $Version) { Fail 'VERSION is empty' }
$Tag = "v$Version"

$Rules = Import-PowerShellDataFile $RulesPath
foreach ($key in 'Exclude', 'Replace', 'Verify', 'Identity') {
    if (-not $Rules.ContainsKey($key)) { Fail "rules file is missing the '$key' key" }
}
if ($Rules.Replace.Count -eq 0) { Fail 'rules file has no Replace entries' }
if (-not $Rules.Identity.Name -or -not $Rules.Identity.Email) { Fail 'rules file Identity needs Name and Email' }

# Every commit and tag on the public side is made with this identity, whatever the machine's
# git config says. A work laptop's corporate address can never reach the showcase.
$IdentityArgs = @('-c', "user.name=$($Rules.Identity.Name)", '-c', "user.email=$($Rules.Identity.Email)")
foreach ($t in $Rules.Verify) {
    if ($Rules.Identity.Email -like "*$t*") { Fail "Identity email matches the verify term '$t'" }
}

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

$PrivateHead = ((Invoke-Git $PrivateRoot @('rev-parse', 'HEAD')) -join '').Trim()

if ($Release) {
    $existing = Get-TagCommit $PrivateRoot $Tag
    if ($existing -and $existing -ne $PrivateHead) {
        Fail "tag $Tag already exists in the private repo on $($existing.Substring(0,7)), not on HEAD; bump VERSION first"
    }
    $remoteTag = (Invoke-Git $ShowcaseRoot @('ls-remote', '--tags', 'origin', "refs/tags/$Tag")) -join ''
    if ($remoteTag) { Fail "tag $Tag already exists on GitHub; bump VERSION first" }
}

Write-Host "    private : $PrivateRoot (HEAD $($PrivateHead.Substring(0,7)))"
Write-Host "    showcase: $ShowcaseRoot ($origin, $branch)"
Write-Host "    version : $Version"
Write-Host "    identity: $($Rules.Identity.Name) <$($Rules.Identity.Email)>"
Write-Host "    rules   : $($Rules.Exclude.Count) exclude, $($ReplaceRules.Count) replace, $($Rules.Verify.Count) verify"

# --- 1. Export HEAD ------------------------------------------------------------------------------

$Export = Join-Path ([System.IO.Path]::GetTempPath()) "docs-versioning-showcase-$([guid]::NewGuid().ToString('N'))"
$Zip    = "$Export.zip"
$Notes  = "$Export.notes.md"
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
        $text = [System.IO.File]::ReadAllText($f.FullName)
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
    # Replace terms are checked with the same word boundaries the replacement used, so a short
    # term does not flag a longer word that contains it; Verify terms are plain substrings.
    $terms = @(
        foreach ($r in $ReplaceRules) {
            if ($r.ContainsKey('WholeWord') -and -not $r.WholeWord) { [regex]::Escape($r.From) } else { '\b' + [regex]::Escape($r.From) + '\b' }
        }
        foreach ($v in $Rules.Verify) { if ($v) { [regex]::Escape($v) } }
    ) | Select-Object -Unique
    $violations = @()
    foreach ($f in (Get-ChildItem $Export -Recurse -File -Force)) {
        $rel = $f.FullName.Substring($Export.Length + 1)
        foreach ($ex in $Rules.Exclude) {
            if ($rel.Replace('\', '/') -like "$ex*") { $violations += "excluded path still present: $rel" }
        }
        if ($KeySecret -and [System.IO.File]::ReadAllText($f.FullName).Contains($KeySecret)) {
            $violations += "${rel}: contains the restic key content"
        }
        if (-not (Test-IsTextFile $f)) { continue }
        $hits = Select-String -Path $f.FullName -Pattern $terms -CaseSensitive:$false
        foreach ($h in $hits) {
            $violations += "{0}:{1}: {2}" -f $rel, $h.LineNumber, $h.Line.Trim()
        }
    }
    if ($violations.Count -gt 0) {
        Write-Host ($violations -join "`n") -ForegroundColor Red
        Fail "$($violations.Count) violation(s) found; nothing was written to the showcase clone"
    }
    Write-Host '    clean'

    # Release notes come from the anonymised export, never from the private CHANGELOG.
    if ($Release) {
        $section = Get-ChangelogSection (Join-Path $Export 'CHANGELOG.md') $Version
        if (-not $section) { Fail "CHANGELOG.md has no '## $Version' section; write it before releasing" }
        [System.IO.File]::WriteAllText($Notes, $section, $utf8)
    }

    # --- 5. Mirror into the showcase clone -------------------------------------------------------

    Write-Step 'Mirroring export into the showcase clone'
    Get-ChildItem $ShowcaseRoot -Force | Where-Object Name -ne '.git' | Remove-Item -Recurse -Force
    Copy-Item -Path (Join-Path $Export '*') -Destination $ShowcaseRoot -Recurse -Force

    Invoke-Git $ShowcaseRoot @('add', '-A') | Out-Null
    $stat = Invoke-Git $ShowcaseRoot @('diff', '--cached', '--stat')

    if (-not $stat) {
        Write-Host '    showcase already matches the export; nothing to commit'
    }
    else {
        Write-Host ($stat -join "`n")

        if ($DryRun) {
            Write-Step 'Dry run: restoring the showcase clone'
            Invoke-Git $ShowcaseRoot @('reset', '--hard', '--quiet') | Out-Null
            Invoke-Git $ShowcaseRoot @('clean', '-fdq') | Out-Null
            return
        }

        $message = "Sync showcase from $Tag"
        Invoke-Git $ShowcaseRoot ($IdentityArgs + @('commit', '--quiet', '-m', $message)) | Out-Null
        Write-Host "    committed: $message"
    }

    if (-not $Push) {
        if ($stat) { Write-Host "    not pushed; run: git -C `"$ShowcaseRoot`" push" }
        return
    }

    # --- 6. Push and release ---------------------------------------------------------------------

    if ($stat) {
        Write-Step 'Pushing showcase'
        Invoke-Git $ShowcaseRoot @('push', 'origin', $branch) | Out-Null
        Write-Host '    pushed'
    }

    if (-not $Release) { return }

    Write-Step "Releasing $Tag on Gitea"
    if (-not (Get-TagCommit $PrivateRoot $Tag)) {
        Invoke-Git $PrivateRoot @('tag', '-a', $Tag, '-m', "Release $Tag") | Out-Null
        Write-Host "    tagged HEAD as $Tag"
    }
    Invoke-Git $PrivateRoot @('push', 'origin', 'HEAD', $Tag) | Out-Null
    Write-Host '    pushed branch and tag'

    if (Get-Command tea -ErrorAction SilentlyContinue) {
        $privateSection = Get-ChangelogSection (Join-Path $PrivateRoot 'CHANGELOG.md') $Version
        $privateNotes = "$Export.private-notes.md"
        [System.IO.File]::WriteAllText($privateNotes, $privateSection, $utf8)
        & tea releases create --tag $Tag --title $Tag --note-file $privateNotes 2>&1 | Out-Host
        Remove-Item $privateNotes -Force
        if ($LASTEXITCODE -ne 0) { Write-Warning 'tea could not create the Gitea release; the tag is pushed and shows under Tags' }
    }
    else {
        Write-Host '    tea not installed: the tag shows under Tags on Gitea; no release object created'
    }

    Write-Step "Releasing $Tag on GitHub"
    Invoke-Git $ShowcaseRoot ($IdentityArgs + @('tag', '-a', $Tag, '-m', "Release $Tag")) | Out-Null
    Invoke-Git $ShowcaseRoot @('push', 'origin', $Tag) | Out-Null
    $repoSlug = ($origin -replace '\.git$', '' -replace '^.*github\.com[:/]', '')
    & gh release create $Tag --repo $repoSlug --title $Tag --notes-file $Notes --verify-tag 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { Fail "gh release create failed; the tag $Tag is pushed, retry with: gh release create $Tag --repo $repoSlug --notes-from-tag" }
    Write-Host "    released $Tag"
}
finally {
    if (Test-Path $Export) { Remove-Item $Export -Recurse -Force }
    if (Test-Path $Zip)    { Remove-Item $Zip -Force }
    if (Test-Path $Notes)  { Remove-Item $Notes -Force }
}
