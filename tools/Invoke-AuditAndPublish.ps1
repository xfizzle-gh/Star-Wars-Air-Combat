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
$auditScript = Join-Path $PSScriptRoot 'Invoke-SourceAudit.ps1'
$hygieneScript = Join-Path $PSScriptRoot 'Test-RepositoryHygiene.ps1'
$outputRoot = Join-Path $repositoryRoot 'audit\generated'

function Select-ExistingDirectory {
    param(
        [Parameter(Mandatory)][string]$Purpose,
        [Parameter(Mandatory)][string[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Container)) {
            return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $candidate).Path)
        }
    }

    throw "$Purpose folder was not found. Checked: $($Candidates -join '; ')"
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter()][switch]$AllowFailure
    )

    & git -C $repositoryRoot @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "git command failed with exit code $exitCode: git $($Arguments -join ' ')"
    }
    return $exitCode
}

$airCombatRoot = Select-ExistingDirectory -Purpose 'Air-combat source' -Candidates @(
    $AirCombatSource,
    'E:\Star-Wars-Air-Combat\sources\air-combat-script',
    'E:\Steam\steamapps\workshop\content\400750\3666036374'
)

$shatteredGalaxyRoot = Select-ExistingDirectory -Purpose 'Shattered Galaxy source' -Candidates @(
    $ShatteredGalaxySource,
    'E:\Star-Wars-Air-Combat\sources\shattered-galaxy',
    'E:\Steam\steamapps\workshop\content\400750\2984016031'
)

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git was not found on PATH. Open the repository once in GitHub Desktop, then run this command again from its repository menu or PowerShell.'
}

if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot '.git'))) {
    throw "This script must run from a cloned Git repository. Repository root: $repositoryRoot"
}

Write-Host "Air-combat source: $airCombatRoot"
Write-Host "Shattered Galaxy source: $shatteredGalaxyRoot"
Write-Host "Reports: $outputRoot"
Write-Host ''

& $auditScript -AirCombatSource $airCombatRoot -ShatteredGalaxySource $shatteredGalaxyRoot -OutputRoot $outputRoot
if ($LASTEXITCODE -ne 0) {
    throw "Source audit failed with exit code $LASTEXITCODE"
}

& $hygieneScript -RepositoryRoot $repositoryRoot
if ($LASTEXITCODE -ne 0) {
    throw "Repository hygiene validation failed with exit code $LASTEXITCODE"
}

$currentBranch = (& git -C $repositoryRoot branch --show-current).Trim()
if ([string]::IsNullOrWhiteSpace($currentBranch)) {
    throw 'Unable to determine the current Git branch.'
}

$branchExists = $false
& git -C $repositoryRoot show-ref --verify --quiet "refs/heads/$BranchName"
if ($LASTEXITCODE -eq 0) {
    $branchExists = $true
}

if ($currentBranch -ne $BranchName) {
    if ($branchExists) {
        Invoke-Git -Arguments @('checkout', $BranchName) | Out-Null
        Invoke-Git -Arguments @('rebase', 'main') | Out-Null
    }
    else {
        Invoke-Git -Arguments @('checkout', '-b', $BranchName, 'main') | Out-Null
    }
}

Invoke-Git -Arguments @('add', '--', 'audit/generated') | Out-Null
& git -C $repositoryRoot diff --cached --quiet
$hasChanges = $LASTEXITCODE -ne 0

if (-not $hasChanges) {
    Write-Host 'No generated audit changes need to be committed.'
}
else {
    Invoke-Git -Arguments @('commit', '-m', 'audit: add sanitized workshop source inventories') | Out-Null
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
    Write-Warning 'GitHub CLI was not found. The branch was pushed successfully, but the pull request could not be opened automatically.'
    Write-Host "Open: https://github.com/xfizzle-gh/Star-Wars-Air-Combat/compare/main...$BranchName?expand=1"
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

Closes no implementation issue. Supplies the evidence needed to begin #2 and #3.
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
