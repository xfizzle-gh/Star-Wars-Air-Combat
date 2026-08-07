[CmdletBinding()]
param(
    [Parameter()]
    [string]$BranchName = 'audit/source-inventories',

    [Parameter()]
    [string]$Repository = 'xfizzle-gh/Star-Wars-Air-Combat',

    [Parameter()]
    [string]$Title = 'audit: inventory air-combat and fighter source dependencies'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($null -eq $gh) {
    Write-Warning 'GitHub CLI was not found. The audit branch is already pushed; open its pull request from GitHub when convenient.'
    exit 0
}

$previousPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'SilentlyContinue'
    $existingNumber = (& gh -R $Repository pr list `
        --head $BranchName `
        --state open `
        --json number `
        --jq '.[0].number // empty' 2>$null | Out-String).Trim()
    $listExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousPreference
}

if ($listExitCode -ne 0) {
    Write-Warning 'The audit branch was pushed, but GitHub CLI could not check for an existing pull request.'
    exit 0
}

if (-not [string]::IsNullOrWhiteSpace($existingNumber)) {
    Write-Host "Pull request #$existingNumber already exists for $BranchName."
    exit 0
}

$body = @'
## Summary

- adds sanitized Workshop source audit reports
- records air-combat framework and TIE/X-wing candidates
- copies no Workshop source assets

Supports #2 and #3.
'@

try {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    & gh -R $Repository pr create `
        --base main `
        --head $BranchName `
        --title $Title `
        --body $body
    $createExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousPreference
}

if ($createExitCode -ne 0) {
    Write-Warning 'The audit branch was pushed successfully, but GitHub CLI could not create the pull request. The audit itself is complete.'
    exit 0
}

Write-Host 'Audit pull request created.'
