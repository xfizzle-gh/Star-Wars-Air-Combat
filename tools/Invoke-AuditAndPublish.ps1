[CmdletBinding()]
param(
    [Parameter()]
    [string]$AirCombatSource,

    [Parameter()]
    [string]$ShatteredGalaxySource,

    [Parameter()]
    [string]$BranchName = 'audit/source-inventories',

    [Parameter()]
    [switch]$SkipPush,

    [Parameter()]
    [switch]$SkipPullRequest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workshopContentRoot = Split-Path -Parent $repositoryRoot
$auditScript = Join-Path $PSScriptRoot 'Invoke-SourceAudit.ps1'
$hygieneScript = Join-Path $PSScriptRoot 'Test-RepositoryHygiene.ps1'
$outputRoot = Join-Path $repositoryRoot 'audit\generated'

function Select-ExistingDirectory {
    param(
        [Parameter(Mandatory)][string]$Purpose,
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Container)) {
            return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $candidate).Path)
        }
    }

    $checkedCandidates = @($Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    throw "$Purpose folder was not found. Checked: $($checkedCandidates -join '; ')"
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter()][switch]$AllowFailure
    )

    & git -C $repositoryRoot @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "git command failed with exit code ${exitCode}: git $($Arguments -join ' ')"
    }
    return $exitCode
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git was not found on PATH. Open the repository in GitHub Desktop and use Repository > Open in Command Prompt, then run the launcher again.'
}

if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot '.git'))) {
    throw "This script must run from a cloned Git repository. Repository root: $repositoryRoot"
}

$dirtyLines = @(& git -C $repositoryRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect the Git working tree.'
}
if ($dirtyLines.Count -gt 0) {
    throw "The repository has uncommitted changes. Commit or discard them before running the source audit.`n$($dirtyLines -join "`n")"
}

Invoke-Git -Arguments @('fetch', 'origin', 'main') | Out-Null

& git -C $repositoryRoot show-ref --verify --quiet "refs/heads/$BranchName"
$branchExists = $LASTEXITCODE -eq 0

if ($branchExists) {
    Invoke-Git -Arguments @('checkout', $BranchName) | Out-Null
    Invoke-Git -Arguments @('rebase', 'origin/main') | Out-Null
}
else {
    Invoke-Git -Arguments @('checkout', '-b', $BranchName, 'origin/main') | Out-Null
}

$airCombatRoot = Select-ExistingDirectory -Purpose 'Air-combat source' -Candidates @(
    $AirCombatSource,
    (Join-Path $repositoryRoot 'sources\air-combat-script'),
    (Join-Path $repositoryRoot 'sources\3666036374'),
    (Join-Path $workshopContentRoot '3666036374'),
    'E:\Star-Wars-Air-Combat\sources\air-combat-script',
    'E:\Steam\steamapps\workshop\content\400750\3666036374'
)

$shatteredGalaxyRoot = Select-ExistingDirectory -Purpose 'Shattered Galaxy source' -Candidates @(
    $ShatteredGalaxySource,
    (Join-Path $repositoryRoot 'sources\shattered-galaxy'),
    (Join-Path $repositoryRoot 'sources\2984016031'),
    (Join-Path $workshopContentRoot '2984016031'),
    'E:\Star-Wars-Air-Combat\sources\shattered-galaxy',
    'E:\Steam\steamapps\workshop\content\400750\2984016031'
)

Write-Host "Repository root: $repositoryRoot"
Write-Host "Air-combat source: $airCombatRoot"
Write-Host "Shattered Galaxy source: $shatteredGalaxyRoot"
Write-Host "Reports: $outputRoot"
Write-Host ''

& $auditScript -AirCombatSource $airCombatRoot -ShatteredGalaxySource $shatteredGalaxyRoot -OutputRoot $outputRoot
& $hygieneScript -RepositoryRoot $repositoryRoot

Invoke-Git -Arguments @('add', '--', 'audit/generated') | Out-Null
& git -C $repositoryRoot diff --cached --quiet
$hasChanges = $LASTEXITCODE -ne 0

if ($hasChanges) {
    Invoke-Git -Arguments @('commit', '-m', 'audit: add sanitized workshop source inventories') | Out-Null
}
else {
    Write-Host 'No generated audit changes need to be committed.'
}

if ($SkipPush) {
    Write-Host 'Push skipped by request.'
    exit 0
}

Invoke-Git -Arguments @('push', '--set-upstream', 'origin', $BranchName) | Out-Null

if ($SkipPullRequest) {
    Write-Host 'Pull-request creation skipped by request.'
    exit 0
}

$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($null -eq $gh) {
    Write-Warning 'GitHub CLI was not found. The audit branch was pushed, but a pull request could not be opened automatically.'
    Write-Host "Open: https://github.com/xfizzle-gh/Star-Wars-Air-Combat/compare/main...audit/source-inventories?expand=1"
    exit 0
}

& gh -R 'xfizzle-gh/Star-Wars-Air-Combat' pr view $BranchName --json number --jq '.number' 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host 'A pull request already exists for the audit branch.'
    exit 0
}

$body = @'
## Summary

- adds sanitized relative-path inventories for both Workshop source mods
- adds air-combat script candidates and include references
- adds TIE fighter and X-wing candidate reports
- copies no source assets

This supplies the evidence needed to begin issues #2 and #3.
'@

& gh -R 'xfizzle-gh/Star-Wars-Air-Combat' pr create `
    --base main `
    --head $BranchName `
    --title 'audit: inventory air-combat and fighter source dependencies' `
    --body $body

if ($LASTEXITCODE -ne 0) {
    throw 'The audit branch was pushed, but GitHub CLI failed to open the pull request.'
}

Write-Host 'Audit reports were generated, committed, pushed, and submitted for review.'
