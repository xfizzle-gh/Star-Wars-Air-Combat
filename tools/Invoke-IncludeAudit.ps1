[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AirCombatSource,

    [Parameter(Mandatory)]
    [string]$ShatteredGalaxySource,

    [Parameter()]
    [string]$InventoryRoot = (Join-Path $PSScriptRoot '..\audit\generated'),

    [Parameter()]
    [int]$MaximumTextFileBytes = 8388608
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param([Parameter(Mandatory)][string]$Path)
    return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
}

function Test-InventoryBoolean {
    param([Parameter(Mandatory)][object]$Value)
    return [string]$Value -match '^(?i:true|1)$'
}

function Read-TextSafely {
    param([Parameter(Mandatory)][string]$Path)

    try {
        $file = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($file.Length -gt $MaximumTextFileBytes) {
            return $null
        }
        return [System.IO.File]::ReadAllText($file.FullName)
    }
    catch {
        return $null
    }
}

function ConvertTo-CsvField {
    param([AllowNull()][object]$Value)

    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    return '"' + ($text -replace '"', '""') + '"'
}

function Write-IncludeReport {
    param(
        [Parameter(Mandatory)][string]$SourceName,
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$InventoryPath,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $includePatterns = @(
        '(?im)^\s*(?:#?include|include_once)\s*[\(\{]?\s*["''](?<target>[^"'']+)["'']',
        '(?im)\{\s*include\s+["''](?<target>[^"'']+)["'']',
        '(?im)\{\s*import\s+["''](?<target>[^"'']+)["'']'
    )

    $entries = @(Import-Csv -LiteralPath $InventoryPath | Where-Object {
        Test-InventoryBoolean -Value $_.IsText
    })

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $writer = New-Object System.IO.StreamWriter($OutputPath, $false, $encoding)
    $writer.WriteLine('"Source","RelativePath","Target","Directive"')

    $matchCount = 0
    $readableCount = 0
    $skippedCount = 0

    try {
        for ($index = 0; $index -lt $entries.Count; $index++) {
            $entry = $entries[$index]
            if (($index % 500) -eq 0) {
                $percent = (($index + 1) / [Math]::Max($entries.Count, 1)) * 100
                Write-Progress -Activity "Extracting include directives from $SourceName" -Status "$($index + 1) / $($entries.Count)" -PercentComplete $percent
            }

            $fullPath = Join-Path $SourceRoot $entry.RelativePath
            $content = Read-TextSafely -Path $fullPath
            if ($null -eq $content) {
                $skippedCount++
                continue
            }

            $readableCount++
            foreach ($pattern in $includePatterns) {
                foreach ($match in [regex]::Matches($content, $pattern)) {
                    $fields = @(
                        ConvertTo-CsvField -Value $SourceName
                        ConvertTo-CsvField -Value $entry.RelativePath
                        ConvertTo-CsvField -Value $match.Groups['target'].Value.Trim()
                        ConvertTo-CsvField -Value $match.Value.Trim()
                    )
                    $writer.WriteLine($fields -join ',')
                    $matchCount++
                }
            }
        }
    }
    finally {
        $writer.Dispose()
        Write-Progress -Activity "Extracting include directives from $SourceName" -Completed
    }

    return [pscustomobject]@{
        Source = $SourceName
        InventoryTextFiles = $entries.Count
        ReadableTextFiles = $readableCount
        SkippedTextFiles = $skippedCount
        IncludeDirectives = $matchCount
        Output = [System.IO.Path]::GetFileName($OutputPath)
    }
}

if (-not (Test-Path -LiteralPath $AirCombatSource -PathType Container)) {
    throw "Air-combat source folder was not found: $AirCombatSource"
}
if (-not (Test-Path -LiteralPath $ShatteredGalaxySource -PathType Container)) {
    throw "Shattered Galaxy source folder was not found: $ShatteredGalaxySource"
}

$airRoot = Resolve-FullPath -Path $AirCombatSource
$galaxyRoot = Resolve-FullPath -Path $ShatteredGalaxySource
$outputRoot = [System.IO.Path]::GetFullPath($InventoryRoot)
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

$airInventoryPath = Join-Path $outputRoot 'air-combat-files.csv'
$galaxyInventoryPath = Join-Path $outputRoot 'shattered-galaxy-files.csv'

if (-not (Test-Path -LiteralPath $airInventoryPath -PathType Leaf)) {
    throw "Existing air-combat inventory was not found: $airInventoryPath"
}
if (-not (Test-Path -LiteralPath $galaxyInventoryPath -PathType Leaf)) {
    throw "Existing Shattered Galaxy inventory was not found: $galaxyInventoryPath"
}

Write-Host 'Resuming from the existing file inventories. Source files will not be copied.'
Write-Host "Air-combat source: $airRoot"
Write-Host "Shattered Galaxy source: $galaxyRoot"
Write-Host ''

$airResult = Write-IncludeReport `
    -SourceName 'air-combat-script' `
    -SourceRoot $airRoot `
    -InventoryPath $airInventoryPath `
    -OutputPath (Join-Path $outputRoot 'air-combat-includes.csv')

$galaxyResult = Write-IncludeReport `
    -SourceName 'shattered-galaxy' `
    -SourceRoot $galaxyRoot `
    -InventoryPath $galaxyInventoryPath `
    -OutputPath (Join-Path $outputRoot 'shattered-galaxy-includes.csv')

$summary = @"
# Resumed include audit

Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')

This pass reused the existing sanitized file inventories. It did not repeat the 80 GB inventory and did not copy source assets.

## Air-combat framework

- Inventory text files: $($airResult.InventoryTextFiles)
- Readable text files: $($airResult.ReadableTextFiles)
- Skipped text files: $($airResult.SkippedTextFiles)
- Include directives: $($airResult.IncludeDirectives)

## Shattered Galaxy

- Inventory text files: $($galaxyResult.InventoryTextFiles)
- Readable text files: $($galaxyResult.ReadableTextFiles)
- Skipped text files: $($galaxyResult.SkippedTextFiles)
- Include directives: $($galaxyResult.IncludeDirectives)
"@

[System.IO.File]::WriteAllText(
    (Join-Path $outputRoot 'include-summary.md'),
    $summary,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ''
Write-Host "Include audit complete: $outputRoot"
$airResult | Format-List
$galaxyResult | Format-List
