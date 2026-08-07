[CmdletBinding()]
param(
    [Parameter()]
    [string]$AirCombatSource,

    [Parameter()]
    [string]$ShatteredGalaxySource,

    [Parameter()]
    [string]$BranchName = 'audit/source-inventories',

    [Parameter()]
    [switch]$SkipPush
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workshopContentRoot = Split-Path -Parent $repositoryRoot
$outputRoot = Join-Path $repositoryRoot 'audit\generated'
$includeScript = Join-Path $PSScriptRoot 'Invoke-IncludeAudit.ps1'
$hygieneScript = Join-Path $PSScriptRoot 'Test-RepositoryHygiene.ps1'

function Select-ExistingDirectory {
    param(
        [Parameter(Mandatory)][string]$Purpose,
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Candidates
    )

    $checked = @()
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $checked += $candidate
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $candidate).Path)
        }
    }

    throw "$Purpose folder was not found. Checked: $($checked -join '; ')"
}

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)

    & git -C $repositoryRoot @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "git command failed with exit code ${exitCode}: git $($Arguments -join ' ')"
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git was not found on PATH. Open the repository in GitHub Desktop and run this launcher again.'
}

if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot '.git'))) {
    throw "This script must run from a cloned Git repository: $repositoryRoot"
}

$dirtyLines = @(& git -C $repositoryRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect the Git working tree.'
}

$unexpectedChanges = @($dirtyLines | Where-Object {
    $line = [string]$_
    $path = if ($line.Length -gt 3) { $line.Substring(3).Replace('/', '\') } else { '' }
    -not $path.StartsWith('audit\generated\', [System.StringComparison]::OrdinalIgnoreCase)
})
if ($unexpectedChanges.Count -gt 0) {
    throw "The repository has changes outside audit/generated. Commit or discard them first.`n$($unexpectedChanges -join "`n")"
}

Invoke-Git -Arguments @('fetch', 'origin', 'main')

$currentBranch = (& git -C $repositoryRoot branch --show-current).Trim()
& git -C $repositoryRoot show-ref --verify --quiet "refs/heads/$BranchName"
$branchExists = $LASTEXITCODE -eq 0

if ($currentBranch -ne $BranchName) {
    if ($branchExists) {
        Invoke-Git -Arguments @('checkout', $BranchName)
    }
    else {
        Invoke-Git -Arguments @('checkout', '-b', $BranchName, 'origin/main')
    }
}

Invoke-Git -Arguments @('rebase', 'origin/main')

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

& $includeScript `
    -AirCombatSource $airCombatRoot `
    -ShatteredGalaxySource $shatteredGalaxyRoot `
    -InventoryRoot $outputRoot
if ($LASTEXITCODE -ne 0) {
    throw "Include audit failed with exit code $LASTEXITCODE"
}

& $hygieneScript -RepositoryRoot $repositoryRoot
if ($LASTEXITCODE -ne 0) {
    throw "Repository hygiene validation failed with exit code $LASTEXITCODE"
}

Invoke-Git -Arguments @('add', '--', 'audit/generated')
& git -C $repositoryRoot diff --cached --quiet
$hasChanges = $LASTEXITCODE -ne 0

if ($hasChanges) {
    Invoke-Git -Arguments @('commit', '-m', 'audit: add sanitized workshop source reports')
}
else {
    Write-Host 'No audit changes need to be committed.'
}

if ($SkipPush) {
    Write-Host 'Push skipped by request.'
    exit 0
}

Invoke-Git -Arguments @('push', '--set-upstream', 'origin', $BranchName)
Write-Host ''
Write-Host 'Audit reports were completed, committed, and pushed.'
Write-Host 'The remote branch is audit/source-inventories.'
